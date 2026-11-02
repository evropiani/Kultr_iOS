**KultrPre is a test build.** It installs next to Kultr as a separate app called **Kultr Pre**, with its own bundle ID (`app.kultr.ios.pre`), App Group and data. Your Kultr install stays as it is. You'll need to sign in to your server again in Kultr Pre. The in-app update check and the SideStore source never offer test builds.

## What's being tested: a whole-app simplification

This is Kultr 1.3.8 with about 150 more lines folded together. Nothing is meant to look or work differently. If something does, that's a bug.

- **Cards draw through one layout.** Album, artist, playlist and radio cards had four copies of the same artwork-title-subtitle stack. Radio station names are now semibold like every other card title.
- **Shared buttons and pickers.** The heart on album and artist pages, the favourite entry in long-press menus, and the three bitrate pickers in Settings each exist once now.
- **Settings pages read and write their switches more directly.** Each page sets its title in one place.
- **The Library pager follows your finger one way instead of two.** It used to track the swipe twice, once for iOS 17.
- **Smaller merges.** Play next and Add to queue share one path. The login fields share one frame. Home and Stats list their tracks the same way album pages do. The two EQ shelf filters use one formula, checked to give the same numbers. Leftovers from the old floating tab bar are gone.

## Please check

- **Settings → Audio and Settings → Offline and cache:** the three quality pickers (On Wi-Fi, On mobile data, Download quality) still list Original, 320, 256, 192, 128 and 96 kbps, and a choice sticks.
- **Equaliser:** a preset with bass or treble boost sounds the same as in Kultr.
- **Library:** swipe between Albums, Artists, Songs and the rest. The underline should follow your finger. Filter each page.
- **Favourites:** heart and unheart an album and an artist from their pages and from a long press.
- **Tabs:** open an album, switch tabs, come back. The album is still open. Tap the tab again to go back to its start.
- **Queue:** Play next and Add to queue from a track's menu, with music playing and with nothing playing.
- **Sign-in:** add a server. The fields should not autocorrect or capitalise.

## Install

Download **KultrPre.ipa** below and install it the same way as Kultr: SideStore, AltStore, Sideloadly, Impactor or Feather. With a free Apple ID, it counts as one more app toward the limit of three.
