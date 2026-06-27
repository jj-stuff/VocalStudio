import SwiftUI

struct ProjectCard: View {
    let project: Project

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: DS.Spacing.sm + DS.Spacing.xxs) {
            thumbnail
            info
            trailingMeta
        }
        .padding(DS.Spacing.sm - 1)
        .background(glassCard)
        .clipShape(.rect(cornerRadius: DS.Radius.card))
        .overlay(cardBorder)
        .shadow(
            color: scheme.r1.opacity(colorScheme == .dark ? 0.15 : 0.20),
            radius: DS.Spacing.xl, x: 0, y: DS.Spacing.xs
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.title), \(project.relativeAge)")
    }

    // MARK: - Liquid glass card background

    @ViewBuilder
    private var glassCard: some View {
        ZStack {
            // Glass base
            Color.clear
                .background(.ultraThinMaterial)

            // Gradient tint from card's color scheme — the key liquid glass effect
            LinearGradient(
                colors: [
                    scheme.r1.opacity(colorScheme == .dark ? 0.18 : 0.12),
                    scheme.r2.opacity(colorScheme == .dark ? 0.12 : 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Specular highlight — top strip
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.07 : 0.55),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.35)
            )
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: DS.Radius.card)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.18 : 0.80),
                        scheme.r1.opacity(colorScheme == .dark ? 0.20 : 0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
    }

    // MARK: - Thumbnail

    private var thumbnail: some View {
        ZStack {
            thumbnailBackground
            miniBars
        }
        .frame(width: DS.Size.thumbnail, height: DS.Size.thumbnail)
        .clipShape(.rect(cornerRadius: DS.Size.thumbRadius))
    }

    private var thumbnailBackground: some View {
        let s = scheme
        return ZStack {
            LinearGradient(colors: [s.bg1, s.bg2], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: [s.r1.opacity(0.85), .clear],
                center: UnitPoint(x: 0.18, y: 0.16), startRadius: 0, endRadius: 40
            )
            RadialGradient(
                colors: [s.r2.opacity(0.70), .clear],
                center: UnitPoint(x: 0.86, y: 0.82), startRadius: 0, endRadius: 40
            )
        }
    }

    private var miniBars: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(barHeights.enumerated()), id: \.offset) { _, h in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.9))
                    .frame(width: 2.5, height: h)
            }
        }
    }

    // MARK: - Info

    private var info: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(project.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(project.subtitleText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Trailing

    private var trailingMeta: some View {
        VStack(alignment: .trailing, spacing: DS.Spacing.xs) {
            Text(project.relativeAge)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.quaternary)
        }
    }

    // MARK: - Gradient scheme (single consistent brand palette)

    private struct Scheme { let r1, r2, bg1, bg2: Color }

    private var scheme: Scheme {
        Scheme(
            r1: DS.Brand.pink,
            r2: DS.Brand.purple1,
            bg1: Color(red: 0.227, green: 0.043, blue: 0.278),
            bg2: Color(red: 0.357, green: 0.067, blue: 0.439)
        )
    }

    // MARK: - Bar heights (seeded from project ID)

    private var barHeights: [CGFloat] {
        let hash = abs(project.id.hashValue)
        return (0..<5).map { i in
            let seed = CGFloat((hash >> (i * 5)) & 0x1F) / 31
            let bases: [CGFloat] = [12, 22, 16, 26, 14]
            return bases[i] + seed * 10
        }
    }

    // Display properties live on Project (the model), not here.
}
