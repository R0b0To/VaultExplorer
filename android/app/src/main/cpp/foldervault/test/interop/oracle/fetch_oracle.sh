#!/bin/bash
# Downloads Cryptomator CLI 0.6.2 (it bundles cryptofs 2.8.0 + cryptolib 2.2.0, the reference implementation)
# and copies just the library jars into ./lib. The CLI's own jar is left out on purpose: it targets Java 24 and
# trips logback's service scan on older JDKs.
set -e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/cli.zip" https://github.com/cryptomator/cli/releases/download/0.6.2/cryptomator-cli-0.6.2-linux-x64.zip
unzip -q "$TMP/cli.zip" -d "$TMP/cli"
MODS="$(dirname "$(find "$TMP/cli" -name 'cryptofs-*.jar' | head -1)")"
mkdir -p "$HERE/lib"; rm -f "$HERE/lib"/*.jar
for j in cryptofs cryptolib dagger javax.inject guava failureaccess caffeine checker-qual error_prone java-jwt \
         jackson-annotations jackson-core jackson-databind siv-mode jsr305 logback slf4j gson; do
  cp "$MODS"/$j*.jar "$HERE/lib/" 2>/dev/null || true
done
ls "$HERE/lib"
