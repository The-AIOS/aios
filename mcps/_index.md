# MCPs — Model Context Protocol Servers

Vendored MCP servers that ship with the vault. Each subfolder is a standalone server with its own README, setup instructions, and dependencies.

This is the **canonical list** referenced by `CLAUDE.md` → MCP Policy. When you bundle a new MCP, add it here.

## Bundled MCPs

| MCP | Folder | What it does | Auth |
|-----|--------|-------------|------|
| Google Workspace | `google-workspace-mcp/` | Calendar, Tasks, Drive, Docs, Sheets, Slides, Gmail, Contacts, Forms | OAuth |
| Slack | `slack-mcp/` | Send/read messages AS YOU, search channels, DMs, threads, unreads | Chrome token extraction (default) or bot token (advanced) |
| Atlassian | `atlassian-mcp/` | Jira issues + Confluence pages | API token (scoped recommended for least-privilege, classic also works) |
| GitHub | `github-mcp/` | Repos, issues, PRs, files, branches, workflows | PAT |
| Stitch | `stitch-mcp/` | AI-native design → code pipeline (Stitch 2.0) | `npx` (no auth) |
| NotebookLM | `notebooklm-mcp/` | Google NotebookLM — notebooks, audio/podcasts, quizzes | `notebooklm login` |
| Playwright¹ | `playwright-mcp/` | Browser automation — auto-publish, testing, screenshots | Browser storage state (Chrome cookie import) |
| Nano Banana | `nano-banana-mcp/` | Gemini 2.5 Flash Image generation (cover images, visuals) | `GEMINI_API_KEY` |
| PDF Generator | `pdf-generator-mcp/` | pandoc (md → HTML) + Chrome (HTML → PDF) | None (local binaries) |
| Spotify DJ | `spotify-dj-mcp/` | Playback control (play, pause, next, volume, search) | Spotify Dev app + OAuth |

¹ **Playwright is setup-only — not a registered MCP server.** It's a *capability layer* (saved browser auth via Chrome cookie extraction in `cookie_import.py`) that Python scripts consume on demand. There is no `server.py`, no `claude mcp add` step. Listed in this table for bundling completeness, but consumption is `Bash(python script.py)`, not MCP tools. See [`playwright-mcp/README.md`](playwright-mcp/README.md) and [`commands/mcps-setup.md`](../commands/mcps-setup.md) Playwright section.

## Setup (all MCPs at once)

```bash
bash mcps/setup.sh
```

Creates virtual environments and installs dependencies for all MCPs. Skips any that are already set up. Run once after cloning, or after `vault-update` adds a new MCP. Non-technical users: Claude can run this for you.

Each MCP's README covers the one-time auth step (API token, OAuth, dev app creation, etc.).

## Platform notes (Windows-specific helpers)

Three known Windows quirks have shipped helpers — bundled in the relevant MCP folder, no extra install needed:

| Quirk | Helper | What it does |
|---|---|---|
| Google OAuth URL mangling in chat → terminal → browser pipelines (HSTS upgrades on `localhost`, terminal line-wrap, `+` encoding in scopes) → Google 400/404 | `google-workspace-mcp/make_auth_link.py` | Auto-detects the latest auth URL from `mcp_server_debug.log` (or accepts one as CLI arg), writes a static `<a href>` HTML file. User opens locally, clicks button, completes OAuth. Generated `auth_link.html` is gitignored. |
| `notebooklm login` race: post-login `goto("accounts.google.com")` is interrupted by Google's auto-redirect to NotebookLM, so `storage_state.json` never saves — leaves authenticated-but-broken state | `notebooklm-mcp/manual_login.py` + `notebooklm-mcp/save_storage.py` | `manual_login.py` runs the full login flow with the race wrapped in try/except (the navigation refresh works regardless of destination). `save_storage.py` is a recovery tool — exports storage state from an already-authenticated persistent profile. |
| `context-monitor.py` statusline crashes on Windows because Python defaults stdout to `cp1252`, can't encode the emoji-rich render (📁 🌿 🟢 🟡 🟠) | `hooks/claude-identity/context-monitor.py` (built-in) | `sys.stdout.reconfigure(encoding="utf-8")` at the top of `main()`. No-op on macOS/Linux where stdout is already UTF-8. |
| Google Workspace MCP OAuth fails with `"Invalid or expired OAuth state parameter"` in a repeating loop. Stale MCP processes accumulate across Claude Code restarts; oldest one holds port 8000 (the callback server); newer process holds the state token. Browser-side OAuth completes; callback hits the wrong process; state lookup fails. | Workaround (no helper yet — upstream fix queued for Phase 0) | **Diagnose:** `Get-Process -Name python \| ForEach-Object { (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine } \| Where-Object { $_ -match 'workspace' }` — if more than one result, that's the bug. **Fix:** `Get-Process -Name python \| Where-Object { (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine -match 'workspace' } \| Stop-Process -Force` → verify port freed with `netstat -ano \| findstr :8000` (empty) → trigger any `mcp__google-workspace__*` tool call → Claude respawns a single fresh MCP → retry OAuth within ~5 min. **Upstream fix queued:** single-instance lock on port 8000 with clear error message, OR filesystem-backed OAuth state in `~/.workspace-mcp/oauth-state/`. |

The `spawn` wrapper itself has a PowerShell port — see `CLAUDE.md` → "Spawning sessions" → "On Windows (PowerShell)" for the full Invoke-ClaudeWithRespawn + spawn install block.

## Canonical registration commands

Some MCPs need an explicit `--permissions` / `--tools` flag so the right services are loaded. Missing a service here means the tool surface silently lacks those endpoints (no error — they just don't appear). Use these commands as the source of truth:

### Google Workspace

```bash
claude mcp add google-workspace \
  -s local \
  -e GOOGLE_OAUTH_CLIENT_ID=<your-client-id> \
  -e GOOGLE_OAUTH_CLIENT_SECRET=<your-client-secret> \
  -e MCP_SINGLE_USER_MODE=true \
  -e USER_GOOGLE_EMAIL=<your-email> \
  -e WORKSPACE_MCP_CREDENTIALS_DIR=$HOME/.google_workspace_mcp/credentials \
  -- uvx workspace-mcp --single-user \
  --permissions drive:full sheets:full slides:full docs:full calendar:full tasks:full gmail:full contacts:full forms:full
```

**Why this exact permission list:** every `:full` service we actually use in the vault workflow. Missing any of these = that service's tools silently don't appear. Services intentionally excluded: `chat` (redundant with Slack), `search` (redundant with built-in WebSearch), `appscript` (scope too broad, no current use). Add them to the list only when a workflow needs them.

**On first call per service, browser opens for OAuth consent.** If you add new scopes to an already-registered server, users must re-consent (Google doesn't grant new scopes against an old token).

## Bundling candidates (not yet bundled)

Services where teammates currently rely on claude.ai-hosted connectors. These should be bundled next to keep account-switch resilience. If you hit one of these, add it to this section and plan the bundle:

- (Currently empty — all known services are bundled. Add here when a new claude.ai-hosted MCP is needed by the team.)

## Reviewed, intentionally not bundled

- **AgentFetch** — Playwright MCP covers every use case (browser automation + content extraction). No gap to fill.
- **Context Mode** — CLAUDE.md's Session Start Ritual and context hierarchy already do this work. No gap to fill.
- **Monday.com** — dropped from the stack (2026-04-21). No replacement needed.

## Adding a new MCP

1. Create a folder: `mcps/{name}-mcp/`
2. Add the server code + `README.md` with: what it does, setup, auth, register command
3. Add an install block to `mcps/setup.sh`
4. Add a row to the **Bundled MCPs** table above
5. Register it locally: `claude mcp add {name} -- {command}`
6. If it replaces a claude.ai-hosted connector, note the disable step in the README
