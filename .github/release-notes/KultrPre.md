**KultrPre is a test build.** It installs next to Kultr as a separate app called **Kultr Pre**, with its own bundle ID (`app.kultr.ios.pre`), App Group and data. Your Kultr install stays as it is. You'll need to sign in to your server again in Kultr Pre. The in-app update check and the SideStore source never offer test builds.

## What's being tested: step 1, six small features

Everything from the Cream look stays as it was. On the first start after updating, a **What's new** page lists what changed. From now on every update has one.

- **Rediscover:** a new shelf on Home, after "Albums you keep coming back to". It shows albums you hearted or played at least three times that nobody has played for a year, on the server or on this phone. It's switched on once for you; Settings → Home page removes it or moves it.
- **Monthly recap:** Listening has a new card at the top that opens a page for this month. It shows how long you listened, plays, tracks and artists, and your top tracks, albums and artists. It also shows your longest day, how many tracks you heard for the first time, and the month before for comparison. The calendar button picks any earlier month. It's made from this phone's own history, because the server only counts plays per track.
- **Gestures on the cover:** in the player, double-tap the cover to heart the track, hold it to mix into the next one, and swipe up to jump to Up next. Settings → Playback → "The cover in the player" changes each one. The other options are lyrics, play or pause, add to a playlist, or nothing. Swiping sideways still skips.
- **Mix now:** fades into the next track over the whole crossfade length (at least 2 seconds), instead of skipping. It's a plain crossfade, not a beat-matched InjeKt mix.
- **Wind down:** with a timed sleep timer, the last 15 minutes put Karousel's calmest picks first: lower energy, slower tempo. The track that's up next and anything you queued yourself stay where they are. It's on by default, with a switch in the sleep timer and in Settings → Playback.
- **Save the session:** the new button at the top of Up next saves what you've played so far, or the whole queue, as a playlist. You can name it before it's saved.
- **Loading and empty pages:** pages show grey rows and covers in their real layout while they load, instead of a spinner. Empty pages say why they're empty and what to do, for example "No albums yet" with a Sync button. A filter that matches nothing says so too.

## Please check

- **What's new** opens once after installing this over Kultr Pre 1.4.0, and not again after you tap Continue or swipe it away.
- **Cover gestures:** double-tap, hold and swipe up on the cover. Check that scrolling the player still works when you start on the cover, and that pulling the player down still closes it.
- **Mix now:** hold the cover in the middle of a track. You should hear a smooth fade into the next one.
- **Rediscover:** does it show albums you'd forgotten, or nothing at all? If it's empty, tell me roughly how long your server has been counting plays.
- **Monthly recap:** open it from Listening and try the calendar button.
- **Wind down:** set a 15-minute sleep timer with Karousel on and look at the order in Up next.
- **Loading:** open Albums, Artists and Songs right after starting the app.

## Install

Download **KultrPre.ipa** below and install it the same way as Kultr: SideStore, AltStore, Sideloadly, Impactor or Feather. With a free Apple ID, it counts as one more app toward the limit of three.
