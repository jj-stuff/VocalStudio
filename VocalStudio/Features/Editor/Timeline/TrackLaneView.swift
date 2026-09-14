import SwiftUI

// MARK: - Track header (fixed left column)

/// One row of the fixed header column: the track's icon and name (tap to open its
/// volume/effects panel) and a mute toggle underneath.
struct TrackHeaderView: View {
    let track: Track
    let isSelected: Bool
    let onTap: () -> Void
    let onMute: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            Button(action: onTap) {
                VStack(spacing: 4) {
                    Image(systemName: track.kind.displayIcon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
                        .frame(width: 32, height: 32)
                        .background(isSelected ? Color.primary : Color(.tertiarySystemFill), in: Circle())
                    Text(track.name)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(track.name) settings")
            .accessibilityHint("Opens volume and effects")

            Button(action: onMute) {
                Image(systemName: track.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(track.isMuted ? Color.red : Color.secondary)
                    .frame(width: 44, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(track.isMuted ? "Unmute \(track.name)" : "Mute \(track.name)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isSelected ? Color.primary.opacity(0.06) : Color.clear)
        .animation(DS.Animation.smooth, value: isSelected)
    }
}

/// Header for the in-flight recording lane — a pulsing red dot so it clearly reads
/// as "capturing right now", not another finished take.
struct RecordingHeaderView: View {
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 32, height: 32)
                // symbolEffect animates SF Symbols only, hence an Image, not a Circle.
                Image(systemName: "circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
            }
            Text("Recording")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.red.opacity(0.06))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording in progress")
    }
}

// MARK: - Clip lane (scrollable right area for one track)

/// The lane for one track: its clips positioned by time. Tapping empty lane space
/// clears the clip selection; scrolling is handled by the enclosing ScrollView.
struct TrackLaneView: View {
    let track: Track
    let geometry: TimelineGeometry
    let selectedClipID: UUID?
    let playheadTime: TimeInterval
    let onSelectClip: (UUID?) -> Void
    let onMoveClip: (UUID, TimeInterval) -> Void
    let onTrimClip: (UUID, TimeInterval, TimeInterval, TimeInterval) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onSelectClip(nil) }

            ForEach(track.clips) { clip in
                ClipView(
                    clip: clip,
                    trackKind: track.kind,
                    geometry: geometry,
                    isSelected: selectedClipID == clip.id,
                    isEditable: track.kind.isUserRecording,
                    playheadTime: playheadTime,
                    neighbourEdges: neighbourEdges(excluding: clip.id),
                    onSelect: { onSelectClip(track.kind.isUserRecording ? clip.id : nil) },
                    onMove: { newOffset in onMoveClip(clip.id, newOffset) },
                    onTrim: { trimStart, trimEnd, offset in onTrimClip(clip.id, trimStart, trimEnd, offset) }
                )
                .padding(.vertical, DS.Spacing.xs)
            }
        }
    }

    /// Start and end of every other clip on this track, as snap targets.
    private func neighbourEdges(excluding clipID: UUID) -> [(clipID: UUID, time: TimeInterval)] {
        track.clips
            .filter { $0.id != clipID }
            .flatMap { [(clipID: $0.id, time: $0.timelineOffset), (clipID: $0.id, time: $0.timelineEnd)] }
    }
}

/// The growing clip for the take being captured. Purely visual — the real,
/// editable clip replaces it the moment recording stops.
struct RecordingLaneView: View {
    let range: ClosedRange<TimeInterval>
    let geometry: TimelineGeometry

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.62, green: 0.12, blue: 0.18),
                                 Color(red: 0.42, green: 0.07, blue: 0.12)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.7), lineWidth: 1)
                }
                .frame(width: max(6, geometry.x(range.upperBound - range.lowerBound)))
                .padding(.vertical, DS.Spacing.xs)
                .offset(x: geometry.x(range.lowerBound))
        }
        .allowsHitTesting(false)
    }
}
