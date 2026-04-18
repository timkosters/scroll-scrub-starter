---
name: scroll-scrub
description: >
  Turn any video into a scroll-scrubbed microsite. Apple AirPods-style animation
  where scrolling plays the video forward and up plays it backward. Use when the
  user says any of: "scroll scrub", "scroll scrubbing", "scroll animation",
  "scrub video", "Apple-style scroll", "Apple website scroll", "AirPods-style
  site", "image sequence site", "make a video into a website", "scroll to play
  video", "scroll-driven video", or when the user provides a video path and
  asks for a scrollable website. Handles frame extraction, aspect-ratio
  detection, optional transparent backgrounds, custom backgrounds, OpenGraph
  preview images, and deploys to Vercel / here-now / folder-only.
argument-hint: "[video-path] [optional: template, --bg color/image, --transparent]"
---

# scroll-scrub skill

Turns a video into a scroll-scrubbed microsite using canvas image-sequence scrubbing.

## Prerequisites

- `ffmpeg` (`brew install ffmpeg` on macOS). If missing, tell the user exactly that before trying anything else.
- Optional: `cwebp` for `--transparent` mode (`brew install webp`)
- Optional deploy target — one of:
  - Vercel CLI authenticated (`vercel whoami`)
  - `here-now` skill available
  - Or no deploy — just hand back the folder and preview command

## What this skill does

1. Ask the user about **background choice** (see Step 2 below — critical)
2. Probe the video (dimensions, duration, orientation)
3. Extract frames with ffmpeg at 24fps, auto-detecting aspect ratio
4. Optionally chroma-key the background and output WebP with alpha (`--transparent`)
5. Auto-extract an OpenGraph preview image (so shared links have a thumbnail)
6. Populate an HTML template with the right aspect ratio, frame count, OG tags, and background style
7. Deploy the static folder

## Step 1 — parse the request

From the user's message, identify:
- **Video path** (required). If missing, ask for it.
- **Project name** (optional). Derive from the video filename in kebab-case if not given (e.g. `MyVideo.mp4` → `my-video`). Must match `[A-Za-z0-9._-]+`.
- **Title / description** (optional). If they mention what it's about, use that.

## Step 2 — ASK about background

**This is important. Do not skip it.** Background choice is the single biggest visual decision. Before running the build, ask the user:

> What background do you want?
> - **Graph paper** (warm cream with blue drafting grid — default, great all-purpose)
> - **Minimal white** (clean, no chrome)
> - **Blueprint** (dark navy with cyan grid — technical/schematic feel)
> - **Custom** — a solid color (hex or name), a gradient, or a background image

If they pick custom:
- Solid color → `--bg "#HEX"` or `--bg colorname`
- Gradient → `--bg "linear-gradient(...)"` (wrap in quotes when invoking the script)
- Image → `--bg-image /path/to/image.jpg`

Also optional to ask:
- Do they want transparent background on the video itself (only if video has a near-solid bg color that can be keyed out)? → `--transparent`
- Template? Default to `graph-paper`. Use `minimal` or `blueprint` only if the user picks.

## Step 3 — build the site

Resolve the skill's own directory (where `build.sh` lives):

```bash
SKILL_DIR="$HOME/.claude/skills/scroll-scrub"
```

Create a working directory somewhere outside the user's home so it doesn't pollute:

```bash
mkdir -p /tmp/scroll-scrub-sites
cd /tmp/scroll-scrub-sites
"$SKILL_DIR/build.sh" "<video-path>" "<project-name>" [flags]
```

The script prints progress across 5 steps. On success it outputs the folder path and next-step commands. On failure it prints a clear error with the reason (missing tool, bad video, invalid name).

Common invocations:

```bash
# Default (graph-paper background)
"$SKILL_DIR/build.sh" /path/to/video.mp4 my-site

# Custom solid color
"$SKILL_DIR/build.sh" /path/to/video.mp4 my-site --bg "#1a1a2e"

# Gradient (note the quotes)
"$SKILL_DIR/build.sh" /path/to/video.mp4 my-site --bg "linear-gradient(180deg, #e8ddf5, #f5ead9)"

# Background image
"$SKILL_DIR/build.sh" /path/to/video.mp4 my-site --bg-image /path/to/bg.jpg

# Blueprint + transparent (for line drawings on white)
"$SKILL_DIR/build.sh" /path/to/video.mp4 my-site --template blueprint --transparent

# With title + description for better OpenGraph
"$SKILL_DIR/build.sh" /path/to/video.mp4 my-site \
  --title "My Product Reveal" \
  --description "Scroll to reveal the product"
```

## Step 4 — verify before deploying

Serve locally and sanity-check both the page and a frame:

```bash
cd /tmp/scroll-scrub-sites/<project-name>
# Prefer python3, fall back to python, then npx serve
if command -v python3 >/dev/null; then
  python3 -m http.server 8765 > /tmp/scroll-scrub-server.log 2>&1 &
elif command -v python >/dev/null; then
  python -m http.server 8765 > /tmp/scroll-scrub-server.log 2>&1 &
else
  echo "need python3 or python to verify locally. skipping verify step."
fi
sleep 2
curl -s -o /dev/null -w "root=%{http_code}\n" http://localhost:8765/
curl -s -o /dev/null -w "frame1=%{http_code}\n" http://localhost:8765/frames/f_0001.jpg
# (or .webp if --transparent was used — check the actual extension first)
```

Both 200 = good. Kill the local server before deploying:

```bash
lsof -t -i :8765 | xargs kill 2>/dev/null
```

## Step 5 — deploy

### Option A — Vercel (default)

First check auth:

```bash
vercel whoami 2>&1 | head -1
```

If it returns a username, deploy:

```bash
cd /tmp/scroll-scrub-sites/<project-name>
vercel --yes --prod 2>&1 | tail -10
```

If Vercel errors with "missing_scope" (non-interactive mode), read the error — it lists valid team/scope names. Retry with `--scope <team-slug>`.

If `vercel` is not installed: tell the user `npm install -g vercel && vercel login`, then fall through to Option B or C.

### Option B — here-now skill

If the `here-now` skill is installed (check with `ls ~/.claude/skills/here-now` or similar), invoke it on the output folder. Good for users without Vercel.

### Option C — folder only

If no deploy target is available, tell the user:
- The folder is at `/tmp/scroll-scrub-sites/<project-name>`
- They can upload it to any static host (Netlify drop, GitHub Pages, S3, Cloudflare Pages, etc.)
- Or they can install Vercel: `npm install -g vercel && vercel login`

## Step 6 — report back

Tell the user:
- Live URL (or folder path if no deploy)
- Total payload size (`du -sh <project-name>`)
- Frame count, fps, template, and background choice
- One-line sanity: the URL, a note that shared links will show a preview (OG image), and that reduced-motion users see a static poster

## Tuning defaults

- **fps**: 24 (override with `--fps`). Higher = smoother, bigger payload.
- **Width**: 1280px (override with `--width`). Sharp at 70-80vw on retina.
- **Payload target**: under 30MB. 10s @ 24fps @ 1280px ≈ 18MB.
- For longer videos: drop fps to 15 or width to 960.

## Video-shooting tips (mention if user hasn't shot yet)

- Lock the camera. No zoom, cuts, or shake.
- One element moves. Subject transforms, background stays still.
- Movement should be linear (scroll maps to time linearly).
- Subject dead center.
- 5-15 seconds is the sweet spot. Longer = slower first load.

## Gotchas

- **Odd source dimensions** get forced to even by ffmpeg. No action needed.
- **HDR/10-bit sources** are transcoded to `yuvj420p` so they don't come out washed.
- **Very short videos (<2 frames)** fail the build with a clear error.
- **`--transparent` needs a solid background** in the source. Default keys near-white. For other colors use `--chroma-color 0xHEXHEX`.
- **Vercel non-interactive**: if `--yes` errors, use `--scope <team-slug>` from the error message.
- **Deploy subpath hosting**: all frame paths are relative (`./frames/...`), so GitHub Pages project pages, S3 folders, and other subpath hosts work out of the box.
