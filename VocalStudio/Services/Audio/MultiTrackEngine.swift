import AVFoundation
import Observation
import QuartzCore

// MARK: - Internal Engine Types

private struct LoadedClip {
    let trackID: UUID
    var clip: AudioClip
    let player: AVAudioPlayerNode
    let file: AVAudioFile
    let sampleRate: Double
}

private struct EffectsChain {
    /// Players route through this mixer, never straight into the EQ: an
    /// AVAudioUnitEQ has a single input bus, so a second clip's player connecting
    /// to it directly would silently disconnect the first. A mixer node has as
    /// many input buses as needed and converts formats per input.
    let input: AVAudioMixerNode
    let equalizer: AVAudioUnitEQ
    let reverb: AVAudioUnitReverb
}

// MARK: - MultiTrackEngine Implementation

@Observable
final class MultiTrackEngine {

    // MARK: - Public State

    private(set) var isPlaying = false
    private(set) var isRecording = false
    /// True while a recording exists but is paused (transport pause during capture).
    private(set) var isRecordingPaused = false
    /// Timeline position where the in-flight recording started — drives the live
    /// "recording" lane in the timeline. Nil when no recording is running.
    private(set) var activeRecordingStart: TimeInterval?
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    // MARK: - Private Audio Graph

    @ObservationIgnored private let engine: AVAudioEngine
    @ObservationIgnored private var loadedClips: [LoadedClip] = []
    @ObservationIgnored private var effectsChains: [UUID: EffectsChain] = [:]
    @ObservationIgnored private var mutedTrackIDs: Set<UUID> = []

    // Timekeeping properties
    @ObservationIgnored private var playAnchorWall: CFTimeInterval = 0
    @ObservationIgnored private var playAnchorTimeline: TimeInterval = 0
    @ObservationIgnored private var recordAnchorWall: CFTimeInterval = 0
    @ObservationIgnored private var recordAnchorTimeline: TimeInterval = 0
    @ObservationIgnored private var pollingTask: Task<Void, Never>?

    // Recording State
    //
    // Deliberately NOT engine.inputNode.installTap. Across multiple real-device test
    // rounds, engine.inputNode.outputFormat(forBus:) reported sampleRate 0 forever —
    // even with a fully correct, verified session/route (category, options, permission,
    // currentRoute.inputs all confirmed valid via diagnostics) — and even after polling
    // for a full second and a full stop/restart. AVAudioRecorder is Apple's dedicated
    // "record the mic to a file" API: it negotiates the hardware format internally and
    // never requires the caller to read inputNode's format at all, which sidesteps the
    // entire problem rather than working around it. We never routed the live mic signal
    // through the effects graph for monitoring anyway (the tap only wrote raw buffers to
    // disk), so this drops in with no functional loss.
    @ObservationIgnored private var audioRecorder: AVAudioRecorder?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var recordingTimelineOffset: TimeInterval = 0
    // `isRecording` only flips true at the very end of startRecording — everything
    // before that (permission, session config) is `await`-suspendable, so a second call
    // (e.g. a double tap) can slip past `guard !isRecording` while the first is still
    // mid-setup. This flag is set synchronously before any `await`, so a second call can
    // never get past the guard.
    @ObservationIgnored private var isStartingRecording = false

    // MARK: - Initialization Lifecycle

    /// Deliberately does no AVFoundation work. `EditorViewModel` constructs this as a
    /// stored property, so anything heavy or session-touching here would run as a side
    /// effect of SwiftUI evaluating a view's `@State` — before microphone permission has
    /// even been requested, and possibly more than once. Session configuration and engine
    /// start happen lazily in `loadTracks`/`startRecording`, right before they're needed.
    init() {
        self.engine = AVAudioEngine()
    }

    // MARK: - Track Loading Engine Graph

    func loadTracks(_ tracks: [Track]) async throws -> [Track] {
        tearDown()
        try configureAudioSession()

        let updatedTracks = tracks.map { wireTrack($0) }

        // Touching mainMixerNode forces AVAudioEngine to lazily create its I/O nodes.
        // Skipping this and calling start() on a graph that has never had a node
        // touched (e.g. an empty project where every clip failed to load) crashes
        // natively with "inputNode != nullptr || outputNode != nullptr" instead of
        // throwing a catchable Swift error — this isn't optional.
        _ = engine.mainMixerNode
        try engine.start()
        return updatedTracks
    }

    /// Wires one additional track into the live graph (a just-finished recording
    /// take) without tearing everything down and rebuilding — playback, the
    /// playhead, and every other track's state carry on untouched.
    func addTrack(_ track: Track) throws -> Track {
        let wired = wireTrack(track)
        if !engine.isRunning {
            _ = engine.mainMixerNode
            try engine.start()
        }
        return wired
    }

    /// Attaches player nodes for every playable clip in `track` and connects them
    /// into the graph (through the track's effects chain when applicable). Returns
    /// the track with clip durations filled in from the audio files, and extends
    /// the engine `duration` to cover them.
    private func wireTrack(_ track: Track) -> Track {
        var updatedTrack = track

        for (clipIndex, clip) in track.clips.enumerated() {
            guard let audioFile = try? AVAudioFile(forReading: clip.url) else { continue }
            let audioFormat = audioFile.processingFormat

            guard audioFormat.sampleRate > 0, audioFormat.channelCount > 0 else { continue }

            let fileDuration = Double(audioFile.length) / audioFormat.sampleRate
            guard fileDuration > 0 else { continue }

            let playerNode = AVAudioPlayerNode()
            playerNode.volume = track.volume
            engine.attach(playerNode)

            if track.effectsApplicable {
                let chain = effectsChain(for: track.id, format: audioFormat)
                engine.connect(playerNode, to: chain.input, format: audioFormat)
            } else {
                engine.connect(playerNode, to: engine.mainMixerNode, format: audioFormat)
            }

            var updatedClip = clip
            updatedClip.duration = fileDuration
            updatedTrack.clips[clipIndex] = updatedClip

            loadedClips.append(LoadedClip(
                trackID: track.id,
                clip: updatedClip,
                player: playerNode,
                file: audioFile,
                sampleRate: audioFormat.sampleRate
            ))

            duration = max(duration, updatedClip.timelineEnd)
        }

        if track.isMuted { mutedTrackIDs.insert(track.id) }
        if let chain = effectsChains[track.id] {
            applySettingsToChain(chain, settings: track.effects)
        }
        return updatedTrack
    }

    /// Returns the track's effects chain, creating and wiring it
    /// (input mixer → EQ → reverb → main mixer) on first use.
    private func effectsChain(for trackID: UUID, format: AVAudioFormat) -> EffectsChain {
        if let chain = effectsChains[trackID] { return chain }
        let chain = makeEffectsChain()
        effectsChains[trackID] = chain
        engine.attach(chain.input)
        engine.attach(chain.equalizer)
        engine.attach(chain.reverb)
        engine.connect(chain.input, to: chain.equalizer, format: format)
        engine.connect(chain.equalizer, to: chain.reverb, format: format)
        engine.connect(chain.reverb, to: engine.mainMixerNode, format: format)
        return chain
    }

    // MARK: - Transport Control API

    func play(from time: TimeInterval) throws {
        // Resuming the transport while a recording is paused resumes the capture
        // too — the recorder appends to the same file, and because the playhead was
        // frozen for exactly the paused span, file time and timeline time stay in
        // lockstep. This must happen before the empty-clips guard: a solo recording
        // (instant record with no backing track) has no clips to play.
        if isRecording, isRecordingPaused {
            audioRecorder?.record()
            isRecordingPaused = false
            recordAnchorWall = CACurrentMediaTime()
            recordAnchorTimeline = time
            startPolling()
        }

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
        if isRecording {
            // Pausing the transport pauses the capture too — otherwise the playhead
            // and the recorded file drift apart by however long the pause lasted.
            audioRecorder?.pause()
            isRecordingPaused = true
            recordAnchorWall = CACurrentMediaTime()
            recordAnchorTimeline = currentTime
            // Polling stays alive so resume picks up seamlessly.
        } else {
            stopPolling()
        }
    }

    func stop() {
        for loadedClip in loadedClips { loadedClip.player.stop() }
        isPlaying = false
        if !isRecording {
            currentTime = 0
            stopPolling()
        }
    }

    func seek(to time: TimeInterval) {
        // A take's timeline position is fixed the moment recording starts — moving
        // the playhead mid-recording would lie about where the audio will land.
        guard !isRecording else { return }
        let wasPlaying = isPlaying
        if wasPlaying { pause() }
        currentTime = max(0, min(time, duration))
        if wasPlaying { try? play(from: currentTime) }
    }

    func setMuted(_ muted: Bool, for trackID: UUID) {
        if muted {
            mutedTrackIDs.insert(trackID)
            loadedClips.filter { $0.trackID == trackID }.forEach { $0.player.stop() }
        } else {
            mutedTrackIDs.remove(trackID)
            if isPlaying {
                syncCurrentTime()
                let startTime = avAudioTime(secondsFromNow: 0.02)
                for loadedClip in loadedClips where loadedClip.trackID == trackID {
                    // scheduleClip starts the player itself — immediately at the
                    // anchor, or later if the clip begins further down the timeline.
                    // Calling play(at:) again here would override that delayed start
                    // and make future clips audible early.
                    scheduleClip(loadedClip, currentTime: currentTime, playAnchor: startTime)
                }
            }
        }
    }

    func applyEffects(_ settings: EffectSettings, to trackID: UUID) {
        guard let chain = effectsChains[trackID] else { return }
        applySettingsToChain(chain, settings: settings)
    }

    func setVolume(_ volume: Float, for trackID: UUID) {
        for loadedClip in loadedClips where loadedClip.trackID == trackID {
            loadedClip.player.volume = volume
        }
    }

    /// Syncs a moved/trimmed clip's data into the engine's own loaded-clip copy.
    /// Without this, moving or trimming a clip changes only what's drawn — the engine
    /// schedules playback from the copy it made back in `loadTracks`, which never
    /// otherwise hears about edits made afterward.
    func updateClip(_ clip: AudioClip, trackID: UUID) {
        guard let index = loadedClips.firstIndex(where: { $0.clip.id == clip.id && $0.trackID == trackID }) else { return }
        loadedClips[index].clip = clip
        duration = max(duration, clip.timelineEnd)
    }

    /// Removes a clip's player node from the graph entirely (deleting a recording).
    func removeClip(id clipID: UUID, trackID: UUID) {
        guard let index = loadedClips.firstIndex(where: { $0.clip.id == clipID && $0.trackID == trackID }) else { return }
        let loadedClip = loadedClips.remove(at: index)
        loadedClip.player.stop()
        engine.detach(loadedClip.player)
    }

    // MARK: - Recording Pipeline

    func startRecording(at timelineOffset: TimeInterval) async throws {
        guard !isRecording, !isStartingRecording else { return }
        isStartingRecording = true
        defer { isStartingRecording = false }

        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { throw AudioEngineError.microphonePermissionDenied }

        // Idempotent — startRecording must work even if loadTracks never ran (e.g. an
        // instant-record flow that starts recording before any playback is loaded).
        try configureAudioSession()

        // The permission prompt and session activation above can take real time
        // (seconds, if this is the first-ever mic request). If the timeline was
        // already rolling, the caller's offset is stale by exactly that much —
        // place the take where the playhead actually is now, not where it was
        // when the button was tapped.
        var effectiveOffset = timelineOffset
        if isPlaying {
            syncCurrentTime()
            effectiveOffset = currentTime
        }

        let recordingsDir = URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        let outputURL = recordingsDir.appendingPathComponent(UUID().uuidString + ".m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: outputURL, settings: settings)

        // Recording into nothing isn't how a timeline works — start the backing
        // track (if there is one) at the same moment, the same way tapping Play
        // does, rather than only ever capturing into silence.
        if !isPlaying { try? play(from: effectiveOffset) }

        // AVAudioRecorder and AVAudioEngine are separate Core Audio clients with
        // independent clocks — there is no API that starts them at a provably
        // identical instant (confirmed: this is a known, unsolved limitation per
        // Apple's own developer forums, not something fixable by trying harder
        // here). Best available mitigation: schedule the recorder's start on ITS
        // own hardware clock (deviceCurrentTime) with the same lookahead `play`
        // just used for the player nodes, so both are told to start relative to
        // "now + 20ms" instead of one starting immediately and the other lagging
        // behind by an unpredictable, uncoordinated amount.
        let lookahead = 0.02
        guard recorder.record(atTime: recorder.deviceCurrentTime + lookahead) else {
            throw AudioEngineError.microphoneFormatUnavailable
        }

        audioRecorder = recorder
        recordingURL = outputURL
        // Correct for the hardware's own capture latency (the gap between a sample
        // arriving at the mic and it actually showing up in the recorded file) so
        // the clip lands closer to where it was actually sung relative to the
        // backing track, not just where the playhead was when record() was called.
        recordingTimelineOffset = effectiveOffset + AVAudioSession.sharedInstance().inputLatency
        recordAnchorWall = CACurrentMediaTime()
        recordAnchorTimeline = effectiveOffset
        activeRecordingStart = effectiveOffset
        isRecording = true
        isRecordingPaused = false
        startPolling()   // advances currentTime in real time even with no playback running
    }

    func finishRecording() throws -> AudioClip? {
        guard isRecording, let recorder = audioRecorder, let url = recordingURL else {
            isRecording = false
            isRecordingPaused = false
            activeRecordingStart = nil
            return nil
        }
        recorder.stop()
        audioRecorder = nil
        isRecording = false
        isRecordingPaused = false
        activeRecordingStart = nil

        // Re-derive duration from the written file rather than recorder.currentTime —
        // consistent with how every other clip's duration is read in this engine.
        let fileDuration = (try? AVAudioFile(forReading: url)).map {
            Double($0.length) / $0.processingFormat.sampleRate
        } ?? 0
        let clip = AudioClip(url: url, timelineOffset: recordingTimelineOffset, duration: fileDuration)
        recordingURL = nil
        return clip
    }

    // MARK: - Resource Cleanup

    func tearDown() {
        stopPolling()

        if isRecording {
            audioRecorder?.stop()
            audioRecorder = nil
            isRecording = false
            isRecordingPaused = false
            activeRecordingStart = nil
        }

        for loadedClip in loadedClips {
            loadedClip.player.stop()
            engine.detach(loadedClip.player)
        }
        loadedClips.removeAll()

        for (_, chain) in effectsChains {
            engine.detach(chain.input)
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

    // MARK: - Private Time Keeping & Logic Utilities

    private func scheduleClip(_ loadedClip: LoadedClip, currentTime: TimeInterval, playAnchor: AVAudioTime) {
        loadedClip.player.stop()
        guard loadedClip.clip.timelineEnd > currentTime else { return }

        let fileReadStartSeconds: TimeInterval
        let playerStartDelaySeconds: TimeInterval

        if loadedClip.clip.timelineOffset <= currentTime {
            fileReadStartSeconds = loadedClip.clip.trimStart + (currentTime - loadedClip.clip.timelineOffset)
            playerStartDelaySeconds = 0
        } else {
            fileReadStartSeconds = loadedClip.clip.trimStart
            playerStartDelaySeconds = loadedClip.clip.timelineOffset - currentTime
        }

        let startFrame = AVAudioFramePosition(fileReadStartSeconds * loadedClip.sampleRate)
        // Stop at the trimmed tail, not the physical end of the file.
        let trimmedEndSeconds = loadedClip.clip.duration - loadedClip.clip.trimEnd
        let endFrame = AVAudioFramePosition(trimmedEndSeconds * loadedClip.sampleRate)
        let availableFrames = min(loadedClip.file.length, endFrame) - startFrame
        let remainingFrames = AVAudioFrameCount(max(0, availableFrames))
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

    private func syncCurrentTime() {
        if isPlaying {
            let elapsed = CACurrentMediaTime() - playAnchorWall
            currentTime = min(playAnchorTimeline + max(0, elapsed), duration)
        } else if isRecording, !isRecordingPaused {
            // No playback clock to follow while recording solo (e.g. instant-record with
            // no backing track) — advance from wall-clock instead, so the playhead still
            // visibly moves. Let duration grow with it so the ruler/scroll width keeps up.
            // While the recording is paused, the playhead holds still (the recorder is
            // paused too, so file time and timeline time stay matched).
            let elapsed = CACurrentMediaTime() - recordAnchorWall
            currentTime = recordAnchorTimeline + max(0, elapsed)
            duration = max(duration, currentTime)
        }
    }

    private func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                self.syncCurrentTime()
                if self.isPlaying, self.duration > 0, self.currentTime >= self.duration {
                    self.isPlaying = false
                }
                if !self.isPlaying && !self.isRecording { break }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func makeEffectsChain() -> EffectsChain {
        let equalizer = AVAudioUnitEQ(numberOfBands: 4)
        for index in 0..<4 {
            equalizer.bands[index].filterType = .parametric
            equalizer.bands[index].frequency = [80.0, 500.0, 2000.0, 8000.0][index]
            equalizer.bands[index].bandwidth = 1.0
            equalizer.bands[index].gain = 0
            equalizer.bands[index].bypass = false
        }
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 15
        return EffectsChain(input: AVAudioMixerNode(), equalizer: equalizer, reverb: reverb)
    }

    private func applySettingsToChain(_ chain: EffectsChain, settings: EffectSettings) {
        chain.reverb.wetDryMix = settings.reverbMix
        for (index, gain) in settings.eqGains.enumerated() where index < chain.equalizer.bands.count {
            chain.equalizer.bands[index].gain = gain
        }
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audioSession.setActive(true)
    }

    private func avAudioTime(secondsFromNow delay: TimeInterval) -> AVAudioTime {
        AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: delay))
    }
}

// MARK: - Error Handling Architecture

enum AudioEngineError: LocalizedError {
    case microphonePermissionDenied
    case microphoneFormatUnavailable

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access was denied. Go to Settings and enable Microphone access."
        case .microphoneFormatUnavailable:
            return "Could not start the microphone. Check that no other app is using it, then try again."
        }
    }
}
