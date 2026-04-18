#!/usr/bin/env bash
# scroll-scrub-starter / build.sh
# Turn a video into a scroll-scrubbed canvas image-sequence site.
#
# Usage:
#   ./build.sh <video-file> <project-name> [options]
#
# Options:
#   --template graph-paper | minimal | blueprint  (default: graph-paper)
#   --transparent             Chroma-key near-white to alpha, output WebP (needs cwebp)
#   --fps <N>                 Frames per second to extract (default: 24)
#   --width <N>               Pixel width to scale to (default: 1280)
#   --chroma-color 0xHEXHEX   For --transparent, color to key out (default: near-white)
#   --outdir <path>           Output folder (default: ./<project-name>)
#
# Output: a folder ready to deploy (e.g. via `vercel --yes` or `here-now`).

set -e

VIDEO=""
NAME=""
TEMPLATE="graph-paper"
TRANSPARENT=0
FPS=24
WIDTH=1280
OUTDIR=""
CHROMA_KEY_COLOR="0xfefefe"
CHROMA_KEY_SIMILARITY="0.25"
CHROMA_KEY_BLEND="0.10"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --template) TEMPLATE="$2"; shift 2 ;;
    --transparent) TRANSPARENT=1; shift ;;
    --fps) FPS="$2"; shift 2 ;;
    --width) WIDTH="$2"; shift 2 ;;
    --chroma-color) CHROMA_KEY_COLOR="$2"; shift 2 ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    *)
      if [[ -z "$VIDEO" ]]; then VIDEO="$1"
      elif [[ -z "$NAME" ]]; then NAME="$1"
      else echo "unknown arg: $1"; exit 1
      fi
      shift ;;
  esac
done

if [[ -z "$VIDEO" || -z "$NAME" ]]; then
  cat <<USAGE
usage: ./build.sh <video-file> <project-name> [options]

options:
  --template graph-paper | minimal | blueprint   (default: graph-paper)
  --transparent                                  chroma-key white to alpha (needs cwebp)
  --fps <N>                                      extraction fps (default: 24)
  --width <N>                                    scale width in px (default: 1280)
  --outdir <path>                                output folder (default: ./<project-name>)

examples:
  ./build.sh ~/Downloads/clip.mp4 my-site
  ./build.sh ~/Downloads/clip.mp4 my-site --template blueprint --transparent
USAGE
  exit 1
fi

if [[ ! -f "$VIDEO" ]]; then
  echo "video not found: $VIDEO"
  exit 1
fi

command -v ffmpeg >/dev/null || { echo "ffmpeg required (brew install ffmpeg)"; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe required (comes with ffmpeg)"; exit 1; }
if [[ "$TRANSPARENT" == "1" ]]; then
  command -v cwebp >/dev/null || { echo "cwebp required for --transparent (brew install webp)"; exit 1; }
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_PATH="$SCRIPT_DIR/templates/${TEMPLATE}.html"
if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "template not found: $TEMPLATE_PATH"
  echo "available templates:"
  ls "$SCRIPT_DIR/templates/" | sed 's/\.html$//'
  exit 1
fi

OUT="${OUTDIR:-./$NAME}"
mkdir -p "$OUT/frames"

echo "[1/4] probing video..."
W_SRC=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$VIDEO")
H_SRC=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$VIDEO")
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO" 2>/dev/null | cut -d. -f1)
echo "  source: ${W_SRC}x${H_SRC}, ${DUR}s"

# Orientation
if [[ "$W_SRC" -gt "$H_SRC" ]]; then
  ORIENT="landscape"
  SCALE="scale=${WIDTH}:-2:flags=lanczos"
elif [[ "$W_SRC" -lt "$H_SRC" ]]; then
  ORIENT="portrait"
  # For vertical, scale height up to WIDTH*2 (or use width as target height)
  SCALE="scale=-2:${WIDTH}:flags=lanczos"
else
  ORIENT="square"
  SCALE="scale=${WIDTH}:${WIDTH}:flags=lanczos"
fi

# WRAP_CSS: width clamped to min(70vw, 80vh-equivalent for aspect), + aspect-ratio
# Example for 16:9: width: min(70vw, calc(80vh * 16 / 9)); aspect-ratio: 16 / 9;
# Bash doesn't do floats well, so send integer ratio.
WRAP_CSS="width: min(70vw, calc(80vh * ${W_SRC} / ${H_SRC})); max-height: 80vh; aspect-ratio: ${W_SRC} / ${H_SRC};"

echo "[2/4] extracting frames at ${FPS}fps, ${ORIENT}..."
if [[ "$TRANSPARENT" == "1" ]]; then
  TMPDIR="$(mktemp -d)"
  ffmpeg -v error -y -i "$VIDEO" \
    -vf "fps=${FPS},${SCALE},colorkey=${CHROMA_KEY_COLOR}:${CHROMA_KEY_SIMILARITY}:${CHROMA_KEY_BLEND},format=rgba" \
    "$TMPDIR/f_%04d.png"
  echo "[3/4] converting to WebP with alpha..."
  EXT="webp"
  for f in "$TMPDIR"/*.png; do
    nm=$(basename "$f" .png)
    cwebp -q 72 -alpha_q 82 "$f" -o "$OUT/frames/${nm}.webp" > /dev/null 2>&1
  done
  rm -rf "$TMPDIR"
else
  ffmpeg -v error -y -i "$VIDEO" -vf "fps=${FPS},${SCALE}" -q:v 5 "$OUT/frames/f_%04d.jpg"
  EXT="jpg"
  echo "[3/4] (skipping webp transparency step)"
fi

FRAME_COUNT=$(ls "$OUT/frames" | wc -l | tr -d ' ')
SIZE=$(du -sh "$OUT/frames" | awk '{print $1}')
echo "  → ${FRAME_COUNT} frames extracted (${SIZE})"

echo "[4/4] writing index.html..."
# escape slashes in WRAP_CSS for sed (use | delimiter, escape | and &)
WRAP_CSS_ESC=$(echo "$WRAP_CSS" | sed -e 's/[|&]/\\&/g')
sed \
  -e "s|{{FRAME_COUNT}}|${FRAME_COUNT}|g" \
  -e "s|{{FRAME_EXT}}|${EXT}|g" \
  -e "s|{{WRAP_CSS}}|${WRAP_CSS_ESC}|g" \
  -e "s|{{NAME}}|${NAME}|g" \
  "$TEMPLATE_PATH" > "$OUT/index.html"

echo ""
echo "✓ done → $OUT"
echo "  template: $TEMPLATE / orientation: $ORIENT / $FRAME_COUNT frames / $SIZE"
echo ""
echo "next steps:"
echo "  cd $OUT"
echo "  python3 -m http.server 8000    # preview at http://localhost:8000"
echo "  vercel --yes                    # deploy to Vercel"
