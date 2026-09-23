# Password Manager Interchange

The Item Vault can exchange its entries (passwords, payment cards, identities,
secure notes, bank accounts, and software licenses) with other password
managers. Open **Tools -> Import / Export Passwords**.

Everything runs on-device. Like the rest of VaultExplorer, this feature never
makes a network request -- reading, decoding, encoding, and writing all
happen locally, using the same file pickers as the rest of the app.

---

## Exporting

1. Pick a vault folder to export from (its Item Vault entries, optionally
   including subfolders).
2. Pick a format.
3. For KDBX, set a master password for the new file.
4. VaultExplorer builds the file in memory, then you pick where to save it
   on device storage (or share it from there, same as any other file).

## Importing

1. Pick a file (KDBX, Bitwarden JSON, or CSV -- VaultExplorer guesses the
   format from the file's content/name, but you can override it).
2. For KDBX, enter its master password.
3. Review the decoded items -- everything is pre-selected; uncheck anything
   you don't want. Rows/entries the codec couldn't confidently read are
   listed as warnings rather than silently dropped or silently guessed.
4. Pick a destination vault folder and confirm.

Nothing is written into a vault until you confirm the import; decoding a
file is always a preview first.

---

## Format support

| Format | Import | Export | Encrypted | Fidelity |
|---|:-:|:-:|:-:|---|
| **KeePass (.kdbx)** | ✓ | ✓ | Yes (its own master password) | Full -- every item type round-trips losslessly, and the file is directly usable in real KeePass/KeePassXC/Strongbox, not just in VaultExplorer |
| **Bitwarden (.json)** | ✓ | ✓ | No (must be an *unencrypted* Bitwarden export) | Full -- Bitwarden's `fields[]` array carries anything without a native Bitwarden equivalent |
| **CSV** | ✓ | ✓ | No | Best-effort on import (see below); the export schema round-trips through VaultExplorer losslessly but a plain CSV can't hold as much as the other two formats |

CSV import auto-detects columns from VaultExplorer's own export, **Bitwarden**,
**LastPass**, **Chrome**, **1Password**, **Dashlane**, **NordPass**, and
**Apple Passwords/iCloud Keychain** exports, by matching the header row
against each format's known column names. It's a heuristic, not a strict
per-vendor parser -- that's why the import screen always shows a preview
before writing anything.

Because a CSV or an unencrypted Bitwarden JSON export is plaintext on disk,
delete it from device storage once you're done importing or sharing it.

---

## KDBX layout

Exporting creates one top-level group per item type that actually has
entries -- `Logins`, `Payment Cards`, `Identities`, `Secure Notes`,
`Bank Accounts`, `Software Licenses` -- with each entry's vault subfolder
recreated as nested groups underneath. This keeps the file genuinely useful
if you open it in real KeePass, not just round-trippable through
VaultExplorer.

Within an entry:

- `Title`, `UserName`, `Password`, `URL`, and `Notes` are used wherever a
  VaultExplorer field means the same thing, so they show up normally in any
  KeePass-compatible app.
- A TOTP secret is written to a custom field named `otp` (protected) -- the
  same convention KeePassXC, Strongbox, and KeeWeb use to show a live code.
- Every other field is written as a custom string field named after
  VaultExplorer's own internal field key (e.g. `account_number`, `cvv`,
  `passport_no`, `iban`). This is what makes round-tripping through
  VaultExplorer exact, and it's still self-explanatory if you're looking at
  the file in another KeePass client.

Importing a `.kdbx` file *not* created by VaultExplorer (no groups matching
the names above) falls back to a simple rule: an entry with a non-empty
password or username becomes a `password` item; everything else becomes a
`secureNote`, with its standard fields folded into the note body so nothing
is dropped.

---

## Field mapping

Fields not listed for a format are carried as that format's generic custom
field mechanism (a KDBX custom string field, a Bitwarden `fields[]` entry, or
folded into a note) rather than being dropped.

| Item type | KDBX | Bitwarden JSON |
|---|---|---|
| **Password** | `UserName` / `Password` / `URL` / `Notes` standard fields; TOTP as custom field `otp` | `login.username` / `login.password` / `login.uris[0].uri` / `login.totp` / `notes` |
| **Payment card** | Custom fields `cardholder`, `number`, `expiry`, `cvv`, `pin`, `bank`; `Notes` | `card.cardholderName` / `card.number` / `card.expMonth`+`expYear` / `card.code`; `pin`/`bank` as Bitwarden custom fields |
| **Identity** | Custom fields per key (`full_name`, `national_id`, `passport_no`, `drivers_license`, `address`, ...); `UserName` = email, `Notes` | `identity.firstName`/`lastName` (split from `full_name`), `.email`, `.phone`, `.ssn` (= `national_id`), `.licenseNumber`, `.passportNumber`, `.address1`; remaining fields as Bitwarden custom fields |
| **Secure note** | `Notes` = `content` | `notes` = `content` |
| **Bank account** | Custom fields per key; `Notes` | No native Bitwarden type -- written as a secure note with every field individually preserved in `fields[]` |
| **Software license** | Custom fields per key; `UserName` = registration email, `URL` = download URL, `Notes` | Same as bank account: secure note with `fields[]` |

CSV only really has room for a login-shaped row (title/username/password/
url/totp/notes); everything else for the other item types is packed into a
JSON `extra` column on VaultExplorer's own export, which only this app's own
CSV import recognizes -- a CSV round-tripped through, say, a spreadsheet
editor will keep that column as opaque text.
