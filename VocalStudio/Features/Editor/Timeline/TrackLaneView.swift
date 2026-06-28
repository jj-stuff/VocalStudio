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
                isSelected ? DS.Brand.purple1.opacity(0.12) : Color(.systemFill).opacity(0.5),
                // Leading corners only — the trailing edge stays flush against the
                // scrollable clip area, so each row reads as a tab sticking out from
                // the timeline grid rather than a fully separate floating card.
                in: UnevenRoundedRectangle(
                    topLeadingRadius: DS.Radius.sm, bottomLeadingRadius: DS.Radius.sm,
                    bottomTrailingRadius: 0, topTrailingRadius: 0
                )
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
    let onTrimClip: (UUID, TimeInterval, TimeInterval, TimeInterval) -> Void
    let onDeleteClip: (UUID) -> Void
    let onSeek: (TimeInterval) -> Void

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
                    },
                    onTrim: { trimStart, trimEnd, timelineOffset in
                        onTrimClip(clip.id, trimStart, trimEnd, timelineOffset)
                    },
                    onDelete: { onDeleteClip(clip.id) }
                )
            }
        }
        .frame(width: totalWidth)
        .clipped()
        // simultaneousGesture (not gesture/highPriorityGesture) — lets a tap seek
        // whether it lands on empty lane space or directly on a clip, without
        // disturbing the clip's own drag-to-move/trim gestures or the ancestor
        // ScrollView's horizontal pan. Tapping and dragging are distinguished by
        // movement, not by which gesture claims the touch first.
        .simultaneousGesture(
            SpatialTapGesture().onEnded { value in
                onSeek(max(0, Double(value.location.x / pixelsPerSecond)))
            }
        )
    }
}
