import SwiftUI

enum DS {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs:  CGFloat = 8
        static let sm:  CGFloat = 12
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 20
        static let xl:  CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    enum Radius {
        static let sm:   CGFloat = 8
        static let md:   CGFloat = 14
        static let card: CGFloat = 22
        static let tile: CGFloat = 24
        static let hero: CGFloat = 28
        // Use Capsule() shape directly — no pill constant needed.
    }

    enum Size {
        static let navIcon:     CGFloat = 34
        static let fab:         CGFloat = 58
        static let thumbnail:   CGFloat = 56
        static let thumbRadius: CGFloat = 16
        static let tabBarH:     CGFloat = 58
        /// Full rendered height of the floating tab bar assembly (pill content plus
        /// its vertical padding). Anything that needs to clear the bar — content
        /// insets, the projects-list FAB — measures against this, so the numbers
        /// can't silently drift apart.
        static let tabBarVisualH: CGFloat = tabBarH + Spacing.xxs * 2
    }

    enum Animation {
        static let spring = SwiftUI.Animation.spring(duration: 0.3, bounce: 0.2)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let blob   = SwiftUI.Animation.easeInOut(duration: 7).repeatForever(autoreverses: true)
    }
}

// MARK: - Brand colours
// Defined in Assets.xcassets; accessed via type-safe ColorResource symbols
// (ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES).
// Edit the hue in the asset catalog, not here.
//
// "Aria" direction (cool twilight): a single analogous purple family, deliberately
// no separate hue per token — `pink` keeps its name (renaming touches every call
// site for no behavioral gain) but is now a mid-purple, not magenta.

extension DS {
    enum Brand {
        static let purple1 = Color(.brandPurple1)  // light lavender — primary accent
        static let purple2 = Color(.brandPurple2)  // deep purple — gradient end
        static let pink    = Color(.brandPink)     // mid purple
        static let teal    = Color(.brandTeal)
        static let orange  = Color(.brandOrange)
    }
}

// MARK: - Brand typeface
//
// Instrument Serif (OFL-licensed, bundled in Resources/Fonts) is the wordmark/
// display face — used sparingly, the way the brand doc uses it: the "Aria"
// wordmark itself and a handful of hero headlines. Everything else (body text,
// controls) stays system font, matching the doc's "Instrument Serif · SF Pro" pairing.

extension DS {
    enum Font {
        /// The italic wordmark face — use only for the literal "Aria" logotype.
        static func wordmark(_ size: CGFloat) -> SwiftUI.Font {
            .custom("InstrumentSerif-Italic", size: size)
        }
        /// Upright serif for hero headlines (e.g. empty-state/import-card copy).
        static func display(_ size: CGFloat) -> SwiftUI.Font {
            .custom("InstrumentSerif-Regular", size: size)
        }
    }
}
