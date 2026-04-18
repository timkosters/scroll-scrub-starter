#!/usr/bin/env bash
# scroll-scrub-starter / build.sh
# Turn a video into a scroll-scrubbed canvas image-sequence site.
#
# Usage:
#   ./build.sh <video-file> [project-name] [options]
#   ./build.sh --check                    # preflight: verify tools and permissions
#
# If project-name is omitted, it's derived from the video filename
# (e.g. Vital Futures.mp4 -> vital-futures).
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
#   --deploy                  After build, try Vercel deploy if available
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
DEPLOY=0
CHECK_ONLY=0

# Preflight/doctor mode
if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=1
fi

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
    --deploy) DEPLOY=1; shift ;;
    --check) CHECK_ONLY=1; shift ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      if [[ -z "$VIDEO" ]]; then VIDEO="$1"
      elif [[ -z "$NAME" ]]; then NAME="$1"
      else echo "unknown arg: $1" >&2; exit 1
      fi
      shift ;;
  esac
done

# --check: preflight and exit
if [[ "$CHECK_ONLY" == "1" ]]; then
  echo "scroll-scrub preflight check"
  echo "─────────────────────────────"
  ok=1
  for bin in ffmpeg ffprobe; do
    if command -v "$bin" >/dev/null; then
      echo "  ✓ $bin  ($(command -v "$bin"))"
    else
      echo "  ✗ $bin  MISSING (brew install ffmpeg)"
      ok=0
    fi
  done
  if command -v cwebp >/dev/null; then
    echo "  ✓ cwebp (optional, for --transparent)"
  else
    echo "  ○ cwebp  not installed (optional; brew install webp to enable --transparent)"
  fi
  if command -v python3 >/dev/null; then
    echo "  ✓ python3 (for local preview + template substitution)"
  elif command -v python >/dev/null; then
    echo "  ✓ python (will use for template substitution)"
  else
    echo "  ✗ python  MISSING (needed for template substitution)"
    ok=0
  fi
  if command -v vercel >/dev/null; then
    if vercel whoami >/dev/null 2>&1; then
      echo "  ✓ vercel  (authed as $(vercel whoami 2>/dev/null))"
    else
      echo "  ○ vercel  installed but not authed (run: vercel login)"
    fi
  else
    echo "  ○ vercel  not installed (optional; npm i -g vercel)"
  fi
  if [[ -w . ]]; then
    echo "  ✓ current dir writable"
  else
    echo "  ✗ current dir not writable"
    ok=0
  fi
  echo ""
  if [[ "$ok" == "1" ]]; then
    echo "ready to build. example:  ./build.sh ~/Downloads/your-video.mp4"
    exit 0
  else
    echo "some requirements are missing. install them and re-run --check."
    exit 1
  fi
fi

if [[ -z "$VIDEO" ]]; then
  cat <<USAGE >&2
usage: ./build.sh <video-file> [project-name] [options]
       ./build.sh --check                  # verify tools and permissions

examples:
  ./build.sh ~/Downloads/clip.mp4                        # auto-names project, graph-paper default
  ./build.sh ~/Downloads/clip.mp4 my-site
  ./build.sh ~/Downloads/clip.mp4 --bg "#1a1a2e"
  ./build.sh ~/Downloads/clip.mp4 --template blueprint --transparent
  ./build.sh ~/Downloads/clip.mp4 --deploy               # build + push to Vercel

options:
  --template graph-paper | minimal | blueprint   (default: graph-paper)
  --bg <CSS value>                               e.g. "#ff00aa", paper, "linear-gradient(...)"
  --bg-image <path>                              local image path
  --title <string>                               page title + og:title
  --description <string>                         meta + og:description
  --transparent                                  chroma-key near-white to alpha (needs cwebp)
  --fps <N>                                      extraction fps (default: 24)
  --width <N>                                    scale width in px (default: 1280)
  --deploy                                       run vercel deploy after build
  --outdir <path>                                output folder (default: ./<project-name>)
USAGE
  exit 1
fi

if [[ ! -f "$VIDEO" ]]; then
  echo "video not found: $VIDEO" >&2
  exit 1
fi

# Derive project name from video filename if not given
if [[ -z "$NAME" ]]; then
  base=$(basename "$VIDEO")
  # Strip extension, then slugify: lowercase, replace non-alnum with hyphens, collapse hyphens
  stem="${base%.*}"
  slug=$(printf '%s' "$stem" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]/-/g' -e 's/-\+/-/g' -e 's/^-//' -e 's/-$//')
  if [[ -z "$slug" ]]; then
    slug="scroll-site-$(date +%s)"
  fi
  NAME="$slug"
  echo "(project name derived from filename: $NAME)"
fi

# Sanitize project name: only allow sensible filename chars
if [[ ! "$NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "project name must contain only letters, digits, dot, underscore, hyphen" >&2
  echo "got: $NAME" >&2
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

echo "[1/6] probing video..."
W_SRC=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$VIDEO" 2>/dev/null || echo "")
H_SRC=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$VIDEO" 2>/dev/null || echo "")
if [[ -z "$W_SRC" || -z "$H_SRC" || "$W_SRC" -eq 0 || "$H_SRC" -eq 0 ]]; then
  echo "could not read video dimensions from $VIDEO. is it a valid video file?" >&2
  exit 1
fi
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO" 2>/dev/null || echo "0")
DUR_INT=${DUR%.*}
echo "  source: ${W_SRC}x${H_SRC}, ${DUR_INT}s"

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

WRAP_CSS="width: min(78vw, calc(82vh * ${W_SRC} / ${H_SRC})); max-height: 82vh; aspect-ratio: ${W_SRC} / ${H_SRC};"

if [[ -n "$BG_IMAGE" ]]; then
  if [[ ! -f "$BG_IMAGE" ]]; then
    echo "bg-image not found: $BG_IMAGE" >&2
    exit 1
  fi
  BG_EXT="${BG_IMAGE##*.}"
  cp "$BG_IMAGE" "$OUT/bg.${BG_EXT}"
  BG_STYLE="background: #0a0a0a url('./bg.${BG_EXT}') center center / cover no-repeat fixed;"
elif [[ -n "$BG" ]]; then
  case "$BG" in
    paper) BG_STYLE="" ;;
    white) BG_STYLE="background: #ffffff;" ;;
    black) BG_STYLE="background: #0a0a0a;" ;;
    cream) BG_STYLE="background: #f7f5ee;" ;;
    *) BG_STYLE="background: ${BG};" ;;
  esac
else
  BG_STYLE=""
fi

echo "[2/6] extracting frames at ${FPS}fps, ${ORIENT}..."
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

  echo "[3/6] converting to WebP with alpha..."
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
  echo "[3/6] (skipping webp transparency step)"
fi

FRAME_COUNT=$(find "$OUT/frames" -maxdepth 1 -name "f_*.${EXT}" | wc -l | tr -d ' ')
SIZE=$(du -sh "$OUT/frames" | awk '{print $1}')
echo "  → ${FRAME_COUNT} frames (${SIZE})"

if [[ "$FRAME_COUNT" -lt 2 ]]; then
  echo "too few frames to build a site. aborting." >&2
  exit 1
fi

echo "[4/6] extracting poster frame..."
POSTER_IDX=$(( FRAME_COUNT * 3 / 10 ))
[[ "$POSTER_IDX" -lt 1 ]] && POSTER_IDX=1
POSTER_NAME=$(printf "f_%04d" "$POSTER_IDX")
POSTER_SRC="$OUT/frames/${POSTER_NAME}.${EXT}"
if [[ "$EXT" == "webp" ]]; then
  ffmpeg -v error -y -i "$POSTER_SRC" -q:v 3 "$OUT/og-image.jpg"
else
  cp "$POSTER_SRC" "$OUT/og-image.jpg"
fi
# Also expose as poster.jpg for a clearer contract
cp "$OUT/og-image.jpg" "$OUT/poster.jpg"

echo "[5/6] writing index.html..."
DISPLAY_TITLE="${TITLE:-$NAME}"
DISPLAY_DESC="${DESCRIPTION:-Scroll-scrubbed video animation. Scroll down to play forward, scroll up to play backward.}"

html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
}
ESC_TITLE=$(html_escape "$DISPLAY_TITLE")
ESC_DESC=$(html_escape "$DISPLAY_DESC")

# Pick a python (python3 or python)
PYBIN=""
if command -v python3 >/dev/null; then PYBIN="python3"
elif command -v python >/dev/null; then PYBIN="python"
else
  echo "python or python3 required for template substitution" >&2
  exit 1
fi

"$PYBIN" - "$TEMPLATE_PATH" "$OUT/index.html" <<PYEOF
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
PYEOF

echo "[6/6] writing build-info.json..."
VIDEO_BASENAME=$(basename "$VIDEO")
cat > "$OUT/build-info.json" <<JSON
{
  "name": "$NAME",
  "title": "$DISPLAY_TITLE",
  "source_video": "$VIDEO_BASENAME",
  "source_dimensions": "${W_SRC}x${H_SRC}",
  "source_duration_seconds": ${DUR_INT:-0},
  "orientation": "$ORIENT",
  "template": "$TEMPLATE",
  "fps": $FPS,
  "frame_count": $FRAME_COUNT,
  "frame_extension": "$EXT",
  "frame_width_px": $WIDTH,
  "payload_size": "$SIZE",
  "transparent": $([[ "$TRANSPARENT" == "1" ]] && echo "true" || echo "false"),
  "background_override": $([[ -n "$BG" || -n "$BG_IMAGE" ]] && echo "true" || echo "false"),
  "generated_by": "scroll-scrub-starter"
}
JSON

echo ""
echo "✓ done → $OUT"
echo "  template: $TEMPLATE / orientation: $ORIENT / $FRAME_COUNT frames / $SIZE"
echo ""

# Optional deploy step
if [[ "$DEPLOY" == "1" ]]; then
  if command -v vercel >/dev/null && vercel whoami >/dev/null 2>&1; then
    echo "deploying to Vercel..."
    ( cd "$OUT" && vercel --yes --prod 2>&1 | tail -6 )
  else
    echo "(--deploy requested but vercel is not installed/authed)"
    echo "to deploy manually:"
    echo "  cd $OUT && vercel --yes --prod"
  fi
else
  echo "preview locally:"
  echo "  cd $OUT && python3 -m http.server 8000"
  echo ""
  echo "deploy:"
  echo "  cd $OUT && vercel --yes"
  echo "  or upload the folder to any static host (Netlify, GitHub Pages, S3, Cloudflare Pages)"
fi
