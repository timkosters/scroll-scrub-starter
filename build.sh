#!/usr/bin/env bash
# scroll-scrub-starter / build.sh
# Turn a video into a scroll-scrubbed canvas image-sequence site.
#
# Usage:
#   ./build.sh <video-file> <project-name> [options]
#
# Options:
#   --template graph-paper | minimal | blueprint   (default: graph-paper)
#   --bg <CSS value>          Override body background. Any valid CSS background value:
#                             a hex color (#ff00aa), a name (lavender), a gradient
#                             (linear-gradient(180deg, #ff00aa, #00ffaa)), or paper
#                             (the default graph paper). Put gradients in quotes.
#   --bg-image <path>         Use a local image as the background (will be copied in)
#   --title <string>          Page title + og:title (default: project name)
#   --description <string>    Meta description + og:description
#   --transparent             Chroma-key near-white to alpha, output WebP (needs cwebp)
#   --fps <N>                 Extraction fps (default: 24)
#   --width <N>               Pixel width to scale to (default: 1280; forced even)
#   --chroma-color 0xHEXHEX   For --transparent, color to key out (default: near-white)
#   --outdir <path>           Output folder (default: ./<project-name>)
#
# Output: a folder ready to deploy (e.g. via `vercel --yes` or `here-now`).

set -euo pipefail
shopt -s nullglob

VIDEO=""
NAME=""
TEMPLATE="graph-paper"
BG=""
BG_IMAGE=""
TITLE=""
DESCRIPTION=""
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
    --bg) BG="$2"; shift 2 ;;
    --bg-image) BG_IMAGE="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --transparent) TRANSPARENT=1; shift ;;
    --fps) FPS="$2"; shift 2 ;;
    --width) WIDTH="$2"; shift 2 ;;
    --chroma-color) CHROMA_KEY_COLOR="$2"; shift 2 ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      if [[ -z "$VIDEO" ]]; then VIDEO="$1"
      elif [[ -z "$NAME" ]]; then NAME="$1"
      else echo "unknown arg: $1" >&2; exit 1
      fi
      shift ;;
  esac
done

if [[ -z "$VIDEO" || -z "$NAME" ]]; then
  cat <<USAGE >&2
usage: ./build.sh <video-file> <project-name> [options]

options:
  --template graph-paper | minimal | blueprint   (default: graph-paper)
  --bg <CSS value>                               e.g. "#ff00aa", paper, "linear-gradient(...)"
  --bg-image <path>                              local image path
  --title <string>                               page title + og:title
  --description <string>                         meta + og:description
  --transparent                                  chroma-key near-white to alpha (needs cwebp)
  --fps <N>                                      extraction fps (default: 24)
  --width <N>                                    scale width in px (default: 1280)
  --outdir <path>                                output folder (default: ./<project-name>)

examples:
  ./build.sh ~/Downloads/clip.mp4 my-site
  ./build.sh ~/Downloads/clip.mp4 my-site --bg "#1a1a2e" --title "My Reveal"
  ./build.sh ~/Downloads/clip.mp4 my-site --template blueprint --transparent
USAGE
  exit 1
fi

# Sanitize project name: only allow sensible filename chars
if [[ ! "$NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "project name must contain only letters, digits, dot, underscore, hyphen" >&2
  echo "got: $NAME" >&2
  exit 1
fi

if [[ ! -f "$VIDEO" ]]; then
  echo "video not found: $VIDEO" >&2
  exit 1
fi

command -v ffmpeg >/dev/null || { echo "ffmpeg required. install with: brew install ffmpeg" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe required (comes with ffmpeg)" >&2; exit 1; }
if [[ "$TRANSPARENT" == "1" ]]; then
  command -v cwebp >/dev/null || { echo "cwebp required for --transparent. install with: brew install webp" >&2; exit 1; }
fi

# Force width to even number (libx264 and other encoders reject odd dims)
WIDTH=$(( WIDTH / 2 * 2 ))

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_PATH="$SCRIPT_DIR/templates/${TEMPLATE}.html"
if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "template not found: $TEMPLATE_PATH" >&2
  echo "available templates:" >&2
  for t in "$SCRIPT_DIR/templates/"*.html; do echo "  $(basename "$t" .html)" >&2; done
  exit 1
fi

OUT="${OUTDIR:-./$NAME}"
mkdir -p "$OUT/frames"

echo "[1/5] probing video..."
W_SRC=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$VIDEO" 2>/dev/null || echo "")
H_SRC=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$VIDEO" 2>/dev/null || echo "")
if [[ -z "$W_SRC" || -z "$H_SRC" || "$W_SRC" -eq 0 || "$H_SRC" -eq 0 ]]; then
  echo "could not read video dimensions from $VIDEO. is it a valid video file?" >&2
  exit 1
fi
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO" 2>/dev/null || echo "?")
echo "  source: ${W_SRC}x${H_SRC}, ${DUR%.*}s"

# Orientation + scale filter
if [[ "$W_SRC" -gt "$H_SRC" ]]; then
  ORIENT="landscape"
  SCALE="scale=${WIDTH}:-2:flags=lanczos"
elif [[ "$W_SRC" -lt "$H_SRC" ]]; then
  ORIENT="portrait"
  SCALE="scale=-2:${WIDTH}:flags=lanczos"
else
  ORIENT="square"
  SCALE="scale=${WIDTH}:${WIDTH}:flags=lanczos"
fi

# CSS for canvas-wrap sizing + aspect
WRAP_CSS="width: min(78vw, calc(82vh * ${W_SRC} / ${H_SRC})); max-height: 82vh; aspect-ratio: ${W_SRC} / ${H_SRC};"

# Background style (body background CSS)
if [[ -n "$BG_IMAGE" ]]; then
  if [[ ! -f "$BG_IMAGE" ]]; then
    echo "bg-image not found: $BG_IMAGE" >&2
    exit 1
  fi
  BG_EXT="${BG_IMAGE##*.}"
  cp "$BG_IMAGE" "$OUT/bg.${BG_EXT}"
  BG_STYLE="background: #0a0a0a url('./bg.${BG_EXT}') center center / cover no-repeat fixed;"
elif [[ -n "$BG" ]]; then
  # Map common words to sensible defaults
  case "$BG" in
    paper)
      BG_STYLE=""  # fall through to template default (graph paper)
      ;;
    white) BG_STYLE="background: #ffffff;" ;;
    black) BG_STYLE="background: #0a0a0a;" ;;
    cream) BG_STYLE="background: #f7f5ee;" ;;
    *)
      # Any other value: use as CSS background
      BG_STYLE="background: ${BG};"
      ;;
  esac
else
  BG_STYLE=""  # template default
fi

echo "[2/5] extracting frames at ${FPS}fps, ${ORIENT}..."
if [[ "$TRANSPARENT" == "1" ]]; then
  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR"' EXIT
  ffmpeg -v error -y -i "$VIDEO" \
    -vf "fps=${FPS},${SCALE},colorkey=${CHROMA_KEY_COLOR}:${CHROMA_KEY_SIMILARITY}:${CHROMA_KEY_BLEND},format=rgba" \
    "$TMPDIR/f_%04d.png"

  pngs=("$TMPDIR"/*.png)
  if [[ ${#pngs[@]} -lt 2 ]]; then
    echo "ffmpeg produced ${#pngs[@]} frames. video may be too short, unreadable, or unsupported." >&2
    exit 1
  fi

  echo "[3/5] converting to WebP with alpha..."
  EXT="webp"
  for f in "${pngs[@]}"; do
    nm=$(basename "$f" .png)
    cwebp -q 72 -alpha_q 82 "$f" -o "$OUT/frames/${nm}.webp" > /dev/null 2>&1
  done
else
  ffmpeg -v error -y -i "$VIDEO" \
    -vf "fps=${FPS},${SCALE}" \
    -pix_fmt yuvj420p -q:v 5 \
    "$OUT/frames/f_%04d.jpg"
  EXT="jpg"

  jpgs=("$OUT/frames"/f_*.jpg)
  if [[ ${#jpgs[@]} -lt 2 ]]; then
    echo "ffmpeg produced ${#jpgs[@]} frames. video may be too short, unreadable, or unsupported." >&2
    rm -rf "$OUT/frames"
    exit 1
  fi
  echo "[3/5] (skipping webp transparency step)"
fi

# Count frames, using explicit pattern match
FRAME_COUNT=$(find "$OUT/frames" -maxdepth 1 -name "f_*.${EXT}" | wc -l | tr -d ' ')
SIZE=$(du -sh "$OUT/frames" | awk '{print $1}')
echo "  → ${FRAME_COUNT} frames (${SIZE})"

if [[ "$FRAME_COUNT" -lt 2 ]]; then
  echo "too few frames to build a site. aborting." >&2
  exit 1
fi

echo "[4/5] extracting poster frame for og:image..."
# Copy a middle-ish frame as og-image. Use ~30% into the sequence (usually more interesting than frame 1).
POSTER_IDX=$(( FRAME_COUNT * 3 / 10 ))
[[ "$POSTER_IDX" -lt 1 ]] && POSTER_IDX=1
POSTER_NAME=$(printf "f_%04d" "$POSTER_IDX")
POSTER_SRC="$OUT/frames/${POSTER_NAME}.${EXT}"
if [[ "$EXT" == "webp" ]]; then
  # Convert to jpg for og-image (broader compatibility)
  ffmpeg -v error -y -i "$POSTER_SRC" -q:v 3 "$OUT/og-image.jpg"
else
  cp "$POSTER_SRC" "$OUT/og-image.jpg"
fi

echo "[5/5] writing index.html..."

# Defaults for TITLE and DESCRIPTION
DISPLAY_TITLE="${TITLE:-$NAME}"
DISPLAY_DESC="${DESCRIPTION:-Scroll-scrubbed video animation. Scroll down to play forward, scroll up to play backward.}"

# HTML-encode values before inserting (basic: & < > " ')
html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
}
ESC_TITLE=$(html_escape "$DISPLAY_TITLE")
ESC_DESC=$(html_escape "$DISPLAY_DESC")

# sed delimiter collision: WRAP_CSS and BG_STYLE contain no control chars;
# NAME is sanitized above. DESC/TITLE go through html_escape which strips HTML-breaking chars.
# We use \x01 as a delimiter to avoid collisions with |, /, #, &, etc.
python3 - "$TEMPLATE_PATH" "$OUT/index.html" <<PYEOF
import sys
src, dst = sys.argv[1], sys.argv[2]
subs = {
    "{{FRAME_COUNT}}":   "${FRAME_COUNT}",
    "{{FRAME_EXT}}":     "${EXT}",
    "{{WRAP_CSS}}":      """${WRAP_CSS}""",
    "{{NAME}}":          """${ESC_TITLE}""",
    "{{DESCRIPTION}}":   """${ESC_DESC}""",
    "{{BG_STYLE}}":      """${BG_STYLE}""",
    "{{OG_IMAGE}}":      "og-image.jpg",
}
with open(src, "r") as f: html = f.read()
for k, v in subs.items(): html = html.replace(k, v)
with open(dst, "w") as f: f.write(html)
print(f"  → wrote {dst}")
PYEOF

echo ""
echo "✓ done → $OUT"
echo "  template: $TEMPLATE / orientation: $ORIENT / $FRAME_COUNT frames / $SIZE"
echo ""
echo "preview locally:"
echo "  cd $OUT && python3 -m http.server 8000"
echo ""
echo "deploy:"
echo "  cd $OUT && vercel --yes             # Vercel"
echo "  or upload the folder to any static host (Netlify, GitHub Pages, S3, etc.)"
