import SwiftUI

struct WaveformBarsView: View {
    var isAnimating = false
    var barCount = 20
    var color: Color = .white

    var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            Canvas { context, size in
                let barWidth = size.width / CGFloat(barCount)
                let t = isAnimating ? timeline.date.timeIntervalSinceReferenceDate : 0
                for i in 0..<barCount {
                    let height: CGFloat = isAnimating
                        ? barHeight(index: i, time: t, maxH: size.height)
                        : staticBarHeight(index: i, maxH: size.height)
                    let x = CGFloat(i) * barWidth + barWidth * 0.2
                    let w = barWidth * 0.6
                    let y = (size.height - height) / 2
                    let rect = CGRect(x: x, y: y, width: w, height: height)
                    let path = Path(roundedRect: rect, cornerRadius: w / 2)
                    context.fill(path, with: .color(color.opacity(0.4 + 0.6 * Double(height / size.height))))
                }
            }
        }
    }

    private func barHeight(index: Int, time: Double, maxH: CGFloat) -> CGFloat {
        let f1 = sin(time * 2.3 + Double(index) * 0.7)
        let f2 = sin(time * 1.7 + Double(index) * 1.2)
        let f3 = sin(time * 3.1 + Double(index) * 0.4)
        let raw = (f1 * 0.5 + f2 * 0.3 + f3 * 0.2 + 1) / 2
        return maxH * 0.12 + maxH * 0.78 * CGFloat(raw)
    }

    private func staticBarHeight(index: Int, maxH: CGFloat) -> CGFloat {
        // Pseudo-random static waveform based on index
        let pseudo = sin(Double(index) * 1.618) * 0.5 + 0.5
        return maxH * 0.15 + maxH * 0.65 * CGFloat(pseudo)
    }
}
