import SwiftUI

/// Appearance: app theme (System / Light / Dark) and background (Minimal / Plain),
/// each chosen from a row of preview cards — the Bevel pattern, where you pick by
/// looking at a miniature of the result rather than reading a label.
struct AppearanceSettingsView: View {
    @AppStorage(AppearanceKeys.theme) private var theme: AppearanceTheme = .system
    @AppStorage(AppearanceKeys.background) private var background: AppBackgroundStyle = .minimal
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List {
            Section("App Theme") {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(AppearanceTheme.allCases) { option in
                        OptionCard(
                            title: option.title,
                            systemImage: option.icon,
                            isSelected: theme == option
                        ) {
                            ThemePreview(theme: option, background: background)
                        } action: {
                            theme = option
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: DS.Spacing.sm, leading: DS.Spacing.sm, bottom: DS.Spacing.sm, trailing: DS.Spacing.sm))
            }

            Section {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(AppBackgroundStyle.allCases) { option in
                        OptionCard(
                            title: option.title,
                            systemImage: nil,
                            isSelected: background == option
                        ) {
                            BackgroundWash(style: option, scheme: theme.colorScheme ?? colorScheme)
                                .overlay { MiniScreen(scheme: theme.colorScheme ?? colorScheme) }
                        } action: {
                            background = option
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: DS.Spacing.sm, leading: DS.Spacing.sm, bottom: DS.Spacing.sm, trailing: DS.Spacing.sm))
            } header: {
                Text("Background")
            } footer: {
                Text("Minimal adds a soft tint behind every screen. Plain keeps it flat.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: theme)
        .sensoryFeedback(.selection, trigger: background)
    }
}

// MARK: - Option card

/// One selectable preview card: a picture on top, a caption underneath, and a
/// ring when selected. Unselected cards are dimmed so the choice reads at a glance.
private struct OptionCard<Preview: View>: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    @ViewBuilder let preview: () -> Preview
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                preview()
                    .frame(height: 96)
                    .clipped()

                HStack(spacing: DS.Spacing.xxs) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.caption.weight(.semibold))
                    }
                    Text(title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                }
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.xs)
                .background(Color(.secondarySystemGroupedBackground))
            }
            .clipShape(.rect(cornerRadius: DS.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(isSelected ? Color.primary : Color(.separator), lineWidth: isSelected ? 2 : 0.5)
            }
            .opacity(isSelected ? 1 : 0.6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(DS.Animation.smooth, value: isSelected)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Previews inside the cards

/// A miniature of the app in a given theme. "System" shows both halves split down
/// the middle, the way iOS's own wallpaper picker does it.
private struct ThemePreview: View {
    let theme: AppearanceTheme
    let background: AppBackgroundStyle

    var body: some View {
        switch theme {
        case .system:
            HStack(spacing: 0) {
                screen(.light)
                screen(.dark)
            }
        case .light:
            screen(.light)
        case .dark:
            screen(.dark)
        }
    }

    private func screen(_ scheme: ColorScheme) -> some View {
        BackgroundWash(style: background, scheme: scheme)
            .overlay { MiniScreen(scheme: scheme) }
    }
}

/// Tiny stand-in for the editor: a title bar and three clip bars. Explicit colours,
/// not semantic ones — the card has to show the *chosen* scheme, not the current one.
private struct MiniScreen: View {
    let scheme: ColorScheme

    private var ink: Color { scheme == .dark ? .white : .black }
    private var card: Color { scheme == .dark ? Color(white: 0.16) : .white }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(ink.opacity(0.8)).frame(width: 28, height: 5)
            VStack(alignment: .leading, spacing: 4) {
                clip(width: 46, color: Color(red: 0.30, green: 0.40, blue: 0.85))
                clip(width: 34, color: Color(red: 0.55, green: 0.35, blue: 0.80))
                clip(width: 40, color: Color(red: 0.80, green: 0.30, blue: 0.45))
            }
            .padding(6)
            .background(card, in: .rect(cornerRadius: 6))
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func clip(width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: width, height: 8)
    }
}
