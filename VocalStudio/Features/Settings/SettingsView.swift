import SwiftUI

/// Settings, presented as a sheet from the project list. A native inset-grouped
/// `List` — the same bones as the system Settings app, so it inherits every
/// platform behaviour (Dynamic Type, VoiceOver row grouping, dark mode, the
/// sheet's own scroll-edge treatment) for free.
struct SettingsView: View {
    @State var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(PlusEntitlement.self) private var entitlement
    @Environment(\.openURL) private var openURL

    @State private var showingDeleteAllConfirm = false
    @State private var showingPaywall = false

    private var showErrorAlert: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { showing in if !showing { viewModel.errorMessage = nil } }
        )
    }

    private var showActionAlert: Binding<Bool> {
        Binding(
            get: { viewModel.lastActionMessage != nil },
            set: { showing in if !showing { viewModel.lastActionMessage = nil } }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if !entitlement.isActive {
                    plusBanner
                }
                appearanceSection
                storageSection
                supportSection
                legalSection
                dangerSection
                footer
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
            }
            .overlay {
                if viewModel.isWorking {
                    loadingOverlay
                }
            }
        }
        .task { viewModel.refresh() }
        .sheet(isPresented: $showingPaywall) {
            PlusPaywallView()
        }
        .alert("Error", isPresented: showErrorAlert) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert(viewModel.lastActionMessage ?? "", isPresented: showActionAlert) {
            Button("OK") { viewModel.lastActionMessage = nil }
        }
        .alert("Delete All Projects?", isPresented: $showingDeleteAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                Task { await viewModel.deleteAllProjects() }
            }
        } message: {
            Text("This permanently deletes every project, recording and separated stem on this device. You can't undo this.")
        }
    }

    // MARK: - Aria Plus banner
    //
    // The Mist-style upgrade card at the top. Tinted with the brand purple so it
    // stands apart from the monochrome rows below it. Hidden once the user has Plus.

    private var plusBanner: some View {
        Section {
            Button {
                showingPaywall = true
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    SettingsIconTile(
                        systemImage: "sparkles",
                        tint: .white.opacity(0.22),
                        symbolColor: .white
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upgrade to \(AppConfig.Plus.productName)")
                            .font(.headline)
                        Text("Autotune and everything coming next.")
                            .font(.footnote)
                            .opacity(0.85)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .opacity(0.8)
                }
                .foregroundStyle(.white)
                .padding(.vertical, DS.Spacing.xxs)
            }
            .buttonStyle(.plain)
            .listRowBackground(
                LinearGradient(
                    colors: [DS.Brand.pink, DS.Brand.purple2],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section {
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                SettingsRowLabel("Appearance", systemImage: "paintbrush.fill")
            }
        }
    }

    private var storageSection: some View {
        Section {
            ForEach(viewModel.folderUsage, id: \.name) { entry in
                SettingsRowLabel(title: label(for: entry.name), systemImage: icon(for: entry.name)) {
                    Text(entry.bytes, format: .byteCount(style: .file))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Button {
                Task { await viewModel.cleanUpUnusedFiles() }
            } label: {
                SettingsRowLabel("Clean Up Unused Files", systemImage: "sparkles")
            }
            .disabled(viewModel.isWorking)
        } header: {
            Text("Storage")
        } footer: {
            Text("Everything stays on this device. Deleting a project removes its files. Clean Up only removes files no project uses any more.")
        }
    }

    private var supportSection: some View {
        Section("Support") {
            SettingsActionRow(title: "Contact Support", systemImage: "envelope.fill") {
                openURL(AppConfig.supportMailURL)
            }
            SettingsActionRow(title: "Rate \(AppConfig.appName)", systemImage: "star.fill") {
                openURL(AppConfig.appStoreReviewURL)
            }
            ShareLink(item: AppConfig.websiteURL) {
                SettingsRowLabel("Share \(AppConfig.appName)", systemImage: "square.and.arrow.up.fill")
            }
        }
    }

    private var legalSection: some View {
        Section("Legal") {
            SettingsActionRow(title: "Terms of Service", systemImage: "doc.text.fill") {
                openURL(AppConfig.termsOfServiceURL)
            }
            SettingsActionRow(title: "Privacy Policy", systemImage: "hand.raised.fill") {
                openURL(AppConfig.privacyPolicyURL)
            }
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteAllConfirm = true
            } label: {
                SettingsRowLabel(
                    "Delete All Projects",
                    systemImage: "trash.fill",
                    tint: .red.opacity(0.12),
                    symbolColor: .red
                )
                .foregroundStyle(.red)
            }
            .disabled(viewModel.isWorking)
        }
    }

    // MARK: - Footer (wordmark + version)

    private var footer: some View {
        Section {
            VStack(spacing: DS.Spacing.xs) {
                Text(AppConfig.appName)
                    .font(DS.Font.wordmark(34))
                Text(AppConfig.versionString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.lg)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Loading

    private var loadingOverlay: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            ProgressView()
                .controlSize(.large)
        }
    }

    // MARK: - Folder display

    private func icon(for folderName: String) -> String {
        switch folderName {
        case "Audio":      "music.note"
        case "Recordings": "mic.fill"
        case "Stems":      "waveform"
        default:           "doc.fill"
        }
    }

    private func label(for folderName: String) -> LocalizedStringKey {
        switch folderName {
        case "Audio":      "Imported Tracks"
        case "Recordings": "Your Recordings"
        case "Stems":      "Separated Stems"
        default:           LocalizedStringKey(folderName)
        }
    }
}
