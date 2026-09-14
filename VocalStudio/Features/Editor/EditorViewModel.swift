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
    /// The clip with the editing handles and the Split/Delete bar. Only the user's
    /// own recordings can be selected — imported and separated audio is locked.
    var selectedClipID: UUID?

    // MARK: - Transport state

    private(set) var isPlaying = false
    private(set) var isRecording = false
    private(set) var isRecordingPaused = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    /// What the play/pause button reflects and toggles: audible playback, or a
    /// recording that is actively capturing. A paused recording counts as paused.
    var transportActive: Bool {
        isPlaying || (isRecording && !isRecordingPaused)
    }

    /// Timeline span of the in-flight recording — drives the live red lane in the
    /// timeline while capturing, so the take is visible before it's finished.
    var recordingRange: ClosedRange<TimeInterval>? {
        guard isRecording, let start = engine.activeRecordingStart else { return nil }
        return start...max(start, currentTime)
    }

    /// Instant-record projects have only a silent placeholder source — nothing
    /// real to separate, so the editor hides the Separate button entirely.
    var canSeparateStems: Bool {
        !project.hasSilentPlaceholderSource
    }

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
        if transportActive {
            engine.pause()
        } else {
            do {
                // Play with the playhead parked at the very end restarts from the
                // top, instead of silently doing nothing until the user rewinds.
                // Never while recording: the playhead sits at the growing end the
                // whole time there, and resuming must continue, not restart.
                let atEnd = duration > 0 && currentTime >= duration && !isRecording
                try engine.play(from: atEnd ? 0 : currentTime)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func rewind() {
        // The engine ignores seeks while recording (the take's position is fixed);
        // don't zero the local playhead either or it flickers for a poll tick.
        guard !isRecording else { return }
        engine.seek(to: 0)
        currentTime = 0
    }

    func seek(to time: TimeInterval) {
        engine.seek(to: time)
    }

    // MARK: - Scrubbing
    //
    // The timeline scrolls under a fixed playhead, so a scroll *is* a scrub. While
    // the user's finger is down (or the scroll is decelerating) playback pauses and
    // every offset change lands here; when the scroll settles, playback resumes
    // from wherever it stopped if it was running before.

    @ObservationIgnored private var resumeAfterScrub = false

    func beginScrub() {
        guard !isRecording else { return }
        resumeAfterScrub = isPlaying
        if isPlaying { engine.pause() }
    }

    func scrub(to time: TimeInterval) {
        guard !isRecording else { return }
        let clamped = time.clamped(to: 0...max(0, duration))
        // Set locally first so the readout follows the finger with zero lag; the
        // poll tick will confirm the same value from the engine a frame later.
        currentTime = clamped
        engine.seek(to: clamped)
    }

    func endScrub() {
        guard resumeAfterScrub else { return }
        resumeAfterScrub = false
        try? engine.play(from: currentTime)
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

    // MARK: - Clip selection

    var selectedClip: (track: Track, clip: AudioClip)? {
        guard let clipID = selectedClipID else { return nil }
        for track in tracks {
            if let clip = track.clips.first(where: { $0.id == clipID }) { return (track, clip) }
        }
        return nil
    }

    func selectClip(_ clipID: UUID?) {
        selectedClipID = clipID
    }

    /// Split is only offered when the playhead is strictly inside the selected
    /// clip — splitting at either end would leave a zero-length piece.
    var canSplitSelectedClip: Bool {
        guard let clip = selectedClip?.clip else { return false }
        let inset = 0.05
        return currentTime > clip.timelineOffset + inset && currentTime < clip.timelineEnd - inset
    }

    // MARK: - Clip editing (user recording clips only)

    func moveClip(id clipID: UUID, inTrack trackID: UUID, to newOffset: TimeInterval) {
        guard let ti = tracks.firstIndex(where: { $0.id == trackID }),
              let ci = tracks[ti].clips.firstIndex(where: { $0.id == clipID }) else { return }
        tracks[ti].clips[ci].timelineOffset = max(0, newOffset)
        commitEdit(to: tracks[ti].clips[ci], trackID: trackID)
    }

    func trimClip(id clipID: UUID, inTrack trackID: UUID, trimStart: TimeInterval, trimEnd: TimeInterval, timelineOffset: TimeInterval) {
        guard let ti = tracks.firstIndex(where: { $0.id == trackID }),
              let ci = tracks[ti].clips.firstIndex(where: { $0.id == clipID }) else { return }
        tracks[ti].clips[ci].trimStart = trimStart
        tracks[ti].clips[ci].trimEnd = trimEnd
        tracks[ti].clips[ci].timelineOffset = timelineOffset
        commitEdit(to: tracks[ti].clips[ci], trackID: trackID)
    }

    /// Cuts the selected clip at the playhead into two clips on the same track.
    /// Both halves keep pointing at the same file — the left one gains a tail trim,
    /// the right one a head trim — so nothing is re-encoded and the cut is exact.
    func splitSelectedClip() {
        guard canSplitSelectedClip,
              let selection = selectedClip,
              let ti = tracks.firstIndex(where: { $0.id == selection.track.id }),
              let ci = tracks[ti].clips.firstIndex(where: { $0.id == selection.clip.id }) else { return }

        let track = selection.track
        let clip = selection.clip
        let cutInClip = currentTime - clip.timelineOffset   // seconds into the trimmed clip

        var left = clip
        left.trimEnd = clip.duration - (clip.trimStart + cutInClip)

        var right = AudioClip(
            url: clip.url,
            timelineOffset: currentTime,
            duration: clip.duration,
            trimStart: clip.trimStart + cutInClip,
            trimEnd: clip.trimEnd
        )

        tracks[ti].clips[ci] = left
        engine.updateClip(left, trackID: track.id)
        if let wired = engine.addClip(right, to: tracks[ti]) { right = wired }
        tracks[ti].clips.insert(right, at: ci + 1)
        engine.refreshPlayback()

        // Persist: update the left half in place, add the right half to the same take.
        var recordings = project.recordings
        if let index = recordings.firstIndex(where: { $0.id == left.id }) {
            recordings[index].trimEnd = left.trimEnd
            recordings.insert(
                Recording(id: right.id, url: right.url, takeID: track.id,
                          timelineOffset: right.timelineOffset, trimStart: right.trimStart, trimEnd: right.trimEnd),
                at: index + 1
            )
        }
        project = project.withRecordings(recordings)
        Task { try? await store.save(project) }

        // Keep the piece under the playhead selected, which is the right half.
        selectedClipID = right.id
    }

    func deleteSelectedClip() {
        guard let selection = selectedClip else { return }
        deleteClip(id: selection.clip.id, inTrack: selection.track.id)
    }

    /// Pushes an edited clip to the engine and to disk. If the clip is sounding
    /// right now, playback is re-scheduled so what you hear matches what you see.
    private func commitEdit(to clip: AudioClip, trackID: UUID) {
        engine.updateClip(clip, trackID: trackID)
        duration = engine.duration
        engine.refreshPlayback()
        persistRecordingMetadata(for: clip)
    }

    /// Keeps the persisted `Recording` entry for a `.userRecording` clip in sync
    /// with its current position/trim, so a move or trim survives reopening the
    /// project — without this, edits only ever lived in the in-memory `tracks`
    /// array and silently reverted on the next fresh launch.
    private func persistRecordingMetadata(for clip: AudioClip) {
        guard let index = project.recordings.firstIndex(where: { $0.id == clip.id }) else { return }
        var recordings = project.recordings
        recordings[index].timelineOffset = clip.timelineOffset
        recordings[index].trimStart = clip.trimStart
        recordings[index].trimEnd = clip.trimEnd
        project = project.withRecordings(recordings)
        Task { try? await store.save(project) }
    }

    /// Deletes a recorded clip. If that was the track's only clip, the now-empty
    /// track is removed too — an empty `.userRecording` row has nothing to show.
    func deleteClip(id clipID: UUID, inTrack trackID: UUID) {
        guard let ti = tracks.firstIndex(where: { $0.id == trackID }),
              let ci = tracks[ti].clips.firstIndex(where: { $0.id == clipID }) else { return }
        tracks[ti].clips.remove(at: ci)
        engine.removeClip(id: clipID, trackID: trackID)
        if selectedClipID == clipID { selectedClipID = nil }

        if tracks[ti].clips.isEmpty {
            tracks.remove(at: ti)
            recordingTracks.removeAll { $0.id == trackID }
            if selectedTrackID == trackID { selectedTrackID = nil }
        } else {
            recordingTracks = tracks.filter { $0.kind.isUserRecording }
        }

        project = project.withRecordings(project.recordings.filter { $0.id != clipID })
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
                // The engine's duration grows live while recording runs past the end
                // of the project — without mirroring it, the timeline never widens
                // and the playhead runs straight off the visible ruler.
                self.duration = self.engine.duration
                self.isPlaying = self.engine.isPlaying
                self.isRecording = self.engine.isRecording
                self.isRecordingPaused = self.engine.isRecordingPaused
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func addRecordingClip(_ clip: AudioClip) {
        let index = recordingTracks.count
        // The track's id is the take id; the clip's id is the recording's id. Both
        // round-trip through `Recording` so a reopened project rebuilds the same
        // tracks and clips (see Track.recordingTracks).
        var newTrack = Track(
            id: clip.id,
            name: String(localized: "Take \(index + 1)"),
            kind: .userRecording(index: index),
            clips: [clip]
        )

        // Wire just this one track into the live graph — a full loadTracks reload
        // here would stop playback and snap the playhead back to zero every time
        // a take finished.
        do {
            newTrack = try engine.addTrack(newTrack)
            duration = engine.duration
        } catch {
            errorMessage = error.localizedDescription
        }
        tracks.append(newTrack)
        recordingTracks.append(newTrack)

        // Persist the full clip position (not just the URL) so it survives app
        // restarts and reopening the project — see Track.buildTracks.
        let recording = Recording(
            id: clip.id,
            url: clip.url,
            takeID: newTrack.id,
            timelineOffset: clip.timelineOffset,
            trimStart: clip.trimStart,
            trimEnd: clip.trimEnd
        )
        project = project.withRecording(recording)
        Task { try? await store.save(project) }
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
        // Carry the live recording tracks over (they may have been trimmed, moved or
        // split since `recordingTracks` was last refreshed) — `tracks` is freshest.
        recordingTracks = tracks.filter { $0.kind.isUserRecording }
        tracks = Track.buildTracks(from: project, existingRecordingTracks: recordingTracks)
        stemStatus = .done
        // Persist stem URLs so the editor reloads them on next launch
        try? await store.save(project)
        await loadEngine()
    }
}
