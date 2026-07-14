import SwiftUI

struct TransportBarView: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let isRecording: Bool
    let stemStatus: StemSeparationStatus
    let onTogglePlayback: () -> Void
    let onRewind: () -> Void
    let onToggleRecord: () -> Void
    let onSeparateStems: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                timeDisplay
                Spacer()
                separateButton
            }

            HStack(spacing: 32) {
                rewindButton
                playPauseButton
                recordButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        // Fully rounded on all four corners — this bar floats as its own island, with
        // margin around it (added by the caller) rather than sitting flush against the
        // nav bar and screen edges.
        .glassEffect(in: RoundedRectangle(cornerRadius: DS.Radius.hero))
        .overlay(alignment: .bottom) {
            RoundedRectangle(cornerRadius: DS.Radius.hero)
                .stroke(Color(.separator).opacity(0.6), lineWidth: 0.5)
        }
    }

    // MARK: - Subviews

    private var timeDisplay: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Monospaced timestamps — the digits don't jitter horizontally as they
            // tick, and it reads as a player readout rather than body text.
            Text(formatTime(currentTime))
                .font(.system(.title, design: .monospaced, weight: .semibold))
                .foregroundStyle(.primary)
            Text(formatTime(duration))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private var rewindButton: some View {
        Button(action: onRewind) {
            Image(systemName: "backward.end.fill")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 52, height: 52)
                .glassEffect(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rewind to start")
    }

    private var playPauseButton: some View {
        Button(action: onTogglePlayback) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 64, height: 64)
                .glassEffect(in: Circle())
        }
        .buttonStyle(.plain)
        .animation(DS.Animation.smooth, value: isPlaying)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }

    private var recordButton: some View {
        Button(action: onToggleRecord) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : Color.red.opacity(0.15))
                    .frame(width: 40, height: 40)
                // One shape morphing circle ⇄ square (the Camera/Voice Memos record
                // affordance) instead of swapping two views, so the corner radius
                // and color animate as a single continuous gesture.
                RoundedRectangle(cornerRadius: isRecording ? 4 : 8)
                    .fill(isRecording ? Color.white : Color.red)
                    .frame(width: 16, height: 16)
            }
            .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .animation(DS.Animation.spring, value: isRecording)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }

    // MARK: - Separate (stem split) button
    //
    // Renamed from "Split" — first-time users read "split" as a cut/trim action.
    // "Separate" matches what the feature actually does (vocals vs. instrumental).

    private var separateButton: some View {
        Group {
            switch stemStatus {
            case .idle:
                Button(action: onSeparateStems) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.badge.plus")
                            .font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Separate")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Vocals / Instrumental")
                                .font(.system(size: 10, weight: .medium))
                                .opacity(0.7)
                        }
                    }
                    .foregroundStyle(DS.Brand.purple1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Separate vocals from instrumental")

            case .running(let p):
                // This is the only progress surface now (no blocking overlay), so it
                // has to carry the state by itself: indeterminate while the ~100MB
                // model loads, then a determinate bar with a live percentage. The
                // editor stays fully usable the whole time.
                VStack(alignment: .leading, spacing: 3) {
                    if p > 0 {
                        ProgressView(value: p)
                            .progressViewStyle(.linear)
                            .tint(DS.Brand.purple1)
                            .frame(width: 88)
                        Text("Separating… \(Int(p * 100))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                        Text("Preparing model…")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

            case .done:
                Label("Separated", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

            case .failed:
                Button(action: onSeparateStems) {
                    Label("Retry", systemImage: "exclamationmark.arrow.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        let ms = Int((t.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, ms)
    }
}
