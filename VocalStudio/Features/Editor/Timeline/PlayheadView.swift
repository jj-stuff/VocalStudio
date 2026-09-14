import SwiftUI

/// The fixed playhead: a thin line with a small cap on the ruler. It never moves —
/// the timeline scrolls underneath it — so it can be a plain overlay with no
/// dependence on time at all.
struct PlayheadView: View {
    var isRecording: Bool

    private var color: Color { isRecording ? .red : .primary }

    var body: some View {
        VStack(spacing: 0) {
            // Cap: a rounded triangle pointing down onto the ruler.
            Capsule()
                .fill(color)
                .frame(width: 10, height: 6)
            Rectangle()
                .fill(color)
                .frame(width: 2)
        }
        .shadow(color: color.opacity(0.35), radius: 3)
        .allowsHitTesting(false)
        .animation(DS.Animation.smooth, value: isRecording)
    }
}
