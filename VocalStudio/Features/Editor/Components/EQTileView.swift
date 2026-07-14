import SwiftUI

struct EQTileView: View {
    let eqGains: [Float]
    let onEQChange: (Float, Int) -> Void

    @State private var values: [Double]

    init(eqGains: [Float], onEQChange: @escaping (Float, Int) -> Void) {
        self.eqGains = eqGains
        self.onEQChange = onEQChange
        _values = State(initialValue: eqGains.map(Double.init))
    }

    private var averageGain: Double {
        values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            eqCurve
            bandSliders
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.Radius.tile))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("EQ")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(2)
                Text("Parametric EQ")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Spacer()
            let sign = averageGain >= 0 ? "+" : ""
            Text("\(sign)\(String(format: "%.1f", averageGain)) dB")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private var eqCurve: some View {
        EQCurveView(gains: values)
            .frame(height: 52)
            .clipShape(.rect(cornerRadius: 8))
    }

    private var bandSliders: some View {
        VStack(spacing: 10) {
            ForEach(Array(EffectSettings.eqBandLabels.enumerated()), id: \.offset) { i, label in
                HStack(spacing: 10) {
                    Text(label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)

                    Slider(value: $values[i], in: -12...12)
                        .tint(.primary)
                        .onChange(of: values[i]) { onEQChange(Float(values[i]), i) }
                        .accessibilityLabel("\(label) gain")

                    let sign = values[i] >= 0 ? "+" : ""
                    Text("\(sign)\(Int(values[i]))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fontDesign(.monospaced)
                        .frame(width: 28, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - EQCurveView

private struct EQCurveView: View {
    let gains: [Double]

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height

            // Grid
            for i in 1..<4 {
                let x = w * CGFloat(i) / 4
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: h))
                context.stroke(path, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            }
            let midY = h / 2
            var midLine = Path()
            midLine.move(to: CGPoint(x: 0, y: midY))
            midLine.addLine(to: CGPoint(x: w, y: midY))
            context.stroke(midLine, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)

            // EQ curve (smooth through 4 band points + endpoints)
            let bandXPositions: [CGFloat] = [0.1, 0.3, 0.65, 0.9]
            var allPoints: [(CGFloat, CGFloat)] = [(0, midY)]
            for (i, gain) in gains.enumerated() {
                let x = w * bandXPositions[i]
                let y = midY - (CGFloat(gain) / 12) * midY * 0.85
                allPoints.append((x, y))
            }
            allPoints.append((w, midY))

            var curvePath = Path()
            curvePath.move(to: CGPoint(x: allPoints[0].0, y: allPoints[0].1))
            for i in 1..<allPoints.count {
                let prev = allPoints[i - 1]
                let curr = allPoints[i]
                let cpX = (prev.0 + curr.0) / 2
                curvePath.addCurve(
                    to: CGPoint(x: curr.0, y: curr.1),
                    control1: CGPoint(x: cpX, y: prev.1),
                    control2: CGPoint(x: cpX, y: curr.1)
                )
            }
            context.stroke(curvePath, with: .color(.primary), lineWidth: 2)

            // Fill under curve
            var fillPath = curvePath
            fillPath.addLine(to: CGPoint(x: w, y: h))
            fillPath.addLine(to: CGPoint(x: 0, y: h))
            fillPath.closeSubpath()
            context.fill(fillPath, with: .color(.primary.opacity(0.06)))
        }
    }
}
