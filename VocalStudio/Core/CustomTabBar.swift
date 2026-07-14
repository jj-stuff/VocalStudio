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
        isSelected ? .primary : Color(.secondaryLabel)
    }
}

struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    let onInstantRecord: () -> Void

    @Namespace private var tabSelection

    private static let recordSize: CGFloat = DS.Size.tabBarH + 4

    var body: some View {
        // Pill bar with the tabs, plus a separate circular record button beside it —
        // the action stands apart from navigation instead of being wedged into the
        // middle of the bar.
        HStack(spacing: DS.Spacing.sm) {
            HStack(spacing: 0) {
                tabItem(.projects)
                tabItem(.settings)
            }
            // Explicit height (not .fixedSize) — pins the bar so the matchedGeometryEffect
            // pill's spring transition between tabs can never read back into the ancestor's
            // ideal-size and visibly resize the whole bar mid-animation.
            .frame(height: DS.Size.tabBarH)
            .padding(.horizontal, DS.Spacing.xxs)
            .padding(.vertical, DS.Spacing.xxs)
            .glassEffect(in: .capsule)
            .overlay(Capsule().stroke(Color(.separator), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 20, y: 8)

            instantRecordButton
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.bottom, DS.Spacing.xl)
        .sensoryFeedback(.selection, trigger: selectedTab)
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
            .padding(.vertical, DS.Spacing.xs)
            .padding(.horizontal, DS.Spacing.md)
            // The selection pill slides between tabs via matchedGeometryEffect,
            // driven by the withAnimation in the button action.
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .matchedGeometryEffect(id: "selectedTabPill", in: tabSelection)
                }
            }
            .frame(maxWidth: .infinity)
            // Make the full content area (icon + label + all padding) tappable,
            // not just the tight bounding rect of the text/image glyphs.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
    }

    // MARK: - Instant record
    //
    // Not a tab — doesn't touch `selectedTab`. A red ring with a punched-out center
    // (the system record affordance) that immediately creates a project and starts
    // recording (see MainTabView.startInstantRecord).

    private var instantRecordButton: some View {
        Button(action: onInstantRecord) {
            ZStack {
                Circle()
                    .fill(Color.red)
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: Self.recordSize * 0.42, height: Self.recordSize * 0.42)
            }
            .frame(width: Self.recordSize, height: Self.recordSize)
            .overlay(Circle().stroke(Color(.separator), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record now")
        .accessibilityHint("Starts a new project and begins recording immediately")
    }
}
