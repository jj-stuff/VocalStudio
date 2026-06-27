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
    static func buildTracks(from project: Project, existingRecordingTracks: [Track] = []) -> [Track] {
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

        // Re-attach any existing recording takes
        tracks.append(contentsOf: existingRecordingTracks)

        return tracks
    }
}
