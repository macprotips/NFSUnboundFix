<p align="center"><img src="Resources/AppIcon.iconset/icon_128x128@2x.png" width="128" alt="NFS Unbound Fix icon"></p>

<h1 align="center">NFS Unbound Fix</h1>

<p align="center">Fixes the black screen at startup in <b>Need for Speed Unbound</b> on Mac, so the game loads and plays in CrossOver.</p>

---

## The problem

If you play Need for Speed Unbound on a Mac through **CrossOver** with **D3DMetal**, the game can get stuck on a black screen when it starts.

A fix was found: change 7 bytes in one game file to turn off an optional graphics cache that's involved in the crash. Doing that by hand means using a hex editor and checking file fingerprints in Terminal. It's easy to get wrong.

**NFS Unbound Fix does it for you.** Drag in your game folder, click one button, and it's done, with a backup made first.

## Before you start

You need:

- A Mac running **macOS 13 Ventura** or later
- **Need for Speed Unbound** from **Steam**, installed in **CrossOver**, at Steam build **16690907**

The app only changes that exact version of the game file. If your game is a different version, it tells you and changes nothing.

## How to use it

1. **Download** the latest `NFSUnboundFix.zip` from the [Releases](../../releases) page.
2. **Unzip it** and drag **NFS Unbound Fix** into your **Applications** folder.
3. **Quit the game** if it's running.
4. **Open NFS Unbound Fix.** Read the short notice and click **I Understand**.
5. **Drag in your game folder.** On Steam, Unbound's folder is named **Excalibur**, not "Need for Speed Unbound". You'll find it inside your CrossOver bottle, usually at:
   ```
   ~/Library/Application Support/CrossOver/Bottles/Steam/drive_c/Program Files (x86)/Steam/steamapps/common/Excalibur
   ```
   You don't have to find it exactly. You can drag in your **whole CrossOver bottle** and the app finds the right file. You can also click **Choose Folder…**.
6. Click **Apply Fix**.
7. **Launch Unbound through Steam in CrossOver** as usual.

That's it. The app shows a checklist of everything it checked and changed.

## Undoing the fix

Drag the game folder in again and click **Undo Fix**. Your original file is put back, exactly as it was.

You can also use **Verify integrity of game files** in Steam, which restores the original file too.

## After a game update

A Steam update or file check may replace the game file and remove the fix. Just open the app again and click **Check again**, or drag the folder in again.

If the update changed the file to a new version, the app says the version isn't supported and doesn't touch it. This fix only applies to build 16690907.

## Is it safe?

The app is careful at every step:

- **Checks the version first.** It compares the file's fingerprint (SHA-256) with the exact version the fix was made for. Any other version is left alone.
- **Makes a backup** of the original before changing anything, and checks the backup is a perfect copy. Backups are kept in `~/Library/Application Support/NFS Unbound Fix/Backups`. The **Backups** button opens the folder.
- **Checks the exact bytes** it's about to change are the expected ones.
- **Checks the result** before saving, saves in a way that can't leave a half-written file, then checks the saved file again. If anything doesn't match, it puts the original back.
- **Doesn't run while the game is open.**

It never touches anything else, and it contains no game code.

## What exactly it changes

For anyone who wants the details:

| | |
| --- | --- |
| File | `Engine.Render.Core2.PlatformPcDx12.dll` |
| Original SHA-256 | `ee3a654be58be406eda32aeadad99ad60894403e374a2d3b847a20008cd30c62` |
| Position | `0x1AB423` |
| Original bytes | `44 38 AB C0 01 00 00` |
| New bytes | `80 A3 C0 01 00 00 00` |
| Fixed SHA-256 | `9dc33b2edebca402c48c53f32cce474aafd5d640e5754275484deaced66134aa` |

## Credits

This app only automates a fix that other people found and shared:

- **Ariel O**, for the tip in the [CodeWeavers Compatibility Database](https://www.codeweavers.com/compatibility) that got Unbound running in CrossOver.
- **[u/ales_sandr](https://www.reddit.com/user/ales_sandr/)**, for the Reddit post that spread the fix.

Thank you both.

## Disclaimer

**Use at your own risk.** NFS Unbound Fix is an independent tool. It isn't made, endorsed or supported by Electronic Arts or Criterion Games, and it's unclear whether EA allows fixes like this. Changing game files may go against EA's user agreement, and playing online with a changed game could put your EA account at risk.

Need for Speed and Need for Speed Unbound are trademarks of Electronic Arts Inc.

---

<details>
<summary><b>For developers</b></summary>

### Build it yourself

Needs Xcode or the Command Line Tools.

```sh
git clone https://github.com/macprotips/NFSUnboundFix.git
cd NFSUnboundFix
swift test                 # runs the safety tests
scripts/build-app.sh       # creates build/NFS Unbound Fix.app
```

### Project layout

| Path | What's there |
| --- | --- |
| `Sources/NFSUnboundFixKit/Patcher.swift` | Finding, checking, backing up, patching and undoing |
| `Sources/NFSUnboundFix` | The app window |
| `Tests/NFSUnboundFixKitTests` | Tests for every step, run against a stand-in file |
| `Tools/make_icon.py` | Draws the app icon |

Every push builds and tests the app on GitHub Actions.

### Signing and notarizing

The build signs the app with a Developer ID certificate and has Apple notarize it once these repository secrets are set (**Settings → Secrets and variables → Actions**):

| Secret | What it is |
| --- | --- |
| `MACOS_CERTIFICATE` | The Developer ID Application certificate and private key, exported as a `.p12` and base64-encoded |
| `MACOS_CERTIFICATE_PASSWORD` | The password chosen when exporting the `.p12` |
| `APPLE_ID` | The Apple ID email of the developer account |
| `APPLE_APP_PASSWORD` | An app-specific password from account.apple.com |

Without them, the app is signed ad hoc and macOS asks for approval on first launch.

</details>
