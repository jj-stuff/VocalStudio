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
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        }
    }

    // MARK: - Subviews

    private var timeDisplay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formatTime(currentTime))
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
            Text(formatTime(duration))
                .font(.system(size: 13, design: .monospaced))
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
                .frame(width: 64, height: 64)
                .glassEffect(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }

    private var recordButton: some View {
        Button(action: onToggleRecord) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : Color.red.opacity(0.15))
                    .frame(width: 40, height: 40)
                if isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: 16, height: 16)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 16, height: 16)
                }
            }
            .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
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
                VStack(spacing: 3) {
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                        .tint(DS.Brand.purple1)
                        .frame(width: 72)
                    Text("Separating…")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
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
