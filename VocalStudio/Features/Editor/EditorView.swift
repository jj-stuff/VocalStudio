import SwiftUI

/// The studio. Three layers, bottom to top: the app background, the readout plus
/// timeline, and a floating control layer (clip actions, transport) over the
/// bottom edge. The timeline scrolls under the control layer, which is what earns
/// the glass on it.
struct EditorView: View {
    @State var viewModel: EditorViewModel

    @State private var showingRename = false
    @State private var pendingTitle = ""
    @FocusState private var renameFieldFocused: Bool

    /// Room the timeline leaves under the floating controls.
    private let controlsClearance: CGFloat = 150

    private var showErrorAlert: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { showing in if !showing { viewModel.errorMessage = nil } }
        )
    }

    // Bridges the track-selection state into a sheet-presented Bool. Every track kind
    // gets a sheet (volume applies to all of them) — only the effects tiles inside
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
            AppBackground()

            VStack(spacing: 0) {
                TimeReadoutView(
                    currentTime: viewModel.currentTime,
                    duration: viewModel.duration,
                    isRecording: viewModel.isRecording
                )
                .padding(.top, DS.Spacing.xs)
                .padding(.bottom, DS.Spacing.sm)

                timeline
            }

            if showingRename {
                renameOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(30)
            }
        }
        .overlay(alignment: .bottom) { controls }
        .navigationTitle(viewModel.project.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.canSeparateStems {
                ToolbarItem(placement: .topBarTrailing) {
                    SeparateButton(status: viewModel.stemStatus, action: viewModel.startStemSeparation)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        pendingTitle = viewModel.project.title
                        withAnimation(DS.Animation.spring) { showingRename = true }
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .animation(DS.Animation.spring, value: viewModel.stemStatus)
        .animation(DS.Animation.spring, value: viewModel.selectedClipID)
        .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.isRecording)
        .sensoryFeedback(.selection, trigger: viewModel.selectedTrackID)
        .sensoryFeedback(.selection, trigger: viewModel.selectedClipID)
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

    // MARK: - Timeline

    private var timeline: some View {
        EditorTimelineView(
            tracks: viewModel.tracks,
            currentTime: viewModel.currentTime,
            duration: viewModel.duration,
            isRecording: viewModel.isRecording,
            recordingRange: viewModel.recordingRange,
            selectedTrackID: viewModel.selectedTrackID,
            selectedClipID: viewModel.selectedClipID,
            bottomInset: controlsClearance,
            onSelectTrack: viewModel.selectTrack,
            onMuteTrack: viewModel.toggleMute,
            onSelectClip: viewModel.selectClip,
            onMoveClip: { trackID, clipID, offset in
                viewModel.moveClip(id: clipID, inTrack: trackID, to: offset)
            },
            onTrimClip: { trackID, clipID, trimStart, trimEnd, offset in
                viewModel.trimClip(id: clipID, inTrack: trackID, trimStart: trimStart, trimEnd: trimEnd, timelineOffset: offset)
            },
            onBeginScrub: viewModel.beginScrub,
            onScrub: viewModel.scrub,
            onEndScrub: viewModel.endScrub
        )
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: DS.Radius.card, topTrailingRadius: DS.Radius.card))
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Floating controls

    private var controls: some View {
        VStack(spacing: DS.Spacing.sm) {
            if viewModel.selectedClip != nil {
                ClipActionBar(
                    canSplit: viewModel.canSplitSelectedClip,
                    onSplit: viewModel.splitSelectedClip,
                    onDelete: viewModel.deleteSelectedClip
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            TransportBarView(
                isPlaying: viewModel.transportActive,
                isRecording: viewModel.isRecording,
                onTogglePlayback: viewModel.togglePlayback,
                onRewind: viewModel.rewind,
                onToggleRecord: viewModel.toggleRecording
            )
        }
        .padding(.bottom, DS.Spacing.sm)
    }

    // MARK: - Rename overlay (custom — never the native alert/TextField)

    private var renameOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture(perform: dismissRename)

            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                Text("Rename Project")
                    .font(.title3.weight(.semibold))

                TextField("Project name", text: $pendingTitle)
                    .font(.body)
                    .padding(DS.Spacing.md)
                    .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: DS.Radius.md))
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($renameFieldFocused)
                    .onSubmit(commitRename)

                HStack(spacing: DS.Spacing.sm) {
                    Button("Cancel", action: dismissRename)
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity)

                    Button("Save", action: commitRename)
                        .buttonStyle(.glassProminent)
                        .tint(DS.Brand.accent)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(DS.Spacing.xl)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.Radius.hero))
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
                    VStack(spacing: DS.Spacing.md) {
                        VolumeTileView(
                            volume: track.volume,
                            onVolumeChange: viewModel.updateVolume
                        )
                        if track.effectsApplicable {
                            PlusGate { AutotuneTileView() }
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
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.lg)
                }
                .scrollIndicators(.hidden)
                .background(AppBackground())
                .navigationTitle(track.name)
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
}

// MARK: - Separate (stem split) button

/// Stem separation, as a navigation bar item. Idle it's a button; running it's a
/// progress ring with the percentage; done it's a checkmark; failed it's Retry.
/// Nothing blocks — the editor stays fully usable during separation.
private struct SeparateButton: View {
    let status: StemSeparationStatus
    let action: () -> Void

    var body: some View {
        switch status {
        case .idle:
            Button(action: action) {
                Label("Separate", systemImage: "waveform.badge.plus")
            }
            .tint(DS.Brand.accent)
            .accessibilityLabel("Separate vocals from instrumental")

        case .running(let progress):
            HStack(spacing: DS.Spacing.xs) {
                if progress > 0 {
                    ProgressView(value: progress)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Separating, \(Int(progress * 100)) percent")

        case .done:
            Label("Separated", systemImage: "checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

        case .failed:
            Button(action: action) {
                Label("Retry", systemImage: "exclamationmark.arrow.circlepath")
            }
            .tint(.orange)
        }
    }
}
