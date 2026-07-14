# Vocal Studio — Feature & UX Reference

What the app actually does today, screen by screen, framed around what the user can
do and how. Written for a design pass — everything here is current, real behavior,
not roadmap. Where something looks functional but isn't wired to anything real, it's
called out explicitly so design doesn't build around a stub.

**Naming note**: the Xcode project/bundle is still "Vocal Studio" — that hasn't
changed. The in-app brand shown to users is **"Aria"**. The visual direction is a
clean, light-first, near-monochrome look (in the spirit of ElevenLabs' iOS app):
system backgrounds, white cards, black-on-white controls, color reserved for
content (project orbs, clips) and for two deliberate accents — red for
record/mute, lavender for the on-device AI separation feature.

## Core concept

Import a backing track (or a video — audio gets extracted), sing over it with live
reverb/EQ monitoring, record your take, optionally separate the backing track into
vocals/instrumental stems, and arrange everything on a timeline. Single-player tool:
no accounts, no server, no cloud — everything runs and stays on-device.

## Navigation

Two real tabs plus one action button, in a custom floating capsule tab bar at the
bottom of the screen:

- **Projects** (`music.note.list`) — the project list. The app's home.
- **Settings** (`gearshape.fill`) — currently a placeholder screen ("App preferences
  and account," no actual settings exist yet).
- **Record button** — not a tab. A red ring with a punched-out center sitting
  beside the pill bar (the action stands apart from navigation). Tapping it
  immediately creates a new project (auto-named, silent placeholder source) and
  opens the editor with recording already running — the "sing first, sort it out
  later" path. No backing track is required to use this.

Tapping a project pushes straight into its editor (no intermediate screen). The
custom tab bar hides itself whenever a full-screen overlay (import menu, the editor
itself, etc.) is active.

## Screen: Projects (list)

**Brand row** (top): a large bold "Aria" title, project count or a loading
spinner trailing.

**Empty state** (no projects yet): a centered icon, "No Projects Yet," and a single
"Import Track" button that opens the same import menu as the "+" button.

**List state**: a search field (only shown once there are 2+ projects — not worth
it for one) above a scrollable list of project cards. Search filters by title,
live, case-insensitive. Each card shows the project's title, a relative "added Xd
ago" subtitle, a small abstract gradient thumbnail with decorative bars (not a real
waveform), and a relative-age tag ("3d," "2w"). Tapping a card opens that project's
editor. Swipe-to-delete is available on each row (standard list swipe gesture) and
respects the current search filter (deletes the right project even when the list is
filtered, not whatever happens to be at that row index).

A floating "+" button (bottom-right, always present once there's at least one
project) opens an import menu — a standard bottom sheet with two row choices:

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

Opened by tapping a project, or automatically via the instant-record donut button.
Three parts, top to bottom:

### 1. Transport bar (floating island, top of screen)

- **Time display** (large, leading): current playhead position over total duration,
  e.g. `1:23.4` over `3:45.0`.
- **Separate button** (trailing): see "Stem separation" below.
- **Rewind**, **Play/Pause**, **Record** — three large circular buttons, centered,
  with Record visually distinguished (red, fills solid when active).

### 2. Timeline (fills the rest of the screen)

- **Track headers** (fixed left column): one row per track, each showing an icon for
  the track's kind (instrumental, vocal, or one of your own recorded takes) and a
  small mute toggle. Tapping a row selects that track and opens its panel (see
  below); tapping the mute icon toggles muting without opening anything.
- **Ruler**: time markers above the tracks. **Drag along the ruler to scrub** — the
  playhead jumps to wherever you drag, live, whether or not playback is running.
- **Track lanes** (horizontally scrollable): each track's audio is drawn as a
  colored clip with a (currently decorative, not real-audio) waveform pattern.
  Color indicates kind: blue/dark for instrumental, purple for vocal stems,
  pink/purple gradient for your own recordings. **Tapping anywhere in a lane — empty
  space or directly on a clip — also moves the playhead there.** Dragging still
  scrolls the timeline horizontally as normal.
- **Pinch to zoom**: two-finger pinch anywhere in the timeline zooms the horizontal
  scale in/out, live.
- **Your own recorded takes are editable; imported/separated tracks are locked.**
  For a take you recorded:
  - **Drag the clip body** to move it earlier/later on the timeline.
  - **Drag either edge** (small grip handles appear at the leading/trailing edge) to
    trim it — trimming the front keeps the remaining audio's absolute timing intact
    (the clip's start position moves right to match what was cut); trimming the back
    just shortens it.
  - **Long-press → "Delete Recording"** removes that take entirely. If it was the
    only clip on that track, the whole (now-empty) track row disappears too.
- **Playhead**: a bright vertical line with a soft glow, showing current position.
  Advances live during playback, and also advances live during recording (so you can
  see time passing even if you're recording without anything else playing).

### 3. Track panel (sheet, slides up from the bottom)

Opened by tapping any track header. Always shows:

- **Volume** — a slider (0–150%) with a simple level-meter visual, applies to that
  track only.

For vocal/recording tracks only (not plain instrumental tracks), the panel also
shows:

- **Reverb** — wet/dry mix slider with a decay-bar visual.
- **EQ** — four-band parametric EQ (bass/low-mid/high-mid/treble) with a live curve
  visual.
- **Autotune** — ⚠️ **visual only, not functional.** Key/scale picker and
  amount/retune-speed sliders are all present and respond to touch, but nothing is
  connected behind them — no pitch correction happens. This is real UI sitting in
  front of an unbuilt feature; don't treat it as a working control when designing
  around it.

Renaming the project happens from a pencil icon in the editor's top bar — opens a
custom name-entry card (not a system dialog), matching the rest of the app's visual
language.

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
nothing else playing. Stopping a recording adds it to the timeline immediately as a
new, editable take (see trim/move above).

## Screen: Settings

Placeholder only. Icon, "Settings," "App preferences and account." No actual
settings exist yet — nothing to design around here except a future entry point.

## Things that look real but aren't (flag for design)

- **Autotune panel** — fully interactive UI, zero effect on audio. See above.
- **Waveforms** — every waveform shown anywhere (project cards, clips in the
  timeline) is a deterministic decorative pattern, not derived from real audio.
- **Reverb/EQ/Volume settings don't persist** — they apply live during the session
  but reset to defaults the next time you open the project. Re-adjust each time, for
  now.
- **No export/mixdown yet** — there's no way to bounce the project to a single file
  or share it outside the app.
- **No metering** during recording (no live input level indicator).
