import SwiftUI

// MARK: - Track header (fixed left column)

struct TrackHeaderView: View {
    let track: Track
    let isSelected: Bool
    let onTap: () -> Void
    let onMute: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            // Icon + name are the tappable "open settings" control. A circular chip
            // (matching the mute/transport buttons' own look) plus a small badge make
            // it read as a button rather than a static label — previously this was
            // just a bare glyph with no visual hint it opened anything.
            Button(action: onTap) {
                VStack(spacing: 3) {
                    Image(systemName: track.kind.displayIcon)
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? Color(.systemBackground) : Color(.secondaryLabel))
                        .frame(width: 30, height: 30)
                        .background(
                            isSelected ? Color.primary : Color(.systemFill),
                            in: Circle()
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(Color(.systemBackground))
                                .frame(width: 12, height: 12)
                                .background(Color.primary, in: Circle())
                                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                        }

                    Text(track.name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: 58)
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(track.name) settings")
            .accessibilityHint("Opens volume and effects")

            Spacer(minLength: 0)

            Button(action: onMute) {
                Image(systemName: track.isMuted ? "speaker.slash.fill" : "speaker.wave.1.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(track.isMuted ? Color.red : Color.secondary)
                    .frame(width: 44, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(track.isMuted ? "Unmute \(track.name)" : "Mute \(track.name)")
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            isSelected ? Color.primary.opacity(0.08) : Color(.systemFill).opacity(0.5),
            // Leading corners only — the trailing edge stays flush against the
            // scrollable clip area, so each row reads as a tab sticking out from
            // the timeline grid rather than a fully separate floating card.
            in: UnevenRoundedRectangle(
                topLeadingRadius: DS.Radius.sm, bottomLeadingRadius: DS.Radius.sm,
                bottomTrailingRadius: 0, topTrailingRadius: 0
            )
        )
        .animation(DS.Animation.smooth, value: isSelected)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(.separator))
                .frame(width: 0.5)
        }
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
                        .fill(Color(.separator).opacity(0.6))
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
