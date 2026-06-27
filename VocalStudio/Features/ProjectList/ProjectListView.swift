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
    @State private var isLoadingPhoto        = false

    private let tabClearance: CGFloat = DS.Size.tabBarH + DS.Spacing.lg

    // Hide the tab bar whenever any full-screen overlay is active.
    private var shouldHideTabBar: Bool {
        showingImportMenu || viewModel.isConvertingVideo || isLoadingPhoto
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AnimatedBlobBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                titleRow
                    .padding(.horizontal, DS.Spacing.md + DS.Spacing.xs)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.sm)

                if viewModel.projects.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    projectList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if !showingImportMenu {
                fabButton
                    .padding(.trailing, DS.Spacing.md)
                    .padding(.bottom, tabClearance)
                    .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
            }

            if showingImportMenu {
                importOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }

            if viewModel.isConvertingVideo || isLoadingPhoto {
                loadingOverlay
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .animation(DS.Animation.spring, value: showingImportMenu)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isConvertingVideo || isLoadingPhoto)
        .preference(key: TabBarHiddenKey.self, value: shouldHideTabBar)
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
            Task { await handlePhotoItem(item) }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task { await viewModel.loadProjects() }
    }

    // MARK: - Title row

    private var titleRow: some View {
        HStack(alignment: .bottom) {
            Text("Projects")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, DS.Spacing.xxs)
            } else {
                Text("\(viewModel.projects.count)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, DS.Spacing.xxs)
            }
        }
    }

    // MARK: - Project list

    private var projectList: some View {
        List {
            ForEach(viewModel.projects) { project in
                Button { onSelectProject(project) } label: {
                    ProjectCard(project: project)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: DS.Spacing.xxs,
                    leading: DS.Spacing.md,
                    bottom: DS.Spacing.xxs,
                    trailing: DS.Spacing.md
                ))
            }
            .onDelete { offsets in Task { await viewModel.delete(at: offsets) } }

            Color.clear
                .frame(height: tabClearance + DS.Size.fab)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [DS.Brand.purple1, DS.Brand.purple2],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 80, height: 80)
                Image(systemName: "mic.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }

            VStack(spacing: DS.Spacing.xs) {
                Text("No Projects Yet")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text("Import a backing track or video\nto start singing over it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button { withAnimation(DS.Animation.spring) { showingImportMenu = true } } label: {
                Label("Import Track", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(DS.Brand.purple1)
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.sm + DS.Spacing.xxs)
                    .glassEffect(in: .capsule)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.xxxl)
        .padding(.bottom, tabClearance)
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button { withAnimation(DS.Animation.spring) { showingImportMenu = true } } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DS.Brand.purple1)
                .frame(width: DS.Size.fab, height: DS.Size.fab)
                .glassEffect(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Import track")
    }

    // MARK: - Import overlay

    private var importOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color(.systemBackground).opacity(0.25))
                .ignoresSafeArea()
                .onTapGesture { withAnimation(DS.Animation.spring) { showingImportMenu = false } }

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("NEW PROJECT")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(2)
                    Text("Where's your\naudio coming from?")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, DS.Spacing.xl + DS.Spacing.xs)
                .padding(.top, DS.Spacing.xxxl + DS.Spacing.lg)

                Spacer()

                VStack(alignment: .trailing, spacing: DS.Spacing.md) {
                    importOptionRow(label: "From Photos", icon: "photo.on.rectangle.angled") {
                        withAnimation(DS.Animation.spring) { showingImportMenu = false }
                        isImportingFromPhotos = true
                    }
                    importOptionRow(label: "From Files", icon: "folder") {
                        withAnimation(DS.Animation.spring) { showingImportMenu = false }
                        isImportingFromFiles = true
                    }

                    Button { withAnimation(DS.Animation.spring) { showingImportMenu = false } } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: DS.Size.fab, height: DS.Size.fab)
                            .glassEffect(in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xxxl + DS.Spacing.sm)
            }
        }
        .ignoresSafeArea()
    }

    private func importOptionRow(label: String, icon: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .glassEffect(in: .capsule)

            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(.primary)
                    .frame(width: DS.Size.fab, height: DS.Size.fab)
                    .glassEffect(in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading overlay

    private var loadingOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: DS.Spacing.xl) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [DS.Brand.purple1.opacity(0.6), DS.Brand.purple2.opacity(0.4)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 72, height: 72)
                        .blur(radius: 22)

                    ProgressView()
                        .controlSize(.large)
                        .tint(DS.Brand.purple1)
                }

                VStack(spacing: DS.Spacing.xxs) {
                    Text(isLoadingPhoto ? "Converting Video" : "Importing Track")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("This might take a moment")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(DS.Spacing.xxxl)
            .glassEffect(in: RoundedRectangle(cornerRadius: DS.Radius.hero))
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

    private func handlePhotoItem(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        do {
            guard let video = try await item.loadTransferable(type: VideoTransferable.self) else {
                viewModel.errorMessage = "Could not load the selected video."
                return
            }
            await viewModel.createProject(title: "", from: video.url)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
