**KultrPre is a test build.** It installs next to Kultr as a separate app called **Kultr Pre**, with its own bundle ID (`app.kultr.ios.pre`), App Group and data. Your Kultr install stays as it is. You'll need to sign in to your server again in Kultr Pre. The in-app update check and the SideStore source never offer test builds.

## What's being tested: a code cleanup

This is Kultr 1.3.7 with about 300 lines of code that no longer did anything removed or merged. Nothing is meant to look or work differently. If something does, that's a bug.

- **Unused InjeKt tempo blending removed.** Since 1.3.1, InjeKt sets the next track's tempo before it starts and never changes a track's speed while it plays, because the iPhone's player stutters when it does. The older mode was still in the code: it eased the playing track toward the next one's tempo, then eased the new track back. It no longer ran. That code, and its two settings already hidden in Settings, are gone.
- **One small fix came out of it.** After a beat-matched mix, a song keeps the tempo it was matched to. If the next transition was a plain crossfade, Kultr used to reset that song to normal speed at the moment the crossfade began. It no longer changes speed mid-song.
- **Copied code merged, unused leftovers deleted.** Ending and cancelling a mix, seeking, starting downloads and the "Download favourites / everything" buttons each existed twice. A dozen small leftovers nothing used anymore are gone.
- **The AirPods test change is undone.** Kultr Pre is back to Kultr's normal audio setup.

## Please check

- Play an album with InjeKt on, through several mixes, with the phone locked.
- Skip, seek, pause and resume, including from the Lock Screen.
- Download favourites from the Downloads and Sync screens.

## Install

Download **KultrPre.ipa** below and install it the same way as Kultr: SideStore, AltStore, Sideloadly, Impactor or Feather. With a free Apple ID, it counts as one more app toward the limit of three.
