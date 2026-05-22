---
tags: [hooks, index]
created: '2026-03-28'
updated: '2026-05-21'
---
# Hooks

> Scripts that run as part of vault commands OR as Claude Code event hooks. Vault-command hooks invoked from command files. Event hooks (UserPromptSubmit + statusLine) wired in `~/.claude/settings.json` per [SETUP.md §10](../SETUP.md).

## Vault-command hooks

| Hook | Used by | What it does |
|------|---------|-------------|
| `pipeline-executor.py` | `/today`, `/close-day` | Pre-loads Google Calendar, Tasks, and Slack data in one batch. Commands read the output instead of calling APIs individually. Runs via `uv run` with inline deps. |
| `markitdown-convert.py` | `/ingest` + standalone | Converts any file (PDF, Word, Excel, PowerPoint, images, audio, YouTube, EPUB, HTML, CSV, JSON, XML, ZIP) → clean markdown. Wraps Microsoft's MarkItDown library. Standalone: `python3 ~/aios/hooks/markitdown-convert.py <file>`. |
| `claude-identity/` | launchd + statusLine | Multi-account quota autopilot. Rotates Anthropic accounts when the 5h/7d rate limit nears the cap; resumes active sessions on the new account. See `claude-identity/README.md`. macOS-only; ≥ 2 Anthropic accounts required. |

## Claude Code event hooks

| Hook | Event | What it does |
|------|-------|-------------|
| `inject-datetime.sh` (`.ps1`) | `UserPromptSubmit` | Injects current system date/time/timezone into Claude's context before each prompt. Eliminates the "Claude infers time from conversational context instead of checking system clock" failure mode. See `antifragile.md` 2026-05-18 entry. Cross-platform: `.sh` for macOS/Linux, `.ps1` for Windows. |
| `claude-identity/claude-identity.sh cache \| context-monitor.py` | `statusLine` | Writes rate-limit cache on every Claude turn (feeds the autopilot's fast-path quota detector) + powers the context-monitor status display. Wired in `~/.claude/settings.json` `statusLine.command`. |

## Operator extensions

- `custom/` — your own hooks (survive `/aios:update`). Documented in `custom/_index.md` with the registry table format.

**Wiring:** event hooks are wired in `.claude/settings.json` (project-level) or `~/.claude/settings.json` (user-level). The vault ships a project-level `.claude/settings.json` that wires `inject-datetime.sh` to `UserPromptSubmit`. On Windows, replace `bash` with `pwsh -File` in the command path.

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
