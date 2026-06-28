import Foundation

/// A positioned audio clip on the project timeline.
/// `timelineOffset` is where the clip starts in seconds from the project's origin.
/// `trimStart`/`trimEnd` are how much is cut from the head/tail of the source file —
/// `duration` always stays the full underlying file length so waveform rendering and
/// re-trimming both have the original length to work from.
struct AudioClip: Identifiable, Codable {
    let id: UUID
    let url: URL
    var timelineOffset: TimeInterval
    var duration: TimeInterval
    var trimStart: TimeInterval
    var trimEnd: TimeInterval

    init(
        id: UUID = UUID(),
        url: URL,
        timelineOffset: TimeInterval = 0,
        duration: TimeInterval = 0,
        trimStart: TimeInterval = 0,
        trimEnd: TimeInterval = 0
    ) {
        self.id = id
        self.url = url
        self.timelineOffset = timelineOffset
        self.duration = duration
        self.trimStart = trimStart
        self.trimEnd = trimEnd
    }

    /// Playable length after both trims.
    var trimmedDuration: TimeInterval { max(0, duration - trimStart - trimEnd) }

    /// End time of this clip on the timeline.
    var timelineEnd: TimeInterval { timelineOffset + trimmedDuration }
}
