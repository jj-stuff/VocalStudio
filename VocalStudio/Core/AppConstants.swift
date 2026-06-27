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

extension DS {
    enum Brand {
        static let purple1 = Color(.brandPurple1)
        static let purple2 = Color(.brandPurple2)
        static let pink    = Color(.brandPink)
        static let teal    = Color(.brandTeal)
        static let orange  = Color(.brandOrange)
    }
}
