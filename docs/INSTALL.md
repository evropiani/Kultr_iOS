# Installing Kultr on your iPhone

This guide assumes you have **never** installed an app from outside the App
Store before. It takes about 20 minutes the first time and 2 minutes after that.
Your iPhone does **not** need to be jailbroken, and nothing here voids your
warranty.

---

## What you are about to do, in plain words

Apple only lets iPhones run apps that Apple has signed. The App Store signs
apps for you, and so does Apple's free developer program: any Apple ID can sign
an app **for its own iPhone**. That is called *sideloading*.

You will:

1. Download the Kultr app file (`Kultr.ipa`) to a computer.
2. Use a free program called **Sideloadly** on that computer. It signs the app
   with your Apple ID and copies it onto your iPhone over a USB cable.
3. Tell your iPhone that you trust apps signed by your own Apple ID.

There is one catch with a free Apple ID: **the app stops opening after 7 days**
unless you refresh it. Refreshing takes a minute and keeps all your data. This
is covered in [Keeping Kultr working](#5-keeping-kultr-working-the-7-day-rule).

---

## What you need

| | |
|---|---|
| An **iPhone or iPad** | running iOS 17 or newer (Settings → General → About → iOS Version) |
| A **computer** | Windows 10/11 or a Mac. You only need it for installing and refreshing |
| A **cable** | the one you charge your iPhone with, and it must carry data, not only charge |
| An **Apple ID** | the one you already use is fine. Some people make a second, free Apple ID just for sideloading. That's optional |
| A **GitHub account** | with access to this repository, because it is private |
| A **Navidrome server** | (or any Subsonic-compatible server) with its address, your username and your password |

---

## 1. Download Kultr

Do this **on the computer**.

1. Open **https://github.com/evropiani/Kultr_iOS/releases** in a web browser.
   - The repository is private. If you see a “404 – page not found”, you are
     either not signed in to GitHub or your account has not been given access.
     Sign in at the top right (or ask the owner to invite you) and try again.
2. At the top is the newest release, called **“Kultr for iOS 1.x.x”**. Under
   **Assets**, click **`Kultr.ipa`**. It downloads to your *Downloads* folder.
   - Do **not** click “Source code (zip)”. That's the source code, not the app.

Leave the file where it is. You will drag it into Sideloadly in a moment.

---

## 2. Install Sideloadly on the computer

### On Windows

Sideloadly needs Apple's own drivers to talk to your iPhone. They come with
iTunes and iCloud, but **only the versions from Apple's website work**. The
versions in the Microsoft Store do **not**.

1. If you already have iTunes or iCloud from the **Microsoft Store**, uninstall
   them first: Start → Settings → Apps → find *iTunes* / *iCloud* → Uninstall.
2. Install **iTunes** from Apple's website:
   https://www.apple.com/itunes/download/win64 (the download starts straight away).
   Run the installer and accept the defaults.
3. Install **iCloud for Windows** from Apple's website. Search for “iCloud for
   Windows download Apple support” and use the link on *support.apple.com*
   that says *“download iCloud for Windows from Apple's website”*, not the Microsoft
   Store button. You don't need to sign in to iCloud afterwards; it only has
   to be installed.
4. Download **Sideloadly** from its official site, **https://sideloadly.io**.
   Pick the Windows version and install it with the defaults.
5. Restart the computer. It's the easiest way to make sure the Apple drivers load.

### On a Mac

1. Download **Sideloadly** from **https://sideloadly.io** (the macOS version).
2. Open the downloaded `.dmg` and drag Sideloadly into *Applications*.
3. Open it from *Applications*. The first time, macOS may ask whether you are
   sure. Click **Open**. If macOS refuses outright, go to System Settings →
   Privacy & Security, scroll down, and click **Open Anyway** next to
   Sideloadly.
4. Sideloadly may ask to install a **Mail plug-in**. Follow its instructions.
   It needs this to talk to Apple on macOS.

> Only ever download Sideloadly from **sideloadly.io**. Sites that offer
> “Sideloadly” downloads or “free iPhone apps” elsewhere are not safe.

---

## 3. Connect your iPhone

1. Unlock your iPhone and plug it into the computer with the cable.
2. The iPhone asks **“Trust This Computer?”** Tap **Trust** and enter your
   iPhone passcode.
   - If the question never appears, unplug and plug it back in with the phone
     unlocked. On Windows, opening iTunes once often triggers it.
3. On Windows you can check it worked by opening iTunes. A small phone icon
   should appear near the top left. You can close iTunes again afterwards.

---

## 4. Install Kultr with Sideloadly

1. Open **Sideloadly**.
2. At the top, the **iDevice** box should show your iPhone's name. If it's
   empty, see [Troubleshooting](#sideloadly-doesnt-see-my-iphone).
3. In the **Apple account** box, type the email address of your Apple ID.
4. Drag **`Kultr.ipa`** from your *Downloads* folder onto the big IPA icon on
   the left of Sideloadly. You can also click the icon and pick the file.
5. Click **Start**.
6. Sideloadly asks for your **Apple ID password**. Type it and press OK.
   - Sideloadly sends it to Apple to create the free signing certificate. It
     does not go anywhere else.
7. If you use two-factor authentication (most people do), your iPhone or Mac
   shows a **6-digit code**. Type it into the box Sideloadly shows.
8. Wait. The bottom of the window shows progress, e.g. *“Signing”* and
   *“Installing”*. After about a minute it says **“Done.”**

The Kultr icon (a silver **K**) is now on your iPhone's home screen, but it
**won't open yet**. Do the next two steps first.

### Trust your own Apple ID on the iPhone

1. On the iPhone, open **Settings → General → VPN & Device Management**.
   (On some iOS versions it's called *Device Management* or *Profiles & Device
   Management*.)
2. Under **Developer App**, tap the entry with **your Apple ID email**.
3. Tap **Trust “your email”**, then **Trust** again.

### Turn on Developer Mode

iPhones need this switched on before they'll open any sideloaded app.

1. Open **Settings → Privacy & Security**.
2. Scroll all the way down and tap **Developer Mode**.
   - If there is no *Developer Mode* entry, install the app first (step 4).
     The option only appears once a sideloaded app is on the phone.
3. Turn it **on**. The iPhone asks to restart. Tap **Restart**.
4. After the restart, unlock the phone. It asks once more whether to turn on
   Developer Mode. Tap **Turn On** and enter your passcode.

### Open Kultr

Tap the **K** icon. Kultr asks for:

- **Server address**: the web address of your Navidrome, e.g.
  `https://music.example.com`. Use the same address you open in a browser.
- **Username** and **Password**: your Navidrome login.

Tap **Connect**. Kultr offers to sync your library. Let it finish once, with
Kultr open. After that it only fetches what changed.

That's it. Kultr is installed. 🎉

---

## 5. Keeping Kultr working (the 7-day rule)

Apps signed with a **free** Apple ID expire **7 days** after you install them.
When that happens, Kultr's icon stays on the home screen but it won't open, or
it closes straight away. **Your music, downloads and settings are not lost.**
You just need to sign it again:

1. Plug the iPhone into the computer and open Sideloadly.
2. Drag the same `Kultr.ipa` (or a newer one) onto it and click **Start**.
3. Done. Kultr opens again for another 7 days, with everything where you left it.

Tip: refresh it once a week, e.g. every Sunday, **before** it expires.

### Letting Sideloadly refresh automatically

Sideloadly can re-sign Kultr for you in the background, over Wi-Fi:

1. Turn on Wi-Fi syncing once, with the cable plugged in:
   - **Windows:** open iTunes → click the phone icon → *Summary* → tick
     **“Sync with this iPhone over Wi-Fi”** → **Apply**.
   - **Mac:** open Finder → click your iPhone in the sidebar → *General* →
     tick **“Show this iPhone when on Wi-Fi”** → **Apply**.
2. In Sideloadly, before clicking **Start**, open **Advanced options** and
   enable **Automatic refresh** (Sideloadly may call it *auto-refresh*).
3. Leave the computer on, with Sideloadly running in the background, on the
   same Wi-Fi as the iPhone. It re-signs Kultr before the 7 days are up.

### Limits of a free Apple ID

- At most **3 sideloaded apps** can be installed at the same time.
- At most **10 new app IDs per 7 days**. Reinstalling Kultr doesn't use a new
  one, but installing lots of different apps does.
- The 7-day expiry described above.

A paid **Apple Developer Program** membership ($99/year) removes these limits
and makes installs last a full year. You don't need it to use Kultr.

---

## 6. Updating to a new version

1. Download the newer `Kultr.ipa` from the
   [Releases page](https://github.com/evropiani/Kultr_iOS/releases), as in step 1.
2. Install it with Sideloadly exactly as in step 4, using the **same Apple ID**.

It installs over the old version and **keeps your servers, library, downloads
and settings**. Don't delete the old app first. Deleting the app deletes its
data.

---

## Troubleshooting

### Sideloadly doesn't see my iPhone
- Unlock the iPhone and make sure you tapped **Trust** (step 3).
- Try a different cable or USB port. Many cheap cables only charge.
- **Windows:** make sure iTunes and iCloud came from **Apple's website**, not
  the Microsoft Store (step 2). Open iTunes once with the phone plugged in, then
  restart Sideloadly.

### “Untrusted Developer” when opening Kultr
You skipped **Trust your own Apple ID**. Go to Settings → General →
VPN & Device Management and trust your Apple ID.

### “Developer Mode required” / Kultr won't open at all
Turn on **Developer Mode** (Settings → Privacy & Security → Developer Mode) and
restart the phone.

### Kultr opened fine for a week, and now it won't
The 7 days are up. Refresh it with Sideloadly ([section 5](#5-keeping-kultr-working-the-7-day-rule)).

### Sideloadly says “maximum number of apps” or “App ID limit reached”
A free Apple ID can have 3 sideloaded apps at once and create 10 app IDs a
week. Delete a sideloaded app you no longer use, or wait a few days.

### Sideloadly asks for a password again and again, or says the login failed
- Check that you can sign in at https://appleid.apple.com with the same email
  and password.
- If you use two-factor authentication, make sure you typed the 6-digit code
  when it appeared.
- **Mac:** make sure Sideloadly's Mail plug-in is enabled (Mail → Settings →
  General → Manage Plug-ins), then restart Sideloadly.

### Kultr can't connect to my server
- Type the address exactly as you open Navidrome in a browser, including
  `https://`. Try it in Safari on the iPhone first. If Safari can't reach it,
  neither can Kultr.
- A server at home (e.g. `http://192.168.1.20:4533`) only works while the
  iPhone is on your home Wi-Fi. If iOS asks whether Kultr may *find devices on
  your local network*, tap **Allow**.
- Tap **Advanced options** on the sign-in screen and try **Plain password** if
  your server sits behind a proxy that rejects token authentication.

### Music stops when I lock the phone
It shouldn't. Kultr plays in the background like any music app. Check that
*Low Power Mode* isn't killing it, and that you are on the latest Kultr release.

---

## Other ways to install

- **AltStore (Classic)**: works much like Sideloadly. You install *AltServer* on
  a computer, which installs the *AltStore* app on your iPhone. AltStore can then
  refresh Kultr over Wi-Fi by itself while the computer is on. Instructions:
  https://altstore.io. In AltStore, open the **My Apps** tab, tap **+** and
  pick `Kultr.ipa` (save it to the iPhone's *Files* app first).
- **Xcode on a Mac**: developers can open `Kultr.xcodeproj`, choose their own
  team under *Signing & Capabilities*, and run it on a connected iPhone.
