import CoreGraphics
import Foundation

/// The one place the timeline converts between seconds and points. Every view in
/// the editor asks this instead of multiplying by its own copy of the zoom, so the
/// ruler, the clips, the playhead and the scroll offset can't drift apart.
///
/// The model is a fixed playhead: the playhead never moves on screen, the content
/// scrolls under it. So `contentOffset == seconds(currentTime)`, and the content
/// gets `viewportWidth` worth of padding split around it so time 0 and the end of
/// the project can both reach the playhead.
struct TimelineGeometry: Equatable {
    /// Horizontal zoom.
    var pixelsPerSecond: CGFloat
    /// Width of the scrolling area (the screen minus the fixed track-header column).
    var viewportWidth: CGFloat
    /// Length of the project. The content is padded past this so there is room to
    /// record or drag a clip beyond the current end.
    var duration: TimeInterval

    static let zoomRange: ClosedRange<CGFloat> = 12...400
    static let defaultZoom: CGFloat = 60

    /// Where the playhead sits inside the viewport, as a fraction of its width.
    /// Slightly left of centre: more of what is *coming* is visible than what has
    /// already played, which is what you want while recording or scrubbing forward.
    static let playheadFraction: CGFloat = 0.4

    /// Extra seconds of room past the end of the project.
    private var tailSeconds: TimeInterval { max(15, duration * 0.25) }

    // MARK: - Positions

    var playheadX: CGFloat { (viewportWidth * Self.playheadFraction).rounded() }
    var leadingPadding: CGFloat { playheadX }
    var trailingPadding: CGFloat { max(0, viewportWidth - playheadX) }

    /// Width of the timeline itself (ruler, lanes), excluding the two paddings.
    var timelineWidth: CGFloat { x(duration + tailSeconds) }
    /// The full scrollable content width.
    var contentWidth: CGFloat { leadingPadding + timelineWidth + trailingPadding }

    /// The furthest the content can scroll — the padded end reaching the playhead.
    var maxOffset: CGFloat { timelineWidth }

    // MARK: - Conversions

    func x(_ time: TimeInterval) -> CGFloat { CGFloat(time) * pixelsPerSecond }
    func time(atX x: CGFloat) -> TimeInterval { TimeInterval(x / pixelsPerSecond) }

    /// Scroll offset that puts `time` under the playhead.
    func offset(for time: TimeInterval) -> CGFloat { x(max(0, time)) }
    /// Time under the playhead for a given scroll offset.
    func time(forOffset offset: CGFloat) -> TimeInterval { max(0, time(atX: offset)) }

    // MARK: - Zoom

    func zoomed(by factor: CGFloat) -> TimelineGeometry {
        var copy = self
        copy.pixelsPerSecond = (pixelsPerSecond * factor).clamped(to: Self.zoomRange)
        return copy
    }

    // MARK: - Ruler

    /// Seconds between ruler ticks at the current zoom — chosen so major labels
    /// stay roughly 80–160pt apart and remain readable.
    var tickInterval: TimeInterval {
        switch pixelsPerSecond {
        case ..<20:  10
        case ..<45:  5
        case ..<110: 2
        case ..<220: 1
        default:     0.5
        }
    }
}

// MARK: - Snapping

/// Pulls a dragged edge onto nearby landmarks (project start, the playhead, other
/// clip edges) when it comes within `threshold` points. Returns the snapped time
/// and which landmark won, so the view can fire a haptic when the target changes.
struct TimelineSnapper {
    enum Target: Equatable {
        case start
        case playhead
        case clipEdge(UUID)
    }

    let geometry: TimelineGeometry
    let playheadTime: TimeInterval
    /// Edges of every *other* clip, tagged with the clip they belong to.
    let clipEdges: [(clipID: UUID, time: TimeInterval)]
    var threshold: CGFloat = 10

    func snap(_ time: TimeInterval) -> (time: TimeInterval, target: Target?) {
        var candidates: [(Target, TimeInterval)] = [(.start, 0), (.playhead, playheadTime)]
        candidates += clipEdges.map { (.clipEdge($0.clipID), $0.time) }

        var best: (Target, TimeInterval, CGFloat)?
        for (target, candidate) in candidates {
            let distance = abs(geometry.x(candidate) - geometry.x(time))
            guard distance <= threshold else { continue }
            if best == nil || distance < best!.2 { best = (target, candidate, distance) }
        }
        if let best { return (best.1, best.0) }
        return (time, nil)
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        // Swift.min/max, fully qualified — inside an extension on CGFloat, the bare
        // names resolve to CGFloat's own static members instead of the global
        // comparison functions.
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension TimeInterval {
    func clamped(to range: ClosedRange<TimeInterval>) -> TimeInterval {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
