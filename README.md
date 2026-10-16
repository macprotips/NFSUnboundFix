<p align="center"><img src="Resources/AppIcon.iconset/icon_128x128@2x.png" width="128" alt="NFS Unbound Fix icon"></p>

<h1 align="center">NFS Unbound Fix</h1>

<p align="center">Fixes the black screen at startup in <b>Need for Speed Unbound</b> on Mac, so the game loads and plays in CrossOver.</p>

---

## The problem

If you play Need for Speed Unbound on a Mac through **CrossOver** with **D3DMetal**, the game can get stuck on a black screen when it starts.

The first fix that was found turns the game's **shader pre-building** off. That stops the crash, but then every shader is built the moment it's first needed while you play, which causes stutter.

**NFS Unbound Fix 1.1 fixes the actual cause instead.** At startup, the game pre-builds the shaders it saved from your last session. A few of them can't be created on a Mac, and the game crashed while cleaning up after them. The fix makes the game skip just those few and carry on. The game starts normally and **keeps pre-building everything else**, so there's less stutter.

Drag in your game folder, click one button, and it's done, with a backup made first.

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

That's it. The app shows a checklist of everything it checked and changed. The first launch after fixing can take a little longer while the game pre-builds its shaders.

## Already using the original fix?

Drag your game folder in. The app recognises the original fix and shows **Update Fix**. Click it to switch to the new fix, or **Undo Fix** to go back to the untouched game.

## Undoing the fix

Drag the game folder in again and click **Undo Fix**. Your original file is put back, exactly as it was. This works for both the new fix and the original fix.

You can also use **Verify integrity of game files** in Steam, which restores the original file too.

## After a game update

A Steam update or file check may replace the game file and remove the fix. Just open the app again and click **Check again**, or drag the folder in again.

If the update changed the file to a new version, the app says the version isn't supported and doesn't touch it. This fix only applies to build 16690907.

## Is it safe?

The app is careful at every step:

- **Checks the version first.** It compares the file's fingerprint (SHA-256) with the exact version the fix was made for. Any other version is left alone.
- **Makes a backup** of the original before changing anything, and checks the backup is a perfect copy. Backups are kept in `~/Library/Application Support/NFS Unbound Fix/Backups`. The **Backups** button opens the folder.
- **Checks the exact bytes** it's about to change are the expected ones.
- **Can always undo.** It can rebuild the untouched original from a fixed file and check it against the original's fingerprint, so undoing works even without the backup.
- **Checks the result** before saving, saves in a way that can't leave a half-written file, then checks the saved file again. If anything doesn't match, it puts the original back.
- **Doesn't run while the game is open.**

It never touches anything else, and it contains no game code.

## What exactly it changes

For anyone who wants the details. All changes are in `Engine.Render.Core2.PlatformPcDx12.dll`:

| | |
| --- | --- |
| Original SHA-256 | `ee3a654be58be406eda32aeadad99ad60894403e374a2d3b847a20008cd30c62` |
| Fixed SHA-256 | `496deaa8f65df105528cfd85e68b3521b11809d208da1724d07fd46494ef4b1f` |

1. **Pre-build cleanup** (`0x43AE0`): skip empty root-signature entries instead of crashing on them.
2. **Graphics pre-build** (`0x433F4`): if a pipeline's root signature couldn't be created, mark that pipeline as failed. The game then drops it from the saved list and builds it normally when it's first needed.
3. **Compute pre-build** (`0x437D9`): the same check for compute pipelines.
4. The two checks live in unused space at the end of the code section (`0x210190`, `0x2101B0`), which is declared as code in the file header (`0x258`).

The exact bytes are listed in [`Patcher.swift`](Sources/NFSUnboundFixKit/Patcher.swift).

The original fix, which the app recognises and can update or undo, changes `44 38 AB C0 01 00 00` at `0x1AB423` to `80 A3 C0 01 00 00 00` (fixed SHA-256 `9dc33b2edebca402c48c53f32cce474aafd5d640e5754275484deaced66134aa`).

## Credits

The new fix builds on the original fix that other people found and shared:

- **Ariel O**, for the tip in the [CodeWeavers Compatibility Database](https://www.codeweavers.com/compatibility) that got Unbound running in CrossOver.
- **[u/ales_sandr](https://www.reddit.com/user/ales_sandr/)**, for the Reddit post that spread the fix.

Thank you both. Without their work there'd be nothing to improve on.

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
