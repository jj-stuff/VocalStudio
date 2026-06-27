import SwiftUI

// Screens push `true` up through this key when they want the tab bar hidden
// (e.g. a full-screen overlay). MainTabView reads it and animates the bar away.
struct TabBarHiddenKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct MainTabView: View {
    let store: ProjectStoreInterface

    @State private var selectedTab: AppTab = .projects
    @Namespace private var tabNamespace
    @State private var tabBarHidden = false

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: DS.Size.tabBarH + DS.Spacing.sm)
                }
                .onPreferenceChange(TabBarHiddenKey.self) { tabBarHidden = $0 }

            if !tabBarHidden {
                CustomTabBar(selectedTab: $selectedTab, namespace: tabNamespace)
                    .ignoresSafeArea(.keyboard)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(DS.Animation.spring, value: tabBarHidden)
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .projects:
            ProjectsTab(store: store)
        case .studio:
            PlaceholderTab(icon: "mic.fill", title: "Studio", subtitle: "Record and monitor your vocals.\nComing in v1.")
        case .explore:
            PlaceholderTab(icon: "sparkles", title: "Explore", subtitle: "Presets, tips, and inspiration.\nComing soon.")
        case .settings:
            PlaceholderTab(icon: "gearshape.fill", title: "Settings", subtitle: "App preferences and account.")
        }
    }
}

// MARK: - Projects tab (owns its own NavigationStack)

private struct ProjectsTab: View {
    let store: ProjectStoreInterface

    @State private var vm: ProjectListViewModel
    @State private var path: [AppDestination] = []

    init(store: ProjectStoreInterface) {
        self.store = store
        _vm = State(initialValue: ProjectListViewModel(store: store))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ProjectListView(viewModel: vm) { project in
                path.append(.editor(project))
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppDestination.self) { dest in
                destination(for: dest)
            }
        }
    }

    @ViewBuilder
    private func destination(for dest: AppDestination) -> some View {
        switch dest {
        case .editor(let project):
            EditorView(viewModel: EditorViewModel(project: project, store: store))
        }
    }
}

// MARK: - Placeholder tab

private struct PlaceholderTab: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: DS.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundStyle(DS.Brand.purple1)
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(DS.Spacing.xl)
        }
    }
}
