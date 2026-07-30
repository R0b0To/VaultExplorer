# Privacy Policy for Vault Explorer

**Last updated: July 2026**

Vault Explorer ("the app") is developed and maintained by the project
contributors listed at https://github.com/R0b0To/VaultExplorer. This policy
explains what the app does and does not do with your data.

## Summary

Vault Explorer does not collect, transmit, or share any personal data,
because it has no way to. The release build of the app does not request
or hold the `INTERNET` permission on Android, so it cannot make network
requests of any kind, to us or to anyone else. There is no account
system, no analytics SDK, no crash reporting service, and no advertising.

## What the app accesses on your device, and why

| Permission | Why it's requested | Where the data goes |
|---|---|---|
| Storage access (`MANAGE_EXTERNAL_STORAGE` / SAF document access) | To let you choose and open encrypted containers, vaults, and drives stored on your device or an attached USB drive. | Nowhere. Files are read and written locally, in memory, to perform decryption/encryption. Nothing is uploaded. |
| Camera / microphone | Only used if you choose to capture a photo or record video directly into an unlocked vault. | The captured photo/video is encrypted and written straight into your vault. It is never transmitted, and no unencrypted copy is written to shared storage. |
| Biometric / fingerprint | Only used if you enable biometric unlock as an alternative to your master password. | Handled entirely by the Android Keystore/BiometricPrompt APIs. The app never sees your raw biometric data — Android just tells it "matched" or "not matched." |
| USB host access | To let you connect and mount USB mass-storage drives containing encrypted volumes. | Same as storage access above: local only. |

## Data stored inside your vaults

Passwords, notes, cards, and other items you choose to store inside an
encrypted vault are encrypted with keys derived from your own master
password/keyfile and never leave your device. The developers have no way
to access, recover, or reset this data — there is no server-side account
or backup service. If you lose your password and don't have a recovery
keyfile, the data is unrecoverable, by design.

## Third parties

The app bundles some open-source components (listed in `NOTICE.md` in the
source repository) for cryptography, filesystem access, and in-app media
viewing. None of them phone home; the whole point of the "zero Internet
permission" build is that none of them can.

## Changes to this policy

If this policy changes, the updated version will be posted at this same
location in the source repository, with a new "Last updated" date above.

## Contact

Questions about this policy or the app's data handling can be filed as an
issue at https://github.com/R0b0To/VaultExplorer/issues.
