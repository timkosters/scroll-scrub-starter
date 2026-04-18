# scroll-scrub-starter

Turn any video into a scroll-scrubbed website. Scroll down, video plays forward. Scroll up, video plays backward. The Apple AirPods Pro effect.

Technique: **canvas image sequence scrub**. Frames are extracted from the video, preloaded, and drawn to a `<canvas>` whose frame index is mapped from scroll position.

## Live examples

- [video-scroll-0920.vercel.app](https://video-scroll-0920.vercel.app) — minimal, 16:9 video
- [video-scroll-bluecity.vercel.app](https://video-scroll-bluecity.vercel.app) — minimal, square video
- [ee26-blueprint.vercel.app](https://ee26-blueprint.vercel.app) — blueprint aesthetic, transparent video with poetic text layer

## What you need

1. `ffmpeg` — `brew install ffmpeg` (macOS) or your OS's package manager
2. Optional for transparent backgrounds: `webp` — `brew install webp`
3. A video file (any format ffmpeg can read)
4. A Vercel account (free tier is fine) if you want to deploy

## One command

```bash
./build.sh <path-to-video> <project-name> [--template minimal|blueprint] [--transparent]
```

Outputs a folder `./<project-name>/` ready to deploy.

### Examples

```bash
# Minimal white-bg site
./build.sh ~/Downloads/clip.mp4 my-site

# Blueprint aesthetic (square video recommended)
./build.sh ~/Downloads/city-build.mp4 city-site --template blueprint

# Blueprint aesthetic with transparent background
# (video should have a near-solid light background that we can key out)
./build.sh ~/Downloads/city-build.mp4 city-site --template blueprint --transparent
```

### Tuning

```bash
./build.sh video.mp4 my-site \
  --fps 30 \                  # more frames = smoother (default 24)
  --width 1600 \              # larger = sharper (default 1280)
  --chroma-color 0x000000 \   # for --transparent, color to key out (default near-white)
```

## Deploy

```bash
cd ./<project-name>
vercel --yes                  # deploys to a vercel.app subdomain
```

Or serve anywhere static: Netlify, GitHub Pages, S3, any web server. The site is a single `index.html` plus a `frames/` directory.

## Test locally

```bash
cd ./<project-name>
python3 -m http.server 8000
# open http://localhost:8000
```

## Shooting your video

Tips from the [HeyGen team](https://x.com/vivi_rizq) (they create great scroll-scrubs):

- **Lock the camera.** No zoom, no cuts, no shake.
- **One element moves.** The subject transforms. Background stays still.
- **Keep movement linear.** Scroll maps time linearly, so non-linear movement feels jerky.
- **Main subject dead center.** Cropping and "cover" fitting both work best when the subject is centered.
- **Keep it short.** 5-15 seconds is the sweet spot. Longer videos = more frames = slower first load.

## How it works

1. `ffmpeg` extracts frames at 24fps, scaled to 1280 wide (smaller = faster load, larger = sharper)
2. Frames are preloaded in parallel (6 concurrent requests — more and browsers stall)
3. A sticky full-viewport canvas sits over a 500vh spacer
4. On scroll, `window.scrollY / maxScroll` → frame index → draw to canvas
5. `requestAnimationFrame` throttles the scroll handler and only redraws on frame change

## Transparent backgrounds

The `--transparent` flag runs each frame through ffmpeg's `colorkey` filter to remove near-white pixels, then `cwebp` converts to WebP with alpha. Works well when your video has a clean solid background (white, green, black). If your background is varied, use Runway's [Remove Background](https://help.runwayml.com/hc/en-us/articles/19112532638995) on the source video first, then run this script without `--transparent`.

## File size budget

A 10-second video at 24fps = 240 frames. At 1280 wide:

| Format | Per frame | Total | Notes |
|---|---|---|---|
| JPEG q=5 | ~75KB | ~18MB | Default for minimal template |
| WebP alpha q=72 | ~75KB | ~18MB | Used by `--transparent` |
| PNG alpha | ~500KB | ~120MB | Don't. |

Keep the total under ~30MB for a reasonable first-load on most connections.

## License

MIT. Fork it, ship it.
