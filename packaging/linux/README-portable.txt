VaultExplorer (portable build)
==============================

Extract this folder anywhere and run ./vaultexplorer. There is no installer and nothing is written
outside your user profile.

System packages it relies on (most desktops already have the first two):

  * GTK 3 and libsecret, plus a Secret Service keyring (GNOME Keyring or KWallet).
    Saved vaults and credentials are stored in the keyring.
  * libmpv  - video and audio playback (optional; without it the viewer reports that libmpv is missing)
  * fuse3   - mounting containers in your file manager (optional)

  Debian / Ubuntu / Mint / KDE neon:
      sudo apt install libgtk-3-0 libsecret-1-0 gnome-keyring libmpv2 fuse3
  Other distributions: install the equivalent packages.

Launcher entry with the VaultExplorer icon (optional):
      ./add-to-app-menu.sh            add to your application menu
      ./add-to-app-menu.sh --remove   take it out again

Settings and saved credentials live in your user profile (XDG data directory and the keyring), not in
this folder, so moving or deleting the folder does not touch them.
