import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ProjectListView: View {
    @State var viewModel: ProjectListViewModel
    let onSelectProject: (Project) -> Void
    /// The red record button: creates a project and opens the editor recording.
    let onInstantRecord: () -> Void
    /// The profile button, top-right. Settings is a sheet owned by `RootView`.
    let onOpenSettings: () -> Void

    @State private var showingImportMenu     = false
    @State private var isImportingFromFiles  = false
    @State private var isImportingFromPhotos = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var searchQuery           = ""

    private var filteredProjects: [Project] {
        guard !searchQuery.isEmpty else { return viewModel.projects }
        return viewModel.projects.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
    }

    private var showErrorAlert: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { showing in if !showing { viewModel.errorMessage = nil } }
        )
    }

    private var isEmpty: Bool {
        viewModel.projects.isEmpty && viewModel.pendingImports.isEmpty && !viewModel.isLoading
    }

    var body: some View {
        ZStack {
            AppBackground()

            if isEmpty {
                emptyState
            } else {
                projectList
            }
        }
        // Native large title + native search. On iPhone the search field lands in
        // the bottom toolbar next to the action buttons (the Mail/Files layout),
        // and minimises to a magnifier once the user scrolls.
        .navigationTitle(AppConfig.appName)
        .searchable(text: $searchQuery, prompt: Text("Search"))
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onOpenSettings) {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("Settings")
            }

            // Bottom bar: search on the leading side, the two actions trailing.
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button {
                    showingImportMenu = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Import track")
            }
            ToolbarItem(placement: .bottomBar) {
                Button(action: onInstantRecord) {
                    Image(systemName: "record.circle.fill")
                }
                .tint(.red)
                .buttonStyle(.glassProminent)
                .foregroundStyle(.white)
                .accessibilityLabel("Record now")
                .accessibilityHint("Starts a new project and begins recording immediately")
            }
        }
        .sheet(isPresented: $showingImportMenu) {
            ImportMenuSheet(
                onPickPhotos: {
                    showingImportMenu = false
                    isImportingFromPhotos = true
                },
                onPickFiles: {
                    showingImportMenu = false
                    isImportingFromFiles = true
                }
            )
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
        .fileImporter(
            isPresented: $isImportingFromFiles,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .photosPicker(
            isPresented: $isImportingFromPhotos,
            selection: $photoPickerItem,
            matching: .videos
        )
        .onChange(of: photoPickerItem) {
            guard let item = photoPickerItem else { return }
            photoPickerItem = nil
            // Fire-and-forget: the view model represents the running import as a
            // pending row in the list, so nothing here blocks the screen.
            Task { await viewModel.importPhotoItem(item) }
        }
        .alert("Error", isPresented: showErrorAlert) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        // A gentle confirmation the moment an import actually lands as a project —
        // by then the picker interaction is long past.
        .sensoryFeedback(.success, trigger: viewModel.projects.count) { old, new in new > old }
        .task { await viewModel.loadProjects() }
    }

    // MARK: - Project list

    private var projectList: some View {
        List {
            ForEach(viewModel.pendingImports) { pending in
                PendingImportRow(pending: pending)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(rowInsets)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if filteredProjects.isEmpty && viewModel.pendingImports.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
                    .padding(.top, DS.Spacing.xxl)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(filteredProjects) { project in
                Button { onSelectProject(project) } label: {
                    ProjectCard(project: project)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(rowInsets)
            }
            .onDelete { offsets in
                let ids = Set(offsets.map { filteredProjects[$0].id })
                Task { await viewModel.delete(ids: ids) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        // Scoped to the List and keyed to pendingImports only: pending rows animate
        // in/out, but the initial projects load doesn't animate the whole screen's
        // layout (which read as everything flying in from the top-left corner).
        .animation(DS.Animation.smooth, value: viewModel.pendingImports)
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(
            top: DS.Spacing.xxs,
            leading: DS.Spacing.lg,
            bottom: DS.Spacing.xxs,
            trailing: DS.Spacing.lg
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Projects", systemImage: "waveform")
        } description: {
            Text("Import a backing track or video, or tap Record to sing straight away.")
        } actions: {
            Button {
                showingImportMenu = true
            } label: {
                Text("Import Track")
                    .padding(.horizontal, DS.Spacing.sm)
            }
            .buttonStyle(.glassProminent)
            .tint(DS.Brand.accent)
            .foregroundStyle(.white)
        }
    }

    // MARK: - Handlers

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await viewModel.createProject(title: "", from: url) }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Pending import row

/// One in-flight import, shown in place in the list: a live indeterminate spinner
/// on a normal-looking row. Deliberately not tappable — there's no project behind
/// it yet — but it never blocks the rest of the screen.
private struct PendingImportRow: View {
    let pending: ProjectListViewModel.PendingImport

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                Image(systemName: "waveform")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .frame(width: DS.Size.thumbnail, height: DS.Size.thumbnail)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("New project")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(pending.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ProgressView()
                .controlSize(.regular)
        }
        .padding(DS.Spacing.sm)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.Radius.card))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Importing project, \(pending.detail)")
    }
}

// MARK: - Import menu sheet

/// Bottom sheet with the two import sources, styled as plain rows — the standard
/// place for a "where from?" choice, and it never takes over the whole screen.
private struct ImportMenuSheet: View {
    let onPickPhotos: () -> Void
    let onPickFiles: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("New Project")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("Where's your audio coming from?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, DS.Spacing.xl)

            VStack(spacing: DS.Spacing.sm) {
                ImportSourceRow(
                    title: "From Photos",
                    subtitle: "Pick a video — its audio is extracted",
                    icon: "photo.on.rectangle.angled",
                    action: onPickPhotos
                )
                ImportSourceRow(
                    title: "From Files",
                    subtitle: "Any audio or video file",
                    icon: "folder",
                    action: onPickFiles
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .presentationBackground(Color(.systemGroupedBackground))
    }
}

private struct ImportSourceRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(Color(.tertiarySystemFill), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(DS.Spacing.sm)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.Radius.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
