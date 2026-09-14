<div align="center">

<img src="docs/assets/icon.png" alt="Siasca" height="120">

# Siasca

**Sing over any song. Split the vocals out. Keep every take.**

An iOS studio that runs entirely on your phone.

<a href="https://stephanbordellier.com/siasca"><img src="https://img.shields.io/badge/Website-5B3FD9?style=for-the-badge" alt="Website"></a>
&nbsp;<img src="https://img.shields.io/badge/App_Store-Coming_soon-1C1C1E?style=for-the-badge&logo=apple" alt="Coming to the App Store">
&nbsp;<img src="https://img.shields.io/badge/iOS_26-000000?style=for-the-badge&logo=apple" alt="iOS 26">
&nbsp;<img src="https://img.shields.io/badge/Swift_6-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 6">

</div>

## The name

**Siasca** is two languages stuck together.

*Sia* comes from the Thai **เสียง** (*sǐang*) — sound, voice. *Sca* comes from the
Swedish **skapa** — to create. Sound, created. I grew up between both places, so
the app is named the way I am.

It's pronounced *see-AHS-ka*.

## What it does

Drop in a song. A model on the phone pulls the vocals away from the
instrumental, so you can mute the original singer and take their place. Record
your take over the backing track, trim it, cut it, stack another one on top.

No account. No upload. No server. Every file stays in the app's own folder on
your device, and the separation model runs on the Neural Engine, offline.

<!-- Drop four device screenshots into docs/assets/ to fill this in. -->
<div align="center">
<img src="docs/assets/projects.png" width="24%" alt="Projects">
<img src="docs/assets/studio.png" width="24%" alt="Studio">
<img src="docs/assets/effects.png" width="24%" alt="Effects">
<img src="docs/assets/settings.png" width="24%" alt="Settings">
</div>

## Features

- **On-device stem separation.** A bundled HTDemucs Core ML model splits a track
  into vocals and instrumental. Nothing leaves the phone, and the editor stays
  usable while it runs.
- **Fixed-playhead timeline.** The playhead holds still and the audio scrolls
  under it, so scrolling *is* scrubbing — the same model GarageBand and Voice
  Memos use. Pinch to zoom, anchored at the playhead.
- **Real editing.** Select a take to trim either edge, split it at the playhead,
  move it, delete it. Edges snap to the playhead, the project start and
  neighbouring clips.
- **Live monitoring.** Reverb, EQ and volume per track through AVAudioEngine
  while you sing.
- **Record first, decide later.** One button makes a project and starts
  recording. A backing track is optional.
- **Waveforms from the actual audio**, decoded once per file and cached.
- **Yours to look at.** Projects live in the app's documents folder and show up
  in the Files app.

[FEATURES.md](FEATURES.md) walks through every screen, including what is still a
stub.

## How it's built

SwiftUI on iOS 26, Swift 6 with `MainActor` default isolation. No third-party
packages.

| | |
|---|---|
| **Audio** | `MultiTrackEngine` wraps `AVAudioEngine` — one player node per clip, routed through a per-track mixer → EQ → reverb chain. Capture is `AVAudioRecorder` rather than an input tap, because `inputNode.outputFormat` reports a zero sample rate on device even with a valid session. |
| **Separation** | `CoreMLStemSeparator` runs HTDemucs in overlapping windows with a Hann fade between them, reporting progress as it goes. |
| **Timeline** | One `TimelineGeometry` value owns every seconds↔points conversion, so the ruler, clips, playhead and scroll offset can't drift apart. Scroll phases decide who owns the playhead: user scroll scrubs, otherwise playback drives `ScrollPosition`. |
| **State** | `@Observable` view models, a `ProjectStoreInterface` protocol over a JSON-on-disk store. |
| **Design** | One accent colour, system fonts, SF Rounded for numeric readouts. Liquid Glass only where content actually scrolls underneath it. |

## Building

Xcode 26 and the iOS 26 SDK. Open `Vocal Studio.xcodeproj`, set your own signing
team, and run — preferably on a device, since the simulator has no real
microphone and no Neural Engine.

The Core ML model ships in `VocalStudio/Resources/Models/` and loads at runtime,
so there is nothing to download.

```
VocalStudio/
├── Core/        App shell, navigation, config, appearance, design tokens
├── Features/    Editor (timeline, transport, effects), ProjectList, Settings, Plus
├── Models/      Project, Track, AudioClip, Stem, Recording, EffectSettings
├── Services/    Audio engine, waveform cache, Core ML separation, storage
└── Resources/   Fonts, string catalog, Core ML model
```

`DevAssets/` is gitignored and only feeds `DevSeedingProjectStore` during
development. Never commit audio you don't own there.

## Roadmap

- Autotune (the UI is built, the DSP is not)
- Mixdown and export
- Lyrics, from on-device transcription or matched for known songs

## Licence

Source-available, not open source. The code is here to read; it isn't licensed
for redistribution or for shipping your own build. See [LICENSE](LICENSE).

Instrument Serif is bundled under the SIL Open Font License — see
`VocalStudio/Resources/Fonts/InstrumentSerif-OFL.txt`. The HTDemucs architecture
comes from Meta's [Demucs](https://github.com/facebookresearch/demucs) project.

---

<div align="center">

Built by <a href="https://stephanbordellier.com">Stephan Bordellier</a> ·
<a href="mailto:support@siasca.app">support@siasca.app</a>

</div>
