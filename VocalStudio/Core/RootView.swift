import SwiftUI

/// The app shell. One `NavigationStack` rooted at the project list; the editor is
/// pushed onto it, Settings is presented as a sheet from the profile button.
///
/// There is deliberately no tab bar: the app has a single destination, so the old
/// two-tab bar spent a permanent strip of the screen on a choice nobody makes
/// more than once a week. Settings lives behind the top-right button, the way
/// Apple Music and Fitness handle their account screens.
///
/// The app theme is deliberately *not* applied here with `preferredColorScheme`:
/// that modifier doesn't reach sheet presentations, so the Settings sheet kept
/// the scheme it opened with. `AppearanceWindowStyler` sets it on the window
/// instead, where every presentation inherits it.
struct RootView: View {
    let store: ProjectStoreInterface

    @State private var entitlement = PlusEntitlement()
    @State private var path: [AppDestination] = []
    @State private var showingSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            ProjectListView(
                viewModel: ProjectListViewModel(store: store),
                onSelectProject: { project in
                    path.append(.editor(project, autoRecord: false))
                },
                onInstantRecord: startInstantRecord,
                onOpenSettings: { showingSettings = true }
            )
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case .editor(let project, let autoRecord):
                    EditorView(viewModel: EditorViewModel(
                        project: project,
                        store: store,
                        autoStartRecording: autoRecord
                    ))
                }
            }
        }
        // Environment first, then the sheet, so Settings (and everything it
        // presents) sees the entitlement too.
        .environment(entitlement)
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: SettingsViewModel(store: store))
                .environment(entitlement)
        }
        .task { await entitlement.refresh() }
    }

    // MARK: - Instant record
    //
    // The record button on the project list doesn't navigate anywhere by itself.
    // It creates a project with a silent placeholder source (so the existing
    // Project/Track pipeline needs no special case) and pushes the editor with
    // recording already running. "Sing first, sort it out later."

    private func startInstantRecord() {
        Task {
            guard let sourceURL = try? SilentAudioFile.make() else { return }
            // Load current titles so the collision-avoiding suffix has something
            // to avoid — passing [] handed out duplicate names.
            let existingTitles = ((try? await store.loadAll()) ?? []).map(\.title)
            let project = Project(
                title: CatBreedNamer.randomName(avoiding: existingTitles),
                sourceURL: sourceURL
            )
            try? await store.save(project)
            path.append(.editor(project, autoRecord: true))
        }
    }
}
