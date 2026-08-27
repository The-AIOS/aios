# Setup Guide — AI-OS Vault

Get the full system running in under 10 minutes (after the prereqs install).

<details>
<summary><strong>📍 Reading this as Claude?</strong> (Operator said "set up my AI-OS" — click for your execution sequence)</summary>

<!-- Deliberately NOT "the N-step sequence". The count was 11, then two necessary steps were added
     (write the update tracker, register the plugin) and it became 13 — while this line, README.md
     and the AIOS App's own handover prompt all went on saying 11. A setup session noticed the
     mismatch and had to decide which to believe. A number repeated across three files, two of
     them in a different repo, is a number that drifts; the list below is the source of truth and
     it counts itself. -->

Operator said *"set up my AI-OS from this repo"* or similar. You're the executor. The flow:

1. Confirm Prerequisites are installed — Obsidian + Node/Git/gh/Python/uv/Claude Code, **plus ONE execution surface**: the **AIOS App** *or* Antigravity IDE/VS Code with AIOS Glass. If the operator reached you from the AIOS App, that surface is already satisfied — do **not** send them to install an IDE or Glass. If anything else is missing, walk the OS-specific block from "Prerequisites" §
2. Clone to `~/aios` (default) and create private GitHub repo `{username}/aios` (or whatever the operator names it) — see "The Setup" §1 below
3. Register bundled skills: `bash skills/setup.sh` (Windows: `pwsh skills/setup.ps1`) — symlinks AIOS skills into `~/.claude/skills` so Claude Code loads them (restart sessions after) · **Do not register the Obsidian MCP here.** `/aios:cold-start-interview`'s Pre-step registers it silently, and it has to: an operator who arrived through the **AIOS App** reaches the interview without ever passing through this list, so the interview is the only place that covers both doors. Registering it here as well gave the command two owners with two different arguments (this copy hardcoded `~/aios/vault`; the interview uses the resolved install path) — and because the interview's registration is guarded by *"skip if already registered"*, whichever copy ran first won permanently, including when it was the wrong one.
   > **Do NOT run `bash mcps/setup.sh` here.** With no arguments it installs all ten bundled MCPs — multiple Chrome-for-Testing downloads, several venvs, minutes of output in which a long download is indistinguishable from a hang and one failure reads as a crash. None of it is needed to use the vault. Slack, Atlassian, Google, image generation and the rest are convenience, installed WHEN the operator says they want one — which is what the interview's Step 11 asks, after the first `/today`. `bash mcps/setup.sh <name>` installs just that one, `--list` shows what exists.
4. **Write the update tracker** — one command, and setup must not end without it:
   ```bash
   printf 'repo=git@github.com:The-AIOS/aios.git\nhash=%s\nsynced=%s\n' \
     "$(git -C ~/aios rev-parse HEAD)" "$(date +%F)" > ~/aios/.aios-update
   ```
   > **Why this is not optional.** `.aios-update` is what tells the operator the framework has moved on. Until now it was only ever written by `/aios:update` — which a fresh setup never runs — so every newcomer finished setup with the update surface reporting *"no config"* / *"not tracked yet"*, `/today` unable to notice a canonical release, and no way to know they were behind except by being told. A brand-new install is exactly the moment we know the hash for certain, so record it then. `repo=` is the FRAMEWORK upstream, deliberately not the operator's own vault remote: the question it answers is "has the framework moved", not "have I pushed". Confirm afterwards with `cat ~/aios/.aios-update` — the hash must be a real 40-character commit, since a placeholder reads as "you are behind" forever.
5. **Register the AIOS plugin** — `claude plugin marketplace add ~/aios && claude plugin install aios@the-aios`. This was missing from this list, and `/aios:today` cannot exist without it: the rituals ARE the plugin's commands, so a setup that skips this ends with an operator whose first instruction fails.
6. **Do NOT invoke `/aios:mcps-setup` here.** This step used to, and it is the single biggest source of
   first-run friction on the terminal path: it fires the connector questions — *"Slack workspace? Gmail?
   GitHub username?"* — **four steps before the operator has seen anything work.** A newcomer asked which
   services they use, before they know what any of them are for, freezes; and the operator who came
   through the AIOS App meets the same wall from a different direction. Connectors are now owned by
   `/aios:cold-start-interview` **Step 11**, which runs them immediately after the first `/today`, when
   the operator has just watched their own calendar come up empty and the question answers itself. One
   service at a time, only the ones they want. Nothing is lost by waiting; the offer is stronger.
7. Install the **spawn wrapper** — `bash ~/aios/hooks/claude-identity/install-wrappers.sh` (or `.ps1` on Windows), then re-source the shell rc
   > **The interview runs this a second time, on purpose — do not "deduplicate" it.** The installer reads `USER.md` to detect which session names are primary, and `USER.md` does not exist yet at this point in the sequence; the interview writes it at its Step 1 and re-runs the installer immediately after. This run gives the operator a working `spawn` during setup; that run makes it identity-aware. The script is idempotent (timestamped backup → strip prior banner → append fresh), so running it twice is free — and unlike the Obsidian registration above, neither run is redundant.
8. Wire the **universal hooks** to `~/.claude/settings.json`: `UserPromptSubmit` → `inject-datetime` (real clock in every prompt) + `statusLine` → `claude-identity.sh cache | context-monitor.py` (rate-limit cache writer + context display). See §10 below for exact JSON.
9. **Do NOT ask the multi-account question here.** It used to live at this step (*"Do you use more than
   one Anthropic account?"*, plus a launchd install). On day one the operator has not hit a 5h/7d cap, so
   the question has no meaning yet and cannot be answered — it is the most expert-coded moment in the
   whole flow. `/aios:cold-start-interview` **Step 10** now schedules it into the Day-7 check-in,
   conditional on the caps having actually bitten. It is the one deferral whose need genuinely takes a
   week to appear, which is exactly why it is deferred by a *week* rather than by an hour.
10. **Personalize — and this is where setup ends and the conversation begins:** invoke
    `/aios:cold-start-interview`. It offers the operator a **~5-minute Core** path (identity, declared
    context, a light INTENT, then their first `/today`) or the **full tour**, and it runs **Steps 0
    through 11** — Step 10 fires the first `/aios:today`, Step 11 then offers connectors in the same
    conversation. **Do not run `/aios:today` yourself afterwards; the interview owns it.** Running it
    twice makes the proof point land as a repeat.
    > **Offer choices, not a blank page.** Wherever a question has recognisable answers — role, industry, how they work, which bundles — present them as a short numbered list with a final *"none of these / let me describe it"* option, rather than asking them to compose prose. An operator meeting the system for the first time does not yet know the vocabulary it wants, and a blank prompt asks them to guess it. Free text stays available for everything a list would flatten.
11. **Do NOT invoke `/agent onboarding-aios` here.** The interview already owns this as its **Depth Step 9**, and by the time control returns to this list the interview has *closed* — it ends on *"Welcome to The AIOS."* after the connectors step. Firing the orientation companion after that goodbye is the third false ending this sequence has had, and it lands worst on the operator who chose the ~5-minute start: they said "quick", were given a clean finish, and then got handed two more things. Route to it **only** if the operator seems lost, which the note at the foot of this block already covers.
12. **Do NOT invoke `/aios:company` or `/aios:collaborate` here either.** Interview **Depth Step 5** presents both and *deliberately defers setup* — *"we'll skip setup now; both deserve their own beats post-cold-start"*. Running them here overrides that decision one step later, in the same session, which is the opposite of deferring. The operator asks for them when they want them; the interview's closing message tells them how.
13. ~~First `/aios:today`~~ — **the interview runs it** (its Step 10), then continues into connectors (Step 11). Setup is complete when the interview is. Kept as a numbered line so the change is visible rather than silently absorbed.

> ⚠️ **Two copies of this sequence exist in this file** — the Claude-facing block above and the operator-facing "The Setup" section below. They just drifted: the connectors step and the interview's duration were corrected in one and not the other, so a first-timer read a promise the executor no longer made. **Change both, or change neither.** They cannot be merged — one is instructions to execute, the other is a human reading what is about to happen to them — but they answer the same questions and must not disagree.

**Defaults to pick without asking** (unless operator overrides): vault path = `~/aios/`, private repo name = `{username}/aios`, substrate for company = GitHub, wrappers + hooks A+B always install (no opt-out — they're load-bearing). **Always ask, never assume**: anything that writes the operator's own words or commits them to a choice only they can make. **Deliberately NOT on this list any more:** Google email, task sources (Slack / GitHub / Linear / Monday), per-connector installs, and the multi-account-Anthropic question. Those are not assumptions to make — they are questions asked at the **wrong time**, and this list was what mandated asking them during setup. Every one of them now has a named owner later in the flow (interview Step 11 for connectors, the Day-7 check-in for multi-account), so asking here is not thoroughness, it is duplication that costs a newcomer their confidence. Show diffs before writing to `USER.md` / `INTENT.md` / `vault/00 - notes/context/declared/*` / `~/.claude/settings.json`.

**Be gentle, not exhaustive.** The operator should feel walked by the hand, not interrogated. One question at a time, sensible defaults, defer anything that risks interrupting the in-flight session (account capture is the canonical example — always deferred).

> **Where this sequence actually ends.** Step 10 hands control to `/aios:cold-start-interview` and **does not get it back**: the interview runs its own Steps 0-11, fires the first `/today`, offers connectors, and closes. Steps 11-13 above are retired *because* of that — every one of them was something that fired after the operator had already been told they were done. When the interview closes, setup is over. Do not add a coda.

**If operator gets lost mid-setup:** route to `/agent onboarding-aios` — that agent knows the full doc map.

</details>

---

> **New here? Read top-to-bottom.** Prerequisites first (install Claude Code + the toolchain), then The Setup (Claude-Driven) runs the framework install.
>
> **Already have Claude Code installed?** Skip to [The Setup (Claude-Driven)](#the-setup-claude-driven).

---

## Prerequisites

Pick your OS path. Each installs the same toolchain (Node, Git, GitHub CLI, Python, uv, Obsidian, Claude Code CLI) plus one execution surface. After this section the Claude-driven flow is OS-agnostic.

> **Already have Claude Code CLI working?** Skip ahead to **[The Setup](#the-setup-claude-driven)** above.

### The two things you'll use daily

The AIOS is *one filesystem, two surfaces*: somewhere to **read and think**, and somewhere to **execute and ship**.

| What | Role | Why it earns its place |
|---|---|---|
| **[Obsidian](https://obsidian.md/)** — **required on every path** | *Reading and thinking* | Beautiful read of your vault — daily notes, project notes, observed context, reflections. Wikilinks resolve, graph view shows connections, the markdown structure compounds visually. It is also what the bundled Obsidian MCP talks to, so it is not a preference. |
| **[AIOS App](https://github.com/The-AIOS/aios-app/releases)** — *pick this **or** the IDE* | *Executing, the simplest way* | The AIOS as a normal desktop app — macOS, Windows and Linux: rituals, agents, sessions, terminals and your vault in one window, point-and-click. **No IDE and no extension** — it is its own glass layer, so skip the Antigravity and AIOS Glass steps below entirely. |
| **[Antigravity IDE](https://antigravity.google/product/antigravity-ide) + AIOS Glass** — *pick this **or** the app* | *Executing, beside a real editor* | Bundles Claude Code natively — agents run in IDE terminals (one per spawn), file edits and git ops feel native. Choose this if you also write code. VS Code works as the alternative; Antigravity is just batteries-included. Then add Glass (below). |

**Pick ONE execution surface.** Both drive the same vault through the same Claude Code, so this is a preference, not a fork — and you can add the other later without redoing anything.

Run your two side-by-side: Obsidian on the left for context, your execution surface on the right. Same vault, both windows.

> **If you chose the IDE, add the glass layer — for that path it is core, not an optional extra.** (On the **AIOS App** path, skip this whole note: the app already *is* this surface.) **AIOS Glass** is a docked panel inside Antigravity that turns the AIOS into a *point-and-click* surface — run rituals, launch agents, browse skills/commands, mount companies, manage spaces, all without typing terminal commands. *Glass, not engine:* it just triggers your existing AIOS through Claude. It's the front door for everyone, and the difference between using the AIOS and bouncing off the terminal for anyone who isn't terminal-native.
>
> **Install it once the AIOS is set up** (it surfaces what's already there — so it comes after, but on the IDE path it is a required part of the setup, not a "maybe later"): Extensions view (`⌘⇧X`/`Ctrl+Shift+X`) → search **"AIOS Glass"** → **Install** (auto-installs the **Foam** dependency + auto-updates) → reload → **click the `AIOS Glass` item in the bottom status bar to open it**, then move it to the secondary side bar. Works in any Open VSX editor (Antigravity / VSCodium / Cursor / Windsurf). On **stock Microsoft VS Code**, sideload the `.vsix` from the [latest release](https://github.com/The-AIOS/aios-glass/releases). Full walkthrough: [`START-HERE.md`](./START-HERE.md) → *Step 4* + the [aios-glass INSTALL.md](https://github.com/The-AIOS/aios-glass/blob/main/INSTALL.md).

### macOS (~5 min)

```bash
# 1. Homebrew (skip if you have it)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Toolchain
brew install node git gh python uv

# 3. Obsidian — required on every path (it is also what the Obsidian MCP talks to)
brew install --cask obsidian

# 4. ONE execution surface — pick a) or b), not both (see "The two things you'll use daily")
# a) AIOS App — simplest: download the macOS .dmg from https://github.com/The-AIOS/aios-app/releases
#    and drag it to Applications. Nothing else; skip the Glass step later.
#    (Windows and Linux have their own artifacts on the same releases page — see those sections.)
# b) Antigravity IDE — download from https://antigravity.google/product/antigravity-ide
#    (no brew cask yet — drag the .dmg to Applications), then install AIOS Glass.

# 5. Claude Code CLI — native installer (self-contained binary, no npm, no optional deps)
curl -fsSL https://claude.ai/install.sh | bash
#    Then OPEN A NEW TERMINAL — the installer writes PATH into your shell rc.

# 6. Verify before moving on — this must print a version number, not an error
claude --version

# 7. Auth (each opens a browser tab)
gh auth login
claude
```

> **Why the native installer and not `npm install -g`.** The npm route exits **green** while leaving a broken command when npm runs with `--omit=optional` or `--ignore-scripts` — which some pnpm setups and corporate `.npmrc` files do without telling you. You get the JS wrapper and no native engine: `claude` then fails with *"native binary not installed"*. Worse, the remedy that error suggests assumes a *local* install, so following it on a global install fails too, and the postinstall it eventually runs cannot help — the platform package was never downloaded. The native installer has no optional dependencies, so **that failure mode is gone by construction rather than by documentation**. Step 6 exists so a failure surfaces at the step that caused it, not three steps later.

### Windows (~15-20 min)

**Workflow target:** Antigravity IDE (Claude Code bundled — recommended) + Obsidian open side-by-side. VS Code works as an alternative IDE. **Avoid** plain `cmd` and Obsidian terminal plugins (polyipseity is unreliable on Windows).

```powershell
# Open PowerShell (not cmd). Run as your user — only escalate if winget refuses.

# 1. Toolchain via winget (preferred — avoids GUI installer pitfalls)
winget install OpenJS.NodeJS.LTS
winget install Git.Git
winget install GitHub.cli
winget install Python.Python.3.12

# 2. Obsidian + your execution surface (see "The two things you'll use daily" above).
#    Either surface works on Windows — the AIOS App ships a Windows installer (v0.8.3+).
winget install Obsidian.Obsidian
# For the AIOS App (simplest — no IDE, no extension): download the Windows installer from
#   https://github.com/The-AIOS/aios-app/releases  — then skip the Antigravity and Glass steps.
#   SmartScreen warns on first run (unsigned): "More info" -> "Run anyway". It does not block.
# For Antigravity IDE (recommended — Claude Code bundled): download from https://antigravity.google/product/antigravity-ide
# For VS Code as the IDE alternative: winget install Microsoft.VisualStudioCode

# 3. uv (Python package runner — vendored MCPs need it)
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"

# 4. Allow PowerShell to run scripts (one-time, still required — npx-based MCPs need it)
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned    # type Y at the prompt

# 5. CLOSE this PowerShell, open a fresh one (PATH only refreshes on new shells)

# 6. Claude Code CLI — Windows uses the PowerShell installer, NOT the bash one
powershell -ExecutionPolicy ByPass -c "irm https://claude.ai/install.ps1 | iex"
#    Downloads the native claude.exe (win32-x64 or win32-arm64) and registers the launcher.
#    Then CLOSE this PowerShell and open a fresh one again.

# 7. Verify before moving on — this must print a version number, not an error
claude --version

# 8. Auth
gh auth login
claude
```

> **Windows takes `install.ps1`, and the bash installer is not an alternative here.** `install.sh` **refuses to run on Windows outright** — it detects `MINGW*/MSYS*/CYGWIN*` and exits 1 with *"Windows is not supported by this script"* — so `curl … | bash` in Git Bash will not work, and reaching for it is a dead end rather than a slow path. `install.ps1` is the Windows equivalent: it picks the right architecture, downloads `claude.exe`, and runs `claude install` to register the launcher and shell integration. Requires 64-bit PowerShell (the script checks and refuses a 32-bit process).

**If `node --version` says "not recognized" after step 1:** PATH didn't take. Fix via GUI — `Win+R` → `sysdm.cpl` → Advanced → Environment Variables → System variables → Path → Edit → New → add `C:\Program Files\nodejs` AND `%AppData%\npm`. Close all shells, open a fresh one. See [Known Gotchas](#known-gotchas) for more.

### Linux (Ubuntu/Debian, ~5 min)

```bash
# 1. Toolchain
sudo apt update
sudo apt install -y nodejs npm git gh python3 python3-pip

# 2. uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# 3. Claude Code CLI — native installer. NO sudo: the installer refuses it on purpose,
#    because a root-owned binary in /root/.local/bin is not on your PATH.
curl -fsSL https://claude.ai/install.sh | bash
#    Then OPEN A NEW TERMINAL — the installer writes PATH into your shell rc.

# 4. Verify before moving on — this must print a version number, not an error
claude --version

# 5. Obsidian + your execution surface (see "The two things you'll use daily" above).
#    Either surface works on Linux — the AIOS App ships a Linux build (v0.8.2+).
# AIOS App (simplest — no IDE, no extension): grab the Linux artifact from
#   https://github.com/The-AIOS/aios-app/releases — then skip the Antigravity and Glass steps.
# Obsidian — download the AppImage from https://obsidian.md/download
# Antigravity IDE (recommended, Claude Code bundled) — https://antigravity.google/product/antigravity-ide
#   or VS Code as the alternative: sudo snap install code --classic

# 6. Auth
gh auth login
claude
```

> **Do not prefix step 3 with `sudo`** (the old instruction did, via `npm -g`). The installer **refuses to run under sudo from a user shell** and says why: the binary would land in `/root/.local/bin`, owned by root, and `claude` would then not be found in your own shell. It also detects musl and picks the right build. On a distro whose `nodejs`/`npm` packages you only installed for Claude Code, step 1 can now drop them — they are still used by npx-based MCPs, so keep them if you plan to run those.

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
2. **The one connector the vault itself needs** is an Obsidian bridge, so Claude can read and write your notes directly. It is a published npm package with no account and no token, so nothing is asked of you and nothing appears in the connector list later — it is registered silently during the interview's opening moments. You will not see this step happen, which is the intent.
3. **Connectors come later, on purpose.** Calendar, Slack, GitHub and the rest are offered by the interview's **Step 11**, right after your first `/today` — when you have just seen your day come up empty and connecting it means something. One service at a time, only the ones you want: it opens the right page, you approve, it checks the connection worked, and you never handle a token. The other nine bundled connectors are convenience rather than prerequisites — `/aios:mcps-setup` adds any of them whenever you like.
4. **Personalize via `/aios:cold-start-interview`** — a guided conversation, not a form. It opens by offering you a **~5-minute start** (who you are, how you work, what you're happy for it to do without asking, then your first `/today`) or the **full tour** (the same start plus your agent team, companies, plugins and the app). Either way nothing is withheld — the tour is one sentence away at any point, including a month from now. This is where the vault becomes *yours*.
5. **Spawn the onboarding companion**: `/agent onboarding-aios` — wears the AIOS-orientation hat. Knows the whole map: org profile, README, SETUP, CHEATSHEET, FORTRESS, START-HERE, USER.md personalization power, the self-update loop, where to look when lost. Invoke anytime later by saying *"I'm lost"* / *"what should I try next"* / *"remind me how this fits together"*.
6. **(Optional) Mount or create a company** via `/aios:company` — if you have a venture-context repo or want to scaffold one (GitHub recommended ✅, see the command's substrate selector)
7. **(Optional) Set up a collaboration space** via `/aios:collaborate` — if you have a known shared space (Drive folder, GitHub repo, local sync folder) to mount or scaffold
8. **Your first `/aios:today` — run by the interview, not separately.** It reads everything you just told it and proposes a plan for the rest of your day. Expect some sections to be empty at first: the calendar and tasks are not connected yet, and connecting them is the step immediately after. From there the daily ritual takes over.

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

**Auto-detect** — Claude runs this at SETUP §1 and again at the top of `/aios:cold-start-interview`. **Both runs are needed and neither is redundant:** the setup sequence needs the path resolved before its own later steps reference `~/aios/...`, and an operator who arrived through the **AIOS App** never runs that sequence, so the interview is their only pass. The second run is **silent when there is nothing to do** — it speaks only if `~/aios` exists and points somewhere else, which is the one case a human has to decide.

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

**Registered for you, once, by `/aios:cold-start-interview`'s Pre-step** — silently, with the resolved install path, and skipped if it is already there. The command is documented here for reference and for the rare manual repair; it is **not** a step to run during setup, and running it by hand with a different path is how the vault ends up bridged to a directory that does not exist:

```bash
claude mcp add obsidian -- npx -y @mauricio.wolff/mcp-obsidian@latest ~/aios/vault
```

### 2. Google Workspace MCP (optional but recommended)

Enables Google Calendar, Tasks, Drive, Docs, Sheets, Slides, Gmail, Contacts and Forms.

**First, create your own OAuth client.** OAuth credentials are per-person secrets, so the repo cannot ship them — it ships a template and gitignores the filled-in file. Follow [`mcps/google-workspace-mcp/personal-account-setup.md`](./mcps/google-workspace-mcp/personal-account-setup.md) (steps 0–4) to create a **Desktop app** OAuth client in Google Cloud Console, then:

```bash
cd ~/aios
cp mcps/google-workspace-mcp/oauth.json.template mcps/google-workspace-mcp/oauth.json
# edit oauth.json — paste your client_id + client_secret (the file is gitignored)
```

**Then register the server.** The server itself is installed on demand from PyPI by `uvx` — nothing to build, and you stay current with upstream (which ships frequently):

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
  -- uvx workspace-mcp --single-user --permissions \
  drive:full sheets:full slides:full docs:full calendar:full tasks:full \
  gmail:full contacts:full forms:full
```

On first use, Claude opens a browser for Google OAuth consent.

> **Enable one Google API per service you list.** The permission list above spans nine services, so your Cloud project needs the matching nine APIs enabled — the core seven (Drive, Docs, Sheets, Slides, Calendar, Tasks, Gmail) **plus People API for `contacts` and Forms API for `forms`** (and Chat API if you add `chat`). A mismatch fails *late*: consent succeeds, the tool appears, then the call returns `403 SERVICE_DISABLED`, which looks like an auth failure and isn't. The error text includes a one-click activation URL. Enabling an API is a project setting, so no re-consent is needed. If you'd rather not enable the extras, drop `contacts:full` / `forms:full` from the list instead — an unused service costs nothing, but a listed-and-unenabled one produces a confusing error the first time you touch it.

> **Register it once, from your vault.** `claude mcp add` defaults to **local** scope, which is *per-directory* — the registration only applies to sessions started in that directory. Run it from `~/aios` and that covers vault sessions, which is where this MCP is used. Adding it again from another directory creates a **second, independent copy that silently drifts** (two registrations diverged exactly this way — one grew Gmail, the other didn't, and neither surface said so). If you genuinely want it everywhere, use one `--scope user` registration instead of several local ones.
>
> **Google Chat is supported but off by default.** The upstream server ships Chat tools (list spaces, read/search/send messages, reactions, attachments); this permission list omits them. To enable, add `chat:full` (or `chat:readonly`) — it requests **new OAuth scopes, so it triggers a fresh consent prompt**. Note that Google restricts *sending* to some space types when using user credentials rather than an app, so verify sending against your own spaces before relying on it.

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

Register the marketplace **pointing at your vault** (`~/aios`), then install the bundled plugin:

```bash
claude plugin marketplace add ~/aios
claude plugin install aios@the-aios
```

Add `"aios@the-aios": true` to `enabledPlugins` in `~/.claude/settings.json`.

> **Point at the vault — never a hand-built copy.** `claude plugin marketplace add` copies *selectively*: only `.claude-plugin/marketplace.json` + the plugin folders its entries reference (~540K), **not** the multi-GB vault — so pointing at `~/aios` is safe. This is load-bearing: the vault's `marketplace.json` is your **single, growing catalog** across all three plugin layers — bundled `aios` now, plus any **custom** plugins you build (`plugins/custom/…`) or **venture** plugins you mount later (`/aios:company` → `plugins/{company}/…`). Each new plugin registers itself in that one `marketplace.json`, and `claude plugin marketplace update the-aios` + `claude plugin install <name>@the-aios` makes it loadable — no SETUP redo.
>
> **Do NOT** hand-copy a frozen `~/.claude/plugins/marketplaces/the-aios/` and register *that* (the old approach): a static copy never tracks the vault, so it froze every operator's catalog at setup-time — aios-only and version-locked — and silently missed every custom/venture plugin + every version bump. (See CHANGELOG 2026-06-24.)

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

Three hooks every operator needs, regardless of OS or account count. Add them to `~/.claude/settings.json` (Claude does this for you during setup — shown here for transparency):

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

**Hook C — `guard-venture-mount` PreToolUse hook** (blocks direct edits to company-context **mounts**). Files under `vault/00 - notes/context/ventures/{v}/` that carry a `.{v}-sync` marker are synced copies of a `{v}-context` source repo — editing them in the vault is silently reverted on the next `/aios:company --sync` and never reaches the source. This hook stops that at the moment of edit and points you at the source repo. Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit|NotebookEdit",
        "hooks": [
          { "type": "command", "command": "python3 ~/aios/hooks/guard-venture-mount.py", "timeout": 10 }
        ]
      }
    ]
  }
}
```

Merge `PreToolUse` alongside your existing `UserPromptSubmit` array — don't replace the `hooks` object. Windows operators use `python` (not `python3`). Design: **fail-open** (any error, or a `ventures/` folder with no `.{v}-sync` marker, → allows — it can never brick editing), **deterministic**, and reversible via `AIOS_ALLOW_MOUNT_EDIT=1` to intentionally edit a mount. Only operators with company mounts (`/aios:company`) will ever see it fire; for everyone else it's a silent no-op.

**Verify hooks A + B fired:** open a fresh Claude Code session, type *"what's today's date?"* — Claude should reply with the actual current date (proves the UserPromptSubmit hook ran). Check the statusLine at the bottom of the terminal — it should show context usage + quota state (proves the statusLine command ran).

**Verify Hook C fired:** ask Claude to edit any `vault/00 - notes/context/ventures/{v}/*.md` file — it should refuse and point you at the `{v}-context` source repo. (No company mounts yet? Skip — there's nothing for it to guard until you `/aios:company --mount`.) Requires a session restart after wiring, since PreToolUse registration loads at session start.

If either hook silently failed: re-read the settings.json and confirm the `hooks.UserPromptSubmit` array + `statusLine.command` are exactly as above. Common gotcha: an existing settings.json with `hooks: {}` empty object — merge the array in, don't replace the empty value at the wrong nesting level.

### 11. Quota autopilot — split: install now, capture later (macOS + Linux, ≥ 2 accounts)

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
- **macOS, Linux and Windows.** The credential store and the scheduler are both platform-detected: Keychain + launchd on macOS; on Linux, the plaintext credentials file Claude Code itself writes (mode 600) + a systemd **user** timer; on Windows, that same credentials file + a **Task Scheduler** task registered by `pwsh -File hooks/claude-identity/install-quota-watch.ps1` (no elevation required). The spawn wrapper + universal hooks work on all three regardless.
  > **Windows caveats, both real:** `chmod 600` is a no-op on NTFS, so the credential blob is protected by your user profile's ACL and nothing more — which is also exactly how Claude Code stores it, so this changes nothing, but do not assume file-mode protection. And while `test-identity-cycle.sh` exercises the full capture/switch/rotate cycle against a fabricated config dir on every platform, a live two-account swap on Windows has not been run against real Anthropic credentials. Treat the first real rotation as a verification step, and note `claude-switch` always writes `.claude.json.bak-claude-switch` before touching anything.
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

**Skip on Windows:** Quota autopilot (above) supports macOS and Linux — single-account use works fine on Windows without it.

### macOS

Brew handles dependencies cleanly. One gotcha, and it matters because **two different failures look almost identical from the operator's chair** — this section used to name only the first, which sent people down the wrong path for several rounds:

| Symptom | Which failure | Fix |
|---|---|---|
| `claude: command not found` | **Not on `$PATH`.** The binary exists, your shell can't see it. | Open a new terminal first (the installer writes PATH into your rc). Still missing → add `~/.local/bin` to `$PATH`. |
| `claude` runs but says **`native binary not installed`** | **The binary was never downloaded.** Only reachable via the old `npm install -g` route, when npm ran with `--omit=optional` or `--ignore-scripts`. | Re-install with the native installer: `curl -fsSL https://claude.ai/install.sh \| bash`. Do **not** chase the `install.cjs` command the error suggests — it assumes a local install, and even resolved via `npm root -g` it cannot help, because the platform package is not on disk. |

**The one-line check that separates them** — run it before trying anything else:

```bash
ls -l ~/.local/bin/claude    # or your npm global prefix, if you installed the old way
```

Present but not runnable → a `$PATH` problem. Absent → a download problem. Guessing between the two is what turns a one-minute fix into several rounds, and it costs two people's attention when a non-technical operator is being helped through setup.

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
