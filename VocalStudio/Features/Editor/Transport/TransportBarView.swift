import SwiftUI

/// The transport: rewind, play/pause, record. Floats over the bottom of the
/// timeline as one Liquid Glass slab, which is earned here — the lanes scroll
/// horizontally straight underneath it, so the glass has something to refract.
///
/// The time readout is not in here any more; it sits above the timeline where the
/// eye already is when scrubbing. Stem separation moved to the navigation bar.
struct TransportBarView: View {
    /// True while the transport is running — playback, or an actively-capturing
    /// recording (a paused recording shows the play icon again).
    let isPlaying: Bool
    let isRecording: Bool
    let onTogglePlayback: () -> Void
    let onRewind: () -> Void
    let onToggleRecord: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: DS.Spacing.lg) {
            HStack(spacing: DS.Spacing.lg) {
                rewindButton
                playPauseButton
                recordButton
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
            .glassEffect(.regular, in: .capsule)
        }
    }

    private var rewindButton: some View {
        Button(action: onRewind) {
            Image(systemName: "backward.end.fill")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isRecording ? .tertiary : .primary)
        .disabled(isRecording)
        .accessibilityLabel("Rewind to start")
    }

    private var playPauseButton: some View {
        Button(action: onTogglePlayback) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 26, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 64, height: 64)
                .foregroundStyle(Color(.systemBackground))
                .background(Color.primary, in: Circle())
        }
        .buttonStyle(.plain)
        .animation(DS.Animation.smooth, value: isPlaying)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }

    private var recordButton: some View {
        Button(action: onToggleRecord) {
            ZStack {
                Circle()
                    .stroke(Color.red, lineWidth: 2.5)
                    .frame(width: 34, height: 34)
                // One shape morphing circle ⇄ square (the Camera/Voice Memos record
                // affordance) instead of swapping two views, so the corner radius
                // animates as a single continuous gesture.
                RoundedRectangle(cornerRadius: isRecording ? 4 : 13)
                    .fill(Color.red)
                    .frame(width: isRecording ? 16 : 26, height: isRecording ? 16 : 26)
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(DS.Animation.spring, value: isRecording)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }
}
