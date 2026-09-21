# Privacy Policy for Vault Explorer

**Last updated: September 2026**

Vault Explorer ("the app") is developed and maintained by the project
contributors listed at https://github.com/R0b0To/VaultExplorer. This policy
explains what the app does and does not do with your data.

## Summary

Vault Explorer does not collect, transmit, or share any personal data,
because it has no way to. The release build of the app does not request
or hold the `INTERNET` permission on Android (nor `ACCESS_NETWORK_STATE`),
so it cannot make network requests of any kind, to us or to anyone else.
There is no account system, no analytics SDK, no crash reporting service,
no telemetry, and no advertising.

The one thing to keep in mind is that *you* can ask the app to hand files
to other apps (open, share, export, sync, cloud bridges). What those apps
do with the files is up to them; see
[When data leaves the app at your request](#when-data-leaves-the-app-at-your-request).

## What the app accesses on your device, and why

| Permission | Why it's requested | Where the data goes |
|---|---|---|
| Storage access (`MANAGE_EXTERNAL_STORAGE`, and `READ_`/`WRITE_EXTERNAL_STORAGE` on older Android versions; otherwise the system file picker / SAF) | To let you choose and open encrypted containers, vaults, and drives stored on your device. "All files access" is optional for that: without it the app uses Android's system file picker, which is slower for large folder vaults. A few features do need it, such as the Mask Mode file manager, joining split containers, and syncing with plain device folders. | Nowhere. Files are read and written locally to perform decryption/encryption. Nothing is uploaded. |
| Camera / microphone (`CAMERA`, `RECORD_AUDIO`) | Only used if you choose to capture a photo or record video directly into an unlocked vault: from the in-app camera, from the optional Quick Capture tile/shortcut, or from an automation you have separately enabled for that vault. | The captured photo/video is encrypted and written straight into your vault. It is never transmitted, and no unencrypted copy is written to shared storage. |
| Biometric / fingerprint (`USE_BIOMETRIC`, `USE_FINGERPRINT`) | Only used if you enable biometric unlock as an alternative to your master password. | Handled entirely by the Android Keystore/BiometricPrompt APIs. The app never sees your raw biometric data — Android just tells it "matched" or "not matched." |
| USB host access | To let you connect and mount USB mass-storage drives containing encrypted volumes. Android asks you to approve each device. | Same as storage access above: local only. |
| Foreground service, notifications, wake lock (`FOREGROUND_SERVICE*`, `POST_NOTIFICATIONS`, `WAKE_LOCK`) | To keep unlocked vaults mounted while the app is in the background, to keep camera recording running with the screen off, and to show progress for long file operations. Android shows a notification while these run. | Nowhere. These only keep the app running locally. |
| Run at startup (`RECEIVE_BOOT_COMPLETED`) | Only to carry out the optional "run a panic action on next boot" trigger, if you have armed it. | Nowhere. |
| Install unknown apps (`REQUEST_INSTALL_PACKAGES`) | Only when you tap to install an APK stored in a vault. Android additionally requires you to allow this per app in system settings. | The APK is streamed to Android's system package installer; the app does not write a decrypted copy of its own. |
| Delete packages (`REQUEST_DELETE_PACKAGES`) | Only used by the "Nuclear Wipe" panic tier to show Android's uninstall prompt (see [Emergency purge and duress](#emergency-purge-and-duress)). | Nowhere. |

The app does **not** request the `INTERNET` permission, location, contacts,
calendar, phone, SMS, or account access, and does not read the Android
advertising ID.

## Data stored on your device

The app has no database and no server. What it keeps locally, in its own
private storage:

- **App settings and your container list**: the locations of containers and
  vaults you have added, per-container options such as bookmarks, and your
  file manager layout.
- **A hash of your master lock credential** (password, PIN, or pattern), if
  you set one. The credential itself is not stored.
- **Secrets you choose to remember**: remembered container passwords,
  PIN/pattern hashes, and cached derived keys are encrypted with AES-GCM
  using a key held in the Android Keystore (hardware-backed where the device
  supports it). This is optional, and you can clear it at any time.
- **Automation credentials**, if you enable the Tasker/MacroDroid
  automation feature: the API token, plus any vault password, keyfile paths,
  or PIM you save so that automation can unlock that vault unattended. These
  are encrypted with their own Keystore key.
- **Thumbnail cache**: thumbnails of files in your vaults are cached in the
  app's private cache folder, encrypted with a key held in the Keystore.
- **Working copies of folder vaults**: while a Cryptomator, gocryptfs, or CryFS
  vault opened through Android's system file picker is unlocked, the app may
  keep working copies of the vault's files, still encrypted, in its private
  storage. They are deleted when the vault locks.
- **Auto-sync rules**: kept inside the vault they belong to, encrypted like
  any other file in it. Only the local folder you chose as the sync target
  is remembered on the device.

Android's backup is turned off for the app (`allowBackup` is `false`), so
none of this is copied to Google's backup service.

**Settings export.** If you use Settings → Export settings, the app writes a
plain JSON file to a location you pick. It contains app preferences and your
file manager layout only. It does not contain passwords, keys, your master
lock credential, or your container list.

**Debug logging.** Off by default. If you turn it on, diagnostic messages go
to Android's on-device system log, which the in-app Logcat viewer can display
and which you can save to a file you choose. Nothing is sent anywhere, but
check any log before posting it publicly.

## Data stored inside your vaults

Passwords, notes, cards, and other items you choose to store inside an
encrypted vault are encrypted with keys derived from your own master
password/keyfile and never leave your device. The developers have no way
to access, recover, or reset this data — there is no server-side account
or backup service. If you lose your password and don't have a recovery
keyfile, the data is unrecoverable, by design.

Decryption and re-encryption happen in memory wherever possible. A few
operations need a real file on disk to work — for example recording video,
exporting or extracting files, working with archives, the file
encrypt/decrypt tool, and generating thumbnails for very large files. For
those, the app briefly keeps a plaintext scratch copy in its own private
cache folder, overwrites it with zeros, and deletes it when the operation
finishes; anything a crash leaves behind is wiped the next time the app
starts. This is best effort: on flash storage, overwriting a file cannot
guarantee that no trace of it remains. The scratch files live in the app's
private storage, which other apps cannot read on a non-rooted device.

## When data leaves the app at your request

The app itself makes no network requests, but several features exist to
move files between a vault and something else. In each case you start the
action, and the files involved are then outside the app's control:

- **Open in another app / share.** When you open a file with another app,
  share it from the file manager, or expose an unlocked vault (or one
  subfolder) so other apps can browse it, the receiving app gets the
  *decrypted* contents. That app's own privacy practices apply to what it
  does next, including caching or uploading.
- **Export, extract, and sync.** Files you export, extract, or copy out of
  a vault (including via Vault Sync and auto-sync) are stored unencrypted
  at the destination you chose; Vault Sync shows a warning about this. If
  that destination is a cloud-synced folder, the sync client is what uploads
  them.
- **Cloud and bridge apps.** If you open a container that lives on Google
  Drive, pCloud, or through a bridge app such as RSAF or Round-Sync, that
  other app handles all network transfer under its own privacy policy. Vault
  Explorer only receives a local file handle, and the container data it
  reads there is still encrypted.
- **Automation.** The Tasker/MacroDroid automation feature is off by
  default. Each vault has to opt in to a permission tier, calls require an
  API token, and camera capture needs its own separate opt-in on top of
  that. Whatever automation app you connect receives the results and files
  you configure it to request.
- **Links and issue reports.** Tapping links in the About screen (source
  code, releases, donations, contributors) hands the address to your
  default browser. "Report an issue" opens a GitHub issue form in the
  browser, prefilled with the app version and Android version as part of
  the page address. Nothing is submitted unless you submit it, but opening
  the page does send that address to GitHub, like any link would. The
  browser's and GitHub's own policies apply from that point.
- **Share app.** The "share app" button only copies a link to your
  clipboard.

## Emergency purge and duress

The optional Emergency Panic features can be triggered from inside the app,
a Quick Settings tile, a paired PanicKit app such as Ripple or Wasted, an
automation broadcast, an armed reboot trigger, or a duress credential entered
on the lock screen. They only delete data; they do not send anything
anywhere:

- **Session Purge** locks every open vault, wipes key material from memory,
  and clears remembered vault credentials.
- **Credential Purge** additionally resets the master lock and app settings,
  clears the vault list, and removes the app's Keystore keys.
- **Nuclear Wipe** additionally shreds the app's own internal storage and
  asks Android to uninstall the app.

Session Purge and Credential Purge never touch your container or vault
files. Nuclear Wipe erases only the app's own storage, but that includes the
app's private folders (its internal storage and its app-specific folder under
`Android/data`). If you keep a container inside one of those, it is erased
too. Containers in shared storage, on USB drives, or on cloud providers are
not touched.

## Third parties

The app bundles some open-source components (listed in `NOTICE.md` in the
source repository) for cryptography, filesystem access, archive handling,
and in-app media viewing. None of them phone home; the whole point of the
"zero Internet permission" build is that none of them can.

## Verifying this yourself

The source code is public. Release builds are reproducible
(`scripts/reproducible_build.sh` and `scripts/compare_builds.sh` in the
repository), so you can confirm that the APK you install matches the source.
You can also dump an installed release APK's permission list with standard
Android tooling (for example `aapt2 dump permissions app-release.apk`) and
confirm that `INTERNET` is not there. Debug and profile
builds used by developers do include it, for Flutter's development tooling;
release builds do not.

## Changes to this policy

If this policy changes, the updated version will be posted at this same
location in the source repository, with a new "Last updated" date above.

## Contact

Questions about this policy or the app's data handling can be filed as an
issue at https://github.com/R0b0To/VaultExplorer/issues.
