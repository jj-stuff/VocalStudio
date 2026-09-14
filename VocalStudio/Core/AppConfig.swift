import Foundation

/// The one place for values that show up in more than one screen — support
/// email, legal links, product names. Edit here, and every screen that mentions
/// them follows. Nothing in this file is fetched at runtime; it is baked in at
/// build time on purpose (no network dependency, no surprise changes).
enum AppConfig {

    /// The in-app brand: Siasca, from Thai เสียง (sǐang, "sound") and Swedish
    /// skapa ("to create"). The Xcode target and bundle id are still "Vocal
    /// Studio" — renaming those is a separate, riskier change, and nothing the
    /// user sees comes from them (the home-screen name is CFBundleDisplayName,
    /// set to Siasca in the target's build settings).
    static let appName = "Siasca"

    /// What the project list calls itself in its large title. Deliberately not
    /// `appName`: the brand is already on the home screen and the App Store
    /// listing, so repeating it at the top of the only screen in the app spends
    /// the title on something the user already knows. "Studio" says where you
    /// are instead — the same move Photos and Files make.
    static var homeTitle: String { String(localized: "Studio") }

    // MARK: - Contact & links
    //
    // Placeholders until the real domain is live. Keep them valid URLs so the
    // `Link`s in Settings never silently no-op.

    static let supportEmail = "support@siasca.app"
    static let websiteURL = URL(string: "https://stephanbordellier.com/siasca")!
    static let privacyPolicyURL = URL(string: "https://stephanbordellier.com/siasca/privacy")!
    static let termsOfServiceURL = URL(string: "https://stephanbordellier.com/siasca/terms")!

    /// App Store ID placeholder — used by the "Rate Siasca" row once the app is listed.
    static let appStoreID = "000000000"
    static var appStoreReviewURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!
    }

    /// `mailto:` link for the support row, pre-filled with the app version so bug
    /// reports arrive with the build attached.
    static var supportMailURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "\(appName) \(versionString)")
        ]
        return components.url!
    }

    // MARK: - Version

    /// "1.0 (12)" — marketing version plus build number, straight from Info.plist.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    // MARK: - Siasca Plus (the paid tier)
    //
    // Autotune is the first Plus-only feature. StoreKit isn't wired yet — the
    // paywall is a placeholder screen and `PlusEntitlement` always reports free.
    // When purchases land, only `PlusEntitlement` should need to change.

    enum Plus {
        static let productName = "Siasca Plus"
        /// Set to true once StoreKit products exist and the paywall can actually sell.
        static let purchasingEnabled = false
    }
}
