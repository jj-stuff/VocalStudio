import SwiftUI

struct SettingsView: View {
    @State var viewModel: SettingsViewModel
    @State private var showingDeleteAllConfirm = false

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    header
                    storageCard
                    dangerZoneCard
                }
                .padding(.horizontal, DS.Spacing.md + DS.Spacing.xs)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Size.tabBarH + DS.Spacing.xl)
            }
            .scrollIndicators(.hidden)

            if viewModel.isWorking {
                loadingOverlay
            }
        }
        .task { viewModel.refresh() }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert(
            viewModel.lastActionMessage ?? "",
            isPresented: .constant(viewModel.lastActionMessage != nil)
        ) {
            Button("OK") { viewModel.lastActionMessage = nil }
        }
        .alert("Delete All Projects?", isPresented: $showingDeleteAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                Task { await viewModel.deleteAllProjects() }
            }
        } message: {
            Text("This permanently deletes every project, recording, and separated stem on this device. This can't be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 22))
                .foregroundStyle(DS.Brand.purple1)
            Text("Settings")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.top, DS.Spacing.sm)
    }

    // MARK: - Storage

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm + DS.Spacing.xxs) {
            HStack {
                Text("STORAGE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.5)
                Spacer()
                Text(Self.byteFormatter.string(fromByteCount: viewModel.totalBytes))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            VStack(spacing: DS.Spacing.sm - DS.Spacing.xxs) {
                ForEach(viewModel.folderUsage, id: \.name) { entry in
                    HStack {
                        Image(systemName: icon(for: entry.name))
                            .font(.system(size: 14))
                            .foregroundStyle(DS.Brand.purple1)
                            .frame(width: 22)
                        Text(label(for: entry.name))
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(Self.byteFormatter.string(fromByteCount: entry.bytes))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider().opacity(0.2)

            Text("Recordings and separated stems are saved on this device only — deleting a project frees its files automatically. Use this if files were ever left behind by an older version of the app.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            Button {
                Task { await viewModel.cleanUpUnusedFiles() }
            } label: {
                Label("Clean Up Unused Files", systemImage: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Brand.purple1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm - DS.Spacing.xxs)
                    .glassEffect(in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isWorking)
        }
        .padding(DS.Spacing.md)
        .glassEffect(in: RoundedRectangle(cornerRadius: DS.Radius.card))
    }

    // MARK: - Danger zone

    private var dangerZoneCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("DANGER ZONE")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1.5)

            Text("Permanently deletes every project, recording, and separated stem on this device. This can't be undone.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Button {
                showingDeleteAllConfirm = true
            } label: {
                Label("Delete All Projects", systemImage: "trash.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm - DS.Spacing.xxs)
                    .glassEffect(in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isWorking)
        }
        .padding(DS.Spacing.md)
        .glassEffect(in: RoundedRectangle(cornerRadius: DS.Radius.card))
    }

    // MARK: - Loading

    private var loadingOverlay: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            ProgressView()
                .controlSize(.large)
                .tint(DS.Brand.purple1)
        }
    }

    // MARK: - Folder display

    private func icon(for folderName: String) -> String {
        switch folderName {
        case "Audio": "music.note"
        case "Recordings": "mic.fill"
        case "Stems": "waveform"
        default: "doc"
        }
    }

    private func label(for folderName: String) -> String {
        switch folderName {
        case "Audio": "Imported Tracks"
        case "Recordings": "Your Recordings"
        case "Stems": "Separated Stems"
        default: folderName
        }
    }
}
