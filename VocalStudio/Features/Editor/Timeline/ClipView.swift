import SwiftUI

/// A single audio clip drawn on the timeline lane.
/// User-recording clips can be dragged to reposition.
struct ClipView: View {
    let clip: AudioClip
    let trackKind: Track.Kind
    let pixelsPerSecond: CGFloat
    let isDraggable: Bool
    let onMove: (TimeInterval) -> Void

    @State private var dragOffsetPx: CGFloat = 0

    private var clipWidth: CGFloat {
        max(4, clip.duration * pixelsPerSecond)
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
        }
        .frame(width: clipWidth)
        .offset(x: clip.timelineOffset * pixelsPerSecond + dragOffsetPx)
        .gesture(isDraggable ? dragGesture : nil)
    }

    // MARK: - Waveform bars (deterministic visual, not real waveform data)

    private var waveformBars: some View {
        let hash = abs(clip.id.hashValue)
        return Canvas { context, size in
            guard size.width > 4, size.height > 4 else { return }
            let barWidth: CGFloat = 2
            let gap: CGFloat = 2
            let step = barWidth + gap
            let barCount = max(1, Int(size.width / step))
            for i in 0..<barCount {
                let seed = CGFloat((hash >> (i % 32)) & 0xF) / 15
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

    // MARK: - Drag

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
