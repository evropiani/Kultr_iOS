**KultrPre is a test build.** It installs next to Kultr as a separate app called **Kultr Pre**, with its own bundle ID (`app.kultr.ios.pre`), App Group and data. Your Kultr install stays as it is. You'll need to sign in to your server again in Kultr Pre. The in-app update check and the Kultr source never offer test builds.

## What's being tested: step 3, Crates, notes and tags, and the glass lens

Everything from 1.4.1 and 1.4.2 is still here. The What's new page opens once after updating.

- **Crates:** folders for albums, artists and tracks, in Library → Crates.
  - **By hand:** hold an album, an artist or a track anywhere (or use ••• on its page, or select several tracks) and tap **Add to crate**. The list ticks the crates it's already in; tap a crate again to take it out.
  - **By rules:** "New crate → Fill it by rules" uses the same rules as stations, plus two new ones: your tags, and when the music was added. It starts as "4 stars and up, added this year".
  - A crate's page plays or shuffles everything in it. ••• renames it, changes its rules, makes a station of the same rules, or deletes it.
  - **Keep as a playlist** keeps a playlist of the same name on your server with the same tracks, updated a moment after the crate changes. Other apps see it too. Deleting the crate leaves the playlist.
- **Notes and tags:** album and artist pages have a "Your notes" section above the info text.
  - **+ Tag** adds a tag of your own, and tapping a tag shows everything with it. Hold a tag to remove it.
  - **Add a note** keeps a note of any length.
  - Library → Tags lists every tag once you've used one. A tag's page can play everything with it, or make it a crate with one tap.
  - Notes and tags are private: they stay on the phone, with your settings, and go into a settings backup (Settings → Backup and reset).
- **Glass lens:** drag along the player's progress bar and a glass lens floats above your finger. It shows the time large, and eight seconds of the track around it with InjeKt's beats marked: the first beat of each bar is taller and orange, and a planned mix is shaded. Before InjeKt has analysed the track, it shows second marks instead.
- **Stations, smaller fixes:** the dial has a faint edge in dark mode, and the Home shelf puts stations that have music first. A station with nothing to play yet says why ("Needs InjeKt analysis").

## Please check

- **Crates:** add an album, an artist and a few tracks to a crate from their menus, then open it from Library → Crates. Do the covers on the crate's card look right?
- **Rules:** make a crate by rules and check that its tracks fit.
- **Keep as a playlist:** switch it on for a crate and look for the playlist in Library → Playlists (pull to refresh), and in another Subsonic app if you use one.
- **Notes and tags:** tag two albums the same, open the tag from the album page and from Library → Tags, and write a note.
- **Lens:** does it sit above your finger without covering what you need, and do the beat marks line up with the music?

## Install

**Easiest:** add the KultrPre source in SideStore or FlareStore, and it offers every new build as an update:
`https://raw.githubusercontent.com/evropiani/Kultr_iOS/kultrpre-source/kultrpre.json`

**Or** download **KultrPre.ipa** below and install it the same way as Kultr: SideStore, AltStore, Sideloadly, Impactor or Feather. This link always gives the newest build: `https://github.com/evropiani/Kultr_iOS/releases/download/kultrpre-latest/KultrPre.ipa`

With a free Apple ID, KultrPre counts as one more app toward the limit of three.
