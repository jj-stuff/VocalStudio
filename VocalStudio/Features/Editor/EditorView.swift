import SwiftUI

struct EditorView: View {
    @State var viewModel: EditorViewModel

    // Bridges the track-selection state into a sheet-presented Bool.
    // When the sheet is drag-dismissed, the binding setter deselects the track.
    private var showEffectsSheet: Binding<Bool> {
        Binding(
            get: { viewModel.selectedTrack?.effectsApplicable == true },
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

                EditorTimelineView(
                    tracks: viewModel.tracks,
                    currentTime: viewModel.currentTime,
                    duration: viewModel.duration,
                    selectedTrackID: viewModel.selectedTrackID,
                    onSelectTrack: viewModel.selectTrack,
                    onMuteTrack: viewModel.toggleMute,
                    onMoveClip: { trackID, clipID, offset in
                        viewModel.moveClip(id: clipID, inTrack: trackID, to: offset)
                    }
                )
                .frame(maxHeight: .infinity)
            }
        }
        .navigationTitle(viewModel.project.title)
        .navigationBarTitleDisplayMode(.inline)
        .preference(key: TabBarHiddenKey.self, value: true)
        .animation(DS.Animation.spring, value: viewModel.stemStatus)
        .task { await viewModel.start() }
        .onDisappear { viewModel.tearDown() }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: showEffectsSheet) {
            effectsSheet
        }
    }

    // MARK: - Effects sheet

    @ViewBuilder
    private var effectsSheet: some View {
        if let track = viewModel.selectedTrack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .scrollIndicators(.hidden)
                .navigationTitle("\(track.name) Effects")
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
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color(.systemBackground)
            RadialGradient(
                colors: [Color(red: 0.18, green: 0.06, blue: 0.38).opacity(0.30), .clear],
                center: .topLeading, startRadius: 0, endRadius: 420
            )
            RadialGradient(
                colors: [Color(red: 0.08, green: 0.04, blue: 0.24).opacity(0.20), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 320
            )
        }
        .ignoresSafeArea()
    }
}
