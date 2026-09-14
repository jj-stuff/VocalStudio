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
            // No stem separation yet — single source track. Instant-record projects
            // have only a generated silent placeholder as their source; showing that
            // as a track put a fake 1-second clip on screen for no reason.
            if !project.hasSilentPlaceholderSource {
                let clip = AudioClip(url: project.sourceURL, timelineOffset: 0)
                tracks.append(Track(
                    id: UUID(),
                    name: String(localized: "Source"),
                    kind: .instrumental,
                    clips: [clip]
                ))
            }
        } else {
            for stem in project.stems {
                let clip = AudioClip(url: stem.url, timelineOffset: 0)
                let kind: Kind = stem.kind == .instrumental ? .instrumental : .vocal
                tracks.append(Track(
                    id: stem.id,
                    name: stem.kind == .instrumental ? String(localized: "Instrumental") : String(localized: "Vocals"),
                    kind: kind,
                    clips: [clip],
                    isMuted: stem.isMuted
                ))
            }
        }

        if let existingRecordingTracks {
            tracks.append(contentsOf: existingRecordingTracks)
        } else {
            tracks.append(contentsOf: recordingTracks(from: project.recordings))
        }

        return tracks
    }

    /// One track per take, in first-appearance order, holding every clip that shares
    /// the take's `takeID` (a split take is several recordings on one track).
    static func recordingTracks(from recordings: [Recording]) -> [Track] {
        var order: [UUID] = []
        var clipsByTake: [UUID: [AudioClip]] = [:]
        for recording in recordings {
            if clipsByTake[recording.takeID] == nil { order.append(recording.takeID) }
            clipsByTake[recording.takeID, default: []].append(recording.clip)
        }
        return order.enumerated().map { index, takeID in
            Track(
                id: takeID,
                name: String(localized: "Take \(index + 1)"),
                kind: .userRecording(index: index),
                clips: (clipsByTake[takeID] ?? []).sorted { $0.timelineOffset < $1.timelineOffset }
            )
        }
    }
}
