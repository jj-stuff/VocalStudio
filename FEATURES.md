# Siasca — Feature & UX Reference

What the app actually does today, screen by screen, framed around what the user can
do and how. Written for a design pass — everything here is current, real behavior,
not roadmap. Where something looks functional but isn't wired to anything real, it's
called out explicitly so design doesn't build around a stub.

**Naming note**: the Xcode project, target and bundle id are still "Vocal Studio";
the brand everywhere the user can see is **Siasca** (Thai เสียง *sǐang*, sound,
plus Swedish *skapa*, to create). `CFBundleDisplayName` carries it to the home
screen and `AppConfig.appName` carries it everywhere in-app.

**Visual direction**: near-monochrome, system-first, working in both light and
dark. One accent (`DS.Brand.accent`, also the target's AccentColor) for anything
interactive that needs to stand out, red reserved for record and mute, and colour
otherwise reserved for content — the clips on the timeline. Liquid Glass appears
only where content actually scrolls beneath it: the transport over the timeline,
the toolbar over the project list. Everything else is flat.

## Core concept

Import a backing track (or a video — audio gets extracted), sing over it with live
reverb/EQ monitoring, record your take, optionally separate the backing track into
vocals/instrumental stems, and arrange everything on a timeline. Single-player tool:
no accounts, no server, no cloud — everything runs and stays on-device.

## Navigation

One `NavigationStack`, no tab bar. The project list is the root; tapping a project
pushes its editor. Settings is a sheet opened from the gear button (top-right).

The bottom toolbar on the project list holds the search field (leading), the
**"+" import button** and the **red Record button** (trailing). Record is not
navigation: it creates a new project (auto-named, silent placeholder source) and
opens the editor with recording already running — the "sing first, sort it out
later" path. No backing track is required.

Appearance (System / Light / Dark) and background (Minimal wash / Plain) are user
settings, applied at the root. Every screen sits on `AppBackground`.

## Screen: Projects (list)

**Title**: native large title "Siasca"; gear button top-right opens Settings.

**Empty state** (no projects yet): a centered icon, "No Projects Yet," and a single
"Import Track" button that opens the same import menu as the "+" button.

**List state**: native search (bottom toolbar, minimises on scroll) above a
scrollable list of project cards. Search filters by title, live, case-insensitive. Each card shows the project's title, a relative "added Xd
ago" subtitle, a small abstract gradient thumbnail with decorative bars (not a real
waveform), and a relative-age tag ("3d," "2w"). Tapping a card opens that project's
editor. Swipe-to-delete is available on each row (standard list swipe gesture) and
respects the current search filter (deletes the right project even when the list is
filtered, not whatever happens to be at that row index).

The "+" button in the bottom toolbar opens an import menu — a standard bottom sheet with two row choices:

- **From Photos** — picks a video from the Photos library; its audio track is
  extracted in the background and becomes the project's source.
- **From Files** — picks an audio or video file from the Files app / any
  file-providing app (iCloud Drive, third-party storage apps, etc.).

**Imports never block the screen.** While a file is copying/converting, it appears
as a live, non-tappable row at the top of the list with a spinner ("Extracting
audio…"); the rest of the app stays fully usable, and several imports can run at
once. The row swaps in place for the real project card when it finishes.

**Naming**: the user is never asked to name a project up front — that prompt was
removed as unnecessary friction. A project is created and named automatically the
moment a file is picked: real audio/video filenames are used as-is; videos with ugly
auto-generated names (e.g. from Photos) get a random, friendly name instead (drawn
from a list of cat breeds, with a number appended on collision — "Persian," "Persian
2," etc.). The name can always be changed later from inside the editor.

## Screen: Editor

Opened by tapping a project, or automatically via the Record button. Layers, back
to front: the app background, the time readout plus timeline, and a floating
control layer over the bottom edge (clip actions when a clip is selected, then
the transport). The timeline scrolls under the control layer.

### 1. Time readout (top)

Large rounded-monospaced current position over the project length. Turns red
while recording.

### 2. Timeline (fills the screen) — fixed playhead

**The playhead never moves. The timeline scrolls under it.** Scrolling *is*
scrubbing: drag or flick the lanes and the playhead position follows, with the
scroll view's own momentum and rubber-banding. While your finger is down (or the
scroll is coasting) playback pauses; when it settles, playback resumes from
there if it was running. During playback and recording the content auto-scrolls
so the current time stays under the playhead. There is no tap-to-seek and no
separate ruler drag — one gesture does it all.

- **Track headers** (fixed left column): icon + name (tap opens that track's
  panel) and a mute toggle. The lanes sit on a card with all four corners rounded
  and a margin around it, rather than a surface running off the bottom edge.
- **Ruler**: scrolls with the content. Tick spacing adapts to zoom.
- **Pinch to zoom**: anchored at the playhead, so the time under it never drifts.
- **Clips** draw real waveforms (peaks decoded once per file and cached).
- **Your own recorded takes are editable; imported/separated tracks are locked.**
  - **Tap** a take to select it. Trim handles appear on it and a floating
    **Split / Delete** bar appears above the transport.
  - **Drag a handle** to trim that edge, live. Trimming the front keeps the audio's
    absolute timing (the clip's start moves to match). Edges snap to the project
    start, the playhead and neighbouring clip edges, with a haptic.
  - **Split** cuts the selected clip at the playhead into two clips on the same
    track (only offered when the playhead is inside the clip). Both halves point at
    the same file with different trims — nothing is re-encoded.
  - **Long-press, then drag** moves a take. The press is what stops a move from
    fighting the scroll-to-scrub gesture: a plain drag scrolls, a held drag picks
    the clip up.
  - **Delete** removes the selected clip. If it was the track's last clip the row
    goes too.
- **Live recording lane**: while capturing, a red lane grows from the record
  start under the playhead.

### 3. Floating control layer (bottom)

One bottom-aligned stack over the timeline card's lower portion. Only the
transport is always present:

- **Clip actions** (Split / Delete) appear *above* the transport when a clip is
  selected.
- **Transport**: Rewind, Play/Pause (large, filled), Record (ring that morphs to
  a square while recording). Rewind is disabled while recording.
- **Track panel** appears *below* the transport when a track is selected, which
  pushes the transport up instead of burying it.

The timeline's bottom scroll inset grows to match whatever is floating, so the
last lane can always be scrolled clear.

### 4. Track panel

Opened by tapping any track header. Fixed height, and deliberately **not a
sheet** — a sheet owns the bottom of the screen, so the transport would sit
underneath it and you'd have to dismiss the panel to hear what a change did.
Here the transport stays directly above it, so you can move a slider and hit
play without closing anything. There is no full-screen state to drag to. Drag
the grabber down past a threshold, or tap Done, to close.

Always shows **Volume**. For vocal/recording tracks it also shows **Autotune**
(Siasca Plus — locked with a badge; tapping opens the paywall placeholder),
**Reverb** and **EQ**.

Renaming the project is in the "…" menu in the navigation bar (custom card, not
a system dialog). Stem separation is a navigation-bar button.

### Stem separation ("Separate" button)

Splits the current source into a vocal track and an instrumental track, replacing
the single source track with two. Runs entirely on-device (a bundled ML model, no
network call). Button states:

- **Idle**: "Separate" (capsule button).
- **Running**: inline in the transport bar — an indeterminate spinner with
  "Preparing model…" while the ~100MB model loads (one-time per session), then a
  determinate bar with a live percentage. Nothing blocks; the editor stays fully
  usable during separation.
- **Done**: "Separated" (no longer tappable — a project only gets split once;
  re-opening the editor remembers that it already happened).
- **Failed**: "Retry" (capsule button, same spot).

A real backing track typically takes some tens of seconds; this is intentionally not
real-time.

### Recording

Tapping Record starts capturing immediately (after the standard one-time
microphone-permission prompt). Recording and playback can happen at the same time —
sing over the backing track while it plays through the speaker, or record solo with
nothing else playing. While recording, a live "Recording" lane (red, pulsing header)
grows along the timeline so the take is visible before it's finished. The transport
play/pause button pauses and resumes the capture together with playback, so the
playhead and the recorded audio always stay matched; rewind/scrub are disabled
during recording since the take's position is fixed at its start. Stopping a
recording swaps the live lane for the finished, editable take (see trim/move above).

Instant-record projects (started from the red record button) have no real source
audio — the silent placeholder is hidden rather than shown as a fake clip, and the
Separate button doesn't appear for them.

## Screen: Settings (sheet)

Native inset-grouped list, close button top-left. Top to bottom:

- **Upgrade to Siasca Plus** banner (hidden once Plus is active) → paywall
  placeholder. Autotune is the first Plus-only feature; StoreKit is not wired.
- **Appearance** → App Theme (System / Light / Dark) and Background (Minimal /
  Plain), each as a row of preview cards.
- **Storage**: per-folder usage, Clean Up Unused Files.
- **Support**: Contact Support (mailto, subject pre-filled with the version), Rate,
  Share.
- **Legal**: Terms, Privacy.
- **Delete All Projects** (red, confirmed).
- Footer: wordmark and version.

Support email, legal URLs, product names and the version string all come from
`Core/AppConfig.swift` — one place to edit.

## Localization

User-facing strings are `LocalizedStringKey`s / `String(localized:)` and are
collected into `Resources/Localization/Localizable.xcstrings` at build time
(String Catalogs). Add a language in the catalog editor; nothing is fetched at
runtime.

## Things that look real but aren't (flag for design)

- **Autotune panel** — fully interactive UI, zero effect on audio. See above.
- **Waveforms on project cards** are decorative. Clips in the timeline draw real
  peaks.
- **Siasca Plus** — the banner, paywall and Autotune lock are real UI with no
  purchase behind them (`AppConfig.Plus.purchasingEnabled` is false).
- **Reverb/EQ/Volume settings don't persist** — they apply live during the session
  but reset to defaults the next time you open the project. Re-adjust each time, for
  now.
- **No export/mixdown yet** — there's no way to bounce the project to a single file
  or share it outside the app.
- **No metering** during recording (no live input level indicator).
