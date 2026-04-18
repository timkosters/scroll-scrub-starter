# scroll-scrub

**One command. Any video. Scroll-scrubbed microsite, live in 60 seconds.**

Apple AirPods-style scroll animation: scroll down to play forward, scroll up to play backward. The subject sits in a framed canvas floating over a graph-paper background (customizable) so the page scrolls visibly around it.

Two ways to use it:
- **As a Claude Code skill** — drop a video in chat, get a live URL back. Claude picks a template and asks about the background.
- **As a CLI** — `./build.sh video.mp4 my-site`, then deploy the folder anywhere static.

## Live examples

- [video-scroll-0920.vercel.app](https://video-scroll-0920.vercel.app) — landscape video, graph-paper default
- [video-scroll-bluecity.vercel.app](https://video-scroll-bluecity.vercel.app) — square video, minimal white
- [ee26-blueprint.vercel.app](https://ee26-blueprint.vercel.app) — blueprint template + transparent background
- [ljr-scroll.vercel.app](https://ljr-scroll.vercel.app) — scroll-driven React animation (no pre-rendered frames)

## Install as a Claude Code skill

```bash
git clone https://github.com/timkosters/scroll-scrub-starter ~/.claude/skills/scroll-scrub
```

That's it. Next time you're in Claude Code, give it a video and ask for a scroll-scrub site:

> Turn `~/Downloads/clip.mp4` into a scroll-scrub site and deploy it.

Claude will run `build.sh` for you, test the build locally, and deploy via Vercel (or `here-now` if you have that skill installed). You'll get a live URL back.

## Install as a CLI

```bash
git clone https://github.com/timkosters/scroll-scrub-starter
cd scroll-scrub-starter
chmod +x build.sh
```

## What you need

1. `ffmpeg` — `brew install ffmpeg` (macOS) or your OS's package manager
2. Optional for transparent backgrounds: `webp` — `brew install webp`
3. A video file (any format ffmpeg can read)
4. A deploy target — Vercel, Netlify, GitHub Pages, S3, any static host

## One command

```bash
./build.sh <video-path> <project-name> [options]
```

Options:
- `--template graph-paper | minimal | blueprint` (default: `graph-paper`)
- `--bg <CSS>` — override background. Any valid CSS: `paper` (default), `white`, `black`, a hex like `#1a1a2e`, a color name, or a full gradient like `"linear-gradient(180deg, #ff00aa, #00ffaa)"`. Wrap gradients in quotes.
- `--bg-image <path>` — use a local image as background (copied into the output)
- `--title <string>` — page title + og:title (default: project name)
- `--description <string>` — meta + og:description
- `--transparent` — chroma-key near-white to transparent, output WebP with alpha
- `--fps N` — extraction fps (default: 24)
- `--width N` — scale width in px (default: 1280, forced even)
- `--chroma-color 0xHEXHEX` — color to key out when `--transparent` is set
- `--outdir path` — output folder (default: `./<project-name>`)

### Examples

```bash
# Default: graph-paper, auto-detect aspect ratio, auto OG preview image
./build.sh ~/Downloads/clip.mp4 my-site

# Custom background color
./build.sh ~/Downloads/clip.mp4 my-site --bg "#1a1a2e"

# Gradient background
./build.sh ~/Downloads/clip.mp4 my-site --bg "linear-gradient(180deg, #e8ddf5, #f5ead9)"

# Image background
./build.sh ~/Downloads/clip.mp4 my-site --bg-image ~/Pictures/bg.jpg

# Blueprint + transparent background (for line drawings on solid-white bg)
./build.sh ~/Downloads/city.mp4 city-site --template blueprint --transparent

# Higher resolution + custom title/description for better social previews
./build.sh ~/Downloads/clip.mp4 my-site --width 1600 --fps 30 \
  --title "My Product Reveal" --description "Scroll to reveal the thing"
```

### Deploy

```bash
cd ./<project-name>
vercel --yes
```

Or serve anywhere static. The site is a single `index.html` plus a `frames/` directory.

### Test locally

```bash
cd ./<project-name>
python3 -m http.server 8000
# open http://localhost:8000
```

## Templates

| Name | Look | Use |
|---|---|---|
| `graph-paper` (default) | Cream paper with light-blue drafting grid, video in a centered shadowed frame | General-purpose — works for any video |
| `minimal` | Pure white background, video full-viewport within max bounds | Clean, no chrome |
| `blueprint` | Midnight-blue with cyan grid, crosshair corners, frame counter, progress ruler | For schematic/technical/drawing-style videos |

## Shooting your video

- **Lock the camera.** No zoom, no cuts, no shake.
- **One element moves.** The subject transforms. Background stays still.
- **Keep movement linear.** Scroll maps time linearly, so non-linear movement feels jerky.
- **Main subject dead center.** Cover-fit works best when the subject is centered.
- **Keep it short.** 5–15 seconds is the sweet spot. Longer videos = more frames = slower first load.

## How it works

1. `ffmpeg` extracts frames at 24fps, scaled to 1280 on the long edge
2. Frames preload in parallel (6 concurrent requests)
3. A sticky full-viewport stage sits over a 500vh spacer
4. On scroll, `scrollY / maxScroll → frame index → draw to canvas`
5. `requestAnimationFrame` throttles the scroll handler and only redraws on frame change

Vector-crisp rendering, 30-second typical load on fast connections, no external dependencies at runtime (pure static HTML + JPEG/WebP).

## Transparent backgrounds

The `--transparent` flag runs each frame through ffmpeg's `colorkey` filter to remove near-white pixels, then `cwebp` converts to WebP with alpha. Works well when your video has a clean solid background (white, green, black). If the background is varied, use Runway's [Remove Background](https://help.runwayml.com/hc/en-us/articles/19112532638995) on the source video first, then run this script without `--transparent`.

## File size budget

A 10-second video at 24fps = 240 frames. At 1280px long-edge:

| Format | Per frame | Total | Notes |
|---|---|---|---|
| JPEG q=5 | ~75KB | ~18MB | Default for opaque templates |
| WebP alpha q=72 | ~75KB | ~18MB | Default for `--transparent` |
| PNG alpha | ~500KB | ~120MB | Don't |

Keep total under ~30MB for a reasonable first-load on most connections.

## License

MIT. Fork it, ship it.
