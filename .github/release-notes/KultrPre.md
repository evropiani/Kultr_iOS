**KultrPre is a test build.** It installs next to Kultr as a separate app called **Kultr Pre**, with its own bundle ID (`app.kultr.ios.pre`), App Group and data. Your Kultr install stays as it is. You'll need to sign in to your server again in Kultr Pre. The in-app update check and the SideStore source never offer test builds.

## What's being tested: the player as a sheet

Pulling the full player down jumped, stalled and stuttered, most of all the first time. The player was Kultr's own card drawn over the app. Every frame of the pull, Kultr redrew the whole card, cut it to shape, shrank it, and redrew the glass tab bar under it. The phone couldn't keep up, so the card moved at 30 frames a second instead of 60 or 120.

The player now opens as an iOS sheet, like a sheet in any Apple app. iOS moves it by itself while you pull, and Kultr draws nothing during the gesture.

- **Pull down from the top of the player to close it.** If you've scrolled down to the queue, scroll back up first, or pull from the top bar.
- **It looks slightly different.** The player has the system's grabber at the top, and rounded top corners.
- **Add to playlist, Rate, the sleep timer and the little messages now open over the player** instead of behind it.

Also in this build, from the last test: the whole-app simplification (cards, settings pickers, Library pager, queue adding, sign-in fields).

## Please check

- **The pull:** open the player and pull it down slowly, quickly, and a little then let go. It should follow your finger smoothly from the first touch, close on a long or fast pull, and spring back on a short one.
- **The first time:** quit Kultr Pre, open it, start music, open the player and pull it down. This was the worst case.
- **Scrolling:** scroll down to Up next, then pull down. The list should scroll up first; once it's at the top, pulling down closes the player.
- **From inside the player:** the ••• menu's Sleep timer, Add to playlist and Rate should open on top of the player. Go to album and Go to artist should close the player and open the page.
- **Messages:** tap the shuffle button in the player. The note at the top should appear over the player.

## Install

Download **KultrPre.ipa** below and install it the same way as Kultr: SideStore, AltStore, Sideloadly, Impactor or Feather. With a free Apple ID, it counts as one more app toward the limit of three.
