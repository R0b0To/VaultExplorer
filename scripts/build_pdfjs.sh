set -euo pipefail
cd "$(dirname "$0")/.."   # repo root
PDFJS_TAG="v6.2.108"
PDFJS_REPO="https://github.com/mozilla/pdf.js.git"
OUT_DIR="android/app/src/main/assets/pdfjs"
SRC_DIR="${TMPDIR:-/tmp}/pdfjs-src-${PDFJS_TAG}"

if [ -f "$OUT_DIR/pdf.min.mjs" ] && [ -f "$OUT_DIR/pdf.worker.min.mjs" ]; then
  echo "pdf.js already built at $OUT_DIR, skipping (delete that dir to force a rebuild)."
  exit 0
fi

command -v node >/dev/null 2>&1 || { echo "error: node.js is required to build pdf.js from source (see README dev setup)" >&2; exit 1; }
command -v npm  >/dev/null 2>&1 || { echo "error: npm is required to build pdf.js from source" >&2; exit 1; }

if [ ! -d "$SRC_DIR" ]; then
  echo "Cloning pdf.js ${PDFJS_TAG}..."
  git clone --branch "$PDFJS_TAG" --depth 1 "$PDFJS_REPO" "$SRC_DIR"
fi

echo "Building pdf.js minified bundle (npm ci && npx gulp minified)..."
(cd "$SRC_DIR" && npm ci && npx gulp minified)

BUILT_DIR="$SRC_DIR/build/minified/build"
if [ ! -f "$BUILT_DIR/pdf.min.mjs" ] || [ ! -f "$BUILT_DIR/pdf.worker.min.mjs" ]; then
  echo "error: pdf.js build finished but expected output not found at $BUILT_DIR" >&2
  echo "       (upstream may have moved the minified gulp task's output path --" >&2
  echo "       check gulpfile.mjs at $PDFJS_TAG for the current MINIFIED_DIR layout)" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
cp "$BUILT_DIR/pdf.min.mjs" "$BUILT_DIR/pdf.worker.min.mjs" "$OUT_DIR/"
echo "pdf.js ${PDFJS_TAG} built and copied to $OUT_DIR"
