**KultrPre is a test build.** It installs next to Kultr as a separate app called **Kultr Pre**, with its own bundle ID (`app.kultr.ios.pre`), App Group and data. Your Kultr install stays as it is. You'll need to sign in to your server again in Kultr Pre. The in-app update check and the Kultr source never offer test builds.

## What's being tested: step 2, Stations, Live Activity and Beat pulse

Everything from 1.4.1 (Rediscover, monthly recap, cover gestures, wind-down, save the session, loading pages) is still here. The What's new page opens once after updating.

- **Stations:** endless mixes from your own library. A new Stations shelf is added at the top of Home once.
  - Tap a card to start the station, or tap the shelf's title for the Stations page.
  - There, turn the glass dial to choose; it clicks at each station. While a station plays, turning the dial and letting go mixes into the new one after a moment.
  - The starting stations are Warm Up, Night Drive, Peak Hour, Deep Focus, Wind Down, Unplayed gems and Favourites, plus one per decade with at least 20 tracks.
  - Karousel follows the station's rules instead of looking for similar music, and InjeKt picks what mixes best from each track. It keeps going even if Karousel is switched off.
  - Up next shows the station, with an End button. Playing anything else also ends it.
- **Your own stations:** every station is a set of rules you can edit: tempo, energy (1 to 10), key (Camelot), genres, years, never played, favourites and minimum rating. While you edit, the page counts how many tracks fit.
  - Use ••• to edit, duplicate or delete a station, and "New station" to add one. ••• in the corner brings back the starting set.
  - Tempo, energy and key come from InjeKt's analysis, so those stations only have tracks InjeKt has analysed (or whose tags carry a tempo). The Stations page says how many are left, with an "Analyse the rest" button.
- **Live Activity:** the Lock Screen and the Dynamic Island show the track, its progress, a play/pause button and a countdown to the next mix, like "Beat-matched blend into Paper Moons in 0:12". Before InjeKt has planned the mix (about half a minute before the end), the countdown is an estimate. It starts the next time music starts with Kultr open. Switch it off in Settings → Playback.
- **Beat pulse:** the play button swells, with a soft orange ring, on the first beat of every bar, once InjeKt has analysed the track. "Tap on the beat" in Settings → Playback makes the phone tap along while the player is open (off at first). With Reduce motion on, it doesn't pulse.

## Please check

- **Stations:** start one from Home and from the dial. Does the music fit the name? Turn the dial while it plays, then let go: it should mix into the new station within a few seconds.
- **The dial:** does it turn smoothly and click once per station?
- **Editing:** make a station of your own and check that the count changes as you change the rules.
- **Live Activity:** lock the phone while music plays. Is the countdown right, and does play/pause work from the Lock Screen and the Dynamic Island? Does it go away when you stop the music?
- **Beat pulse:** with a track InjeKt has analysed, does the pulse land on the beat? Try "Tap on the beat" too.

## Install

**Easiest:** add the KultrPre source in SideStore or FlareStore, and it offers every new build as an update:
`https://raw.githubusercontent.com/evropiani/Kultr_iOS/kultrpre-source/kultrpre.json`

**Or** download **KultrPre.ipa** below and install it the same way as Kultr: SideStore, AltStore, Sideloadly, Impactor or Feather. This link always gives the newest build: `https://github.com/evropiani/Kultr_iOS/releases/download/kultrpre-latest/KultrPre.ipa`

With a free Apple ID, KultrPre counts as one more app toward the limit of three.
