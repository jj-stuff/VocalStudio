import SwiftUI

/// The volume/effects panel for one track.
///
/// Deliberately **not** a `.sheet`. A sheet owns the bottom of the screen, so the
/// transport ends up underneath it and you have to dismiss the panel to hear what
/// a change did — which is backwards for a control surface whose whole job is
/// "turn the knob, listen, turn it again". Here the panel is just the last item in
/// the editor's floating control stack, so the transport sits directly above it
/// and playback is one tap away the entire time.
///
/// It also can't be dragged to full screen, because there is no full-screen state
/// to drag to. Drag down past a threshold to dismiss, or tap Done.
struct TrackPanelView: View {
    let track: Track
    let onVolumeChange: (Float) -> Void
    let onReverbChange: (Float) -> Void
    let onEQChange: (Float, Int) -> Void
    let onDismiss: () -> Void

    /// Fixed. The editor reserves exactly this much scroll room under the timeline,
    /// so the two can't disagree about how much of the lanes the panel is covering.
    static let height: CGFloat = 380
    private static let dismissThreshold: CGFloat = 90

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            grabber
            header
            tiles
        }
        .frame(height: Self.height)
        .background(.regularMaterial, in: .rect(cornerRadius: DS.Radius.hero))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.hero)
                .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        .offset(y: max(0, dragOffset))
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Chrome

    /// The grabber is the drag target, not the whole panel — dragging anywhere
    /// would fight the sliders, which are the main thing you touch in here.
    private var grabber: some View {
        Capsule()
            .fill(Color(.tertiaryLabel))
            .frame(width: 36, height: 5)
            .padding(.top, DS.Spacing.xs)
            .padding(.bottom, DS.Spacing.xxs)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = $0.translation.height }
                    .onEnded { value in
                        if value.translation.height > Self.dismissThreshold {
                            onDismiss()
                        }
                        withAnimation(DS.Animation.spring) { dragOffset = 0 }
                    }
            )
            .accessibilityLabel("Close panel")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, onDismiss)
    }

    private var header: some View {
        HStack {
            Label(track.name, systemImage: track.kind.displayIcon)
                .font(.headline)
                .labelStyle(.titleAndIcon)
            Spacer()
            Button("Done", action: onDismiss)
                .font(.body.weight(.semibold))
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - Tiles

    private var tiles: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.sm) {
                VolumeTileView(volume: track.volume, onVolumeChange: onVolumeChange)
                if track.effectsApplicable {
                    PlusGate { AutotuneTileView() }
                    ReverbTileView(reverbMix: track.effects.reverbMix, onReverbChange: onReverbChange)
                    EQTileView(eqGains: track.effects.eqGains, onEQChange: onEQChange)
                }
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.bottom, DS.Spacing.md)
        }
        .scrollIndicators(.hidden)
    }
}
