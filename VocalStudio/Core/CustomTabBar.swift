import SwiftUI

enum AppTab: String, CaseIterable {
    case projects = "Projects"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .projects: "music.note.list"
        case .settings: "gearshape.fill"
        }
    }

    // Display logic lives on the model, not in the view body.
    func iconWeight(isSelected: Bool) -> Font.Weight { isSelected ? .semibold : .regular }
    func itemColor(isSelected: Bool) -> Color {
        isSelected ? DS.Brand.purple1 : Color(.secondaryLabel)
    }
}

struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    let onInstantRecord: () -> Void

    private static let donutSize: CGFloat = DS.Size.tabBarH + 12

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                tabItem(.projects)
                // Reserves the center column so the two real tabs don't crowd the donut.
                Color.clear.frame(width: Self.donutSize - DS.Spacing.md)
                tabItem(.settings)
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

            instantRecordButton
                .offset(y: -10)
        }
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
            // Make the full content area (icon + label + all padding) tappable,
            // not just the tight bounding rect of the text/image glyphs.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
    }

    // MARK: - Instant record (donut)
    //
    // Not a tab — doesn't touch `selectedTab`. A circle with a punched-out center,
    // centered on the bar and slightly taller than it, that immediately creates a
    // project and starts recording (see MainTabView.startInstantRecord).

    private var instantRecordButton: some View {
        Button(action: onInstantRecord) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [DS.Brand.pink, DS.Brand.purple1],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: Self.donutSize * 0.42, height: Self.donutSize * 0.42)
            }
            .frame(width: Self.donutSize, height: Self.donutSize)
            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
            .shadow(color: DS.Brand.purple1.opacity(0.4), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record now")
        .accessibilityHint("Starts a new project and begins recording immediately")
    }
}
