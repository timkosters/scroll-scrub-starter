# AGENTS.md

This repo ships an **agent skill**: `SKILL.md` at the root tells any coding agent (Claude Code, Codex, Cursor, Copilot, Gemini CLI, Aider, Zed, Windsurf, and others that read agent-skill files) how to turn a user's video into a scroll-scrubbed microsite.

**Read `SKILL.md` first.** It has the full flow: prerequisites, the background-choice question to ask the user, the build commands, the verification step, and the deploy options.

## Quick summary for agents

- **Entry point:** `./build.sh <video-path> <project-name> [flags]`
- **Defaults:** graph-paper background, 24fps, 1280px wide, JPEG frames
- **Key flags:** `--bg`, `--bg-image`, `--template`, `--transparent`, `--title`, `--description`
- **Output:** a folder `./<project-name>/` with `index.html` + `frames/` + `og-image.jpg` — ready to deploy to any static host
- **Required of you before building:** ask the user which background they want (see SKILL.md Step 2)

## Setup

```bash
# macOS
brew install ffmpeg       # required
brew install webp         # only if the user wants --transparent

# Verify
ffmpeg --version
ffprobe --version
```

## If invoked as an installed skill

Some agents (Claude Code) support user-wide skill install. Users who want the skill globally run:

```bash
git clone https://github.com/timkosters/scroll-scrub-starter ~/.claude/skills/scroll-scrub
```

The agent then invokes it by keyword match (see `SKILL.md` description for trigger phrases). No need to be inside the cloned repo.

## If invoked as a project (repo-cloned)

If the user cloned this repo and is asking you to run it inside this directory, `SKILL.md` still applies — use the CLI directly (`./build.sh ...`).
