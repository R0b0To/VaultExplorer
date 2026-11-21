#!/usr/bin/env bash
# Packages a Flutter Linux release bundle as:
#   * a portable .tar.gz  (extract anywhere, run ./vaultexplorer)
#   * an installable .deb (installs to /opt/vaultexplorer, adds /usr/bin/vaultexplorer, a menu entry and icons)
#
#   packaging/linux/build_packages.sh <bundle-dir> <version> <out-dir> [build-number]
#
#   <bundle-dir>   build/linux/x64/release/bundle (contains vaultexplorer, lib/, data/)
#   <version>      e.g. 1.66.0 (the part of pubspec.yaml's version before the "+")
#   <out-dir>      where the finished packages are written
#   [build-number] optional, e.g. 67; becomes part of the .deb version (1.66.0+67)
#
# Needs: bash, tar, dpkg-deb and dpkg-shlibdeps (package dpkg-dev). Run on the same distro release the
# bundle was built on: the .deb's library dependencies are computed from the bundle's ELF files.
set -euo pipefail

if [[ $# -lt 3 ]]; then
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
  exit 2
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE="$(cd "$1" && pwd)"
VERSION="$2"
mkdir -p "$3"
OUT="$(cd "$3" && pwd)"
BUILD_NUMBER="${4:-}"

APP_ID="com.aeidolon.vaultexplorer"
BIN="vaultexplorer"
HOMEPAGE="https://github.com/R0b0To/VaultExplorer"

[[ -x "$BUNDLE/$BIN" ]] || { echo "error: $BUNDLE/$BIN not found or not executable" >&2; exit 1; }
[[ -f "$BUNDLE/data/app_icon.png" ]] || { echo "error: $BUNDLE/data/app_icon.png missing; was linux/CMakeLists.txt's icon install step skipped?" >&2; exit 1; }
[[ -f "$BUNDLE/lib/libvaultexplorer_engine.so" ]] || { echo "error: $BUNDLE/lib/libvaultexplorer_engine.so missing; build the engine first (scripts/build_desktop_engine.sh)" >&2; exit 1; }

DEB_ARCH="$(dpkg --print-architecture)"
case "$DEB_ARCH" in
  amd64) ARCH_TAG="x64" ;;
  *)     ARCH_TAG="$DEB_ARCH" ;;
esac
BASENAME="VaultExplorer-v${VERSION}-linux-${ARCH_TAG}"
DEB_VERSION="$VERSION${BUILD_NUMBER:+"+$BUILD_NUMBER"}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------- portable .tar.gz
echo "==> portable tarball"
PORTABLE="$WORK/portable/$BASENAME"
mkdir -p "$PORTABLE"
cp -a "$BUNDLE/." "$PORTABLE/"
install -m 0644 "$HERE/README-portable.txt" "$PORTABLE/README.txt"
install -m 0755 "$HERE/add-to-app-menu.sh" "$PORTABLE/add-to-app-menu.sh"
tar --sort=name --owner=0 --group=0 --numeric-owner -C "$WORK/portable" -czf "$OUT/$BASENAME.tar.gz" "$BASENAME"

# ---------------------------------------------------------------- .deb
echo "==> .deb"
ROOT="$WORK/deb"
mkdir -p "$ROOT/opt/$BIN" "$ROOT/usr/bin" "$ROOT/usr/share/applications" "$ROOT/usr/share/doc/$BIN" "$ROOT/DEBIAN"
cp -a "$BUNDLE/." "$ROOT/opt/$BIN/"
ln -s "/opt/$BIN/$BIN" "$ROOT/usr/bin/$BIN"
install -m 0644 "$HERE/$APP_ID.desktop" "$ROOT/usr/share/applications/$APP_ID.desktop"
cp -a "$HERE/icons/." "$ROOT/usr/share/icons/"
cat > "$ROOT/usr/share/doc/$BIN/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: VaultExplorer
Source: $HOMEPAGE

Files: *
Copyright: the VaultExplorer authors
License: GPL-3+
 This program is free software: you can redistribute it and/or modify it under the terms of the GNU
 General Public License as published by the Free Software Foundation, either version 3 of the License,
 or (at your option) any later version.
 .
 On Debian systems, the full text of the GNU General Public License version 3 can be found in
 /usr/share/common-licenses/GPL-3. Third-party components are listed in NOTICE.md in the source tree.
EOF

# Normalise permissions: directories 755, regular files 644, anything that was executable stays 755.
find "$ROOT" -type d -exec chmod 0755 {} +
find "$ROOT" -type f ! -perm /111 -exec chmod 0644 {} +
find "$ROOT" -type f -perm /111 -exec chmod 0755 {} +

# Library dependencies, computed from the ELF files exactly as Debian packaging does. The bundle's own
# libraries (lib/) are on the search path so they are not reported as missing.
SHLIBS="$WORK/shlibs"
mkdir -p "$SHLIBS/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "$BIN" "$BIN" > "$SHLIBS/debian/control"
ELF_ARGS=("-e$BUNDLE/$BIN")
while IFS= read -r -d '' lib; do ELF_ARGS+=("-e$lib"); done < <(find "$BUNDLE/lib" -maxdepth 1 -type f -name '*.so*' -print0)
SHLIBS_DEPENDS="$(cd "$SHLIBS" && dpkg-shlibdeps -O -l"$BUNDLE/lib" "${ELF_ARGS[@]}" 2>"$WORK/shlibdeps.log" | sed -n 's/^shlibs:Depends=//p')" || {
  cat "$WORK/shlibdeps.log" >&2; echo "error: dpkg-shlibdeps failed" >&2; exit 1; }
[[ -n "$SHLIBS_DEPENDS" ]] || { cat "$WORK/shlibdeps.log" >&2; echo "error: dpkg-shlibdeps produced no dependencies" >&2; exit 1; }
echo "    Depends: $SHLIBS_DEPENDS"

INSTALLED_SIZE="$(du -sk --apparent-size "$ROOT" | cut -f1)"
cat > "$ROOT/DEBIAN/control" <<EOF
Package: $BIN
Version: $DEB_VERSION
Section: utils
Priority: optional
Architecture: $DEB_ARCH
Maintainer: R0b0To <R0b0To@users.noreply.github.com>
Installed-Size: $INSTALLED_SIZE
Depends: $SHLIBS_DEPENDS
Recommends: libmpv2 | libmpv1, fuse3, gnome-keyring | kwalletd5 | kwalletd6
Homepage: $HOMEPAGE
Description: Encrypted container explorer (VeraCrypt, LUKS, BitLocker and more)
 VaultExplorer opens and manages VeraCrypt, LUKS, BitLocker, VHD/VHDX, Cryptomator, gocryptfs and
 CryFS volumes. A native engine decrypts in memory where possible and the app never uses the network.
 .
 Recommended: libmpv for video and audio playback, fuse3 to mount containers in the file manager, and a
 Secret Service keyring (GNOME Keyring or KWallet), where saved vaults and credentials are stored.
EOF

dpkg-deb --root-owner-group -Zxz --build "$ROOT" "$OUT/$BASENAME.deb" >/dev/null

echo "==> done"
ls -lh "$OUT/$BASENAME.tar.gz" "$OUT/$BASENAME.deb"
