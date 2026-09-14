import SwiftUI

/// One audio clip on a lane.
///
/// Interaction model (only for the user's own recordings — imported and separated
/// audio is locked):
/// - **Tap** selects the clip. Selection shows the trim handles and the Split/Delete
///   bar in the editor.
/// - **Drag a handle** trims that edge, live, with snapping to the project start,
///   the playhead and neighbouring clip edges.
/// - **Long-press, then drag** moves the clip. The press is what keeps a move from
///   colliding with the scroll-to-scrub gesture: a plain drag scrolls, a held drag
///   picks the clip up (the same rule Reminders uses for reordering).
///
/// Every gesture previews in local pixel state and commits seconds on release, so
/// the model only changes once per edit.
struct ClipView: View {
    let clip: AudioClip
    let trackKind: Track.Kind
    let geometry: TimelineGeometry
    let isSelected: Bool
    let isEditable: Bool
    /// Time under the playhead, for snapping.
    let playheadTime: TimeInterval
    /// Edges of the other clips on this track, for snapping.
    let neighbourEdges: [(clipID: UUID, time: TimeInterval)]
    let onSelect: () -> Void
    let onMove: (TimeInterval) -> Void
    /// (trimStart, trimEnd, timelineOffset) — offset only changes when trimming the
    /// leading edge, so the underlying source audio's absolute timing never shifts.
    let onTrim: (TimeInterval, TimeInterval, TimeInterval) -> Void

    private static let minimumClipLength: TimeInterval = 0.2
    private static let handleHitWidth: CGFloat = 44
    private static let cornerRadius: CGFloat = 8

    @State private var peaks: WaveformPeaks?
    @State private var dragOffsetPx: CGFloat = 0
    @State private var leadingTrimDeltaPx: CGFloat = 0
    @State private var trailingTrimDeltaPx: CGFloat = 0
    @State private var isLifted = false
    @State private var snapTarget: TimelineSnapper.Target?

    // MARK: - Derived layout

    private var pps: CGFloat { geometry.pixelsPerSecond }

    private var clipWidth: CGFloat {
        // Leading handle dragged right (+dx) shrinks from the left; trailing handle
        // dragged left (−dx) shrinks from the right. Both deltas are stored so that
        // subtracting them gives the previewed width.
        max(6, clip.trimmedDuration * pps - leadingTrimDeltaPx - trailingTrimDeltaPx)
    }

    private var snapper: TimelineSnapper {
        TimelineSnapper(geometry: geometry, playheadTime: playheadTime, clipEdges: neighbourEdges)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            clipBody
            if isEditable && isSelected {
                handles
            }
        }
        .frame(width: clipWidth)
        .offset(x: clip.timelineOffset * pps + dragOffsetPx + leadingTrimDeltaPx)
        .scaleEffect(isLifted ? 1.03 : 1, anchor: .center)
        .shadow(color: .black.opacity(isLifted ? 0.25 : 0), radius: 10, y: 4)
        .zIndex(isLifted ? 10 : (isSelected ? 5 : 0))
        .animation(DS.Animation.spring, value: isLifted)
        .animation(DS.Animation.smooth, value: isSelected)
        .onTapGesture(perform: onSelect)
        .highPriorityGesture(isEditable ? moveGesture : nil)
        .sensoryFeedback(.impact(weight: .medium), trigger: isLifted) { _, lifted in lifted }
        .sensoryFeedback(.alignment, trigger: snapTarget) { _, target in target != nil }
        .task(id: clip.url) {
            peaks = await WaveformCache.shared.peaks(for: clip.url)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    // MARK: - Body

    private var clipBody: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius)
            .fill(fill)
            .overlay {
                waveform
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .stroke(isSelected ? Color.white : Color.white.opacity(0.18), lineWidth: isSelected ? 2 : 0.5)
            }
            .contentShape(Rectangle())
    }

    // MARK: - Colour
    //
    // Dark, saturated fills so the white waveform always has contrast. Instrumental
    // and vocal stems are fixed hues; each take picks a stable colour from its id.

    private static let takePalette: [(top: Color, bottom: Color)] = [
        (Color(red: 0.30, green: 0.10, blue: 0.50), Color(red: 0.20, green: 0.06, blue: 0.36)),  // deep violet
        (Color(red: 0.55, green: 0.12, blue: 0.30), Color(red: 0.40, green: 0.08, blue: 0.22)),  // deep rose
        (Color(red: 0.05, green: 0.33, blue: 0.36), Color(red: 0.03, green: 0.23, blue: 0.26)),  // deep teal
        (Color(red: 0.12, green: 0.22, blue: 0.52), Color(red: 0.08, green: 0.15, blue: 0.38)),  // deep indigo
    ]

    private var fill: LinearGradient {
        let pair: (top: Color, bottom: Color)
        switch trackKind {
        case .instrumental:
            pair = (Color(red: 0.12, green: 0.18, blue: 0.40), Color(red: 0.08, green: 0.12, blue: 0.30))
        case .vocal:
            pair = (Color(red: 0.27, green: 0.08, blue: 0.42), Color(red: 0.18, green: 0.05, blue: 0.30))
        case .userRecording:
            // UUID bytes, not hashValue — hashValue is re-seeded every launch and
            // would recolour clips on each app start.
            let bytes = clip.id.uuid
            let folded = [bytes.0, bytes.1, bytes.2, bytes.3].reduce(0) { ($0 &* 31) &+ Int($1) }
            pair = Self.takePalette[abs(folded) % Self.takePalette.count]
        }
        return LinearGradient(colors: [pair.top, pair.bottom], startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Waveform

    /// Real peaks from the file, drawn as mirrored bars. While a trim handle is
    /// being dragged the visible window shifts live, so the bars stay glued to the
    /// audio rather than to the clip's edges.
    private var waveform: some View {
        let visibleStart = clip.trimStart + TimeInterval(leadingTrimDeltaPx / pps)
        return Canvas { context, size in
            guard let peaks, size.width > 2, size.height > 4 else {
                Self.drawPlaceholder(in: &context, size: size)
                return
            }
            let barWidth: CGFloat = 2
            let step: CGFloat = 3
            let secondsPerBar = TimeInterval(step / pps)
            let barCount = Int(size.width / step)
            let mid = size.height / 2
            for i in 0..<barCount {
                let t0 = visibleStart + Double(i) * secondsPerBar
                let a = peaks.index(at: t0)
                let b = max(a + 1, peaks.index(at: t0 + secondsPerBar))
                guard a < peaks.peaks.count else { break }
                let slice = peaks.peaks[a..<min(b, peaks.peaks.count)]
                let peak = CGFloat(slice.max() ?? 0)
                let h = max(2, peak * (size.height - 2))
                let rect = CGRect(x: CGFloat(i) * step, y: mid - h / 2, width: barWidth, height: h)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.white.opacity(0.7)))
            }
        }
        .allowsHitTesting(false)
    }

    /// A flat centre line while peaks are still decoding.
    private static func drawPlaceholder(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(x: 0, y: size.height / 2 - 1, width: size.width, height: 2)
        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.white.opacity(0.25)))
    }

    // MARK: - Trim handles

    private var handles: some View {
        HStack(spacing: 0) {
            trimHandle(edge: .leading, gesture: leadingHandleGesture)
            Spacer(minLength: 0)
            trimHandle(edge: .trailing, gesture: trailingHandleGesture)
        }
    }

    private func trimHandle(edge: HorizontalEdge, gesture: some Gesture) -> some View {
        // A 44pt hit area centred on the clip edge, half of it outside the clip, so
        // even a short clip is easy to grab. The visible grip stays inside.
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: edge == .leading ? Self.cornerRadius : 0,
                bottomLeadingRadius: edge == .leading ? Self.cornerRadius : 0,
                bottomTrailingRadius: edge == .trailing ? Self.cornerRadius : 0,
                topTrailingRadius: edge == .trailing ? Self.cornerRadius : 0
            )
            .fill(.white)
            .frame(width: 14)
            .overlay {
                Capsule()
                    .fill(.black.opacity(0.35))
                    .frame(width: 2, height: 18)
            }
        }
        .frame(width: Self.handleHitWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .offset(x: edge == .leading ? -Self.handleHitWidth / 2 + 7 : Self.handleHitWidth / 2 - 7)
        .highPriorityGesture(gesture)
        .accessibilityLabel(edge == .leading ? "Trim start" : "Trim end")
    }

    private var leadingHandleGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                // Snap the previewed edge, then store the snapped delta in pixels.
                let proposed = clip.timelineOffset + TimeInterval(value.translation.width / pps)
                let (snapped, target) = snapper.snap(proposed)
                let delta = snapped - clip.timelineOffset
                let maxDelta = clip.trimmedDuration - Self.minimumClipLength
                let clamped = delta.clamped(to: -clip.trimStart...max(-clip.trimStart, maxDelta))
                leadingTrimDeltaPx = clamped * pps
                snapTarget = clamped == delta ? target : nil
            }
            .onEnded { _ in
                let deltaSeconds = TimeInterval(leadingTrimDeltaPx / pps)
                let newTrimStart = max(0, clip.trimStart + deltaSeconds)
                let appliedDelta = newTrimStart - clip.trimStart
                leadingTrimDeltaPx = 0
                snapTarget = nil
                onTrim(newTrimStart, clip.trimEnd, clip.timelineOffset + appliedDelta)
            }
    }

    private var trailingHandleGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let proposed = clip.timelineEnd + TimeInterval(value.translation.width / pps)
                let (snapped, target) = snapper.snap(proposed)
                let delta = snapped - clip.timelineEnd   // + lengthens, − shortens
                let minDelta = -(clip.trimmedDuration - Self.minimumClipLength)
                let clamped = delta.clamped(to: min(minDelta, clip.trimEnd)...clip.trimEnd)
                trailingTrimDeltaPx = -clamped * pps
                snapTarget = clamped == delta ? target : nil
            }
            .onEnded { _ in
                let deltaSeconds = TimeInterval(-trailingTrimDeltaPx / pps)
                let newTrimEnd = max(0, clip.trimEnd - deltaSeconds)
                trailingTrimDeltaPx = 0
                snapTarget = nil
                onTrim(clip.trimStart, newTrimEnd, clip.timelineOffset)
            }
    }

    // MARK: - Move (long-press, then drag)

    private var moveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    isLifted = true
                    onSelect()
                case .second(true, let drag?):
                    let proposedStart = clip.timelineOffset + TimeInterval(drag.translation.width / pps)
                    // Snap either edge, whichever lands closer to a landmark.
                    let (snappedStart, startTarget) = snapper.snap(proposedStart)
                    let (snappedEnd, endTarget) = snapper.snap(proposedStart + clip.trimmedDuration)
                    let start: TimeInterval
                    if startTarget != nil {
                        start = snappedStart; snapTarget = startTarget
                    } else if endTarget != nil {
                        start = snappedEnd - clip.trimmedDuration; snapTarget = endTarget
                    } else {
                        start = proposedStart; snapTarget = nil
                    }
                    dragOffsetPx = (max(0, start) - clip.timelineOffset) * pps
                default:
                    break
                }
            }
            .onEnded { _ in
                let newOffset = clip.timelineOffset + TimeInterval(dragOffsetPx / pps)
                let moved = dragOffsetPx != 0
                dragOffsetPx = 0
                isLifted = false
                snapTarget = nil
                if moved { onMove(newOffset) }
            }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        let start = Duration.seconds(clip.timelineOffset).formatted(.time(pattern: .minuteSecond))
        let length = Duration.seconds(clip.trimmedDuration).formatted(.time(pattern: .minuteSecond))
        return String(localized: "Clip starting at \(start), \(length) long")
    }
}
