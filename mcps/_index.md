# MCPs — Model Context Protocol Servers

Vendored MCP servers that ship with the vault. Each subfolder is a standalone server with its own README, setup instructions, and dependencies.

This is the **canonical list** referenced by `CLAUDE.md` → MCP Policy. When you bundle a new MCP, add it here.

## Bundled MCPs

| MCP | Folder | What it does | Auth |
|-----|--------|-------------|------|
| Google Workspace | `google-workspace-mcp/` (config + docs only — server runs from PyPI via `uvx`) | Calendar, Tasks, Drive, Docs, Sheets, Slides, Gmail, Contacts, Forms — **Chat supported upstream but off by default** (add `chat:full`; needs re-consent) | OAuth |
| Slack | `slack-mcp/` | Send/read messages AS YOU, search channels, DMs, threads, unreads | Chrome token extraction (default) or bot token (advanced) |
| Atlassian | `atlassian-mcp/` | Jira issues + Confluence pages | API token (scoped recommended for least-privilege, classic also works) |
| GitHub | `github-mcp/` | Repos, issues, PRs, files, branches, workflows | PAT |
| Stitch | `stitch-mcp/` | AI-native design → code pipeline (Stitch 2.0) | `npx` (no auth) |
| NotebookLM | `notebooklm-mcp/` | Google NotebookLM — notebooks, audio/podcasts, quizzes | `notebooklm login` ⚠️ **needs Python 3.10+ — see README** |
| Playwright¹ | `playwright-mcp/` | Browser automation — auto-publish, testing, screenshots | Browser storage state (Chrome cookie import) |
| Nano Banana | `nano-banana-mcp/` | Gemini 2.5 Flash Image generation (cover images, visuals) | `GEMINI_API_KEY` |
| PDF Generator | `pdf-generator-mcp/` | pandoc (md → HTML) + Chrome (HTML → PDF) | None (local binaries) |
| Spotify DJ | `spotify-dj-mcp/` | Playback control (play, pause, next, volume, search) | Spotify Dev app + OAuth |

¹ **Playwright is setup-only — not a registered MCP server.** It's a *capability layer* (saved browser auth via Chrome cookie extraction in `cookie_import.py`) that Python scripts consume on demand. There is no `server.py`, no `claude mcp add` step. Listed in this table for bundling completeness, but consumption is `Bash(python script.py)`, not MCP tools. See [`playwright-mcp/README.md`](playwright-mcp/README.md) and [`plugins/aios/commands/mcps-setup.md`](../plugins/aios/commands/mcps-setup.md) Playwright section.

## Source attribution

MCPs come from two places: **vendored** from an upstream open-source repo (we track upstream HEAD via `.upstream-sync`) or **AIOS-built** in this framework. `/aios:housekeeping` Bucket 18 checks each vendored MCP's upstream for new commits since last sync.

| MCP | Origin | Upstream | License |
|---|---|---|---|
| Google Workspace | **PyPI at runtime** (`uvx workspace-mcp`) — not vendored, no code redistributed | [taylorwilsdon/google_workspace_mcp](https://github.com/taylorwilsdon/google_workspace_mcp) | MIT (upstream's own; we ship none of it) |
| Slack | vendored | [jtalk22/slack-mcp-server](https://github.com/jtalk22/slack-mcp-server) | MIT |
| Atlassian | vendored | [sooperset/mcp-atlassian](https://github.com/sooperset/mcp-atlassian) | MIT |
| GitHub | vendored (Anthropic) | [modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers) → `src/github` | MIT |
| NotebookLM | vendored | [teng-lin/notebooklm-py](https://github.com/teng-lin/notebooklm-py) | MIT |
| Stitch | npm proxy | `@_davideast/stitch-mcp` (auto-updates via `npx`) | — |
| Nano Banana | AIOS-built | — | GPL-2.0-or-later |
| PDF Generator | AIOS-built | — | GPL-2.0-or-later |
| Spotify DJ | AIOS-built | — | GPL-2.0-or-later |
| Playwright | AIOS-built | — | GPL-2.0-or-later |

Each vendored MCP has a `.upstream-sync` file in its folder recording `repo=`, `hash=`, `date=` (and optional `subdir=` for monorepo subdirs). When `/aios:housekeeping` Bucket 18 runs, it compares each recorded hash against the upstream's current HEAD and surfaces drift with the commit list since last sync. MCP updates often require dependency bumps + restart — Bucket 18 flags these explicitly.

## Setup (all MCPs at once)

```bash
bash mcps/setup.sh
```

Creates virtual environments and installs dependencies for all MCPs. Skips any that are already set up. Run once after cloning, or after `/aios:update` adds a new MCP. Non-technical users: Claude can run this for you.

Each MCP's README covers the one-time auth step (API token, OAuth, dev app creation, etc.).

## Where credentials live (don't panic when an MCP fails)

When an MCP shows `✗ Failed to connect`, operators often assume their API keys are lost and go hunting for `.env` files that don't exist. **They're not lost.** MCP credentials live in two places, both of which survive `/aios:update`, repo cleanup, branch switches, and history rewrites:

- **`~/.claude.json` (user-scope config)** — every MCP server's registration, including the `Environment` block (`GEMINI_API_KEY`, `GITHUB_TOKEN`, `GOOGLE_OAUTH_CLIENT_ID`, etc.) passed to the server process on launch. This is per-machine and is NOT in the repo. Inspect with `claude mcp list` (shows command + connection status) or read `~/.claude.json` directly.
- **OAuth token caches** — e.g. `~/.google_workspace_mcp/credentials/{email}.json`. Per-machine, regenerated by re-auth. Never in the repo.

So a failed MCP is almost always a **local state issue** (stale token, missing `.venv`, double-nested folder, port held by a stale process), NOT a lost-key issue. Start debugging locally — check `claude mcp list`, the MCP's `.venv`, and `mcp_server_debug.log` — before touching any cloud console. See `google-workspace-mcp/TROUBLESHOOTING.md` for the full local-first recovery flow. For wiring the MCP to a **personal Google account** (an agent's own gmail — External consent screen, test-user, `--single-user` token), see `google-workspace-mcp/personal-account-setup.md`.

## Platform notes (Windows-specific helpers)

Three known Windows quirks have shipped helpers — bundled in the relevant MCP folder, no extra install needed:

| Quirk | Helper | What it does |
|---|---|---|
| Google OAuth URL mangling in chat → terminal → browser pipelines (HSTS upgrades on `localhost`, terminal line-wrap, `+` encoding in scopes) → Google 400/404 | `google-workspace-mcp/make_auth_link.py` | Auto-detects the latest auth URL from `mcp_server_debug.log` (or accepts one as CLI arg), writes a static `<a href>` HTML file. User opens locally, clicks button, completes OAuth. Generated `auth_link.html` is gitignored. |
| `notebooklm login` race: post-login `goto("accounts.google.com")` is interrupted by Google's auto-redirect to NotebookLM, so `storage_state.json` never saves — leaves authenticated-but-broken state | `notebooklm-mcp/manual_login.py` + `notebooklm-mcp/save_storage.py` | `manual_login.py` runs the full login flow with the race wrapped in try/except (the navigation refresh works regardless of destination). `save_storage.py` is a recovery tool — exports storage state from an already-authenticated persistent profile. |
| `context-monitor.py` statusline crashes on Windows because Python defaults stdout to `cp1252`, can't encode the emoji-rich render (📁 🌿 🟢 🟡 🟠) | `hooks/claude-identity/context-monitor.py` (built-in) | `sys.stdout.reconfigure(encoding="utf-8")` at the top of `main()`. No-op on macOS/Linux where stdout is already UTF-8. |
| Google Workspace MCP OAuth fails with `"Invalid or expired OAuth state parameter"` in a repeating loop. Stale MCP processes accumulate across Claude Code restarts; oldest one holds port 8000 (the callback server); newer process holds the state token. Browser-side OAuth completes; callback hits the wrong process; state lookup fails. | Workaround (no helper yet — upstream fix queued for Phase 0) | **Diagnose:** `Get-Process -Name python \| ForEach-Object { (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine } \| Where-Object { $_ -match 'workspace' }` — if more than one result, that's the bug. **Fix:** `Get-Process -Name python \| Where-Object { (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine -match 'workspace' } \| Stop-Process -Force` → verify port freed with `netstat -ano \| findstr :8000` (empty) → trigger any `mcp__google-workspace__*` tool call → Claude respawns a single fresh MCP → retry OAuth within ~5 min. **Upstream fix queued:** single-instance lock on port 8000 with clear error message, OR filesystem-backed OAuth state in `~/.workspace-mcp/oauth-state/`. |

The `spawn` wrapper itself has a PowerShell port — see `CLAUDE.md` → "Spawning sessions" → "On Windows (PowerShell)" for the full Invoke-ClaudeWithRespawn + spawn install block.

## Registration commands live in the manifests, not here

Every bundled folder carries a **`connector.json`** — machine-readable, beside the thing it describes:

```
mcps/<id>-mcp/connector.json
```

It holds the `id`, the operator-facing `service` name and `value`, the `connect` mode, anything the
connector `requires` on disk, and the full `register` block (transport, command, args, env). **That is
the single source of truth.** `mcps/setup.sh` installs dependencies and deliberately does not register
anything; the AIOS App reads these manifests to build its Connectors card and ships **no copy** of any
register command, so a missing manifest means a connector is simply not listed — honest silence rather
than a guess.

**This section used to carry the commands, and that is exactly why it went stale.** It declared itself
the source of truth while holding **one** entry (Google Workspace) out of eleven; the other ten lived
in per-README prose in inconsistent shapes, three of them with no command at all. A section that
*holds* data drifts from the thing it describes. A section that *points* cannot.

**`{framework}` is mandatory in any manifest path — a literal `~/aios` is a bug.** `~/aios` is a
symlink on some machines, so a hardcoded copy documents a path that differs from the one that actually
works, and it is **invisible** on every machine where the clone and the symlink happen to agree. That
was a real finding: a README documenting `~/aios/mcps/…` beside a live registration carrying the
resolved path. Substitute `{framework}` with the resolved framework root at registration time.

### Google Workspace — the permission list, stated once

The nine `:full` services the vault workflow actually uses live in
`mcps/google-workspace-mcp/connector.json`. **Deliberately excluded**, with reasons, because an
exclusion needs a rationale a future reader can weigh:

| Excluded | Why |
|---|---|
| `chat` | Redundant with Slack, which is the bundled connector for messaging |
| `search` | Redundant with built-in WebSearch |
| `appscript` | Scope far too broad for the benefit; no consumer in the framework |

**Verified 2026-08-27, because "no current use" is a claim that decays:** a sweep of every
`mcp__google-workspace__*` reference across `plugins/`, `agents/`, `skills/` and `hooks/` found **zero**
consumers of any chat tool (`list_spaces`, `send_message`, `get_messages`, `search_messages`) and
**zero** of any Apps Script tool. The exclusions hold on evidence, not on habit.

> ⚠️ **A live registration carrying `chat:full appscript:full` is drift, not a newer decision.** It was
> found on a real machine while this contract was being written, contradicting this file with no surface
> anywhere reporting the difference — which is the diagnostic the App's Connectors card exists to
> provide. **Correcting it is free:** removing a service needs no re-consent (the token keeps the scope
> Google already granted; the tools simply stop being exposed), so re-register from the manifest and
> restart. Adding scopes later is what costs a consent round-trip, not dropping them.

**On first call per service a browser opens for OAuth consent.** Adding new scopes to an
already-registered server requires re-consent — Google does not grant new scopes against an old token.

### Registration scope — the trap worth knowing once

`claude mcp add` defaults to **local** (per-directory) scope, so registrations land under
`projects[<dir>].mcpServers` in `~/.claude.json` rather than at the top level. Two consequences a
newcomer meets by accident:

- **Open the same framework from a second directory and your connectors appear to vanish** — they are
  still there, filed under the first directory.
- **Register again from that second directory and you now maintain two copies**, which drift
  independently and with nothing reporting it.

Pass `-s user` when you want a registration that follows you across directories. Neither choice is
wrong; the default simply is not the one most operators would pick if asked, and nothing asks.


## Bundling candidates (not yet bundled)

Services where teammates currently rely on claude.ai-hosted connectors. These should be bundled next to keep account-switch resilience. If you hit one of these, add it to this section and plan the bundle:

- (Currently empty — all known services are bundled. Add here when a new claude.ai-hosted MCP is needed by the team.)

## Adding a new MCP

1. Create a folder: `mcps/{name}-mcp/`
2. Add the server code + `README.md` with: what it does, setup, auth, register command
3. **Add `connector.json`** (required — without it the AIOS App will not list the connector at all).
   **This applies to `mcps/custom/` too**, and that case is easier to miss because nothing in canonical
   checks it: `/aios:update` never touches `custom/`, and the test suite is repo infrastructure that is
   deliberately never synced to a vault. A custom MCP was found **registered and working with no
   manifest** — invisible to the card while functioning perfectly — which surfaced only once the App
   began reporting folders that have no manifest. See `mcps/custom/_index.md` for the operator-facing
   version of this.
   Copy the shape from any bundled folder. Non-negotiable fields:
   - `id` **must equal the registered server name**, or a reader cannot match manifest to registration
   - `service` is the service as the operator would name it — **never** containing the string "MCP"
   - every path uses **`{framework}`**, never a literal `~/aios` (see above)
   - `connect` is `one-click` (fully specified, no operator secret) · `needs-key` (command known, operator supplies values) · `guided` (multi-step auth a human must perform)
   - `requires` lists anything that must exist on disk first, so a connector pointing at a `.venv`
     `setup.sh` has not built yet is detectable **before** a registration is written rather than at
     first use
   - **not an MCP server at all?** Set `registers: false` and describe the real delivery path. Two
     bundled folders are in this category (`notebooklm-mcp`, `playwright-mcp`) — they live under
     `mcps/` by history, deliver capability through a skill and through direct Python respectively, and
     have no server to register. A reader must not treat a missing registration for these as drift.
4. Add an install block to `mcps/setup.sh`
5. Add a row to the **Bundled MCPs** table above
6. Register it locally: `claude mcp add {name} -- {command}` (prefer `-s user` — see the scope trap above)
6. If it replaces a claude.ai-hosted connector, note the disable step in the README
