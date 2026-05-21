# Setup Guide — AI-OS Vault

Get the full system running in under 10 minutes.

---

## The Setup (Claude-Driven)

Open any terminal with Claude Code and say:

```
Set up my AI-OS from https://github.com/The-AIOS/aios
```

Claude reads this file and handles everything:
1. **Clones** the repo to `~/obsidian`
2. **Installs** MCPs, plugins, and CLI tools (auto-detects what's already installed)
3. **Creates a private repo** for your vault (`gh repo create --private`) and switches the remote — your personal content never goes back to the shared repo
4. **Configures** `USER.md` with your sources, organization, and identity
5. **Pushes** to your new private remote

You confirm decisions. Claude executes.

**What Claude auto-detects:**
- Git identity from `~/.gitconfig` or local repo config
- GitHub username from `gh auth status`
- SSH keys from `~/.ssh/`
- Already-installed MCPs, CLI tools, and plugins
- Bundled OAuth credentials for Google Workspace

**What Claude asks you (only if needed):**
- Your Google email (for Calendar/Tasks/Drive)
- Which task sources you use (GitHub Issues, etc.)
- What to name your private vault repo (defaults to `{username}/obsidian`)

---

## Prerequisites

Pick your OS path. Each installs the same toolchain (Node, Git, GitHub CLI, Python, uv, Obsidian, Claude Code CLI). After this section the Claude-driven flow is OS-agnostic.

> **Already have Claude Code CLI working?** Skip ahead to **[The Setup](#the-setup-claude-driven)** above.

### macOS (~5 min)

```bash
# 1. Homebrew (skip if you have it)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Toolchain
brew install node git gh python uv
brew install --cask obsidian

# 3. Claude Code CLI
npm install -g @anthropic-ai/claude-code

# 4. Auth (each opens a browser tab)
gh auth login
claude
```

### Windows (~15-20 min)

**Workflow target:** VS Code (with its integrated PowerShell terminal) + Obsidian open side-by-side. Or **Antigravity** IDE — it bundles Claude Code natively if you want fewer moving parts. **Avoid** plain `cmd` and Obsidian terminal plugins (polyipseity is unreliable on Windows).

```powershell
# Open PowerShell (not cmd). Run as your user — only escalate if winget refuses.

# 1. Toolchain via winget (preferred — avoids GUI installer pitfalls)
winget install OpenJS.NodeJS.LTS
winget install Git.Git
winget install GitHub.cli
winget install Python.Python.3.12
winget install Microsoft.VisualStudioCode    # or download Antigravity: https://antigravity.dev
winget install Obsidian.Obsidian

# 2. uv (Python package runner — vendored MCPs need it)
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"

# 3. Allow PowerShell to run npm scripts (one-time, required)
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned    # type Y at the prompt

# 4. CLOSE this PowerShell, open a fresh one (PATH only refreshes on new shells)

# 5. Claude Code CLI
npm install -g @anthropic-ai/claude-code

# 6. Auth
gh auth login
claude
```

**If `node --version` says "not recognized" after step 1:** PATH didn't take. Fix via GUI — `Win+R` → `sysdm.cpl` → Advanced → Environment Variables → System variables → Path → Edit → New → add `C:\Program Files\nodejs` AND `%AppData%\npm`. Close all shells, open a fresh one. See [Known Gotchas](#known-gotchas) for more.

### Linux (Ubuntu/Debian, ~5 min)

```bash
# 1. Toolchain
sudo apt update
sudo apt install -y nodejs npm git gh python3 python3-pip

# 2. uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# 3. Claude Code CLI
sudo npm install -g @anthropic-ai/claude-code

# 4. Obsidian — download the AppImage from https://obsidian.md/download

# 5. Auth
gh auth login
claude
```

(For Fedora/Arch/etc., swap the package manager — the package names are the same.)

---

## What Claude Installs

### 1. Obsidian MCP

The Obsidian MCP lets Claude read and write your vault notes directly.

```bash
claude mcp add obsidian -- npx -y @mauricio.wolff/mcp-obsidian@latest ~/obsidian/vault
```

### 2. Google Workspace MCP (optional but recommended)

Enables Google Calendar, Tasks, Drive, Docs, Sheets, and Slides access. The OAuth app credentials are **bundled in the repo** at `mcps/google-workspace-mcp/oauth.json`.

```bash
cd ~/obsidian
CLIENT_ID=$(python3 -c "import json; print(json.load(open('mcps/google-workspace-mcp/oauth.json'))['client_id'])")
CLIENT_SECRET=$(python3 -c "import json; print(json.load(open('mcps/google-workspace-mcp/oauth.json'))['client_secret'])")

claude mcp add google-workspace \
  -e GOOGLE_OAUTH_CLIENT_ID="$CLIENT_ID" \
  -e GOOGLE_OAUTH_CLIENT_SECRET="$CLIENT_SECRET" \
  -e MCP_SINGLE_USER_MODE=true \
  -e USER_GOOGLE_EMAIL="you@company.io" \
  -e WORKSPACE_MCP_CREDENTIALS_DIR="$HOME/.google_workspace_mcp/credentials" \
  -- uv run --directory ~/obsidian/mcps/google-workspace-mcp python -m main --single-user --permissions \
  drive:full sheets:full slides:full docs:full calendar:full tasks:full
```

On first use, Claude opens a browser for Google OAuth consent.

### 3. GitHub CLI

```bash
brew install gh
gh auth login
```

Claude uses `gh` directly — it's a CLI tool, not an MCP.

### 4. Local Slack MCP (optional)

Provides `conversations_unreads` — used by the pipeline executor for daily triage.

```bash
cd ~/obsidian/mcps/slack-mcp && npm install --production
claude mcp add slack-local -- node ~/obsidian/mcps/slack-mcp/src/server.js
npx @jtalk22/slack-mcp --setup
```

### 5. Pipeline executor (no action needed)

The pipeline executor (`hooks/pipeline-executor.py`) pre-loads Google Calendar, Tasks, and Slack data for `/today` and `/close-day`. It runs via `uv run` with inline dependencies — no installation step. Just needs `uv` (listed in prerequisites).

### 6. vault-commands plugin

```bash
mkdir -p ~/.claude/plugins/marketplaces/local/plugins
mkdir -p ~/.claude/plugins/marketplaces/local/.claude-plugin

mkdir -p ~/.claude/plugins/marketplaces/local/plugins/vault-commands/commands
cp ~/obsidian/commands/*.md \
  ~/.claude/plugins/marketplaces/local/plugins/vault-commands/commands/

cp ~/obsidian/commands/marketplace.json \
  ~/.claude/plugins/marketplaces/local/.claude-plugin/marketplace.json

claude plugin marketplace add ~/.claude/plugins/marketplaces/local/
claude plugin install vault-commands@local
```

Add `"vault-commands@local": true` to `enabledPlugins` in `~/.claude/settings.json`.

### 7. Calendar folder

```bash
mkdir -p ~/obsidian/vault/01\ -\ calendar/$(date +%Y-%m)
```

### 8. Create your private repo and switch remote

Your vault should live in your own private repo — not the shared team repo. Claude does this automatically during setup. Manual:

```bash
cd ~/obsidian
gh repo create {your-username}/obsidian --private --source=. --push
```

This creates a private GitHub repo, sets it as your remote, and pushes. From here on, your content never goes back to the AIOS framework. `/aios:update` pulls AIOS framework updates from `The-AIOS/aios`; `/company` pulls company venture-context from each mounted company's repo — but you push only to your private personal vault.

### 9. Spawn wrapper (cross-platform — recommended)

The bundled `spawn` shell function lets you open a named worker session with one command — e.g. `spawn accountant "review last quarter's P&L"` — and survives Anthropic-account rate-limit swaps without losing the terminal. Install via the canonical script for your platform:

**macOS / Linux:**
```bash
bash ~/obsidian/hooks/claude-identity/install-wrappers.sh
source ~/.zshrc   # or ~/.bashrc
```

**Windows (PowerShell):**
```powershell
pwsh -File ~\obsidian\hooks\claude-identity\install-wrappers.ps1
. $PROFILE
```

Both installers are **idempotent** — timestamped backup → strip prior wrapper block → append canonical version → content-verify → auto-rollback on failure. Safe to re-run; if your wrapper is already current, re-running is a no-op.

What gets installed:
- `_claude_with_respawn` / `Invoke-ClaudeWithRespawn` — auto-respawn loop with 3-strike circuit-breaker (kills the silent-session-loss bug during account swaps)
- `spawn` — named worker opener that detects your environment (IDE tab on macOS, Windows Terminal tab on Windows, Terminal.app fallback)

After install, run `spawn SESSION_NAME [TASK]` from any Claude Code session.

### 10. Quota autopilot (optional, macOS only — needs ≥ 2 Anthropic accounts)

If you run two or more Anthropic accounts to manage the 5h/7d rate limits, the bundled `hooks/claude-identity/` autopilot rotates between them automatically. When the active account nears the cap, it swaps to the next account in your `USER.md` rotation list and respawns active Claude Code sessions on the new account so transcripts continue uninterrupted. The launchd agent does the watching; you don't have to run anything once it's loaded.

The autopilot **builds on top of the spawn wrapper** (section 9) — the wrapper handles the in-place respawn; the autopilot is the Mac-only watcher that decides when to swap.

The full setup walkthrough lives in **`hooks/claude-identity/README.md` → `## Setup`** — 7 interactive steps your Claude session can walk you through (configure accounts in USER.md, capture identities, customize the launchd plist, wire the cache writer to your statusLine, verify). Just say *"set up the quota autopilot"* in any Claude Code session and Claude reads the README and walks you through it. Same flow runs automatically when `/aios:update` first surfaces this feature.

Hard preconditions:
- **macOS only.** Uses Keychain Services and launchd. On Linux/Windows the autopilot stays dormant; the spawn wrapper from section 9 still works on all platforms.
- **≥ 2 Anthropic accounts.** A single-account setup gets no value from the autopilot.

---

## After Setup

### 1. Open Obsidian

Add the vault folder: `~/obsidian/vault` (Obsidian → Open another vault → Open folder as vault)

### 2. Fill in USER.md

`USER.md` at the repo root is your personal configuration — the single file that makes the vault yours. Fill in (same order as the file):

- **Identity** — your named sessions and greeting styles
- **Session cascade** — files to read on start, per identity (optional)
- **Remote machines** — SSH patterns for other computers (optional)
- **Organization** — your team repo and venture folder
- **Sources** — timezone, Google accounts (primary + personal), Slack, dev projects
- **Growth routines** — evening reading/writing habits (optional)
- **Command personalizations** — override any command's default behavior (optional)

### 3. Tell Claude about yourself

Fill in your declared context. Templates for all files are in `vault/02 - templates/`.

```
vault/00 - notes/context/declared/
├── about_me.md            ← Who you are: background, roles, values
├── working_style.md       ← How you operate: decisions, energy, preferences
├── personal_voice.md      ← How you communicate: tone, audience, style
├── about_business.md      ← Distilled overview of your ventures
└── role-expectations.md   ← (optional) Role, pillars, success signals
```

Start with `about_me.md` — even 5 bullet points make a huge difference.

**Set up your ventures:** Each venture gets a folder in `vault/00 - notes/context/ventures/`:
1. Create subfolder: `ventures/{venture-name}/`
2. Create `about_venture.md` inside it (use `vault/02 - templates/about_venture-template.md`)
3. Add deep-dive files as needed (positioning, personas, pricing, GTM)
4. Update `about_business.md` with a summary entry pointing to the venture folder

### 4. Create your projects

Each project is a note in `vault/00 - notes/projects/`. Ask Claude: *"Create a project note for [name]"* or copy from `vault/02 - templates/project-template.md`. Projects bridge your external tools (GitHub, Monday, Google Tasks) to your daily plan.

### 5. Run your first command

```
aios:today
```

Restart Claude Code first (plugins load at session start).

### 6. First run expectations

Your first `/aios:today` will be sparse — that's normal. The system gets smarter as you add context:

1. **Start with `about_me.md`** — even 5 bullet points make a huge difference
2. **Run `/aios:today` again** — notice how priorities change
3. **After your first day, run `/aios:close-day`** — this captures what happened and starts building observed context
4. **By day 3**, the system knows your patterns, projects, and rhythm

---

## How the Vault Works

### Three-layer context model

```
Declared  →  You write it  →  Who you are, how you work, what you're building
Observed  →  Claude writes it  →  What Claude learns about you over time
Project   →  Both write it  →  Active work, decisions, open threads
```

### Bundled integrations

| Integration | Type | What it does |
|---|---|---|
| Obsidian | Local MCP | Vault read/write — the OS core |
| Google Workspace | Local MCP (vendored) | Calendar, Tasks, Drive, Docs, Sheets, Slides |
| Slack | Local MCP (vendored) | Unreads, history, send messages, search |
| GitHub | CLI tool | Repos, issues, PRs |

See `mcps/_index.md` for details on each integration.

### The vault-commands plugin

24 slash commands that read your vault and generate plans, insights, and content.

Run them via: `aios:<command-name>`

| Cadence | Commands |
|---------|----------|
| Daily | `today`, `close-day`, `close-session` |
| Weekly | `7plan`, `drift`, `weekly-learnings` |
| Bi-weekly | `graduate`, `emerge` |
| Monthly | `compact`, `housekeeping` (mid-month, or when triggers fire) |
| As needed | `ideas`, `ghost`, `challenge`, `trace`, `connect`, `learned`, `role-report`, `company` (multi-company mount/sync), `vault-update`, `agent`, `cold-start-interview` (first-run only) |

---

## Known Gotchas

OS-specific debugging fixes documented as the team hit them. Cross-reference if something breaks during prereq install or first run.

### Windows

| Issue | Cause | Fix |
|---|---|---|
| Node GUI installer crashes on "additional tools" step | "Automatically install necessary tools" checkbox triggers VS Build Tools, which fails on aka.ms requests | UNCHECK that box during install — OR skip the GUI entirely, use `winget install OpenJS.NodeJS.LTS` (cleaner, ~30s) |
| `node --version` not recognized after install | PATH not picked up; PowerShell's `SetEnvironmentVariable` sometimes fails silently | Fix via GUI: `Win+R` → `sysdm.cpl` → Advanced → Environment Variables → System variables → Path → Edit → New → add `C:\Program Files\nodejs` AND `%AppData%\npm`. Close all shells, open fresh. |
| `npm --version` says "running scripts is disabled on this system" | Default PowerShell execution policy blocks `.ps1` scripts | One-time: `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` (type Y) |
| `claude` not found in `cmd` | Node.js installer doesn't add Claude to cmd's PATH | Use VS Code's integrated PowerShell terminal, Antigravity's terminal, or Git Bash — never plain `cmd` |
| Pipeline crashes with emojis | Windows uses `cp1252` encoding | Already fixed — `pipeline-executor.py` reconfigures to UTF-8 on Windows |
| Slack recap fails with timezone | Python on Windows lacks timezone DB | Already fixed — `tzdata>=2024.1` in pipeline dependencies |
| Terminal in Obsidian doesn't work | polyipseity plugin incompatible | Use VS Code or Antigravity terminal instead. Uninstall the plugin. |
| Atlassian auth doesn't open popup | VS Code OAuth popup blocked | Authenticate at claude.ai → Settings → Connectors → Atlassian. VS Code detects it after. *(Skip if you don't use Jira/Confluence.)* |

**Skip on Windows:** Quota autopilot (above) is macOS-only — single-account use works fine on Windows without it.

### macOS

No platform-specific gotchas observed. Brew handles dependencies cleanly. If `claude` isn't found after `npm install -g`, ensure `~/.npm-global/bin` (or wherever npm installs globals) is on your `$PATH`.

---

## Troubleshooting

**`aios:today` not found**
→ Restart Claude Code. Plugins load at session start.
→ If still missing: `claude plugin marketplace add` + `claude plugin install vault-commands@local`.

**Obsidian MCP not connecting**
→ `claude mcp list` to verify. Re-run the add command if missing.

**Commands writing to wrong folder**
→ MCP path must point to `~/obsidian/vault` (the vault directory), not `~/obsidian` (the repo root).

**Edited a command but change isn't showing**
→ Sync to cache: `claude plugin update vault-commands@local`
