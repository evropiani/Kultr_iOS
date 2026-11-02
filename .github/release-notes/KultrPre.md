**KultrPre is a test build.** It installs next to Kultr as a separate app called **Kultr Pre**, with its own bundle ID (`app.kultr.ios.pre`), App Group and data. Your Kultr install stays as it is. You'll need to sign in to your server again in Kultr Pre. The in-app update check and the Kultr source never offer test builds.

## What's being tested: step 5, Kultr Studio and widgets on Home

This is the last step before everything goes to Kultr as 1.5.0. Everything from 1.4.1 to 1.4.4 is still here, and the What's new page opens once after updating.

- **Kultr Studio:** Settings → Kultr Studio has the whole look in one place, with a live preview of the player at the top.
  - **Start from a style:** Cream (the default), Night (pure black), Ember (dark, colour from the cover, blurred cover behind the player, glowing playhead), Paper (light, sharp corners, compact) or Console (dark, sharp, tempo and key in the info line, the cover at the bottom). A style only changes the look; your library and other settings stay.
  - **Colours, shape and glass:** theme, night mode, colour from the artwork, corners, cover size, compact rows, the playhead, and clear instead of frosted glass for everything that floats.
  - **The player, top to bottom:** cover, title, info line, progress and buttons. Switch parts off, or hold a row and drag it to reorder.
  - **The info line:** write your own with names in braces, like `{bpm} BPM{?key: · {key}}`. A part in `{?key:…}` only shows when the track has that value. Tap a name to add it; the "Looks like" line previews it. bpm, key and energy come from InjeKt's analysis.
  - **Share:** send the style as a link or a file, copy the link, or use one from the clipboard or a file. Opening a `kultr://style/…` link shows a preview first, with "Use this style" or "Not now".
- **Widgets on Home:** under the buttons at the top of Home, three to start with: Now playing (medium), This week and Next mix (small).
  - **Kinds:** now playing (play, skip, tap to open the player), listening this week against your usual, the next mix with a countdown, a station, a crate, or a shortcut that does anything you could type in Search ("shuffle all", "sleep in 30 minutes", your own words).
  - **Sizes:** small ones sit side by side; medium and large ones go across.
  - **Editing:** hold a widget and they all wiggle. The minus takes one away, dragging one onto another moves it, "Add a widget" offers the rest, and "Done" stops.

## Please check

- **Studio:** try each style, then change a few things and watch the preview. Share the link to yourself (Notes or Messages) and open it: you should see the preview sheet first.
- **Player blocks:** move the cover to the bottom and switch off the info line. Does the player still pull down and scroll well?
- **Widgets:** hold one to edit, move a widget, add a station, a crate and a shortcut, and remove one. Do the sizes fit on your screen?

## Install

**Easiest:** add the KultrPre source in SideStore or FlareStore, and it offers every new build as an update:
`https://raw.githubusercontent.com/evropiani/Kultr_iOS/kultrpre-source/kultrpre.json`

**Or** download **KultrPre.ipa** below and install it the same way as Kultr: SideStore, AltStore, Sideloadly, Impactor or Feather. This link always gives the newest build: `https://github.com/evropiani/Kultr_iOS/releases/download/kultrpre-latest/KultrPre.ipa`

With a free Apple ID, KultrPre counts as one more app toward the limit of three.
