# Kultr for iOS

A native iPhone client for **Navidrome** and other Subsonic-compatible servers.
It's the iOS version of [Kultr for Android](https://github.com/evropiani/Kultr_Android),
with the same look, the same features and the same settings file.

**➡️ New to installing apps outside the App Store? Read the step-by-step
guide: [docs/INSTALL.md](docs/INSTALL.md).**

Download: [latest release](https://github.com/evropiani/Kultr_iOS/releases/latest) → `Kultr.ipa`.

## Features

- **Your library on the phone.** Kultr syncs a copy of your library into a
  local database, so browsing is instant and works offline. After the first
  sync, only changes are fetched.
- **InjeKt.** Tracks are analysed for tempo, key, energy and structure, and
  transitions are planned like a DJ would: beat-matched, bar-aligned, with bass
  swap and harmonic mixing. When the queue runs out, InjeKt keeps going with
  similar music.
- **Two-deck playback** with real crossfades (four fade shapes), gapless
  playback, ReplayGain and a 10-band equaliser.
- **Offline downloads** for albums, artists, playlists, favourites or
  everything, with a Wi-Fi-only option and a download queue.
- **Lock screen and Control Center** controls, **AirPlay**, and **scrobbling**
  (queued while offline).
- Lyrics (synced when the server has them), favourites, ratings, playlists,
  internet radio, listening stats, drag-and-drop onto *Play next*, *Queue*,
  *Favourite* and *Sync offline*.
- Several servers, with passwords kept in the iOS Keychain.
- Settings export/import, compatible with Kultr on Android and the web.

## Differences from Android

| Android | iOS |
|---|---|
| Chromecast | AirPlay |
| Android Auto | not available |
| Periodic background sync (WorkManager) | background refresh when iOS allows it; always checks on launch |
| Opus / Vorbis transcoding | MP3 or AAC. iOS can't stream Opus/Vorbis, so Kultr asks the server for MP3 instead |

## Building

Requirements: Xcode 16 or newer, iOS 17 SDK.

```sh
open Kultr.xcodeproj           # pick your team under Signing & Capabilities, then Run
swift test --package-path KultrCore   # unit tests for the core
```

- `KultrCore/`: platform-independent code: Subsonic client, settings, InjeKt
  (DSP + planner), the playback engine, library sync and the SQLite mirror.
  The app target compiles these sources directly. The Swift package exists so
  they can be tested with `swift test`.
- `Kultr/`: the app: data layer, AVFoundation decks with an audio tap for
  gain/EQ/filters, and the SwiftUI interface.

CI (`.github/workflows/ios.yml`) runs the core tests and builds on every push.
Pushes to `main` also build an unsigned `Kultr.ipa` and attach it to the
GitHub release for the current version.

## Contact

Questions, ideas, or something broken: [Discord @evropiani](https://discord.com/users/319246364246540288)
· [kultr.cc](https://kultr.cc/)
