**KultrPre is a test build.** It installs next to Kultr as a separate app called **Kultr Pre**, with its own bundle ID (`app.kultr.ios.pre`), App Group and data. Your Kultr install stays as it is. You'll need to sign in to your server again in Kultr Pre. The in-app update check and the Kultr source never offer test builds.

## What's being tested: step 4, the energy planner and the command bar

Everything from 1.4.1 to 1.4.3 is still here. The What's new page opens once after updating.

- **Energy planner:** tap "Plan a set" on Home (or ••• on the Stations page).
  - Draw the shape of the set with your finger, low for calm and high for peak, or start from a shape: Warm up and peak, Steady, Build, Wind down.
  - Choose 30 minutes to 2 hours, and the whole library or one station's music.
  - "Build the set" picks, for each moment, the track whose energy is closest to your line. It also has to mix well out of the one before (close tempo, a neighbouring key), can't be by the same artist and can't repeat. Dots on the drawing show where each track lands.
  - Play it as it is, or save it as a playlist. It only uses tracks InjeKt has analysed; the page says how many are left.
- **Command bar:** Search also does things. Type a command and an orange row appears above the results; tap it or press Return.
  - Playing: "play Night Drive" (a station), "play" or "shuffle" and an artist or album, "shuffle all", "play" and a crate's name.
  - Controls: "pause", "play", "next", "back", "mix now".
  - Sleep timer: "sleep in 30 minutes", "stop in an hour", "sleep after this song".
  - Pages: "open settings", "show my stations", "open recap", "open" and a crate.
  - Planning: "plan an hour".
- **In your own words:** with Apple Intelligence on, longer requests the usual phrasings don't cover get an "Ask Kultr to do it" row. Apple's model reads it on the iPhone itself, and nothing is sent anywhere. Without Apple Intelligence, the row doesn't appear.

## Please check

- **Planner:** draw a shape, build a set, and look at whether the dots follow your line. Play it: do the mixes hold together?
- **Command bar:** try the commands above, and some of your own. Tell me what you'd expect to work but doesn't.
- **Apple Intelligence:** if your iPhone has it, try something like "put on something calm for an hour".

## Install

**Easiest:** add the KultrPre source in SideStore or FlareStore, and it offers every new build as an update:
`https://raw.githubusercontent.com/evropiani/Kultr_iOS/kultrpre-source/kultrpre.json`

**Or** download **KultrPre.ipa** below and install it the same way as Kultr: SideStore, AltStore, Sideloadly, Impactor or Feather. This link always gives the newest build: `https://github.com/evropiani/Kultr_iOS/releases/download/kultrpre-latest/KultrPre.ipa`

With a free Apple ID, KultrPre counts as one more app toward the limit of three.
