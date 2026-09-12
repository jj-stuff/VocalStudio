# Vocal Studio

An iOS vocal recording and editing app. Import a backing track (or a video, the audio gets extracted), sing over it with live reverb and EQ monitoring, record your take, split the backing track into vocal and instrumental stems on-device, and arrange it all on a multi-track timeline.

Everything runs and stays on the phone. No accounts, no server, no cloud.

## Highlights

- Multi-track timeline with clips, a ruler, and a transport bar
- Live monitoring effects while recording (reverb, EQ, volume, autotune tile)
- On-device stem separation using an HTDemucs Core ML model
- Projects persisted to the app's documents folder, visible in the Files app

See [FEATURES.md](FEATURES.md) for a screen-by-screen description of current behaviour, including what is still a stub.

## Requirements

- Xcode 26, iOS 26 SDK
- A physical device is recommended for audio input and Core ML performance

## Building

Open `Vocal Studio.xcodeproj`, select your own signing team, and run on a device. The stem separation model ships in `VocalStudio/Resources/Models/` and is loaded at runtime, so there is nothing to download.

`DevAssets/` is gitignored and only used by `DevSeedingProjectStore` to seed sample projects during development. Never commit third-party audio there.

## Layout

```
VocalStudio/
├── Core/        App shell, tab bar, navigation, constants
├── Features/    Editor, ProjectList, Settings
├── Models/      Project, Track, AudioClip, Stem, Recording, EffectSettings
├── Services/    Audio engine, Core ML stem separation, storage
└── Resources/   Fonts and the Core ML model
```

## License

The Instrument Serif font is bundled under the SIL Open Font License, see `VocalStudio/Resources/Fonts/InstrumentSerif-OFL.txt`.
