---
name: scroll-scrub
description: >
  Turn any video into a scroll-scrubbed website. Apple AirPods-style animation where
  scrolling down plays the video forward and scrolling up plays it backward.
  Use when: (1) user says "scroll scrub", "scroll animation", "scrub video",
  "Apple-style scroll", "scroll to play video", or provides a video and asks for a
  scrollable website; (2) user wants to turn a generated/rendered video into an
  interactive webpage; (3) user asks for the image-sequence scrub technique.
  Handles: ffmpeg extraction, template selection (graph-paper default, minimal, blueprint),
  optional transparent backgrounds, and deploy to Vercel or `here-now`.
argument-hint: "[video-path] [optional: template, transparent, deploy target]"
---

# scroll-scrub skill

Turn any video into a scroll-scrubbed microsite using canvas image-sequence scrubbing.

## Prerequisites

- `ffmpeg` installed (`brew install ffmpeg`)
- Optional: `cwebp` for transparent backgrounds (`brew install webp`)
- A deploy target. One of:
  - Vercel CLI authenticated (`vercel whoami`)
  - `here-now` skill available
  - Or just produce the folder locally, skip deploy

## What this skill does

1. Probe the user's video (dimensions, duration, orientation)
2. Extract frames with `ffmpeg` at 24fps into `<project>/frames/`
3. Optionally chroma-key the background and output WebP with alpha (`--transparent`)
4. Populate an HTML template with the right aspect ratio and frame count
5. Deploy the resulting static folder

The default template is `graph-paper`: a light cream background with a blue drafting-paper grid and the video sitting in a centered, shadowed frame at ~70vw. The frame shows the video in context — you see the grid scrolling around the edges as the canvas stays sticky.

## Step 1 — understand the request

Parse the user's message to find:
- **Video path** (required). If missing, ask the user.
- **Project name** (optional). If not provided, derive from the video filename (kebab-case, no extension).
- **Template preference**: `graph-paper` (default), `minimal` (plain white), or `blueprint` (dark navy).
- **Transparent background**: if the user says "transparent", "key out the background", "just the subject", or similar, set `--transparent`. Works best when the video has a near-solid light background.
- **Deploy target**: Vercel by default. If user says "here-now" or "quick share", try that skill instead.

## Step 2 — build the site

```bash
SCRIPT_DIR="$(cd "$(dirname "SKILL_PATH")" && pwd)"
cd /tmp/scroll-scrub-sites
"$SCRIPT_DIR/build.sh" "<video-path>" "<project-name>" [flags]
```

Substitute `SKILL_PATH` with the actual path to this skill's directory (likely `~/.claude/skills/scroll-scrub/`). Use `/tmp/scroll-scrub-sites/` as the working directory so the user's home doesn't get polluted.

The script output tells you where the build landed and the next commands.

## Step 3 — verify before deploying

Serve the folder locally and sanity-check:

```bash
cd /tmp/scroll-scrub-sites/<project-name>
python3 -m http.server 8765 > /tmp/scroll-scrub-server.log 2>&1 &
curl -s -o /dev/null -w "root=%{http_code}\n" http://localhost:8765/
curl -s -o /dev/null -w "f1=%{http_code}\n" http://localhost:8765/frames/f_0001.jpg
# (or .webp if --transparent was used)
```

If both return 200, the build is good. Kill the local server before deploying:
`lsof -t -i :8765 | xargs kill 2>/dev/null`

## Step 4 — deploy

### Option A — Vercel (default)

```bash
cd /tmp/scroll-scrub-sites/<project-name>
vercel --yes --prod 2>&1 | tail -10
```

The output includes the live URL (aliased production URL and deploy-specific URL). Return that to the user.

If vercel prompts for scope (non-interactive), use `--scope <team-slug>`. Read the error message — it usually lists valid scopes to pick from.

### Option B — here-now

If the `here-now` skill is available and the user prefers it, invoke that skill on the output folder. It provides instant static hosting at `{slug}.here.now`.

### Option C — folder only

If the user wants no deploy, just report the output path and the next-step commands.

## Step 5 — report back

Give the user:
- Live URL
- Total deploy size (run `du -sh <project-name>` to compute)
- Frame count and template used
- One-line sanity: "Video renders on scroll, background visible around the frame."

## Tuning notes

- **Default fps is 24.** Higher fps = smoother scrub but bigger payload. 30fps is fine for short videos; 15fps is fine for very long ones.
- **Default width is 1280px.** Sharp enough on retina at 70vw viewport. Go higher (1600, 1920) for very large displays or zoomed-in views.
- **Total payload target: under 30MB.** A 10-second 24fps video at 1280px comes in around 18MB as JPEG q=5 or WebP alpha q=72. Longer videos need lower fps or smaller width.
- **Aspect ratio is auto-detected.** Landscape / portrait / square are all handled by the `--width` flag scaling the long edge.

## Video-shooting tips (pass to users who haven't shot yet)

- Lock the camera. No zoom, no cuts, no shake.
- One element moves. Subject transforms, background stays still.
- Movement should be linear — scroll maps to time linearly.
- Subject dead center (crop-safe).
- Keep it 5–15 seconds.

## Gotchas

- **`cover` fitting crops a bit.** If the source aspect doesn't perfectly match the canvas-wrap aspect, the drawFrame function does cover-fit. The aspect-ratio CSS should match the source so cropping is minimal.
- **Large frame count = slow first load.** Loader shows progress. Tell the user if the expected load is >10s on a slow connection.
- **Transparent mode needs a solid background.** The chroma-key default is near-white (`0xfefefe`). If the video has a green or black background, pass `--chroma-color 0x00ff00` or `0x000000`.
- **Vercel scope required in non-interactive mode.** Read the error, it tells you the scope to use. For Timour that's `timkosters-projects`.
