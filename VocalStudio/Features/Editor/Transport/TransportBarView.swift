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
        HStack(spacing: 0) {
            // Time display
            timeDisplay
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)

            // Core transport buttons
            HStack(spacing: 20) {
                rewindButton
                playPauseButton
                recordButton
            }
            .frame(maxWidth: .infinity)

            // Stem separation button
            stemButton
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 16)
        }
        .frame(height: 64)
        .glassEffect(in: Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    // MARK: - Subviews

    private var timeDisplay: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(formatTime(currentTime))
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
            Text(formatTime(duration))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private var rewindButton: some View {
        Button(action: onRewind) {
            Image(systemName: "backward.end.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rewind to start")
    }

    private var playPauseButton: some View {
        Button(action: onTogglePlayback) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
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
                    .frame(width: 30, height: 30)
                if isRecording {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white)
                        .frame(width: 12, height: 12)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }

    private var stemButton: some View {
        Group {
            switch stemStatus {
            case .idle:
                Button(action: onSeparateStems) {
                    Label("Split", systemImage: "waveform.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Brand.purple1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Separate stems")

            case .running(let p):
                VStack(spacing: 2) {
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                        .tint(DS.Brand.purple1)
                        .frame(width: 56)
                    Text("Splitting…")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }

            case .done:
                Label("Split", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

            case .failed:
                Button(action: onSeparateStems) {
                    Label("Retry", systemImage: "exclamationmark.arrow.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
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
