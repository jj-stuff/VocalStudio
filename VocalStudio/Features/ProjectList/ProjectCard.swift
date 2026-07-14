import SwiftUI

struct ProjectCard: View {
    let project: Project

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            thumbnail
            info
            trailingMeta
        }
        .padding(DS.Spacing.sm)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.title), \(project.relativeAge)")
    }

    // MARK: - Thumbnail
    //
    // A colorful gradient orb, one hue family per project (picked from the ID, so
    // it's stable). The chrome around it stays monochrome — like voice avatars,
    // the orb is the only place color appears in a row.

    private var thumbnail: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [scheme.light, scheme.dark],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.55), .clear],
                        center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: 30
                    )
                )
            miniBars
        }
        .frame(width: DS.Size.thumbnail, height: DS.Size.thumbnail)
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
                .font(.system(size: 12))
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

    // MARK: - Orb color scheme (stable per project)

    private struct Scheme { let light, dark: Color }

    private static let schemes: [Scheme] = [
        Scheme(light: Color(red: 0.95, green: 0.60, blue: 0.35), dark: Color(red: 0.75, green: 0.30, blue: 0.15)),  // amber
        Scheme(light: Color(red: 0.45, green: 0.75, blue: 0.95), dark: Color(red: 0.15, green: 0.40, blue: 0.75)),  // blue
        Scheme(light: Color(red: 0.75, green: 0.60, blue: 0.95), dark: Color(red: 0.45, green: 0.25, blue: 0.75)),  // violet
        Scheme(light: Color(red: 0.50, green: 0.85, blue: 0.70), dark: Color(red: 0.15, green: 0.55, blue: 0.45)),  // teal
        Scheme(light: Color(red: 0.95, green: 0.55, blue: 0.65), dark: Color(red: 0.70, green: 0.20, blue: 0.40)),  // rose
    ]

    private var scheme: Scheme {
        Self.schemes[stableHash % Self.schemes.count]
    }

    /// Swift's Hashable is randomly seeded per launch — using `id.hashValue` here
    /// would recolor every orb on every app start. Fold the UUID's raw bytes instead.
    private var stableHash: Int {
        let bytes = project.id.uuid
        let folded = [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7]
            .reduce(0) { ($0 &* 31) &+ Int($1) }
        return abs(folded)
    }

    // MARK: - Bar heights (seeded from project ID)

    private var barHeights: [CGFloat] {
        let hash = stableHash
        return (0..<5).map { i in
            let seed = CGFloat((hash >> (i * 5)) & 0x1F) / 31
            let bases: [CGFloat] = [10, 18, 14, 20, 12]
            return bases[i] + seed * 8
        }
    }
}
