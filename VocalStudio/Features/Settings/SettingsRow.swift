import SwiftUI

/// The label used by every Settings row: a small rounded icon tile on the left,
/// the title, and whatever the row wants trailing. Matches the Bevel/Mist pattern
/// (and Apple's own Settings app), so rows read as one family.
struct SettingsRowLabel<Trailing: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    /// Tile background. Defaults to the neutral fill; pass a colour to call a row out.
    var tint: Color = Color(.tertiarySystemFill)
    /// Symbol colour. Defaults to primary so the tile stays monochrome.
    var symbolColor: Color = .primary
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            SettingsIconTile(systemImage: systemImage, tint: tint, symbolColor: symbolColor)
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: DS.Spacing.xs)
            trailing()
        }
    }
}

extension SettingsRowLabel where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String,
         tint: Color = Color(.tertiarySystemFill), symbolColor: Color = .primary) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.symbolColor = symbolColor
        self.trailing = { EmptyView() }
    }
}

/// The rounded-square icon on the leading edge of a Settings row.
struct SettingsIconTile: View {
    let systemImage: String
    var tint: Color = Color(.tertiarySystemFill)
    var symbolColor: Color = .primary

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(symbolColor)
            .frame(width: DS.Size.settingsIconTile, height: DS.Size.settingsIconTile)
            .background(tint, in: .rect(cornerRadius: DS.Radius.sm))
    }
}

/// A row that opens something (a link, a sheet) — title plus chevron, and the whole
/// row is tappable. `List` doesn't draw a chevron for plain `Button`s, so this
/// adds one to keep "tap to go somewhere" rows visually consistent with
/// `NavigationLink`s.
struct SettingsActionRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    var tint: Color = Color(.tertiarySystemFill)
    var symbolColor: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowLabel(title: title, systemImage: systemImage, tint: tint, symbolColor: symbolColor) {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
