import SwiftUI

/// User-facing appearance choices. Both are persisted with `@AppStorage` under the
/// keys in `AppearanceKeys`, so any view can read them with the same one-liner.

/// Which colour scheme the app runs in, independent of the system setting.
enum AppearanceTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// `nil` means "follow the device", which is what `preferredColorScheme` expects.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light:  String(localized: "Light")
        case .dark:   String(localized: "Dark")
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light:  "sun.max.fill"
        case .dark:   "moon.fill"
        }
    }
}

/// What sits behind every screen. "Minimal" is the soft tinted wash; "Plain" is
/// the flat system grouped background for people who want nothing behind the cards.
enum AppBackgroundStyle: String, CaseIterable, Identifiable {
    case minimal
    case plain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimal: String(localized: "Minimal")
        case .plain:   String(localized: "Plain")
        }
    }
}

/// `@AppStorage` keys — one place, so a typo can't split a setting in two.
enum AppearanceKeys {
    static let theme = "appearance.theme"
    static let background = "appearance.background"
}
