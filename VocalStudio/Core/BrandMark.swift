import SwiftUI

/// The app's mark: a gradient rounded square with a stylized rising-waveform glyph,
/// matching the "Aria" brand direction's app-icon motif. Used wherever the app needs
/// a small logo (the projects list brand row) rather than just a wordmark.
struct BrandMark: View {
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(LinearGradient(
                    colors: [DS.Brand.purple1, DS.Brand.purple2],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    RoundedRectangle(cornerRadius: h * 0.05)
                        .fill(Color.black.opacity(0.22))
                        .frame(width: w * 0.66, height: max(1, h * 0.09))
                        .position(x: w * 0.5, y: h * 0.68)

                    WaveGlyph()
                        .stroke(
                            Color.white.opacity(0.95),
                            style: StrokeStyle(lineWidth: max(1.4, h * 0.08), lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: w * 0.6, height: h * 0.46)
                        .position(x: w * 0.46, y: h * 0.4)

                    Circle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: h * 0.13, height: h * 0.13)
                        .position(x: w * 0.73, y: h * 0.3)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

private struct WaveGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.92))
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.08),
            control1: CGPoint(x: rect.width * 0.34, y: -rect.height * 0.3),
            control2: CGPoint(x: rect.width * 0.6, y: rect.height * 0.55)
        )
        return path
    }
}

#Preview {
    BrandMark(size: 80)
        .padding()
        .background(Color.black)
}
