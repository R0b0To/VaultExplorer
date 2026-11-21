VaultExplorer (portable build)
==============================

Extract this folder anywhere (a USB stick works too) and run vaultexplorer.exe. There is no installer and
nothing is written to the registry. The Visual C++ runtime is included, so no extra downloads are needed.

Optional: to mount containers as a drive letter / folder in Windows Explorer, install WinFsp
(https://winfsp.dev). Without it VaultExplorer still opens and browses containers normally.

Where your data lives
---------------------
"Portable" means no installation is required. It does not move your settings: preferences and saved
vaults/credentials are stored in your Windows user profile, not in this folder. Moving or deleting this
folder does not touch them, and a second copy of the app on the same Windows account shares them.

Windows may show a SmartScreen warning the first time because the program is not code-signed
("More info" -> "Run anyway").
