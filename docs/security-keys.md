# Hardware security keys (FIDO2 / YubiKey)

VaultExplorer unlocks two vault formats with a FIDO2 security key, using the
**same on-disk schemes as the desktop tools**, so a vault enrolled on a
computer opens on the phone and the other way round. Nothing here is a
VaultExplorer-only format.

| Format | Scheme | Desktop tool | Unlock | Create/enroll |
| --- | --- | --- | --- | --- |
| gocryptfs | `FIDO2` feature flag + `FIDO2` section in `gocryptfs.conf` | `gocryptfs -init -fido2` | yes | yes (new vaults) |
| LUKS2 | `systemd-fido2` token in the LUKS2 JSON metadata | `systemd-cryptenroll --fido2-device=` | yes | no (enroll on desktop) |

Cryptomator, CryFS, VeraCrypt and BitLocker have no key scheme shared with other
tools, so they are intentionally not supported.

## How the secret is derived

Both schemes use the CTAP2 **hmac-secret** extension. The salt stored in the
vault is sent to the key *unchanged* (no WebAuthn "PRF" hashing), which is why
`Fido2HmacSecret` talks CTAP2 directly instead of using yubikit's extension
helper.

* **gocryptfs**: relying party `gocryptfs`; the 32-byte output is the vault
  "password", fed to scrypt as raw bytes (never through a string/UTF-8 step).
* **LUKS2**: relying party from the token (`io.systemd.cryptsetup` by default);
  the LUKS passphrase is the standard padded base64 text of the 32-byte output.

## PIN and user verification

A key derives a *different* hmac-secret depending on whether the assertion was
user-verified. The PIN is therefore sent only when the vault says so
(`pin=true` in gocryptfs `AssertOptions`, `fido2-clientPin-required` in the
LUKS2 token), or when the key enforces always-UV. Vaults that require built-in
user verification without a PIN (e.g. a fingerprint-only policy) are reported
as unsupported.

## Transports

NFC (hold the key against the phone) and USB. On NFC the key must stay in
place for the whole operation, so a PIN-protected vault asks for the PIN
*before* the key is presented.

## Limits

* Changing the credentials of a gocryptfs security-key vault is refused (same
  as upstream); there is no password to change.
* A security-key vault cannot be remembered, quick-unlocked or re-mounted
  automatically from saved credentials. It needs the key each time.
* Losing the key (and having no other enrolled key/passphrase) means losing
  the vault. LUKS2 can hold a recovery passphrase in another keyslot; gocryptfs
  cannot, so keep the master key from `gocryptfs-xray -dumpmasterkey` if you
  need a fallback.
