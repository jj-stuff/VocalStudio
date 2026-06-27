import SwiftUI

struct EditorTimelineView: View {
    let tracks: [Track]
    let currentTime: TimeInterval
    let duration: TimeInterval
    let selectedTrackID: UUID?
    let onSelectTrack: (UUID) -> Void
    let onMuteTrack: (UUID) -> Void
    let onMoveClip: (UUID, UUID, TimeInterval) -> Void  // (trackID, clipID, newOffset)

    @State private var zoom: CGFloat = 80  // pixels per second

    private static let headerWidth: CGFloat = 64
    private static let trackHeight: CGFloat = 88
    private static let rulerHeight: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let totalWidth = max(
                geo.size.width - Self.headerWidth,
                CGFloat(duration) * zoom + 200
            )

            HStack(spacing: 0) {
                // Fixed left column — track headers
                VStack(spacing: 1) {
                    Color.clear.frame(height: Self.rulerHeight + 1)

                    ForEach(tracks) { track in
                        TrackHeaderView(
                            track: track,
                            isSelected: selectedTrackID == track.id,
                            onTap: { onSelectTrack(track.id) },
                            onMute: { onMuteTrack(track.id) }
                        )
                        .frame(height: Self.trackHeight)
                    }
                }
                .frame(width: Self.headerWidth)
                .background(Color(.systemBackground).opacity(0.06))

                // Scrollable right area
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            RulerView(duration: duration + 10, pixelsPerSecond: zoom)
                                .frame(width: totalWidth, height: Self.rulerHeight)

                            Rectangle()
                                .fill(.white.opacity(0.06))
                                .frame(width: totalWidth, height: 1)

                            ForEach(tracks) { track in
                                TrackClipAreaView(
                                    track: track,
                                    pixelsPerSecond: zoom,
                                    totalWidth: totalWidth,
                                    onMoveClip: { clipID, newOffset in
                                        onMoveClip(track.id, clipID, newOffset)
                                    }
                                )
                                .frame(height: Self.trackHeight)

                                Rectangle()
                                    .fill(.white.opacity(0.05))
                                    .frame(width: totalWidth, height: 1)
                            }
                        }

                        // Playhead — full height
                        let playheadH = Self.rulerHeight + CGFloat(tracks.count) * (Self.trackHeight + 1)
                        Group {
                            Rectangle()
                                .fill(Color.white.opacity(0.85))
                                .frame(width: 1.5, height: playheadH)
                                .offset(x: CGFloat(currentTime) * zoom - 0.75)

                            Rectangle()
                                .fill(DS.Brand.purple1.opacity(0.4))
                                .frame(width: 4, height: playheadH)
                                .blur(radius: 3)
                                .offset(x: CGFloat(currentTime) * zoom - 2)
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(width: totalWidth)
                }
            }
        }
        .background(Color(.systemBackground).opacity(0.08))
    }
}
