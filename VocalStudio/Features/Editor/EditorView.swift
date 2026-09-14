import SwiftUI

/// The studio. Three layers, bottom to top — the app background, the readout and
/// the timeline card, and a floating control layer over the card's lower portion.
///
/// The control layer is one bottom-aligned stack, and everything in it is optional
/// except the transport: clip actions appear above the transport when a clip is
/// selected, the track panel appears below it when a track is. Because the stack
/// grows downward from the transport, opening the track panel pushes the transport
/// *up* rather than burying it, so you can move a slider and hit play without
/// closing anything. The timeline's bottom scroll inset grows to match, so the
/// last lane can always be scrolled clear of whatever is currently floating.
struct EditorView: View {
    @State var viewModel: EditorViewModel

    @State private var showingRename = false
    @State private var pendingTitle = ""
    @FocusState private var renameFieldFocused: Bool

    // Heights the timeline reserves so its last lane can always be scrolled clear
    // of whatever is floating over the bottom of the card.
    private static let transportClearance: CGFloat = 96
    private static let actionBarClearance: CGFloat = 52

    /// Scroll room under the lanes, grown by whatever is currently floating.
    private var timelineBottomInset: CGFloat {
        var inset = Self.transportClearance
        if viewModel.selectedClip != nil { inset += Self.actionBarClearance }
        if viewModel.selectedTrack != nil { inset += TrackPanelView.height + DS.Spacing.sm }
        return inset
    }

    private var showErrorAlert: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { showing in if !showing { viewModel.errorMessage = nil } }
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
        .animation(DS.Animation.spring, value: viewModel.selectedTrackID)
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
            bottomInset: timelineBottomInset,
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
        // A card with all four corners rounded and a margin around it, rather than
        // a rounded-top surface bleeding off the bottom of the screen — that read
        // as the panel being cut off rather than as a deliberate edge. The floating
        // controls sit over its lower portion, so content still scrolls beneath
        // them and the glass on them is earned.
        .clipShape(.rect(cornerRadius: DS.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card)
                .stroke(Color(.separator).opacity(0.6), lineWidth: 0.5)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.xs)
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

            // Last in the stack, so the transport is pushed up above it and stays
            // reachable while you are adjusting a slider. Re-identified per track:
            // the tiles copy their initial values into @State, so without this the
            // previous track's volume/EQ would show — and apply — to the new one.
            if let track = viewModel.selectedTrack {
                TrackPanelView(
                    track: track,
                    onVolumeChange: viewModel.updateVolume,
                    onReverbChange: viewModel.updateReverb,
                    onEQChange: viewModel.updateEQGain,
                    onDismiss: viewModel.deselectTrack
                )
                .id(track.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.xs)
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
