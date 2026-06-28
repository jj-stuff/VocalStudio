import SwiftUI

/// A single audio clip drawn on the timeline lane.
/// User-recording clips can be dragged to reposition, and trimmed from either edge.
struct ClipView: View {
    let clip: AudioClip
    let trackKind: Track.Kind
    let pixelsPerSecond: CGFloat
    let isDraggable: Bool
    let onMove: (TimeInterval) -> Void
    /// (trimStart, trimEnd, timelineOffset) — offset only changes when trimming the
    /// leading edge, so the underlying source audio's absolute timing never shifts.
    let onTrim: (TimeInterval, TimeInterval, TimeInterval) -> Void
    let onDelete: () -> Void

    private static let minimumClipLength: TimeInterval = 0.2
    private static let handleWidth: CGFloat = 14

    @State private var dragOffsetPx: CGFloat = 0
    @State private var leadingTrimDeltaPx: CGFloat = 0
    @State private var trailingTrimDeltaPx: CGFloat = 0

    private var clipWidth: CGFloat {
        // Leading handle: dragging right (+dx) shrinks the clip from the left, so it
        // subtracts. Trailing handle: trailingTrimDeltaPx is already stored negated
        // (see trailingHandleGesture), so subtracting it adds back the dragged amount.
        max(4, clip.trimmedDuration * pixelsPerSecond - leadingTrimDeltaPx - trailingTrimDeltaPx)
    }

    private var clipColor: LinearGradient {
        switch trackKind {
        case .instrumental:
            return LinearGradient(
                colors: [Color(red: 0.12, green: 0.18, blue: 0.40),
                         Color(red: 0.08, green: 0.12, blue: 0.30)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .vocal:
            return LinearGradient(
                colors: [Color(red: 0.27, green: 0.08, blue: 0.42),
                         Color(red: 0.18, green: 0.05, blue: 0.30)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .userRecording:
            return LinearGradient(
                colors: [DS.Brand.purple1.opacity(0.8), DS.Brand.pink.opacity(0.6)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Clip body
            RoundedRectangle(cornerRadius: 6)
                .fill(clipColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                }
                .overlay(alignment: .leading) {
                    waveformBars
                        .padding(.horizontal, 6)
                }

            if isDraggable {
                HStack {
                    trimHandle(gesture: leadingHandleGesture)
                    Spacer()
                    trimHandle(gesture: trailingHandleGesture)
                }
            }
        }
        .frame(width: clipWidth)
        .offset(x: clip.timelineOffset * pixelsPerSecond + dragOffsetPx + leadingTrimDeltaPx)
        .gesture(isDraggable ? dragGesture : nil)
        .contextMenu {
            if isDraggable {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Recording", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Trim handles

    private func trimHandle(gesture: some Gesture) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.white.opacity(0.6))
            .frame(width: 3, height: 22)
            .frame(width: Self.handleWidth)
            .contentShape(Rectangle())
            .highPriorityGesture(gesture)
    }

    private var leadingHandleGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in leadingTrimDeltaPx = value.translation.width }
            .onEnded { value in
                let deltaSeconds = Double(value.translation.width / pixelsPerSecond)
                let maxTrimStart = clip.duration - clip.trimEnd - Self.minimumClipLength
                let newTrimStart = max(0, min(maxTrimStart, clip.trimStart + deltaSeconds))
                let appliedDelta = newTrimStart - clip.trimStart
                leadingTrimDeltaPx = 0
                onTrim(newTrimStart, clip.trimEnd, clip.timelineOffset + appliedDelta)
            }
    }

    private var trailingHandleGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in trailingTrimDeltaPx = -value.translation.width }
            .onEnded { value in
                let deltaSeconds = Double(value.translation.width / pixelsPerSecond)
                let maxTrimEnd = clip.duration - clip.trimStart - Self.minimumClipLength
                let newTrimEnd = max(0, min(maxTrimEnd, clip.trimEnd - deltaSeconds))
                trailingTrimDeltaPx = 0
                onTrim(clip.trimStart, newTrimEnd, clip.timelineOffset)
            }
    }

    // MARK: - Waveform bars (deterministic visual, not real waveform data)

    private var waveformBars: some View {
        let hash = abs(clip.id.hashValue)
        let trimStart = clip.trimStart
        let pps = pixelsPerSecond
        return Canvas { context, size in
            guard size.width > 4, size.height > 4 else { return }
            let barWidth: CGFloat = 2
            let gap: CGFloat = 2
            let step = barWidth + gap
            let barCount = max(1, Int(size.width / step))
            // Anchor each bar's seed to its absolute position in the SOURCE file
            // (trimStart's bar offset + i), not its render-relative index (i alone).
            // Bars were regenerating from index 0 at whatever the current left edge
            // was, so trimming the head re-drew the same pattern starting over —
            // visually indistinguishable from trimming the tail instead.
            let trimStartBars = Int(trimStart * Double(pps) / Double(step))
            for i in 0..<barCount {
                let seed = CGFloat((hash >> ((trimStartBars + i) % 32)) & 0xF) / 15
                let barHeight = 4 + seed * (size.height - 8)
                let x = CGFloat(i) * step
                let y = (size.height - barHeight) / 2
                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .color(.white.opacity(0.55))
                )
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Drag (reposition)

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                dragOffsetPx = value.translation.width
            }
            .onEnded { value in
                let deltaSeconds = value.translation.width / pixelsPerSecond
                let newOffset = clip.timelineOffset + deltaSeconds
                dragOffsetPx = 0
                onMove(newOffset)
            }
    }
}
