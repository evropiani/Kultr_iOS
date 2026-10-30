**KultrPre is a test build.** It installs next to Kultr as a separate app called **Kultr Pre**, with its own bundle ID (`app.kultr.ios.pre`), App Group and data. Your Kultr install stays as it is. You'll need to sign in to your server again in Kultr Pre. The in-app update check and the SideStore source never offer test builds.

## What's being tested

- **Standard audio setup.** Kultr has used the "long-form audio" setting, which makes it play to the same output the Music app uses. With that setting, iOS didn't send Kultr a pause when one AirPod came out. Apple Music does pause. This build drops the setting. If taking one AirPod out now pauses the music, and AirPods, Bluetooth, AirPlay and calls still behave as before, the change goes into Kultr.
- A "stop" command from iOS, if it ever sends one, now pauses and appears in the playback log.

## Install

Download **KultrPre.ipa** below and install it the same way as Kultr: SideStore, AltStore, Sideloadly or Impactor. With a free Apple ID, it counts as one more app toward the limit of three.
