import AVFoundation
import Observation

// MARK: - Internal types

private struct LoadedClip {
    let trackID: UUID
    var clip: AudioClip
    let player: AVAudioPlayerNode
    let file: AVAudioFile
    let sampleRate: Double
}

private struct EffectsChain {
    let equalizer: AVAudioUnitEQ
    let reverb: AVAudioUnitReverb
}

// MARK: - Engine

/// Multi-track AVAudioEngine wrapper.
///
/// Signal path per effects-bearing track:  player → equalizer → reverb → mainMixerNode
/// Signal path per instrumental track:     player → mainMixerNode
///
/// All player nodes start at the same AVAudioTime so playback is sample-accurate.
/// Important: never pass nil to engine.connect — always supply the file's processingFormat.
@Observable
final class MultiTrackEngine {

    // MARK: - Public state

    private(set) var isPlaying = false
    private(set) var isRecording = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    // MARK: - Private audio graph

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var loadedClips: [LoadedClip] = []
    @ObservationIgnored private var effectsChains: [UUID: EffectsChain] = [:]
    @ObservationIgnored private var mutedTrackIDs: Set<UUID> = []

    // Wall-clock anchor set when play() is called, used to compute currentTime cheaply
    @ObservationIgnored private var playAnchorWall: CFTimeInterval = 0
    @ObservationIgnored private var playAnchorTimeline: TimeInterval = 0
    @ObservationIgnored private var pollingTask: Task<Void, Never>?

    // Recording state
    @ObservationIgnored private var recordingFile: AVAudioFile?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var recordingTimelineOffset: TimeInterval = 0

    // MARK: - Load

    /// Open every clip audio file, wire up the AVAudioEngine graph, and start it.
    /// Returns the same tracks with `AudioClip.duration` populated from the actual files.
    func loadTracks(_ tracks: [Track]) async throws -> [Track] {
        tearDown()

        // Configure the session before touching the engine at all. The input node can
        // latch a zero/invalid format for the rest of the process if engine.start() ever
        // runs before the session is .playAndRecord — this is the root cause behind
        // "could not read the microphone input format" needing an app restart to clear.
        try configureAudioSession()

        var updatedTracks = tracks
        var projectDuration: TimeInterval = 0

        for (trackIndex, track) in tracks.enumerated() {
            // Tracks the first clip that successfully wired the chain → mainMixer,
            // because eq→reverb→mainMixer must only be connected once per effects chain.
            var effectsChainWiredToOutput = false

            for (clipIndex, clip) in track.clips.enumerated() {

                // 1. Open the audio file
                guard let audioFile = try? AVAudioFile(forReading: clip.url) else { continue }
                let audioFormat = audioFile.processingFormat

                // Guard against /dev/null or otherwise empty/corrupt files
                guard audioFormat.sampleRate > 0, audioFormat.channelCount > 0 else { continue }

                let fileDuration = Double(audioFile.length) / audioFormat.sampleRate
                guard fileDuration > 0 else { continue }

                // 2. Attach a dedicated player node for this clip
                let playerNode = AVAudioPlayerNode()
                engine.attach(playerNode)

                // 3. Wire the player into the graph
                if track.effectsApplicable {
                    // Create the effects chain lazily on the first valid clip for this track
                    if effectsChains[track.id] == nil {
                        let chain = makeEffectsChain()
                        effectsChains[track.id] = chain
                        engine.attach(chain.equalizer)
                        engine.attach(chain.reverb)
                        // Do NOT connect equalizer→reverb→mainMixer here yet.
                        // The playerNode must be connected to the equalizer first so that
                        // AVAudioEngine can infer a valid format through the chain.
                    }
                    let chain = effectsChains[track.id]!

                    // player → equalizer (explicit format from the source file)
                    engine.connect(playerNode, to: chain.equalizer, format: audioFormat)

                    // equalizer → reverb → mainMixer (same explicit format, done once per chain)
                    if !effectsChainWiredToOutput {
                        engine.connect(chain.equalizer, to: chain.reverb,         format: audioFormat)
                        engine.connect(chain.reverb,    to: engine.mainMixerNode, format: audioFormat)
                        effectsChainWiredToOutput = true
                    }
                } else {
                    // Instrumental / source track — no effects processing
                    engine.connect(playerNode, to: engine.mainMixerNode, format: audioFormat)
                }

                // 4. Store updated clip with real duration
                var updatedClip = clip
                updatedClip.duration = fileDuration
                updatedTracks[trackIndex].clips[clipIndex] = updatedClip

                loadedClips.append(LoadedClip(
                    trackID: track.id,
                    clip: updatedClip,
                    player: playerNode,
                    file: audioFile,
                    sampleRate: audioFormat.sampleRate
                ))

                projectDuration = max(projectDuration, updatedClip.timelineEnd)
            }

            if track.isMuted { mutedTrackIDs.insert(track.id) }
            if let chain = effectsChains[track.id] {
                applySettingsToChain(chain, settings: track.effects)
            }
        }

        duration = projectDuration

        // Start the engine even if no clip loaded (e.g. an empty project) — recording
        // must still work, and the session is already configured above.
        try engine.start()
        return updatedTracks
    }

    // MARK: - Transport

    func play(from time: TimeInterval) throws {
        guard !loadedClips.isEmpty else { return }
        if !engine.isRunning { try engine.start() }

        let startTime = avAudioTime(secondsFromNow: 0.02)

        for loadedClip in loadedClips {
            guard !mutedTrackIDs.contains(loadedClip.trackID) else { continue }
            scheduleClip(loadedClip, currentTime: time, playAnchor: startTime)
        }

        playAnchorWall = CACurrentMediaTime() + 0.02
        playAnchorTimeline = time
        isPlaying = true
        startPolling()
    }

    func pause() {
        syncCurrentTime()
        for loadedClip in loadedClips { loadedClip.player.pause() }
        isPlaying = false
        stopPolling()
    }

    func stop() {
        for loadedClip in loadedClips { loadedClip.player.stop() }
        isPlaying = false
        currentTime = 0
        stopPolling()
    }

    func seek(to time: TimeInterval) {
        let wasPlaying = isPlaying
        if wasPlaying { pause() }
        currentTime = max(0, min(time, duration))
        if wasPlaying { try? play(from: currentTime) }
    }

    // MARK: - Per-track control

    func setMuted(_ muted: Bool, for trackID: UUID) {
        if muted {
            mutedTrackIDs.insert(trackID)
            loadedClips.filter { $0.trackID == trackID }.forEach { $0.player.stop() }
        } else {
            mutedTrackIDs.remove(trackID)
            if isPlaying {
                let startTime = avAudioTime(secondsFromNow: 0.01)
                for loadedClip in loadedClips where loadedClip.trackID == trackID {
                    scheduleClip(loadedClip, currentTime: currentTime, playAnchor: startTime)
                    loadedClip.player.play(at: startTime)
                }
            }
        }
    }

    func applyEffects(_ settings: EffectSettings, to trackID: UUID) {
        guard let chain = effectsChains[trackID] else { return }
        applySettingsToChain(chain, settings: settings)
    }

    // MARK: - Recording

    /// Request microphone permission then start capturing to a temp file.
    func startRecording(at timelineOffset: TimeInterval) async throws {
        guard !isRecording else { return }

        print("[Engine] startRecording: requesting microphone permission")
        let granted = await AVAudioApplication.requestRecordPermission()
        print("[Engine] startRecording: granted = \(granted)")
        guard granted else {
            throw AudioEngineError.microphonePermissionDenied
        }

        // Idempotent — don't assume loadTracks already configured the session
        // (an empty/source-less project still needs to be able to record).
        try configureAudioSession()
        let audioSession = AVAudioSession.sharedInstance()
        print("[Engine] startRecording: session category = \(audioSession.category.rawValue), options = \(audioSession.categoryOptions.rawValue)")
        print("[Engine] startRecording: engine.isRunning = \(engine.isRunning)")

        if !engine.isRunning {
            print("[Engine] startRecording: engine was stopped — starting now")
            try engine.start()
        }

        var hardwareFormat = engine.inputNode.inputFormat(forBus: 0)
        print("[Engine] startRecording: inputFormat sampleRate=\(hardwareFormat.sampleRate) channels=\(hardwareFormat.channelCount)")

        if hardwareFormat.sampleRate <= 0 || hardwareFormat.channelCount == 0 {
            // The input node can latch an invalid format if it was ever created before
            // the session went .playAndRecord. Recover the way restarting the app used
            // to: fully stop and restart the engine under the now-correct session, then
            // re-read the format once before giving up.
            print("[Engine] startRecording: input format invalid — restarting engine to recover")
            engine.stop()
            try configureAudioSession()
            try engine.start()
            hardwareFormat = engine.inputNode.inputFormat(forBus: 0)
            print("[Engine] startRecording: post-recovery inputFormat sampleRate=\(hardwareFormat.sampleRate) channels=\(hardwareFormat.channelCount)")
        }

        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            print("[Engine] startRecording: ERROR — input format still zero after recovery attempt")
            throw AudioEngineError.microphoneFormatUnavailable
        }

        // Persist recordings in Documents so they survive app restarts
        let recordingsDir = URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        let outputURL = recordingsDir.appendingPathComponent(UUID().uuidString + ".caf")
        print("[Engine] startRecording: output → \(outputURL.lastPathComponent)")

        recordingURL = outputURL
        recordingTimelineOffset = timelineOffset

        // Pass nil format so the engine delivers buffers in its native hardware format.
        // The output file is created lazily on the first buffer so its format is guaranteed
        // to match the buffers we receive — no format mismatch possible.
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            if self.recordingFile == nil {
                self.recordingFile = try? AVAudioFile(
                    forWriting: outputURL,
                    settings: buffer.format.settings
                )
                print("[Engine] recording: file created with format \(buffer.format)")
            }
            try? self.recordingFile?.write(from: buffer)
        }

        print("[Engine] startRecording: tap installed, recording started")
        isRecording = true
    }

    func finishRecording() throws -> AudioClip? {
        guard isRecording else { return nil }
        engine.inputNode.removeTap(onBus: 0)

        guard let url = recordingURL, let file = recordingFile else {
            isRecording = false
            return nil
        }

        let fileDuration = Double(file.length) / file.processingFormat.sampleRate
        let clip = AudioClip(
            url: url,
            timelineOffset: recordingTimelineOffset,
            duration: fileDuration
        )

        recordingFile = nil
        recordingURL = nil
        isRecording = false

        return clip
    }

    // MARK: - Teardown

    func tearDown() {
        stopPolling()

        if isRecording {
            engine.inputNode.removeTap(onBus: 0)
            isRecording = false
        }

        for loadedClip in loadedClips {
            loadedClip.player.stop()
            engine.detach(loadedClip.player)
        }
        loadedClips.removeAll()

        for (_, chain) in effectsChains {
            engine.detach(chain.equalizer)
            engine.detach(chain.reverb)
        }
        effectsChains.removeAll()
        mutedTrackIDs.removeAll()

        if engine.isRunning { engine.stop() }
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    // MARK: - Private — clip scheduling

    /// Schedule one clip's audio against the shared playback anchor time.
    private func scheduleClip(
        _ loadedClip: LoadedClip,
        currentTime: TimeInterval,
        playAnchor: AVAudioTime
    ) {
        loadedClip.player.stop()

        guard loadedClip.clip.timelineEnd > currentTime else { return }

        let fileReadStartSeconds: TimeInterval
        let playerStartDelaySeconds: TimeInterval

        if loadedClip.clip.timelineOffset <= currentTime {
            // Playhead is already inside this clip — seek into the file
            fileReadStartSeconds = loadedClip.clip.trimStart + (currentTime - loadedClip.clip.timelineOffset)
            playerStartDelaySeconds = 0
        } else {
            // Clip starts in the future — read from its trim point, delay the player start
            fileReadStartSeconds = loadedClip.clip.trimStart
            playerStartDelaySeconds = loadedClip.clip.timelineOffset - currentTime
        }

        let startFrame = AVAudioFramePosition(fileReadStartSeconds * loadedClip.sampleRate)
        let remainingFrames = AVAudioFrameCount(max(0, loadedClip.file.length - startFrame))
        guard remainingFrames > 0 else { return }

        loadedClip.player.scheduleSegment(
            loadedClip.file,
            startingFrame: startFrame,
            frameCount: remainingFrames,
            at: nil
        )

        if playerStartDelaySeconds > 0 {
            loadedClip.player.play(at: avAudioTime(secondsFromNow: playerStartDelaySeconds + 0.02))
        } else {
            loadedClip.player.play(at: playAnchor)
        }
    }

    // MARK: - Private — clock

    private func syncCurrentTime() {
        guard isPlaying else { return }
        let elapsed = CACurrentMediaTime() - playAnchorWall
        currentTime = min(playAnchorTimeline + max(0, elapsed), duration)
    }

    private func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                self.syncCurrentTime()
                if self.isPlaying, self.duration > 0, self.currentTime >= self.duration {
                    self.isPlaying = false
                    break
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Private — graph helpers

    private func makeEffectsChain() -> EffectsChain {
        let equalizer = AVAudioUnitEQ(numberOfBands: 4)
        let frequencies: [Float] = [80, 500, 2000, 8000]
        for (index, frequency) in frequencies.enumerated() {
            equalizer.bands[index].filterType = .parametric
            equalizer.bands[index].frequency = frequency
            equalizer.bands[index].bandwidth = 1.0
            equalizer.bands[index].gain = 0
            equalizer.bands[index].bypass = false
        }

        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 15

        return EffectsChain(equalizer: equalizer, reverb: reverb)
    }

    private func applySettingsToChain(_ chain: EffectsChain, settings: EffectSettings) {
        chain.reverb.wetDryMix = settings.reverbMix
        for (index, gain) in settings.eqGains.enumerated() where index < chain.equalizer.bands.count {
            chain.equalizer.bands[index].gain = gain
        }
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        // Always playAndRecord so the input node is ready from engine start.
        // .defaultToSpeaker routes audio to the speaker instead of the earpiece.
        // .allowBluetooth allows AirPods and other BT devices for both mic and playback.
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true)
    }

    /// Convert a future delay in seconds into an AVAudioTime.
    private func avAudioTime(secondsFromNow delay: TimeInterval) -> AVAudioTime {
        AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: delay))
    }
}

// MARK: - Errors

enum AudioEngineError: LocalizedError {
    case microphonePermissionDenied
    case microphoneFormatUnavailable

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access was denied. Go to Settings → Vocal Studio and enable Microphone."
        case .microphoneFormatUnavailable:
            return "No microphone input is available right now. On the Simulator, check that an input device is selected in your Mac's Sound settings; on a device, try reopening the project."
        }
    }
}
