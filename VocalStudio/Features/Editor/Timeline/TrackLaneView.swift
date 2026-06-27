import SwiftUI

// MARK: - Track header (fixed left column)

struct TrackHeaderView: View {
    let track: Track
    let isSelected: Bool
    let onTap: () -> Void
    let onMute: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                Image(systemName: track.kind.displayIcon)
                    .font(.system(size: 19))
                    .foregroundStyle(isSelected ? DS.Brand.purple1 : .secondary)

                Button(action: onMute) {
                    Image(systemName: track.isMuted ? "speaker.slash.fill" : "speaker.wave.1.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(track.isMuted ? DS.Brand.pink : Color.secondary)
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(track.isMuted ? "Unmute \(track.name)" : "Mute \(track.name)")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                isSelected
                    ? DS.Brand.purple1.opacity(0.12)
                    : Color(.systemFill).opacity(0.5)
            )
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(track.name)
    }
}

// MARK: - Clip canvas (scrollable right area for one track)

struct TrackClipAreaView: View {
    let track: Track
    let pixelsPerSecond: CGFloat
    let totalWidth: CGFloat
    let onMoveClip: (UUID, TimeInterval) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            // Lane background
            Color(.systemBackground).opacity(0.04)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.white.opacity(0.05))
                        .frame(height: 0.5)
                }

            // Clips
            ForEach(track.clips) { clip in
                ClipView(
                    clip: clip,
                    trackKind: track.kind,
                    pixelsPerSecond: pixelsPerSecond,
                    isDraggable: track.kind.isUserRecording,
                    onMove: { newOffset in
                        onMoveClip(clip.id, newOffset)
                    }
                )
            }
        }
        .frame(width: totalWidth)
        .clipped()
    }
}
