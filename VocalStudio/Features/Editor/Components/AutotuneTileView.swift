import SwiftUI

enum MusicKey: String, CaseIterable, Identifiable {
    case c = "C", cSharp = "C#", d = "D", dSharp = "D#"
    case e = "E", f = "F", fSharp = "F#", g = "G"
    case gSharp = "G#", a = "A", aSharp = "A#", b = "B"

    var id: String { rawValue }

    var isSharp: Bool { rawValue.hasSuffix("#") }
}

enum TuningScale: String, CaseIterable {
    case major = "Major", minor = "Minor"
}

struct AutotuneTileView: View {
    @State private var selectedKey: MusicKey = .c
    @State private var scale: TuningScale = .major
    @State private var amount: Double = 64
    @State private var retuneSpeed: Double = 78

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            keyChips
            scalePicker
            pitchViz
            sliders
        }
        .padding(20)
        .background(tileBackground)
        .clipShape(.rect(cornerRadius: 24))
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AUTOTUNE")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.6))
                    .tracking(2)
                Text("Pitch Correction")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Image(systemName: "waveform.and.mic")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var keyChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MusicKey.allCases) { key in
                    Button {
                        withAnimation(.spring(duration: 0.2)) { selectedKey = key }
                    } label: {
                        Text(key.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedKey == key ? Color(red: 0.22, green: 0.05, blue: 0.3) : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedKey == key
                                    ? Color(red: 1.0, green: 0.45, blue: 0.75)
                                    : Color.white.opacity(key.isSharp ? 0.12 : 0.2),
                                in: .capsule
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var scalePicker: some View {
        Picker("Scale", selection: $scale) {
            ForEach(TuningScale.allCases, id: \.self) { s in
                Text(s.rawValue).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .colorMultiply(Color(red: 1, green: 0.7, blue: 0.85))
    }

    private var pitchViz: some View {
        PitchVisualizationView(key: selectedKey)
            .frame(height: 52)
            .clipShape(.rect(cornerRadius: 8))
    }

    private var sliders: some View {
        VStack(spacing: 14) {
            TileSliderRow(label: "Amount", value: $amount, range: 0...100, unit: "%")
            TileSliderRow(label: "Retune Speed", value: $retuneSpeed, range: 0...100, unit: "%")
        }
    }

    private var tileBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.05, blue: 0.2), Color(red: 0.18, green: 0.06, blue: 0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 1.0, green: 0.2, blue: 0.55).opacity(0.45), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 220
            )
            RadialGradient(
                colors: [Color(red: 0.5, green: 0.1, blue: 0.9).opacity(0.3), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 180
            )
        }
    }
}

// MARK: - PitchVisualizationView

private struct PitchVisualizationView: View {
    let key: MusicKey

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let noteCount = 12
            let noteW = w / CGFloat(noteCount)

            // Draw grid lines
            for i in 0..<noteCount {
                let x = CGFloat(i) * noteW
                var linePath = Path()
                linePath.move(to: CGPoint(x: x, y: 0))
                linePath.addLine(to: CGPoint(x: x, y: h))
                context.stroke(linePath, with: .color(.white.opacity(0.08)), lineWidth: 0.5)
            }

            // Draw pitch curve
            var curvePath = Path()
            let points = pitchPoints(width: w, height: h)
            curvePath.move(to: points[0])
            for i in 1..<points.count {
                let cp1 = CGPoint(x: (points[i-1].x + points[i].x) / 2, y: points[i-1].y)
                let cp2 = CGPoint(x: (points[i-1].x + points[i].x) / 2, y: points[i].y)
                curvePath.addCurve(to: points[i], control1: cp1, control2: cp2)
            }
            context.stroke(curvePath, with: .color(Color(red: 1.0, green: 0.5, blue: 0.8)), lineWidth: 2)

            // Highlight selected key band
            let keyIndex = MusicKey.allCases.firstIndex(of: key) ?? 0
            let kx = CGFloat(keyIndex) * noteW
            let band = Path(CGRect(x: kx, y: 0, width: noteW, height: h))
            context.fill(band, with: .color(Color(red: 1.0, green: 0.45, blue: 0.75).opacity(0.2)))
        }
    }

    private func pitchPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        (0...20).map { i in
            let x = width * CGFloat(i) / 20
            let y = height / 2 + sin(Double(i) * 0.9) * height * 0.28
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - TileSliderRow

struct TileSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 90, alignment: .leading)

            Slider(value: $value, in: range)
                .tint(Color(red: 1.0, green: 0.45, blue: 0.75))

            Text("\(Int(value))\(unit)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .fontDesign(.monospaced)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
