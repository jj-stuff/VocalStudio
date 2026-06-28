import SwiftUI

struct AnimatedBlobBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var blob1Offset = CGSize(width: -60, height: -80)
    @State private var blob2Offset = CGSize(width: 80, height: 60)
    @State private var blob3Offset = CGSize(width: -20, height: 120)
    @State private var blob1Scale: CGFloat = 1.0
    @State private var blob2Scale: CGFloat = 0.9
    @State private var blob3Scale: CGFloat = 1.1

    var body: some View {
        ZStack {
            // Base system background
            Color(.systemBackground)

            // Blob 1 — purple
            blob(
                color: DS.Brand.purple1,
                size: 360,
                offset: blob1Offset,
                scale: blob1Scale,
                blur: 80
            )
            .offset(x: -60, y: -120)

            // Blob 2 — pink/magenta
            blob(
                color: DS.Brand.pink,
                size: 300,
                offset: blob2Offset,
                scale: blob2Scale,
                blur: 90
            )
            .offset(x: 100, y: -40)

            // Blob 3 — deepest purple (keeps the trio a single analogous family,
            // no stray hue, matching the Aria palette's "no neon" rule)
            blob(
                color: Color(red: 0.353, green: 0.290, blue: 0.549),
                size: 280,
                offset: blob3Offset,
                scale: blob3Scale,
                blur: 100
            )
            .offset(x: 20, y: 160)
        }
        .onAppear { animate() }
    }

    private func blob(color: Color, size: CGFloat, offset: CGSize, scale: CGFloat, blur: CGFloat) -> some View {
        Circle()
            .fill(color.opacity(colorScheme == .dark ? 0.35 : 0.22))
            .frame(width: size, height: size)
            .offset(offset)
            .scaleEffect(scale)
            .blur(radius: blur)
    }

    private func animate() {
        withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
            blob1Offset = CGSize(width: 80, height: -140)
            blob1Scale = 1.25
        }
        withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true).delay(1.5)) {
            blob2Offset = CGSize(width: -100, height: 80)
            blob2Scale = 1.1
        }
        withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true).delay(3)) {
            blob3Offset = CGSize(width: 60, height: -60)
            blob3Scale = 0.85
        }
    }
}
