import Foundation

/// A positioned audio clip on the project timeline.
/// `timelineOffset` is where the clip starts in seconds from the project's origin.
/// `trimStart` is the in-point within the source audio file.
struct AudioClip: Identifiable, Codable {
    let id: UUID
    let url: URL
    var timelineOffset: TimeInterval
    var duration: TimeInterval
    var trimStart: TimeInterval

    init(
        id: UUID = UUID(),
        url: URL,
        timelineOffset: TimeInterval = 0,
        duration: TimeInterval = 0,
        trimStart: TimeInterval = 0
    ) {
        self.id = id
        self.url = url
        self.timelineOffset = timelineOffset
        self.duration = duration
        self.trimStart = trimStart
    }

    /// End time of this clip on the timeline.
    var timelineEnd: TimeInterval { timelineOffset + (duration - trimStart) }
}
