import Foundation

/// A persisted reference to one of the user's own recorded takes — enough to
/// faithfully rebuild the `.userRecording` `Track`/`AudioClip` it came from when a
/// project is reopened fresh (no in-memory `Track` state to fall back on).
struct Recording: Identifiable, Codable {
    let id: UUID
    let url: URL
    let createdAt: Date
    var timelineOffset: TimeInterval
    var trimStart: TimeInterval
    var trimEnd: TimeInterval

    init(
        id: UUID = UUID(),
        url: URL,
        createdAt: Date = .now,
        timelineOffset: TimeInterval = 0,
        trimStart: TimeInterval = 0,
        trimEnd: TimeInterval = 0
    ) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
        self.timelineOffset = timelineOffset
        self.trimStart = trimStart
        self.trimEnd = trimEnd
    }

    // Custom decoding so projects.json written before timelineOffset/trimStart/
    // trimEnd existed still loads — missing keys default to 0 instead of failing
    // the decode (which would otherwise blank out the whole project list).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        timelineOffset = try container.decodeIfPresent(TimeInterval.self, forKey: .timelineOffset) ?? 0
        trimStart = try container.decodeIfPresent(TimeInterval.self, forKey: .trimStart) ?? 0
        trimEnd = try container.decodeIfPresent(TimeInterval.self, forKey: .trimEnd) ?? 0
    }
}
