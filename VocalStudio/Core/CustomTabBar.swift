import SwiftUI

enum AppTab: String, CaseIterable {
    case projects = "Projects"
    case studio   = "Studio"
    case explore  = "Explore"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .projects: "music.note.list"
        case .studio:   "mic.fill"
        case .explore:  "sparkles"
        case .settings: "gearshape.fill"
        }
    }

    func iconWeight(isSelected: Bool) -> Font.Weight { isSelected ? .semibold : .regular }
    func itemColor(isSelected: Bool) -> Color {
        isSelected ? DS.Brand.purple1 : Color(.secondaryLabel)
    }
}

struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    var namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabItem(tab)
            }
        }
        // Explicit height (not .fixedSize) — pins the bar so the matchedGeometryEffect
        // pill's spring transition between tabs can never read back into the ancestor's
        // ideal-size and visibly resize the whole bar mid-animation.
        .frame(height: DS.Size.tabBarH)
        .padding(.horizontal, DS.Spacing.xxs)
        .padding(.vertical, DS.Spacing.xxs)
        .glassEffect(in: .capsule)
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.bottom, DS.Spacing.xl)
    }

    // MARK: - Tab item

    private func tabItem(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(DS.Animation.spring) { selectedTab = tab }
        } label: {
            // VStack drives the size. The pill lives in .background so it
            // inherits the VStack bounds rather than becoming a greedy ZStack child.
            // contentShape ensures the entire pill area — including padding — is tappable.
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17, weight: tab.iconWeight(isSelected: isSelected)))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tab.itemColor(isSelected: isSelected))

                Text(tab.rawValue)
                    .font(.system(size: 10, weight: tab.iconWeight(isSelected: isSelected)))
                    .foregroundStyle(tab.itemColor(isSelected: isSelected))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xs)
            .background {
                if isSelected {
                    Capsule()
                        .fill(DS.Brand.purple1.opacity(0.22))
                        .matchedGeometryEffect(id: "tabPill", in: namespace)
                }
            }
            // Make the full content area (icon + label + all padding) tappable,
            // not just the tight bounding rect of the text/image glyphs.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
    }
}
