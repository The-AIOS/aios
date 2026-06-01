# Setup Guide — AI-OS Vault

Get the full system running in under 10 minutes (after the prereqs install).

<details>
<summary><strong>📍 Reading this as Claude?</strong> (Operator said "set up my AI-OS" — click for your 11-step execution sequence)</summary>

Operator said *"set up my AI-OS from this repo"* or similar. You're the executor. The flow:

1. Confirm Prerequisites are installed (Obsidian + Antigravity IDE/VS Code + Node/Git/gh/Python/uv/Claude Code) — if not, walk OS-specific block from "Prerequisites" §
2. Clone to `~/aios` (default) and create private GitHub repo `{username}/aios` (or whatever the operator names it) — see "The Setup" §1 below
3. Bulk MCP deps: `bash mcps/setup.sh` · Register bundled skills: `bash skills/setup.sh` (Windows: `pwsh skills/setup.ps1`) — symlinks AIOS skills into `~/.claude/skills` so Claude Code loads them (restart sessions after)
4. Guided MCP auth: invoke `/aios:mcps-setup`
5. Install the **spawn wrapper** — `bash ~/aios/hooks/claude-identity/install-wrappers.sh` (or `.ps1` on Windows), then re-source the shell rc
6. Wire the **universal hooks** to `~/.claude/settings.json`: `UserPromptSubmit` → `inject-datetime` (real clock in every prompt) + `statusLine` → `claude-identity.sh cache | context-monitor.py` (rate-limit cache writer + context display). See §10 below for exact JSON.
7. (Conditional, macOS multi-account only) — **ask the operator**: *"Do you use more than one Anthropic account?"* If yes → install the launchd plist + drop a `vault/.pending-quota-autopilot-capture` marker. **Don't run the account-capture login/logout dance during setup** — it would interrupt this session. The first `/today` will surface it as a deliberate task. See §11 below for the exact pattern.
8. Personalize: invoke `/aios:cold-start-interview` (15-25 min interactive; follow its Steps 0-10)
9. Wear the hat: `/agent onboarding-aios` (orientation companion)
10. Optional: `/aios:company` (mount/create venture-context) + `/aios:collaborate` (shared space)
11. First `/aios:today` (the proof point — also surfaces the deferred quota-autopilot capture if marker present)

**Defaults to pick without asking** (unless operator overrides): vault path = `~/aios/`, private repo name = `{username}/aios`, substrate for company = GitHub, wrappers + hooks A+B always install (no opt-out — they're load-bearing). **Always ask, never assume**: Google email, task sources (Slack/GitHub/Linear/Monday), MCP-by-MCP installs (let `/aios:mcps-setup` handle that), the multi-account-Anthropic question (§7 above — affects whether to defer capture). Show diffs before writing to `USER.md` / `INTENT.md` / `vault/00 - notes/context/declared/*` / `~/.claude/settings.json`.

**Be gentle, not exhaustive.** The operator should feel walked by the hand, not interrogated. One question at a time, sensible defaults, defer anything that risks interrupting the in-flight session (account capture is the canonical example — always deferred).

**If operator gets lost mid-setup:** route to `/agent onboarding-aios` — that agent knows the full doc map.

</details>

---

> **New here? Read top-to-bottom.** Prerequisites first (install Claude Code + the toolchain), then The Setup (Claude-Driven) runs the framework install.
>
> **Already have Claude Code installed?** Skip to [The Setup (Claude-Driven)](#the-setup-claude-driven).

---

## Prerequisites

Pick your OS path. Each installs the same toolchain (Node, Git, GitHub CLI, Python, uv, Obsidian, Antigravity IDE, Claude Code CLI). After this section the Claude-driven flow is OS-agnostic.

> **Already have Claude Code CLI working?** Skip ahead to **[The Setup](#the-setup-claude-driven)** above.

### Two apps you'll use daily — both required

The AIOS is *one filesystem, two surfaces*. Install both:

| App | Role | Why |
|---|---|---|
| **[Obsidian](https://obsidian.md/)** | User-friendly *note reading* | Beautiful read of your vault — daily notes, project notes, observed context, reflections. Wikilinks resolve, graph view shows connections, the markdown structure compounds visually. You think + reflect here. |
| **[Antigravity IDE](https://antigravity.google/product/antigravity-ide)** | User-friendly *file editing + agent spawning* | Bundles Claude Code natively — agents run in IDE terminals (one per spawn), Obsidian vault opens as a project, file edits + git ops feel native. You execute + ship here. Use VS Code as the alternative if you prefer it; Antigravity is just batteries-included. |

You don't pick one — you run them side-by-side. Obsidian on the left for context, Antigravity IDE on the right for execution. Same vault, both windows.

> **Then add the glass layer:** once the AIOS is set up (below), install **AIOS Glass** into Antigravity — a docked graphical surface for running rituals/agents/spaces by *clicking* instead of typing (great if you, or someone you onboard, aren't heavy terminal users). Open VSX → search **"AIOS Glass"** → Install. Walkthrough: see [`START-HERE.md`](./START-HERE.md) → *Step 4 — Install AIOS Glass*.

### macOS (~5 min)

```bash
# 1. Homebrew (skip if you have it)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Toolchain
brew install node git gh python uv

# 3. The two daily apps (see "Two apps you'll use daily" above)
brew install --cask obsidian
# Download Antigravity IDE from https://antigravity.google/product/antigravity-ide (no brew cask yet — drag .dmg to Applications)

# 4. Claude Code CLI
npm install -g @anthropic-ai/claude-code

# 5. Auth (each opens a browser tab)
gh auth login
claude
```

### Windows (~15-20 min)

**Workflow target:** Antigravity IDE (Claude Code bundled — recommended) + Obsidian open side-by-side. VS Code works as an alternative IDE. **Avoid** plain `cmd` and Obsidian terminal plugins (polyipseity is unreliable on Windows).

```powershell
# Open PowerShell (not cmd). Run as your user — only escalate if winget refuses.

# 1. Toolchain via winget (preferred — avoids GUI installer pitfalls)
winget install OpenJS.NodeJS.LTS
winget install Git.Git
winget install GitHub.cli
winget install Python.Python.3.12

# 2. The two daily apps (Obsidian + IDE — see "Two apps you'll use daily" above)
winget install Obsidian.Obsidian
# For Antigravity IDE (recommended — Claude Code bundled): download from https://antigravity.google/product/antigravity-ide
# For VS Code as the IDE alternative: winget install Microsoft.VisualStudioCode

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

# 4. The two daily apps (see "Two apps you'll use daily" above)
# Obsidian — download the AppImage from https://obsidian.md/download
# Antigravity IDE (recommended, Claude Code bundled) — https://antigravity.google/product/antigravity-ide
#   or VS Code as the alternative: sudo snap install code --classic

# 5. Auth
gh auth login
claude
```

(For Fedora/Arch/etc., swap the package manager — the package names are the same.)

---

## The Setup (Claude-Driven)

Open any terminal with Claude Code and say:

```
Set up my AI-OS from https://github.com/The-AIOS/aios
```

Claude reads this file and walks you through the full onboarding — clone → install → personalize → orient → optional company + collaboration → first daily plan. Each step is interactive; you confirm decisions, Claude executes.

**The end-to-end flow:**

1. **Clone** the repo to `~/aios` and create your private vault repo (`gh repo create {your-username}/aios --private` — matches the local path; renameable later) — your personal content never goes back to the shared framework. **If you cloned elsewhere**, Claude creates a `~/aios` symlink to the actual install path (see § Path portability below) so every framework reference resolves cleanly.
2. **Install MCP dependencies** via `bash mcps/setup.sh` (creates venvs, installs Python/Node deps for every bundled MCP)
3. **Guided MCP auth** via `/aios:mcps-setup` (one MCP at a time — asks "want this?", walks you through tokens, registers with `claude mcp add`, verifies the connection works)
4. **Personalize via `/aios:cold-start-interview`** — 15-25 min interactive interview: identity (USER.md), declared context (`about_me`, `personal_voice`, `working_style`), trust contract (`INTENT.md`), bundle install choices, optional Anthropic plugins. This is where the vault becomes *yours*.
5. **Spawn the onboarding companion**: `/agent onboarding-aios` — wears the AIOS-orientation hat. Knows the whole map: org profile, README, SETUP, CHEATSHEET, FORTRESS, START-HERE, USER.md personalization power, the self-update loop, where to look when lost. Invoke anytime later by saying *"I'm lost"* / *"what should I try next"* / *"remind me how this fits together"*.
6. **(Optional) Mount or create a company** via `/aios:company` — if you have a venture-context repo or want to scaffold one (GitHub recommended ✅, see the command's substrate selector)
7. **(Optional) Set up a collaboration space** via `/aios:collaborate` — if you have a known shared space (Drive folder, GitHub repo, local sync folder) to mount or scaffold
8. **First `/aios:today`** — the proof point. Reads everything you just configured, pulls your Calendar + Tasks + Slack, and generates a grounded plan for the rest of today. From here, the daily ritual takes over.

**What Claude auto-detects** (saves asking):
- Git identity from `~/.gitconfig` or local repo config
- GitHub username from `gh auth status`
- SSH keys from `~/.ssh/`
- Already-installed MCPs, CLI tools, and plugins
- Bundled OAuth credentials for Google Workspace

**What Claude asks you** (only if needed):
- Your Google email (for Calendar/Tasks/Drive)
- Which task sources you use (GitHub Issues, Linear, Monday, etc.)
- What to name your private vault repo (defaults to `{username}/aios` — matches the local path `~/aios/`; pick a different name if you prefer, e.g., `{username}/vault` or `{username}/my-aios`)
- Substrate choices when running `/company` or `/collaborate`

**If you ever feel lost during or after setup** — say *"I'm lost"* or *"where do I start"* and Claude routes to the [[onboarding-aios]] agent automatically. That agent is your standing companion for orientation throughout the framework's lifetime.

---

## Path portability (fallback for non-default installs)

**Default and recommended: clone to `~/aios/`.** Everything in the framework — commands, hooks, MCPs, agents, READMEs — references `~/aios/` as the canonical install path. If you can clone there, do.

**If you can't** (corporate machine restricts home-folder layout, you already have a different convention, you're trying the framework from `/tmp/...`, etc.), Claude creates a one-time symlink so the hardcoded references still resolve. This is a fallback, not an equal alternative — pick the default unless you have a specific reason.

**Auto-detect** — Claude runs this at SETUP §1 and again at the top of `/aios:cold-start-interview`: if the cloned repo path ≠ `~/aios/`, create the symlink for you.

**Manual** (if you ever need to redo it):

```bash
# macOS / Linux / WSL / Git Bash — works everywhere
ln -s "$(pwd)" ~/aios

# Windows PowerShell (requires Developer Mode OR admin — one-time Win 10+ toggle)
New-Item -ItemType SymbolicLink -Path "$HOME\aios" -Target (Get-Location).Path

# Windows CMD fallback (no admin needed; directory junction; same volume only)
mklink /J "%USERPROFILE%\aios" "%CD%"
```

**Why a symlink and not config-driven paths:** the symlink is a single filesystem-level redirect that costs zero code changes. The framework's 20+ hardcoded `~/aios/` references "just work" once `~/aios` resolves to your actual install. Power users who later move the install only need to update the symlink, not edit code.

**Verify it worked:** `ls -la ~/aios` should show the symlink arrow pointing at your real install path. If you see actual files instead of an arrow, you may have cloned directly to `~/aios/` — that's fine; no symlink needed.

---

## What Claude Installs

### 1. Obsidian MCP

The Obsidian MCP lets Claude read and write your vault notes directly.

```bash
claude mcp add obsidian -- npx -y @mauricio.wolff/mcp-obsidian@latest ~/aios/vault
```

### 2. Google Workspace MCP (optional but recommended)

Enables Google Calendar, Tasks, Drive, Docs, Sheets, and Slides access. The OAuth app credentials are **bundled in the repo** at `mcps/google-workspace-mcp/oauth.json`.

```bash
cd ~/aios
CLIENT_ID=$(python3 -c "import json; print(json.load(open('mcps/google-workspace-mcp/oauth.json'))['client_id'])")
CLIENT_SECRET=$(python3 -c "import json; print(json.load(open('mcps/google-workspace-mcp/oauth.json'))['client_secret'])")

claude mcp add google-workspace \
  -e GOOGLE_OAUTH_CLIENT_ID="$CLIENT_ID" \
  -e GOOGLE_OAUTH_CLIENT_SECRET="$CLIENT_SECRET" \
  -e MCP_SINGLE_USER_MODE=true \
  -e USER_GOOGLE_EMAIL="you@company.io" \
  -e WORKSPACE_MCP_CREDENTIALS_DIR="$HOME/.google_workspace_mcp/credentials" \
  -- uv run --directory ~/aios/mcps/google-workspace-mcp python -m main --single-user --permissions \
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
cd ~/aios/mcps/slack-mcp && npm install --production
claude mcp add slack-local -- node ~/aios/mcps/slack-mcp/src/server.js
npx @jtalk22/slack-mcp --setup
```

### 5. Pipeline executor (no action needed)

The pipeline executor (`hooks/pipeline-executor.py`) pre-loads Google Calendar, Tasks, and Slack data for `/today` and `/close-day`. It runs via `uv run` with inline dependencies — no installation step. Just needs `uv` (listed in prerequisites).

### 6. aios plugin

```bash
mkdir -p ~/.claude/plugins/marketplaces/the-aios/.claude-plugin
mkdir -p ~/.claude/plugins/marketplaces/the-aios/plugins/aios/{commands,.claude-plugin}

cp ~/aios/plugins/aios/commands/*.md \
  ~/.claude/plugins/marketplaces/the-aios/plugins/aios/commands/

cp ~/aios/.claude-plugin/marketplace.json \
  ~/.claude/plugins/marketplaces/the-aios/.claude-plugin/marketplace.json

cp ~/aios/plugins/aios/.claude-plugin/plugin.json \
  ~/.claude/plugins/marketplaces/the-aios/plugins/aios/.claude-plugin/plugin.json

claude plugin marketplace add ~/.claude/plugins/marketplaces/the-aios/
claude plugin install aios@the-aios
```

Add `"aios@the-aios": true` to `enabledPlugins` in `~/.claude/settings.json`.

### 7. Calendar folder

```bash
mkdir -p ~/aios/vault/01\ -\ calendar/$(date +%Y-%m)
```

### 8. Create your private repo and switch remote

Your vault should live in your own private repo — not the shared team repo. Claude does this automatically during setup. Manual:

```bash
cd ~/aios
gh repo create {your-username}/aios --private --source=. --push
```

> **Naming:** `{username}/aios` matches the local path `~/aios/` and the framework brand. Alternatives if you prefer: `{username}/vault`, `{username}/my-aios`, or anything else — Claude defaults to `{username}/aios` unless you say otherwise.

This creates a private GitHub repo, sets it as your remote, and pushes. From here on, your content never goes back to the AIOS framework. `/aios:update` pulls AIOS framework updates from `The-AIOS/aios`; `/company` pulls company venture-context from each mounted company's repo — but you push only to your private personal vault.

### 9. Spawn wrapper (cross-platform — recommended)

The bundled `spawn` shell function lets you open a named worker session with one command — e.g. `spawn accountant "review last quarter's P&L"` — and survives Anthropic-account rate-limit swaps without losing the terminal. Install via the canonical script for your platform:

**macOS / Linux:**
```bash
bash ~/aios/hooks/claude-identity/install-wrappers.sh
source ~/.zshrc   # or ~/.bashrc
```

**Windows (PowerShell):**
```powershell
pwsh -File ~\aios\hooks\claude-identity\install-wrappers.ps1
. $PROFILE
```

Both installers are **idempotent** — timestamped backup → strip prior wrapper block → append canonical version → content-verify → auto-rollback on failure. Safe to re-run; if your wrapper is already current, re-running is a no-op.

What gets installed:
- `_claude_with_respawn` / `Invoke-ClaudeWithRespawn` — auto-respawn loop with 3-strike circuit-breaker (kills the silent-session-loss bug during account swaps)
- `spawn` — named worker opener that detects your environment (IDE tab on macOS, Windows Terminal tab on Windows, Terminal.app fallback)

After install, run `spawn SESSION_NAME [TASK]` from any Claude Code session.

### 10. Wire the universal hooks (required — runs every operator)

Two hooks every operator needs, regardless of OS or account count. Add them to `~/.claude/settings.json` (Claude does this for you during setup — shown here for transparency):

**Hook A — `inject-datetime` UserPromptSubmit hook** (eliminates the "Claude infers wrong weekday/time from conversation" failure mode). Adds a `<system-time>` block to every user prompt so Claude reads the real clock.

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "bash ~/aios/hooks/inject-datetime.sh" }
        ]
      }
    ]
  }
}
```

Windows operators use `pwsh -File "$HOME\aios\hooks\inject-datetime.ps1"` instead.

**Hook B — `claude-identity` statusLine** (writes the rate-limit cache on every Claude turn — feeds the fast-path quota detector used by the autopilot in §11, and powers the context-monitor status display). Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash -c 'tee >($HOME/aios/hooks/claude-identity/claude-identity.sh cache > /dev/null) | python3 $HOME/aios/hooks/claude-identity/context-monitor.py'"
  }
}
```

**Verify both fired:** open a fresh Claude Code session, type *"what's today's date?"* — Claude should reply with the actual current date (proves the UserPromptSubmit hook ran). Check the statusLine at the bottom of the terminal — it should show context usage + quota state (proves the statusLine command ran).

If either hook silently failed: re-read the settings.json and confirm the `hooks.UserPromptSubmit` array + `statusLine.command` are exactly as above. Common gotcha: an existing settings.json with `hooks: {}` empty object — merge the array in, don't replace the empty value at the wrong nesting level.

### 11. Quota autopilot — split: install now, capture later (macOS only, ≥ 2 accounts)

**Why this is split.** The autopilot has two install phases. The first is file-system-only (drop the plist, load the launchd agent) — safe to do during setup. The second is the **account-capture dance** (login → capture identity → logout → switch → repeat) — that one cycles Claude's auth, and running it during setup would interrupt the very session that's setting things up. So we ALWAYS defer capture to the operator's first `/today`, where it's a deliberate task with no other in-flight work to disrupt.

**During setup, ask the operator one question:**

> *"Do you use (or plan to use) more than one Anthropic account to manage the 5h/7d rate limits? (yes / no — single account)"*

- **If no** → skip the rest of §11 entirely. The spawn wrapper (§9) + universal hooks (§10) still work — they're not multi-account-dependent.

- **If yes** → install the file-system pieces now, defer the capture:

  ```bash
  # File-system install (safe to run during setup):
  cp ~/aios/hooks/claude-identity/com.aios.claude-quota-watch.plist ~/Library/LaunchAgents/
  launchctl load ~/Library/LaunchAgents/com.aios.claude-quota-watch.plist

  # Verify the agent loaded:
  launchctl list | grep com.aios.claude-quota-watch
  ```

  Then **mark the capture as pending** so the first `/today` surfaces it as a task:

  ```bash
  # Marker file — /today checks for this and surfaces a setup task when present.
  # Removed automatically once capture completes (see hooks/claude-identity/README.md § Setup).
  mkdir -p ~/aios/vault
  touch ~/aios/vault/.pending-quota-autopilot-capture
  ```

  Tell the operator:

  > *"The agent is installed and watching. The account-capture step (login + Keychain identity capture per account) will run during your first `/today` — it's a deliberate task there so we don't interrupt this setup session. When that task fires, just say yes and I'll walk you through the per-account login dance safely, then swap back to your primary."*

**The full capture walkthrough** is at `hooks/claude-identity/README.md` → `## Setup` — 7 interactive steps: configure accounts in USER.md, capture identities, verify cache writes, run a swap dry-run. That walkthrough is what fires from `/today` when the marker is present.

Hard preconditions:
- **macOS only.** Uses Keychain Services and launchd. On Linux/Windows the autopilot stays dormant; the spawn wrapper + universal hooks still work on all platforms.
- **≥ 2 Anthropic accounts.** A single-account setup gets no value — skip this section entirely.

### 12. Advanced — two-machine architecture (optional, power users)

If you want **24/7 autonomous agents** running overnight or while you're away — a Mac mini as always-on agent host alongside your MacBook as day-to-day driver — see [`FORTRESS.md`](./FORTRESS.md). That doc walks both machines through:

- **Network isolation** — agent host firewalled, no public ingress
- **SSH hardening** — key-only access, mesh routing via Tailscale
- **One-way data flow** — main reads from mini, mini never writes back to main's identity
- **Permission gates** — granular per-tool auth at the agent layer
- **Recovery mechanisms** — backup paths if either machine is compromised

Claude reads `FORTRESS.md` end-to-end and configures both machines. Hard preconditions: macOS on both, Mac mini on AC power with stable network, willingness to keep the secondary machine on 24/7. Skip if you don't need 24/7 agents — the spawn wrapper (§9) + autopilot (§11) handle the single-machine case beautifully.

---

## After Setup

### 1. Open Obsidian

Add the vault folder: `~/aios/vault` (Obsidian → Open another vault → Open folder as vault)

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

Fill in your declared context. Templates for all files are in `templates/`.

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
2. Create `about_venture.md` inside it (use `templates/aios/about_venture-template.md`)
3. Add deep-dive files as needed (positioning, personas, pricing, GTM)
4. Update `about_business.md` with a summary entry pointing to the venture folder

### 4. Create your projects

Each project is a note in `vault/00 - notes/projects/`. Ask Claude: *"Create a project note for [name]"* or copy from `templates/aios/project-template.md`. Projects bridge your external tools (GitHub, Monday, Google Tasks) to your daily plan.

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

### The aios plugin

24 slash commands that read your vault and generate plans, insights, and content.

Run them via: `/aios:<command-name>`

| Cadence | Commands |
|---------|----------|
| Daily | `today`, `close-day`, `close-session` |
| Weekly | `7plan`, `drift`, `weekly-learnings` |
| Bi-weekly | `graduate`, `emerge` |
| Monthly | `compact`, `housekeeping` (mid-month, or when triggers fire) |
| As needed | `ideas`, `ghost`, `challenge`, `trace`, `connect`, `learned`, `role-report`, `company` (multi-company mount/sync), `update`, `agent`, `cold-start-interview` (first-run only) |

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
→ If still missing: `claude plugin marketplace add` + `claude plugin install aios@the-aios`.

**Obsidian MCP not connecting**
→ `claude mcp list` to verify. Re-run the add command if missing.

**Commands writing to wrong folder**
→ MCP path must point to `~/aios/vault` (the vault directory), not `~/aios` (the repo root).

**Edited a command but change isn't showing**
→ Sync to cache: `claude plugin update aios@the-aios`
