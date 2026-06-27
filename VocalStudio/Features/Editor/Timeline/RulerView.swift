import SwiftUI

/// Time ruler that runs across the top of the timeline scroll area.
struct RulerView: View {
    let duration: TimeInterval
    let pixelsPerSecond: CGFloat

    private var tickInterval: TimeInterval {
        // Choose a human-readable tick spacing depending on zoom
        switch pixelsPerSecond {
        case ..<30:  return 10
        case ..<80:  return 5
        case ..<160: return 2
        default:     return 1
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let interval = tickInterval
            let tickCount = Int(duration / interval) + 2

            for i in 0..<tickCount {
                let t = Double(i) * interval
                let x = t * pixelsPerSecond
                guard x <= size.width else { break }

                // Tick mark
                let isMajor = (i % 4 == 0)
                let tickH: CGFloat = isMajor ? 10 : 6
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height - tickH))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(.white.opacity(isMajor ? 0.4 : 0.2)), lineWidth: isMajor ? 1 : 0.5)

                // Label on major ticks only
                if isMajor {
                    let label = formatTime(t)
                    ctx.draw(
                        Text(label)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5)),
                        at: CGPoint(x: x + 3, y: size.height - 14),
                        anchor: .topLeading
                    )
                }
            }
        }
        .frame(height: 24)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return m > 0 ? "\(m):\(String(format: "%02d", s))" : "\(s)s"
    }
}
