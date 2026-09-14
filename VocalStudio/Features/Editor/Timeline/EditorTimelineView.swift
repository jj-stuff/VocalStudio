import SwiftUI

/// The multi-track timeline, built around a **fixed playhead**.
///
/// The playhead is a static overlay; the content scrolls beneath it. That makes
/// scrolling and scrubbing the same gesture — there is no separate "drag the
/// ruler" or "tap to seek", the ScrollView's own physics (momentum, rubber-band)
/// do the work — and it is the model Voice Memos, GarageBand and Logic use on
/// iPhone. The only other single-finger gestures on the timeline are on clips
/// (tap, handle drag, long-press-to-move), and those are designed not to overlap
/// with a plain drag.
///
/// Playback drives the scroll offset; user scrolling drives the playhead. The two
/// never fight because scroll phases tell us who is in charge: while the user is
/// touching or the scroll is decelerating, offset changes are scrubs and playback
/// is paused; the rest of the time offset changes come from us and are ignored.
struct EditorTimelineView: View {
    let tracks: [Track]
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isRecording: Bool
    /// Span of an in-flight recording. Non-nil while capturing: the timeline shows
    /// a live, growing red lane for it, so the take is visible before it's stopped.
    let recordingRange: ClosedRange<TimeInterval>?
    let selectedTrackID: UUID?
    let selectedClipID: UUID?
    /// Space to leave at the bottom so the last lane can scroll out from under the
    /// floating transport bar.
    let bottomInset: CGFloat

    let onSelectTrack: (UUID) -> Void
    let onMuteTrack: (UUID) -> Void
    let onSelectClip: (UUID?) -> Void
    let onMoveClip: (UUID, UUID, TimeInterval) -> Void  // (trackID, clipID, newOffset)
    let onTrimClip: (UUID, UUID, TimeInterval, TimeInterval, TimeInterval) -> Void  // (trackID, clipID, trimStart, trimEnd, newOffset)
    let onBeginScrub: () -> Void
    let onScrub: (TimeInterval) -> Void
    let onEndScrub: () -> Void

    @State private var zoom: CGFloat = TimelineGeometry.defaultZoom
    @GestureState private var pinchScale: CGFloat = 1
    @State private var scrollPosition = ScrollPosition()
    /// True while a scroll is user-driven (touching, or coasting after a flick).
    @State private var isUserScrolling = false

    private static let headerWidth: CGFloat = 64
    private static let trackHeight: CGFloat = 88
    private static let rulerHeight: CGFloat = 22

    /// Rows drawn = real tracks plus the live recording lane while capturing.
    private var rowCount: Int { tracks.count + (recordingRange == nil ? 0 : 1) }
    private var lanesHeight: CGFloat { Self.rulerHeight + CGFloat(rowCount) * Self.trackHeight }

    var body: some View {
        GeometryReader { proxy in
            let geometry = TimelineGeometry(
                pixelsPerSecond: (zoom * pinchScale).clamped(to: TimelineGeometry.zoomRange),
                viewportWidth: max(1, proxy.size.width - Self.headerWidth),
                duration: duration
            )

            // The panel always fills the screen even with one track, so the grid
            // reads as a surface the audio sits on rather than a card that stops
            // halfway down. Lanes only exist where there are tracks; the rest is
            // empty timeline, which is exactly what it is.
            let contentHeight = max(lanesHeight, proxy.size.height)
            // Only make room for the floating transport when the lanes are actually
            // long enough to go under it — otherwise a one-track project scrolls
            // 150pt for no reason.
            let needsBottomRoom = lanesHeight + bottomInset > proxy.size.height

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    headerColumn
                        .frame(width: Self.headerWidth, height: contentHeight)

                    horizontalTimeline(geometry, height: contentHeight)
                        .frame(height: contentHeight)
                }
                // A finished take slides its new row in instead of popping, and the
                // live recording lane appears/disappears the same way.
                .animation(DS.Animation.spring, value: rowCount)
            }
            .contentMargins(.bottom, needsBottomRoom ? bottomInset : 0, for: .scrollContent)
            .scrollIndicators(.hidden)
            .simultaneousGesture(pinchGesture)
            // Playback (and recording) pull the content along under the playhead.
            .onChange(of: currentTime) { follow(geometry) }
            // Zooming keeps the time under the playhead fixed — the pinch is anchored
            // at the playhead, not at the fingers, so it never feels like it drifts.
            .onChange(of: geometry.pixelsPerSecond) { follow(geometry) }
            .onAppear { follow(geometry) }
        }
        .background(Color(.systemBackground).opacity(0.35))
    }

    // MARK: - Header column

    private var headerColumn: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.rulerHeight)
            ForEach(tracks) { track in
                TrackHeaderView(
                    track: track,
                    isSelected: selectedTrackID == track.id,
                    onTap: { onSelectTrack(track.id) },
                    onMute: { onMuteTrack(track.id) }
                )
                .frame(height: Self.trackHeight)
            }
            if recordingRange != nil {
                RecordingHeaderView()
                    .frame(height: Self.trackHeight)
            }
            Spacer(minLength: 0)
        }
        .background(.thinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color(.separator)).frame(width: 0.5)
        }
    }

    // MARK: - Scrolling timeline

    private func horizontalTimeline(_ geometry: TimelineGeometry, height: CGFloat) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                // Leading pad: lets time 0 reach the playhead.
                Color.clear.frame(width: geometry.leadingPadding)
                lanes(geometry)
                    .frame(width: geometry.timelineWidth, height: height, alignment: .top)
                // Trailing pad: lets the end of the project reach the playhead.
                Color.clear.frame(width: geometry.trailingPadding)
            }
        }
        .scrollPosition($scrollPosition)
        .scrollIndicators(.hidden)
        .onScrollPhaseChange { _, newPhase in
            let userDriven = newPhase == .tracking || newPhase == .interacting || newPhase == .decelerating
            guard userDriven != isUserScrolling else { return }
            isUserScrolling = userDriven
            if userDriven { onBeginScrub() } else { onEndScrub() }
        }
        .onScrollGeometryChange(for: CGFloat.self) { scroll in
            scroll.contentOffset.x
        } action: { _, offset in
            // Only the user's scrolls are scrubs. Our own `scrollTo` calls during
            // playback also land here, and feeding those back would seek the
            // engine to the position it just reported.
            guard isUserScrolling else { return }
            onScrub(geometry.time(forOffset: offset))
        }
        .overlay(alignment: .topLeading) {
            PlayheadView(isRecording: isRecording)
                .frame(height: height)
                .offset(x: geometry.playheadX - 5)
        }
    }

    private func lanes(_ geometry: TimelineGeometry) -> some View {
        VStack(spacing: 0) {
            RulerView(geometry: geometry)
                .frame(height: Self.rulerHeight)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(.separator)).frame(height: 0.5)
                }

            ForEach(tracks) { track in
                TrackLaneView(
                    track: track,
                    geometry: geometry,
                    selectedClipID: selectedClipID,
                    playheadTime: currentTime,
                    onSelectClip: onSelectClip,
                    onMoveClip: { clipID, newOffset in onMoveClip(track.id, clipID, newOffset) },
                    onTrimClip: { clipID, trimStart, trimEnd, offset in
                        onTrimClip(track.id, clipID, trimStart, trimEnd, offset)
                    }
                )
                .frame(height: Self.trackHeight)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(.separator).opacity(0.5)).frame(height: 0.5)
                }
            }

            if let recordingRange {
                RecordingLaneView(range: recordingRange, geometry: geometry)
                    .frame(height: Self.trackHeight)
            }

            // Empty timeline below the last lane. Tapping it clears the clip
            // selection, same as tapping empty space inside a lane.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onSelectClip(nil) }
        }
    }

    // MARK: - Follow

    /// Scrolls so `currentTime` sits under the playhead — unless the user is the
    /// one scrolling, in which case they are telling *us* where the playhead is.
    private func follow(_ geometry: TimelineGeometry) {
        guard !isUserScrolling else { return }
        scrollPosition.scrollTo(x: geometry.offset(for: currentTime))
    }

    // MARK: - Pinch to zoom

    /// Two-finger pinch, scaling live during the gesture (via `pinchScale`) and
    /// committing to `zoom` on release. A pinch is a distinct two-touch recognizer,
    /// so it coexists with the ScrollView's single-finger pan instead of competing
    /// with it for the same touch.
    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .updating($pinchScale) { value, state, _ in state = value.magnification }
            .onEnded { value in
                zoom = (zoom * value.magnification).clamped(to: TimelineGeometry.zoomRange)
            }
    }
}
