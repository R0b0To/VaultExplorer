#!/bin/sh
# Runs the OFFICIAL CommonMark runner (spec_tests.py, spec 0.31.2) against the
# viewer parser, through md2html.dart.
#
#   sh tool/commonmark_spec/run_official.sh            (from the repo root)
#   sh tool/commonmark_spec/run_official.sh -n 42      (single example, with diff)
#   sh tool/commonmark_spec/run_official.sh -P "Links" (sections matching a regex)
#
# Needs dart (the Flutter SDK's is fine), python3 and curl (first run only).
# Expected: "652 passed, 0 failed" and exit code 0. The adapter (md2html.dart)
# runs the parser with MdParseOptions.commonMark, the strict profile; the
# viewer itself uses MdParseOptions.app (HTML shown as text, bare URLs linked,
# comments hidden, ...), which is covered by the unit tests.
set -eu
VER=0.31.2
OUT=build/commonmark/official
BASE=https://raw.githubusercontent.com/commonmark/commonmark-spec/$VER
mkdir -p "$OUT"
for f in spec.txt test/spec_tests.py test/cmark.py test/normalize.py; do
  [ -f "$OUT/$(basename "$f")" ] || curl -sSfL "$BASE/$f" -o "$OUT/$(basename "$f")"
done
# PACKAGES=/path/to/package_config.json is only needed outside a pub-resolved checkout.
dart compile kernel ${PACKAGES:+--packages="$PACKAGES"} tool/commonmark_spec/md2html.dart -o "$OUT/md2html.dill" >/dev/null
printf '#!/bin/sh\nexec %s %s/md2html.dill\n' "$(command -v dart)" "$(pwd)/$OUT" > "$OUT/md2html.sh"
chmod +x "$OUT/md2html.sh"
cd "$OUT"
python3 spec_tests.py -p "$(pwd)/md2html.sh" -s spec.txt "$@"
