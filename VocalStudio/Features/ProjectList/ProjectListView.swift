import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ProjectListView: View {
    @State var viewModel: ProjectListViewModel
    let onSelectProject: (Project) -> Void

    @State private var showingImportMenu     = false
    @State private var isImportingFromFiles  = false
    @State private var isImportingFromPhotos = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var searchQuery           = ""
    @FocusState private var isSearchFocused: Bool

    /// Distance from the safe-area bottom to the TOP of the floating tab bar —
    /// derived from the bar's real metrics so nothing overlaps it.
    private let tabClearance: CGFloat = DS.Size.tabBarVisualH + DS.Spacing.xl

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

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.sm)

                if viewModel.projects.isEmpty && viewModel.pendingImports.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    if viewModel.projects.count > 1 {
                        searchField
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.bottom, DS.Spacing.sm)
                    }
                    projectList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .zIndex(0)
            // Tap anywhere — header, empty space, or the list itself — to drop
            // search focus. simultaneousGesture so it doesn't steal taps meant for
            // row buttons or the search field's own clear button.
            .simultaneousGesture(
                TapGesture().onEnded { isSearchFocused = false }
            )

            // Trailing padding matches the tab bar's horizontal padding, and the
            // record button is the same diameter — so the "+" floats exactly on
            // the record button's vertical axis, a spacing step above the bar.
            fabButton
                .padding(.trailing, DS.Spacing.xl)
                .padding(.bottom, tabClearance + DS.Spacing.sm)
                .zIndex(5)
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            Text("Aria")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("\(viewModel.projects.count)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search", text: $searchQuery)
                .font(.system(size: 15))
                .autocorrectionDisabled()
                .focused($isSearchFocused)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(Color(.secondarySystemGroupedBackground), in: .capsule)
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

            Color.clear
                .frame(height: tabClearance + DS.Size.fab)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
        VStack(spacing: DS.Spacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.primary)
                    .frame(width: 80, height: 80)
                Image(systemName: "mic.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color(.systemBackground))
            }

            VStack(spacing: DS.Spacing.xs) {
                Text("No Projects Yet")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Text("Import a backing track or video\nto start singing over it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showingImportMenu = true
            } label: {
                Label("Import Track", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.sm + DS.Spacing.xxs)
                    .background(Color.primary, in: .capsule)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.xxxl)
        .padding(.bottom, tabClearance)
    }

    // MARK: - FAB

    private var fabButton: some View {
        Image(systemName: "plus")
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: DS.Size.fab, height: DS.Size.fab)
            .background(Color(.secondarySystemGroupedBackground), in: Circle())
            .overlay(Circle().stroke(Color(.separator), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
            .contentShape(Circle())
            // highPriorityGesture, not a Button — the FAB overlaps the List underneath
            // it (in the bottomTrailing ZStack corner), and the List's own UIKit-backed
            // scroll/row gesture recognizers intermittently won the touch over a plain
            // Button despite zIndex, which only orders SwiftUI's own hit-testing, not
            // UIKit's responder chain. This forces the tap to win outright.
            .highPriorityGesture(
                TapGesture().onEnded { showingImportMenu = true }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Import track")
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
