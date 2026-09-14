import SwiftUI

/// The canvas every screen sits on. Reads the user's background choice and draws
/// it via `BackgroundWash`. Put it at the back of a `ZStack`; it already ignores
/// the safe area.
struct AppBackground: View {
    @AppStorage(AppearanceKeys.background) private var style: AppBackgroundStyle = .minimal
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        BackgroundWash(style: style, scheme: colorScheme)
            .ignoresSafeArea()
    }
}

/// The actual drawing, with the style and scheme passed in explicitly so the
/// Appearance picker can render previews of choices that aren't the saved one.
///
/// "Minimal" is a quiet mesh-gradient wash over the system grouped background.
/// It is deliberately low-saturation: the clips and the record button are the
/// colour in this app, and the background's only jobs are to stop the screen
/// feeling flat and to give Liquid Glass controls something to refract.
/// "Plain" is the flat system background, nothing else.
struct BackgroundWash: View {
    let style: AppBackgroundStyle
    let scheme: ColorScheme

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            if style == .minimal {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: Self.points,
                    colors: scheme == .dark ? Self.darkColors : Self.lightColors
                )
                // Blend into the system background rather than replacing it, so
                // the wash stays subtle at every brightness.
                .opacity(scheme == .dark ? 0.55 : 0.75)
            }
        }
        .environment(\.colorScheme, scheme)
    }

    // A 3×3 mesh with the middle row nudged so the tint pools toward the top,
    // where the title sits, and fades out under the content.
    private static let points: [SIMD2<Float>] = [
        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
        [0.0, 0.45], [0.55, 0.4], [1.0, 0.5],
        [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
    ]

    // Light: a warm lavender-to-peach wash over near-white.
    private static let lightColors: [Color] = [
        Color(red: 0.93, green: 0.90, blue: 0.99), Color(red: 0.97, green: 0.93, blue: 0.97), Color(red: 0.99, green: 0.94, blue: 0.91),
        Color(red: 0.96, green: 0.95, blue: 0.99), Color(red: 0.97, green: 0.96, blue: 0.98), Color(red: 0.98, green: 0.96, blue: 0.95),
        Color(red: 0.96, green: 0.96, blue: 0.97), Color(red: 0.96, green: 0.96, blue: 0.97), Color(red: 0.96, green: 0.96, blue: 0.97),
    ]

    // Dark: the same hues pulled down to a deep twilight over near-black.
    private static let darkColors: [Color] = [
        Color(red: 0.14, green: 0.10, blue: 0.22), Color(red: 0.12, green: 0.09, blue: 0.17), Color(red: 0.16, green: 0.10, blue: 0.13),
        Color(red: 0.09, green: 0.08, blue: 0.13), Color(red: 0.08, green: 0.07, blue: 0.11), Color(red: 0.10, green: 0.08, blue: 0.11),
        Color(red: 0.06, green: 0.06, blue: 0.07), Color(red: 0.06, green: 0.06, blue: 0.07), Color(red: 0.06, green: 0.06, blue: 0.07),
    ]
}
