# Kultr for iOS

A native iPhone client for [Navidrome](https://www.navidrome.org/) and other
Subsonic-compatible servers. It's the iOS counterpart of the
[Kultr web client](https://github.com/evropiani/Kultr) and of
[Kultr for Android](https://github.com/evropiani/Kultr_Android). It keeps
their behaviour and settings (a settings file exported from one opens in the
others) and runs as a proper iOS music app: background playback, lock-screen
and Control Center controls, AirPlay, and downloads for offline listening.

## Features

- **Liquid glass.** On iOS 26 the tab bar is the system's own liquid glass
  bar, with the lens that follows your finger, a round search button that
  grows into the search field, and the mini player riding on it; on iOS 17
  and 18 Kultr draws a floating glass bar that behaves the same way. Light
  and dark follow the iPhone's own setting. Every tab keeps its own pages with
  iOS's navigation bar, and Settings is a list of native pages.
- **Library mirror.** The whole library is synced into a local database, so
  browsing and search are instant and work offline. Later syncs fetch only
  what changed. They run when Kultr starts, and in the background whenever
  iOS allows it.
- **Two-deck playback.** Every track plays on one of two players, so Kultr can
  crossfade (with a choice of curves), play gapless albums seamlessly, or cut.
- **InjeKt transitions.** Tracks are analysed on the phone (tempo, beat grid,
  key, energy and intro/outro structure), and transitions are planned from
  that. You get tempo-matched blends that land on the downbeat, a bass swap, a
  filter sweep, and key-aware ordering for an endless automatic queue.
- **Offline.** Download albums, playlists, favourites or the whole library, at
  a bitrate of your choosing, on Wi-Fi only if you like. A Downloads page shows
  what is coming down, what is queued or failed, and what is already on the
  phone. Downloaded tracks play before the network is tried, and a stream
  cache keeps recent tracks too.
- **AirPlay** to a HomePod, Apple TV or any AirPlay speaker from the player.
- **Long-press menus and swipes.** Long-press a track, album, artist or
  playlist to play it next, queue it, favourite, download or remove it;
  swipe a track to play it next or add it to the queue.
- **Listening on your server.** Every play is sent to Navidrome with the time
  it happened (offline plays go later, exactly once), and plays from your
  other devices come back, so "played recently" and "played the most" are the
  same everywhere.
- **Several servers.** Sign in to more than one server, name them as you
  like, and switch between them. Each has its own library, downloads and
  history. Passwords are kept in the iOS Keychain.
- **Home shelves** you choose and reorder: jump back in, recently added, most
  played, albums at random, favourites, playlists on repeat, internet radio
  and more.
- **Audio:** ten-band equaliser with presets, ReplayGain (track or album),
  per-network streaming bitrate, sleep timer (after minutes or at the end of
  the track).
- **Also:** synced and plain lyrics, ratings and favourites, playlist editing,
  scrobbling with an offline queue, listening stats, internet radio, a
  now-playing screen tinted by the artwork, and settings backup and restore.

## Getting it

Kultr isn't on the App Store. You install it yourself, a process called
*sideloading*, which works on any iPhone or iPad running iOS 17 or later
without jailbreaking. All you need is a free Apple ID, and either a computer
(Windows, macOS or Linux) or, on iOS 27, just the iPhone.

**➡️ Step-by-step guide for first-timers: [docs/INSTALL.md](docs/INSTALL.md)**

In short: download `Kultr.ipa` from the
[latest release](https://github.com/evropiani/Kultr_iOS/releases/latest),
then install it with your Apple ID:

- **With a computer:** [Sideloadly](https://sideloadly.io) (Windows, macOS),
  [AltStore](https://altstore.io) (Windows, macOS) or
  [Impactor](https://github.com/khcrysalis/PlumeImpactor) (Linux).
- **Without a computer:** connect
  [LocalDevVPN](https://apps.apple.com/app/localdevvpn/id6755608044), let
  [SideInstaller](https://github.com/FrizzleM/SideInstaller) (only from
  [sideinstaller.net](https://sideinstaller.net/)) install SideStore, and
  install `Kultr.ipa` in SideStore. That works start to finish on iOS 27; iOS
  18 to 26 need a pairing file made on a computer once.
  [How](docs/INSTALL.md#without-a-computer-sideinstaller-and-localdevvpn)

With a free Apple ID the app has to be re-signed every 7 days. SideStore and
Sideloadly can do that for you automatically. Your library, downloads and
settings survive it, and installing a new release over the old one keeps them
too.

The IPA is unsigned: the tool you install it with signs it for your device.
Every push to `main` is built by GitHub Actions, and the resulting IPA
replaces the one on the current release.

## Building

Requirements: macOS with Xcode 26 or newer (the iOS 26 SDK; the app itself runs on iOS 17 and later). Then:

```sh
swift test --package-path KultrCore     # core unit tests, no simulator needed
open Kultr.xcodeproj                    # choose your team under Signing & Capabilities, then Run
```

To build the same unsigned IPA the workflow publishes:

```sh
xcodebuild build -project Kultr.xcodeproj -scheme Kultr -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO
mkdir -p Payload && cp -R build/Build/Products/Release-iphoneos/Kultr.app Payload/
zip -qry Kultr.ipa Payload
```

### Releasing

Bump `MARKETING_VERSION` in `Kultr.xcodeproj/project.pbxproj`, add notes as
`.github/release-notes/v<version>.md`, and push to `main`. The **iOS** workflow runs the core tests, builds the IPA and publishes
it as the GitHub release `v<version>`, creating the release if it doesn't
exist yet or replacing its IPA if it does. The build number is the workflow's
run number.

It then adds the release to the AltStore / SideStore source kept in a gist
([apps.json](https://gist.github.com/evropiani/6e3a3c18525a228d03924674430c4d48),
by `.github/scripts/update-source.py`), when the repository has a `GIST_TOKEN`
secret (a classic token with only the *gist* scope).

## How it is put together

| Part | What it holds |
| --- | --- |
| `KultrCore` | Plain Swift, no UIKit or AVFoundation: the Subsonic API client, the audio analysis (FFT, tempo, key, structure), the InjeKt transition planner, the two-deck playback engine, the library sync, the SQLite library mirror, and the settings model with its import/export. A Swift package, unit-tested with `swift test`. The app compiles the same sources directly. |
| `Kultr` | The iOS app: a database per server, a download queue, background refresh for sync, a player that drives two AVFoundation decks through the core engine (with an audio tap for fades, EQ and filters), Now Playing and remote-command integration, and the SwiftUI interface. |

No third-party dependencies: SwiftUI, AVFoundation, MediaPlayer, SQLite3,
CryptoKit, Network and BackgroundTasks from the iOS SDK.

## License

Apache License 2.0. See [LICENSE](LICENSE).
