import SwiftUI

/// Time ruler across the top of the timeline. Scrolls with the content, so the
/// numbers passing under the fixed playhead always agree with the readout.
struct RulerView: View {
    let geometry: TimelineGeometry

    var body: some View {
        Canvas { ctx, size in
            let interval = geometry.tickInterval
            let tickCount = Int(size.width / geometry.x(interval)) + 1

            for i in 0...tickCount {
                let t = Double(i) * interval
                let x = geometry.x(t)
                guard x <= size.width else { break }

                // Every tick gets a label; the half-way point gets a short minor tick.
                var major = Path()
                major.move(to: CGPoint(x: x, y: size.height - 8))
                major.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(major, with: .color(.secondary.opacity(0.7)), lineWidth: 1)

                let halfX = geometry.x(t + interval / 2)
                if halfX <= size.width {
                    var minor = Path()
                    minor.move(to: CGPoint(x: halfX, y: size.height - 4))
                    minor.addLine(to: CGPoint(x: halfX, y: size.height))
                    ctx.stroke(minor, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
                }

                ctx.draw(
                    Text(Self.label(for: t, interval: interval))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary),
                    at: CGPoint(x: x + 3, y: 2),
                    anchor: .topLeading
                )
            }
        }
    }

    /// "0:05", "1:30", or "0:02.5" when the zoom is fine enough for half seconds.
    private static func label(for t: TimeInterval, interval: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        if interval < 1 {
            let tenths = Int((t.truncatingRemainder(dividingBy: 1)) * 10)
            return String(format: "%d:%02d.%d", m, s, tenths)
        }
        return String(format: "%d:%02d", m, s)
    }
}
