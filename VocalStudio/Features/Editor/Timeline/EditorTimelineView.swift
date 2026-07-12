import SwiftUI

struct EditorTimelineView: View {
    let tracks: [Track]
    let currentTime: TimeInterval
    let duration: TimeInterval
    let selectedTrackID: UUID?
    let onSelectTrack: (UUID) -> Void
    let onMuteTrack: (UUID) -> Void
    let onMoveClip: (UUID, UUID, TimeInterval) -> Void  // (trackID, clipID, newOffset)
    let onTrimClip: (UUID, UUID, TimeInterval, TimeInterval, TimeInterval) -> Void  // (trackID, clipID, trimStart, trimEnd, newOffset)
    let onDeleteClip: (UUID, UUID) -> Void  // (trackID, clipID)
    let onScrub: (TimeInterval) -> Void

    @State private var zoom: CGFloat = 80  // pixels per second, committed value
    @GestureState private var pinchScale: CGFloat = 1.0

    private static let headerWidth: CGFloat = 64
    private static let trackHeight: CGFloat = 88
    private static let rulerHeight: CGFloat = 24
    private static let zoomRange: ClosedRange<CGFloat> = 20...400

    /// What layout actually uses — `zoom` scaled live by an in-flight pinch, so the
    /// timeline visibly zooms while you pinch instead of only snapping at the end.
    private var effectiveZoom: CGFloat { zoom * pinchScale }

    var body: some View {
        GeometryReader { geo in
            let totalWidth = max(
                geo.size.width - Self.headerWidth,
                CGFloat(duration) * effectiveZoom + 200
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
                            RulerView(duration: duration + 10, pixelsPerSecond: effectiveZoom)
                                .frame(width: totalWidth, height: Self.rulerHeight)
                                .contentShape(Rectangle())
                                // highPriorityGesture, not gesture — the ruler lives inside a
                                // horizontal ScrollView, whose own pan recognizer otherwise wins
                                // a plain .gesture() since both interpret the same horizontal
                                // drag. This is why scrubbing never did anything.
                                .highPriorityGesture(scrubGesture)

                            Rectangle()
                                .fill(Color(.separator))
                                .frame(width: totalWidth, height: 1)

                            ForEach(tracks) { track in
                                TrackClipAreaView(
                                    track: track,
                                    pixelsPerSecond: effectiveZoom,
                                    totalWidth: totalWidth,
                                    onMoveClip: { clipID, newOffset in
                                        onMoveClip(track.id, clipID, newOffset)
                                    },
                                    onTrimClip: { clipID, trimStart, trimEnd, newOffset in
                                        onTrimClip(track.id, clipID, trimStart, trimEnd, newOffset)
                                    },
                                    onDeleteClip: { clipID in onDeleteClip(track.id, clipID) },
                                    onSeek: onScrub
                                )
                                .frame(height: Self.trackHeight)

                                Rectangle()
                                    .fill(Color(.separator).opacity(0.6))
                                    .frame(width: totalWidth, height: 1)
                            }
                        }

                        // Playhead — full height
                        let playheadH = Self.rulerHeight + CGFloat(tracks.count) * (Self.trackHeight + 1)
                        Group {
                            Capsule()
                                .fill(Color.primary.opacity(0.85))
                                .frame(width: 2.5, height: playheadH)
                                .offset(x: CGFloat(currentTime) * effectiveZoom - 1.25)

                            Capsule()
                                .fill(DS.Brand.purple1.opacity(0.4))
                                .frame(width: 5, height: playheadH)
                                .blur(radius: 3)
                                .offset(x: CGFloat(currentTime) * effectiveZoom - 2.5)
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(width: totalWidth)
                }
                .simultaneousGesture(pinchGesture)
            }
            // A finished take slides its new row in instead of popping.
            .animation(DS.Animation.spring, value: tracks.count)
        }
        .background(Color(.systemBackground).opacity(0.08))
    }

    // MARK: - Scrubbing

    /// Tap or drag along the ruler to move the playhead. `location.x` is already in
    /// the scrollable content's own coordinate space (the gesture lives inside the
    /// ScrollView's content), so it converts to seconds with no extra offsetting.
    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                onScrub(max(0, min(duration, Double(value.location.x / effectiveZoom))))
            }
    }

    // MARK: - Pinch to zoom

    /// Two-finger pinch, scaling live during the gesture (via `effectiveZoom`) and
    /// committing to `zoom` on release. Pinch rather than a +/- button because
    /// MagnificationGesture is a distinct two-touch recognizer — it coexists with the
    /// ScrollView's single-finger pan instead of competing with it for the same touch,
    /// unlike every single-finger drag gesture in this file.
    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in state = value }
            .onEnded { value in
                zoom = (zoom * value).clamped(to: Self.zoomRange)
            }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        // Swift.min/max, fully qualified — inside an extension on CGFloat, the bare
        // names resolve to CGFloat's own static members instead of the global
        // comparison functions.
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
