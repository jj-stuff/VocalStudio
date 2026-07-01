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
    @State private var tabBarHidden = false
    @State private var instantRecordProject: Project?

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: DS.Size.tabBarH + DS.Spacing.sm)
                }
                .onPreferenceChange(TabBarHiddenKey.self) { tabBarHidden = $0 }

            if !tabBarHidden {
                CustomTabBar(selectedTab: $selectedTab, onInstantRecord: startInstantRecord)
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
            ProjectsTab(store: store, instantRecordProject: $instantRecordProject)
        case .settings:
            SettingsView(viewModel: SettingsViewModel(store: store))
        }
    }

    // MARK: - Instant record
    //
    // The donut button doesn't select a tab — it creates a project (a silent source
    // so the existing Project/Track pipeline needs no changes) and asks the Projects
    // tab to push straight into the editor with recording already running. "Sing and
    // play at the same time, separate the vocals later" is the whole point — no
    // backing track required up front.

    private func startInstantRecord() {
        selectedTab = .projects
        Task {
            guard let sourceURL = try? SilentAudioFile.make() else { return }
            let project = Project(title: CatBreedNamer.randomName(avoiding: []), sourceURL: sourceURL)
            try? await store.save(project)
            instantRecordProject = project
        }
    }
}

// MARK: - Projects tab (owns its own NavigationStack)

private struct ProjectsTab: View {
    let store: ProjectStoreInterface
    @Binding var instantRecordProject: Project?

    @State private var vm: ProjectListViewModel
    @State private var path: [AppDestination] = []

    init(store: ProjectStoreInterface, instantRecordProject: Binding<Project?>) {
        self.store = store
        self._instantRecordProject = instantRecordProject
        _vm = State(initialValue: ProjectListViewModel(store: store))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ProjectListView(viewModel: vm) { project in
                path.append(.editor(project, autoRecord: false))
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppDestination.self) { dest in
                destination(for: dest)
            }
        }
        .onChange(of: instantRecordProject) {
            guard let project = instantRecordProject else { return }
            instantRecordProject = nil
            path.append(.editor(project, autoRecord: true))
        }
    }

    @ViewBuilder
    private func destination(for dest: AppDestination) -> some View {
        switch dest {
        case .editor(let project, let autoRecord):
            EditorView(viewModel: EditorViewModel(project: project, store: store, autoStartRecording: autoRecord))
        }
    }
}
