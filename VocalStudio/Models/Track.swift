import Foundation

/// Runtime-only editor track. Built from a Project's stems + recordings when the editor opens.
/// Not persisted directly — the underlying Project data is the source of truth.
struct Track: Identifiable {
    enum Kind: Equatable {
        case instrumental
        case vocal
        case userRecording(index: Int)

        var isUserRecording: Bool {
            if case .userRecording = self { return true }
            return false
        }

        var effectsApplicable: Bool {
            switch self {
            case .vocal, .userRecording: return true
            case .instrumental: return false
            }
        }

        var displayIcon: String {
            switch self {
            case .instrumental: return "music.note.list"
            case .vocal:        return "music.mic"
            case .userRecording: return "waveform.circle"
            }
        }
    }

    let id: UUID
    var name: String
    var kind: Kind
    var clips: [AudioClip]
    var isMuted: Bool = false
    var volume: Float = 1.0
    var effects: EffectSettings = .default

    var effectsApplicable: Bool { kind.effectsApplicable }

    // MARK: - Factory

    /// Builds the initial track list from a project.
    /// Durations are zero until the audio engine loads them.
    ///
    /// `existingRecordingTracks`: pass the in-memory list when rebuilding within an
    /// already-open editor session (e.g. after adding a take or separating stems) —
    /// that's the freshest source. Pass `nil` (the default) for a freshly-opened
    /// editor with no in-memory state yet; recording tracks are then reconstructed
    /// from `project.recordings` instead, which is the only place they survive
    /// between sessions.
    static func buildTracks(from project: Project, existingRecordingTracks: [Track]? = nil) -> [Track] {
        var tracks: [Track] = []

        if project.stems.isEmpty {
            // No stem separation yet — single source track
            let clip = AudioClip(url: project.sourceURL, timelineOffset: 0)
            tracks.append(Track(
                id: UUID(),
                name: "Source",
                kind: .instrumental,
                clips: [clip]
            ))
        } else {
            for stem in project.stems {
                let clip = AudioClip(url: stem.url, timelineOffset: 0)
                let kind: Kind = stem.kind == .instrumental ? .instrumental : .vocal
                tracks.append(Track(
                    id: stem.id,
                    name: stem.kind == .instrumental ? "Instrumental" : "Vocals",
                    kind: kind,
                    clips: [clip],
                    isMuted: stem.isMuted
                ))
            }
        }

        if let existingRecordingTracks {
            tracks.append(contentsOf: existingRecordingTracks)
        } else {
            for (index, recording) in project.recordings.enumerated() {
                let clip = AudioClip(
                    url: recording.url,
                    timelineOffset: recording.timelineOffset,
                    trimStart: recording.trimStart,
                    trimEnd: recording.trimEnd
                )
                tracks.append(Track(
                    id: UUID(),
                    name: "Take \(index + 1)",
                    kind: .userRecording(index: index),
                    clips: [clip]
                ))
            }
        }

        return tracks
    }
}
