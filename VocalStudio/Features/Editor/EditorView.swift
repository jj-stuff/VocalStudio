import SwiftUI

struct EditorView: View {
    @State var viewModel: EditorViewModel

    @State private var showingRename = false
    @State private var pendingTitle = ""
    @FocusState private var renameFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

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
                    isPlaying: viewModel.isPlaying,
                    isRecording: viewModel.isRecording,
                    stemStatus: viewModel.stemStatus,
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

            if case .running(let progress) = viewModel.stemStatus {
                separationOverlay(progress: progress)
                    .transition(.opacity)
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
                .onTapGesture {
                    withAnimation(DS.Animation.spring) { showingRename = false }
                }

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
                    Button("Cancel") {
                        withAnimation(DS.Animation.spring) { showingRename = false }
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm + DS.Spacing.xxs)
                    .glassEffect(in: .capsule)
                    .buttonStyle(.plain)

                    Button(action: commitRename) {
                        Text("Save")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Spacing.sm + DS.Spacing.xxs)
                            .background(
                                LinearGradient(
                                    colors: [DS.Brand.purple1, DS.Brand.purple2],
                                    startPoint: .leading, endPoint: .trailing
                                ),
                                in: .capsule
                            )
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
        withAnimation(DS.Animation.spring) { showingRename = false }
    }

    // MARK: - Separation overlay
    //
    // The model is bundled in the app, not downloaded — but loading an ~100MB Core ML
    // graph the first time still takes a few real seconds, and the old inline progress
    // bar in the transport bar was too small to explain that. This makes the two
    // phases (loading the model vs. actually processing audio) legible without being
    // technical about either one.

    private func separationOverlay(progress: Double) -> some View {
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

                    if progress > 0 {
                        ProgressView(value: progress)
                            .progressViewStyle(.circular)
                            .controlSize(.large)
                            .tint(DS.Brand.purple1)
                    } else {
                        ProgressView()
                            .controlSize(.large)
                            .tint(DS.Brand.purple1)
                    }
                }

                VStack(spacing: DS.Spacing.xxs) {
                    Text(progress > 0 ? "Separating Vocals" : "Preparing On-Device Model")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(progress > 0
                        ? "Pulling vocals away from the instrumental — \(Int(progress * 100))%"
                        : "This runs entirely on your device, no upload needed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(DS.Spacing.xxxl)
            .glassEffect(in: RoundedRectangle(cornerRadius: DS.Radius.hero))
            .padding(.horizontal, DS.Spacing.xl)
        }
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
        ZStack {
            Color(.systemBackground)
            // A whisper of the brand purples over the system background. Much
            // lighter in light mode — the deep-purple radials were tuned for dark
            // backgrounds and read as smudges over white.
            RadialGradient(
                colors: [DS.Brand.purple2.opacity(colorScheme == .dark ? 0.30 : 0.10), .clear],
                center: .topLeading, startRadius: 0, endRadius: 420
            )
            RadialGradient(
                colors: [DS.Brand.purple1.opacity(colorScheme == .dark ? 0.20 : 0.08), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 320
            )
        }
        .ignoresSafeArea()
    }
}
