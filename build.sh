#!/usr/bin/env bash
# scroll-scrub-starter / build.sh
# Turn a video into a scroll-scrubbed canvas image-sequence site.
#
# Usage:
#   ./build.sh <video-file> <project-name> [--template minimal|blueprint] [--transparent]
#
# Examples:
#   ./build.sh ~/Downloads/clip.mp4 my-scroll-site
#   ./build.sh ~/Downloads/clip.mp4 my-site --template blueprint
#   ./build.sh ~/Downloads/clip.mp4 my-site --template blueprint --transparent
#
# Output: a folder ready to deploy (e.g. via `vercel --yes`).

set -e

VIDEO=""
NAME=""
TEMPLATE="minimal"
TRANSPARENT=0
FPS=24
WIDTH=1280
CHROMA_KEY_COLOR="0xfefefe"   # near-white. tune if your bg is different.
CHROMA_KEY_SIMILARITY="0.25"
CHROMA_KEY_BLEND="0.10"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --template) TEMPLATE="$2"; shift 2 ;;
    --transparent) TRANSPARENT=1; shift ;;
    --fps) FPS="$2"; shift 2 ;;
    --width) WIDTH="$2"; shift 2 ;;
    --chroma-color) CHROMA_KEY_COLOR="$2"; shift 2 ;;
    *)
      if [[ -z "$VIDEO" ]]; then VIDEO="$1"
      elif [[ -z "$NAME" ]]; then NAME="$1"
      else echo "unknown arg: $1"; exit 1
      fi
      shift ;;
  esac
done

if [[ -z "$VIDEO" || -z "$NAME" ]]; then
  echo "usage: ./build.sh <video-file> <project-name> [--template minimal|blueprint] [--transparent]"
  exit 1
fi

if [[ ! -f "$VIDEO" ]]; then
  echo "video not found: $VIDEO"
  exit 1
fi

command -v ffmpeg >/dev/null || { echo "ffmpeg required"; exit 1; }
if [[ "$TRANSPARENT" == "1" ]]; then
  command -v cwebp >/dev/null || { echo "cwebp required for --transparent (brew install webp)"; exit 1; }
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_PATH="$SCRIPT_DIR/templates/${TEMPLATE}.html"
if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "template not found: $TEMPLATE_PATH"
  exit 1
fi

OUT="./$NAME"
mkdir -p "$OUT/frames"

echo "[1/4] probing video..."
ASPECT=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$VIDEO" | awk -F, '{print $1 "/" $2}')
WIDTH_H=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$VIDEO")
HEIGHT_H=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$VIDEO")
IS_SQUARE=$(awk -v w="$WIDTH_H" -v h="$HEIGHT_H" 'BEGIN { print (w == h) ? 1 : 0 }')

# scale filter: keep aspect, cap width at $WIDTH
if [[ "$IS_SQUARE" == "1" ]]; then
  SCALE="scale=${WIDTH}:${WIDTH}:flags=lanczos"
  WRAP_CSS="aspect-ratio: 1 / 1;"
else
  SCALE="scale=${WIDTH}:-2:flags=lanczos"
  WRAP_CSS="aspect-ratio: ${ASPECT};"
fi

echo "[2/4] extracting frames at ${FPS}fps..."
if [[ "$TRANSPARENT" == "1" ]]; then
  TMPDIR="$(mktemp -d)"
  ffmpeg -v error -y -i "$VIDEO" \
    -vf "fps=${FPS},${SCALE},colorkey=${CHROMA_KEY_COLOR}:${CHROMA_KEY_SIMILARITY}:${CHROMA_KEY_BLEND},format=rgba" \
    "$TMPDIR/f_%04d.png"
  echo "[3/4] converting to WebP with alpha..."
  EXT="webp"
  for f in "$TMPDIR"/*.png; do
    name=$(basename "$f" .png)
    cwebp -q 72 -alpha_q 82 "$f" -o "$OUT/frames/${name}.webp" > /dev/null 2>&1
  done
  rm -rf "$TMPDIR"
else
  ffmpeg -v error -y -i "$VIDEO" -vf "fps=${FPS},${SCALE}" -q:v 5 "$OUT/frames/f_%04d.jpg"
  EXT="jpg"
  echo "[3/4] (skipping webp step)"
fi

FRAME_COUNT=$(ls "$OUT/frames" | wc -l | tr -d ' ')
echo "  → ${FRAME_COUNT} frames extracted ($(du -sh "$OUT/frames" | awk '{print $1}'))"

echo "[4/4] writing index.html..."
sed \
  -e "s|{{FRAME_COUNT}}|${FRAME_COUNT}|g" \
  -e "s|{{FRAME_EXT}}|${EXT}|g" \
  -e "s|{{WRAP_CSS}}|${WRAP_CSS}|g" \
  -e "s|{{NAME}}|${NAME}|g" \
  "$TEMPLATE_PATH" > "$OUT/index.html"

echo ""
echo "done → $OUT"
echo ""
echo "next steps:"
echo "  cd $OUT"
echo "  python3 -m http.server 8000    # test locally at http://localhost:8000"
echo "  vercel --yes                    # deploy to vercel"
