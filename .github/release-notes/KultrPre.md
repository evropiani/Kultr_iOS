**KultrPre is a test build.** It installs next to Kultr as a separate app called **Kultr Pre**, with its own bundle ID (`app.kultr.ios.pre`), App Group and data. Your Kultr install stays as it is. You'll need to sign in to your server again in Kultr Pre. The in-app update check and the Kultr source never offer test builds.

## What's being tested: pulling the player down, hold Next to mix, the update log

Everything from 1.4.1 to 1.4.5 is still here, apart from what's listed as gone below. The What's new page opens once after updating.

- **Pulling the player down closes it again, from anywhere.**
  - **Why it stopped working:** the cover's gestures caught the pull. Double-tap, hold and swipe-up each waited for your finger, and the sideways swipe claimed every drag that started on the cover.
  - **What's left:** the sideways swipe only, and it now lets the sheet see the same drag. Up and down belong to the sheet; clearly sideways still skips.
- **Hold Next to mix.** Hold the player's Next button and Kultr mixes into the next track over the whole crossfade (at least 2 seconds) instead of cutting. A tap still skips. VoiceOver offers "Mix into the next track" as an action on the button.
- **Update log:** Settings → About → Update log opens a card with every version, from 1.0.0 to this one, newest first. Each version has its date and what changed. The KultrPre builds since 1.4.0 are there too.
- **Gone:**
  - The Live Activity. One still showing from an earlier build is ended when Kultr Pre starts.
  - The beat pulse on the play button, and its tapping.
  - "The cover in the player" in Settings → Playback.

## Please check

- **Pulling down:** pull the player down starting on the cover, on the title, on the buttons' row and on the queue (scrolled to the top). It should close every time.
- **Swipe and hold:** swipe the cover sideways to skip, and hold Next to mix.
- **Update log:** open it, scroll to the bottom, and swipe it closed.

## Install

**Easiest:** add the KultrPre source in SideStore or FlareStore, and it offers every new build as an update:
`https://raw.githubusercontent.com/evropiani/Kultr_iOS/kultrpre-source/kultrpre.json`

**Or** download **KultrPre.ipa** below and install it the same way as Kultr: SideStore, AltStore, Sideloadly, Impactor or Feather. This link always gives the newest build: `https://github.com/evropiani/Kultr_iOS/releases/download/kultrpre-latest/KultrPre.ipa`

With a free Apple ID, KultrPre counts as one more app toward the limit of three.
