#!/usr/bin/env sh
# Adds (or with --remove, removes) an application-menu entry for this extracted copy of VaultExplorer.
set -eu
APP_ID=com.aeidolon.vaultexplorer
DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${XDG_DATA_HOME:-$HOME/.local/share}/applications/$APP_ID.desktop"

if [ "${1:-}" = "--remove" ]; then
  rm -f "$TARGET"
  echo "Removed $TARGET"
  exit 0
fi

mkdir -p "$(dirname "$TARGET")"
cat > "$TARGET" <<DESKTOP
[Desktop Entry]
Type=Application
Name=VaultExplorer
GenericName=Encrypted Container Explorer
Comment=Open, browse and manage VeraCrypt, LUKS, BitLocker and other encrypted containers
Exec="$DIR/vaultexplorer"
Icon=$DIR/data/app_icon.png
Path=$DIR
Terminal=false
Categories=Utility;Security;
Keywords=VeraCrypt;LUKS;BitLocker;Cryptomator;encryption;vault;container;
StartupNotify=true
StartupWMClass=$APP_ID
DESKTOP
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$(dirname "$TARGET")" 2>/dev/null || true
fi
echo "Added $TARGET"
echo "If you move this folder, run this script again."
