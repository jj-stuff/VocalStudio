import SwiftUI

struct EditorView: View {
    @State var viewModel: EditorViewModel

    @State private var showingRename = false
    @State private var pendingTitle = ""
    @FocusState private var renameFieldFocused: Bool

    private var showErrorAlert: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { showing in if !showing { viewModel.errorMessage = nil } }
        )
    }

    // Bridges the track-selection state into a sheet-presented Bool. Every track kind
    // gets a sheet now (volume applies to all of them) — only the effects tiles inside
    // are conditional on effectsApplicable. When the sheet is drag-dismissed, the
    // binding setter deselects the track.
    private var showEffectsSheet: Binding<Bool> {
        Binding(
            get: { viewModel.selectedTrack != nil },
            set: { showing in if !showing { viewModel.deselectTrack() } }
        )
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                TransportBarView(
                    currentTime: viewModel.currentTime,
                    duration: viewModel.duration,
                    isPlaying: viewModel.transportActive,
                    isRecording: viewModel.isRecording,
                    stemStatus: viewModel.stemStatus,
                    showsSeparate: viewModel.canSeparateStems,
                    onTogglePlayback: viewModel.togglePlayback,
                    onRewind: viewModel.rewind,
                    onToggleRecord: viewModel.toggleRecording,
                    onSeparateStems: viewModel.startStemSeparation
                )
                .padding(.horizontal, DS.Spacing.md)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.xs)

                EditorTimelineView(
                    tracks: viewModel.tracks,
                    currentTime: viewModel.currentTime,
                    duration: viewModel.duration,
                    recordingRange: viewModel.recordingRange,
                    selectedTrackID: viewModel.selectedTrackID,
                    onSelectTrack: viewModel.selectTrack,
                    onMuteTrack: viewModel.toggleMute,
                    onMoveClip: { trackID, clipID, offset in
                        viewModel.moveClip(id: clipID, inTrack: trackID, to: offset)
                    },
                    onTrimClip: { trackID, clipID, trimStart, trimEnd, offset in
                        viewModel.trimClip(id: clipID, inTrack: trackID, trimStart: trimStart, trimEnd: trimEnd, timelineOffset: offset)
                    },
                    onDeleteClip: { trackID, clipID in
                        viewModel.deleteClip(id: clipID, inTrack: trackID)
                    },
                    onScrub: viewModel.seek
                )
                .frame(maxHeight: .infinity)
            }

            if showingRename {
                renameOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(30)
            }
        }
        .navigationTitle(viewModel.project.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    pendingTitle = viewModel.project.title
                    withAnimation(DS.Animation.spring) { showingRename = true }
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Rename project")
            }
        }
        .preference(key: TabBarHiddenKey.self, value: true)
        .animation(DS.Animation.spring, value: viewModel.stemStatus)
        .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.isRecording)
        .sensoryFeedback(.selection, trigger: viewModel.selectedTrackID)
        .sensoryFeedback(trigger: viewModel.stemStatus) { _, newStatus in
            switch newStatus {
            case .done: .success
            case .failed: .error
            default: nil
            }
        }
        .task { await viewModel.start() }
        .onDisappear { viewModel.tearDown() }
        .alert("Error", isPresented: showErrorAlert) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: showEffectsSheet) {
            effectsSheet
        }
    }

    // MARK: - Rename overlay (custom — never the native alert/TextField)

    private var renameOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture(perform: dismissRename)

            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("RENAME")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(2)
                    Text("Name this project")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                }

                TextField("Project name", text: $pendingTitle)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(DS.Spacing.md)
                    .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: DS.Radius.md))
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($renameFieldFocused)
                    .onSubmit(commitRename)

                HStack(spacing: DS.Spacing.sm) {
                    Button("Cancel", action: dismissRename)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm + DS.Spacing.xxs)
                    .glassEffect(in: .capsule)
                    .buttonStyle(.plain)

                    Button(action: commitRename) {
                        Text("Save")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color(.systemBackground))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Spacing.sm + DS.Spacing.xxs)
                            .background(Color.primary, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DS.Spacing.xl)
            .glassEffect(in: RoundedRectangle(cornerRadius: DS.Radius.hero))
            .padding(.horizontal, DS.Spacing.lg)
        }
        .ignoresSafeArea(.container)
        // Renaming is a one-field flow — bring the keyboard up with the card
        // instead of demanding an extra tap into the field.
        .onAppear { renameFieldFocused = true }
    }

    private func commitRename() {
        viewModel.renameProject(to: pendingTitle)
        dismissRename()
    }

    /// Every dismissal path drops field focus FIRST, so the keyboard animates down
    /// on its own — removing the overlay while the field is still focused yanks the
    /// keyboard away with no animation.
    private func dismissRename() {
        renameFieldFocused = false
        withAnimation(DS.Animation.spring) { showingRename = false }
    }

    // MARK: - Effects sheet

    @ViewBuilder
    private var effectsSheet: some View {
        if let track = viewModel.selectedTrack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        VolumeTileView(
                            volume: track.volume,
                            onVolumeChange: viewModel.updateVolume
                        )
                        if track.effectsApplicable {
                            AutotuneTileView()
                            ReverbTileView(
                                reverbMix: track.effects.reverbMix,
                                onReverbChange: viewModel.updateReverb
                            )
                            EQTileView(
                                eqGains: track.effects.eqGains,
                                onEQChange: viewModel.updateEQGain
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .scrollIndicators(.hidden)
                // Grouped background so the flat white tiles read as cards — on the
                // sheet's default plain background they'd disappear in light mode.
                .background(Color(.systemGroupedBackground))
                .navigationTitle(track.effectsApplicable ? "\(track.name) Effects" : track.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { viewModel.deselectTrack() }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            // Background interaction means a different track header can be tapped
            // while this sheet stays up. The tiles copy their initial values into
            // @State, so without re-identifying the whole sheet per track, the old
            // track's volume/EQ values would be shown — and applied — to the new one.
            .id(track.id)
        }
    }

    // MARK: - Background

    private var background: some View {
        // Flat system background — the editor's chrome (transport card, timeline
        // grid) provides the structure; the canvas itself stays quiet.
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
    }
}
