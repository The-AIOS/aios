---
tags: [hooks, index]
created: '2026-03-28'
updated: '2026-07-13'
---
# Hooks

> Scripts that run as part of vault commands OR as Claude Code event hooks. Vault-command hooks invoked from command files. Event hooks (UserPromptSubmit + statusLine) wired in `~/.claude/settings.json` per [SETUP.md §10](../SETUP.md).

## Vault-command hooks

| Hook | Used by | What it does |
|------|---------|-------------|
| `pipeline-executor.py` | `/today`, `/close-day` | Pre-loads Google Calendar, Tasks, and Slack data in one batch. Commands read the output instead of calling APIs individually. Runs via `uv run` with inline deps. |
| `markitdown-convert.py` | `/ingest` + standalone | Converts any file (PDF, Word, Excel, PowerPoint, images, audio, YouTube, EPUB, HTML, CSV, JSON, XML, ZIP) → clean markdown. Wraps Microsoft's MarkItDown library. **The universal, cross-platform default converter** — the two media hooks below are macOS *enhancements*, not replacements. Standalone: `python3 ~/aios/hooks/markitdown-convert.py <file>`. |
| `transcribe.py` *(macOS)* | `/ingest` (long-form audio/video) + standalone | Local long-form transcription (`ffmpeg → mlx-whisper large-v3-turbo`) — the macOS upgrade for MarkItDown's one audio weakness (its Web-Speech path fails past a sentence). Arbitrary length, on-device, no third party. **macOS/Apple-Silicon only** (mlx); MarkItDown remains the non-Mac path. Optional deps: `python3 -m venv hooks/.venv && hooks/.venv/bin/pip install mlx-whisper`. Standalone: `python3 ~/aios/hooks/transcribe.py <file-or-URL> [out.txt]`. |
| `video-watch.py` + `ocr-image.swift` *(macOS)* | `/ingest` (screen-comprehension, opt-in) + standalone | Reads the video **screen** (slides · code · diagrams · on-screen text) — the capability MarkItDown lacks entirely (it discards every frame). Pipeline: transcript-first → `ffmpeg` scene-keyframes → pHash dedup → per-frame reader (`ocr` verbatim via Apple Vision `ocr-image.swift` · `vlm` structure via `claude -p` · `both`) → merged timeline. Fortress-clean (on-device OCR + subscription-auth VLM, no API key). **Opt-in** ("read the slides / code on screen"). OCR reader is macOS-only (Apple Vision); the `vlm` reader is cross-platform (`--reader vlm` off-Mac). Compose with `transcribe.py --transcript` to skip a second whisper model. Guide: `hooks/video-watch-guide.md`. |
| `claude-identity/` | launchd + statusLine | Multi-account quota autopilot. Rotates Anthropic accounts when the 5h/7d rate limit nears the cap; resumes active sessions on the new account. See `claude-identity/README.md`. macOS-only; ≥ 2 Anthropic accounts required. |

## Claude Code event hooks

| Hook | Event | What it does |
|------|-------|-------------|
| `inject-datetime.sh` (`.ps1`) | `UserPromptSubmit` | Injects current system date/time/timezone into Claude's context before each prompt. Eliminates the "Claude infers time from conversational context instead of checking system clock" failure mode. See `antifragile.md` 2026-05-18 entry. Cross-platform: `.sh` for macOS/Linux, `.ps1` for Windows. |
| `claude-identity/claude-identity.sh cache \| context-monitor.py` | `statusLine` | Writes rate-limit cache on every Claude turn (feeds the autopilot's fast-path quota detector) + powers the context-monitor status display. Wired in `~/.claude/settings.json` `statusLine.command`. |
| `guard-venture-mount.py` | `PreToolUse` (Edit/Write/MultiEdit/NotebookEdit) | Blocks direct edits to company-context **mounts** — `context/ventures/{v}/` files carrying a `.{v}-sync` marker are synced copies of a `{v}-context` source repo; editing them is reverted on the next `/aios:company --sync`. Points at the source repo instead. The framework's first PreToolUse hook. **Fail-open** (never bricks editing), **deterministic** (~nil false-positives), escape hatch `AIOS_ALLOW_MOUNT_EDIT=1`; the rsync sync path is exempt (Bash, not Edit/Write). Wire per SETUP §10 Hook C. Born from `antifragile.md` #81. |

## Operator extensions

- `custom/` — your own hooks (survive `/aios:update`). Documented in `custom/_index.md` with the registry table format.

**Wiring:** event hooks are wired in `.claude/settings.json` (project-level) or `~/.claude/settings.json` (user-level). The vault ships a project-level `.claude/settings.json` that wires `inject-datetime.sh` to `UserPromptSubmit`. On Windows, replace `bash` with `pwsh -File` in the command path. **`PreToolUse` hooks** (e.g. `guard-venture-mount.py`) wire the same way with a `matcher` — see SETUP §10 Hook C.

## Adding a hook

**Vault-command hooks** (referenced by command files):
1. Create the script in this folder
2. Document it in this index
3. Update SETUP.md to install it to `~/.claude/hooks/`
4. Reference it from the command that needs it

**Claude Code event hooks** (run automatically on Claude Code events):
1. Create the script in this folder (executable for `.sh`; ASCII-only for `.ps1` to survive Windows PowerShell 5.1)
2. Document it in this index
3. Wire it in `.claude/settings.json` under `hooks.{EventName}` — see existing examples
4. Restart Claude Code session to pick up the new hook
