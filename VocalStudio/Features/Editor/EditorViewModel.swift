import Foundation
import Observation

enum StemSeparationStatus: Equatable {
    case idle
    case running(Double)  // 0.0–1.0
    case done
    case failed(String)
}

@Observable
final class EditorViewModel {

    // MARK: - Project + tracks

    private(set) var project: Project
    private(set) var tracks: [Track] = []
    var selectedTrackID: UUID?

    // MARK: - Transport state

    private(set) var isPlaying = false
    private(set) var isRecording = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    // MARK: - Stem separation

    private(set) var stemStatus: StemSeparationStatus = .idle

    // MARK: - Misc

    var errorMessage: String?

    // MARK: - Private

    @ObservationIgnored private let engine = MultiTrackEngine()
    @ObservationIgnored private let stemSeparator: StemSeparationService
    @ObservationIgnored private let store: ProjectStoreInterface
    @ObservationIgnored private var engineLoaded = false
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var recordingTracks: [Track] = []
    @ObservationIgnored private let autoStartRecording: Bool

    init(
        project: Project,
        store: ProjectStoreInterface,
        autoStartRecording: Bool = false,
        stemSeparator: StemSeparationService = CoreMLStemSeparator()
    ) {
        self.project = project
        self.store = store
        self.autoStartRecording = autoStartRecording
        self.stemSeparator = stemSeparator
        self.tracks = Track.buildTracks(from: project)
        // Seed in-memory tracking with whatever buildTracks just reconstructed from
        // project.recordings, so a later in-session rebuild (a new take, a stem
        // separation) keeps these instead of only ever keeping takes recorded
        // after this launch.
        self.recordingTracks = self.tracks.filter { $0.kind.isUserRecording }
        // A fresh EditorViewModel is created every time this project is opened, but
        // separation already happened in a previous session if stems are persisted —
        // without this, stemStatus always restarts at .idle and "Separate" reappears,
        // re-running on project.sourceURL (the original, pre-split file) instead of
        // being a no-op like it should be.
        self.stemStatus = project.stems.isEmpty ? .idle : .done
    }

    // MARK: - Lifecycle (called from EditorView .task)

    func start() async {
        await loadEngine()
        startPolling()
        if autoStartRecording {
            toggleRecording()
        }
    }

    func tearDown() {
        pollingTask?.cancel()
        pollingTask = nil
        engine.tearDown()
    }

    // MARK: - Transport

    func togglePlayback() {
        if isPlaying {
            engine.pause()
        } else {
            do {
                try engine.play(from: currentTime)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func rewind() {
        engine.seek(to: 0)
        currentTime = 0
    }

    func seek(to time: TimeInterval) {
        engine.seek(to: time)
    }

    // MARK: - Recording

    func toggleRecording() {
        if isRecording {
            do {
                if let clip = try engine.finishRecording() {
                    addRecordingClip(clip)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            Task {
                do {
                    try await engine.startRecording(at: currentTime)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Track control

    func toggleMute(trackID: UUID) {
        guard let i = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[i].isMuted.toggle()
        engine.setMuted(tracks[i].isMuted, for: trackID)
    }

    func selectTrack(_ trackID: UUID) {
        selectedTrackID = selectedTrackID == trackID ? nil : trackID
    }

    func deselectTrack() {
        selectedTrackID = nil
    }

    var selectedTrack: Track? {
        guard let id = selectedTrackID else { return nil }
        return tracks.first { $0.id == id }
    }

    // MARK: - Volume (every track, regardless of effects-applicability)

    func updateVolume(_ volume: Float) {
        guard let id = selectedTrackID, let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[i].volume = volume
        engine.setVolume(volume, for: id)
    }

    // MARK: - Effects (apply to selected track)

    func updateReverb(_ mix: Float) {
        guard let id = selectedTrackID, let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[i].effects = tracks[i].effects.withReverb(mix)
        engine.applyEffects(tracks[i].effects, to: id)
    }

    func updateEQGain(_ gain: Float, at band: Int) {
        guard let id = selectedTrackID, let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[i].effects = tracks[i].effects.withEQGain(gain, at: band)
        engine.applyEffects(tracks[i].effects, to: id)
    }

    // MARK: - Clip editing (user recording clips only)

    func moveClip(id clipID: UUID, inTrack trackID: UUID, to newOffset: TimeInterval) {
        guard let ti = tracks.firstIndex(where: { $0.id == trackID }),
              let ci = tracks[ti].clips.firstIndex(where: { $0.id == clipID }) else { return }
        tracks[ti].clips[ci].timelineOffset = max(0, newOffset)
        engine.updateClip(tracks[ti].clips[ci], trackID: trackID)
        persistRecordingMetadata(for: tracks[ti].clips[ci])
    }

    func trimClip(id clipID: UUID, inTrack trackID: UUID, trimStart: TimeInterval, trimEnd: TimeInterval, timelineOffset: TimeInterval) {
        guard let ti = tracks.firstIndex(where: { $0.id == trackID }),
              let ci = tracks[ti].clips.firstIndex(where: { $0.id == clipID }) else { return }
        tracks[ti].clips[ci].trimStart = trimStart
        tracks[ti].clips[ci].trimEnd = trimEnd
        tracks[ti].clips[ci].timelineOffset = timelineOffset
        engine.updateClip(tracks[ti].clips[ci], trackID: trackID)
        persistRecordingMetadata(for: tracks[ti].clips[ci])
    }

    /// Keeps the persisted `Recording` entry for a `.userRecording` clip in sync
    /// with its current position/trim, so a move or trim survives reopening the
    /// project — without this, edits only ever lived in the in-memory `tracks`
    /// array and silently reverted on the next fresh launch.
    private func persistRecordingMetadata(for clip: AudioClip) {
        guard let index = project.recordings.firstIndex(where: { $0.url == clip.url }) else { return }
        var recordings = project.recordings
        recordings[index].timelineOffset = clip.timelineOffset
        recordings[index].trimStart = clip.trimStart
        recordings[index].trimEnd = clip.trimEnd
        project = project.withRecordings(recordings)
        Task { try? await store.save(project) }
    }

    /// Deletes a recorded take. If that was the track's only clip, the now-empty
    /// track is removed too — an empty `.userRecording` row has nothing to show.
    func deleteClip(id clipID: UUID, inTrack trackID: UUID) {
        guard let ti = tracks.firstIndex(where: { $0.id == trackID }),
              let ci = tracks[ti].clips.firstIndex(where: { $0.id == clipID }) else { return }
        let deletedURL = tracks[ti].clips[ci].url
        tracks[ti].clips.remove(at: ci)
        engine.removeClip(id: clipID, trackID: trackID)

        if tracks[ti].clips.isEmpty {
            tracks.remove(at: ti)
            recordingTracks.removeAll { $0.id == trackID }
            if selectedTrackID == trackID { selectedTrackID = nil }
        }

        project = project.withRecordings(project.recordings.filter { $0.url != deletedURL })
        Task { try? await store.save(project) }
    }

    // MARK: - Project title

    func renameProject(to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != project.title else { return }
        project = project.withTitle(trimmed)
        Task { try? await store.save(project) }
    }

    // MARK: - Stem separation

    func startStemSeparation() {
        guard stemStatus == .idle else { return }
        stemStatus = .running(0)

        Task {
            do {
                let result = try await stemSeparator.separate(
                    sourceURL: project.sourceURL,
                    onProgress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            switch progress {
                            case .loading:          self?.stemStatus = .running(0)
                            case .processing(let p): self?.stemStatus = .running(p)
                            case .done:             break
                            }
                        }
                    }
                )
                await integrateStemResult(result)
            } catch {
                await MainActor.run { [weak self] in
                    self?.stemStatus = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Private helpers

    private func loadEngine() async {
        do {
            let updatedTracks = try await engine.loadTracks(tracks)
            tracks = updatedTracks
            duration = engine.duration
            engineLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                self.currentTime = self.engine.currentTime
                self.isPlaying = self.engine.isPlaying
                self.isRecording = self.engine.isRecording
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func addRecordingClip(_ clip: AudioClip) {
        let index = recordingTracks.count
        let newTrack = Track(
            id: UUID(),
            name: "Take \(index + 1)",
            kind: .userRecording(index: index),
            clips: [clip]
        )
        tracks.append(newTrack)
        recordingTracks.append(newTrack)

        // Persist the full clip position (not just the URL) so it survives app
        // restarts and reopening the project — see Track.buildTracks.
        let recording = Recording(
            url: clip.url,
            timelineOffset: clip.timelineOffset,
            trimStart: clip.trimStart,
            trimEnd: clip.trimEnd
        )
        project = project.withRecording(recording)
        Task { try? await store.save(project) }

        Task { await loadEngine() }
    }

    @MainActor
    private func integrateStemResult(_ result: StemSeparationResult) async {
        let vocalStem  = Stem(id: UUID(), kind: .vocal,        url: result.vocalURL,        isMuted: false)
        let instrStem  = Stem(id: UUID(), kind: .instrumental, url: result.instrumentalURL, isMuted: false)
        project = Project(
            id: project.id, title: project.title, sourceURL: project.sourceURL,
            createdAt: project.createdAt, stems: [instrStem, vocalStem],
            recordings: project.recordings, effects: project.effects
        )
        tracks = Track.buildTracks(from: project, existingRecordingTracks: recordingTracks)
        stemStatus = .done
        // Persist stem URLs so the editor reloads them on next launch
        try? await store.save(project)
        await loadEngine()
    }
}
