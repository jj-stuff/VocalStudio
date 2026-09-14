import Foundation

/// A persisted reference to one clip of the user's own recorded audio — enough to
/// faithfully rebuild the `.userRecording` `Track`/`AudioClip` it came from when a
/// project is reopened fresh (no in-memory `Track` state to fall back on).
///
/// `id` doubles as the clip's id in the editor, so edits round-trip by id rather
/// than by file URL. `takeID` groups clips onto one track: splitting a take at the
/// playhead produces two `Recording`s with the same `takeID` and the same `url`,
/// each pointing at a different slice of that file.
struct Recording: Identifiable, Codable {
    let id: UUID
    let url: URL
    let createdAt: Date
    /// Which track (take) this clip belongs to. Equals `id` for an unsplit take.
    let takeID: UUID
    var timelineOffset: TimeInterval
    var trimStart: TimeInterval
    var trimEnd: TimeInterval

    init(
        id: UUID = UUID(),
        url: URL,
        createdAt: Date = .now,
        takeID: UUID? = nil,
        timelineOffset: TimeInterval = 0,
        trimStart: TimeInterval = 0,
        trimEnd: TimeInterval = 0
    ) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
        self.takeID = takeID ?? id
        self.timelineOffset = timelineOffset
        self.trimStart = trimStart
        self.trimEnd = trimEnd
    }

    /// Builds the editor clip for this recording. `duration` is filled in later by
    /// the audio engine once it has opened the file.
    var clip: AudioClip {
        AudioClip(id: id, url: url, timelineOffset: timelineOffset, trimStart: trimStart, trimEnd: trimEnd)
    }

    // Custom decoding so projects.json written before these keys existed still
    // loads — missing keys fall back to sensible defaults instead of failing the
    // decode (which would otherwise blank out the whole project list).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        takeID = try container.decodeIfPresent(UUID.self, forKey: .takeID) ?? id
        timelineOffset = try container.decodeIfPresent(TimeInterval.self, forKey: .timelineOffset) ?? 0
        trimStart = try container.decodeIfPresent(TimeInterval.self, forKey: .trimStart) ?? 0
        trimEnd = try container.decodeIfPresent(TimeInterval.self, forKey: .trimEnd) ?? 0
    }
}
