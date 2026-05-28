---
tags:
  - aios
  - command
  - onboarding
description: First-touch interview for a freshly-cloned AIOS vault. Walks the new operator through USER.md, declared context, bundle install choices, MCP setup, and optional Anthropic plugins. Run once, immediately after `git clone`.
allowed-tools: mcp__obsidian__*, Read, Write, Edit, Bash(git:*), Bash(gh:*), Bash(npx:*), Bash(claude:*), Bash(ls:*), Bash(cat:*), Bash(stat:*)
argument-hint: "(no arguments — fully interactive)"
---

# /cold-start-interview — First Session After You Clone AIOS

A 15-25 minute interview that turns a freshly-cloned AIOS template into your personalized vault. Walks you through identity (`USER.md`), declared context (`about_me`, `personal_voice`, `working_style`, `INTENT.md`), bundle install choices (which of the 6 agent bundles you need), MCP setup, optional Anthropic plugins, and your first `/today` run.

> **When to run:** immediately after `git clone git@github.com:The-AIOS/aios.git ~/aios` (or equivalent). Run once. If you skip it, the system still works — you'll just spend more time figuring things out yourself.

## When to use

Immediately after the first clone of an AIOS vault — turns the freshly-cloned template into the operator's personalized vault. 15-25 minute interactive interview walking through identity (USER.md), declared context, INTENT.md, bundles, MCPs. Run once; re-runnable to revisit specific sections.


## Detection

The command is safe to run multiple times — it detects what's already configured and skips. But the most useful first invocation is on a vault where:

- `USER.md` still has template placeholders (`{{full name}}`, `{{your-email}}`)
- `vault/00 - notes/context/declared/about_me.md` is the template scaffold (not filled in)
- No daily notes exist yet in `vault/01 - calendar/`
- `agents/custom/_index.md` registry is empty

If all of those are TRUE → fresh vault → run the full interview. If some are filled → ask the operator which sections they want to revisit.

## Steps

### Pre-step — Path portability check (silent, runs before welcome)

Before the welcome message, run this check **once** to ensure the framework's hardcoded `~/aios/` references resolve to the actual install:

```bash
# Resolve the actual repo path (cold-start-interview runs from the cloned repo root)
INSTALL_PATH="$(pwd)"
CANONICAL="$HOME/aios"

if [ "$INSTALL_PATH" = "$CANONICAL" ]; then
  echo "path-portability: already at ~/aios — no action needed"
elif [ -L "$CANONICAL" ] && [ "$(readlink "$CANONICAL")" = "$INSTALL_PATH" ]; then
  echo "path-portability: symlink already points to this install — ok"
elif [ -e "$CANONICAL" ]; then
  echo "path-portability: CONFLICT — ~/aios exists and points elsewhere. Operator must resolve before continuing."
else
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      # Git Bash on Windows: `ln -s` does NOT create a real link — by MSYS default
      # (unless MSYS=winsymlinks:nativestrict is exported) it silently creates a
      # STALE DIRECTORY COPY. The operator then runs the framework against a frozen
      # pre-migration snapshot while the real install drifts ahead — every update
      # appears to land but nothing changes. Caught on a Windows operator 2026-05-26.
      # Fix: create a real Windows directory junction instead of a symlink.
      cmd //c mklink /J "$(cygpath -w "$CANONICAL")" "$(cygpath -w "$INSTALL_PATH")" \
        && echo "path-portability: created ~/aios junction → $INSTALL_PATH" \
        || echo "path-portability: junction failed — use the PowerShell snippet below (run as Developer Mode / elevated)"
      ;;
    *)
      ln -s "$INSTALL_PATH" "$CANONICAL" && echo "path-portability: created ~/aios → $INSTALL_PATH"
      ;;
  esac
fi
```

**On CONFLICT** (the `~/aios` path exists and points elsewhere): surface this to the operator immediately and ask whether to back up the existing path (`mv ~/aios ~/aios.backup-$(date +%Y%m%d)`) or skip the symlink (operator commits to running the framework from a non-default path, knowing some references will need manual translation). **Default: do not auto-resolve conflicts** — operator decides. **On Windows, also flag a stale `~/aios` directory copy** (a non-junction folder that looks like a link but isn't) as a CONFLICT to resolve — `ls ~/aios` showing pre-migration content while the real install moved on is the signature.

**On Windows PowerShell** (where `ln -s` isn't available natively — and as the fallback if the Git Bash junction above fails), use:
```powershell
$Install = (Get-Location).Path
$Canonical = "$HOME\aios"
if ((Test-Path $Canonical) -and -not (Get-Item $Canonical).Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
  Write-Host "path-portability: CONFLICT — $Canonical exists as a real folder"
} elseif (-not (Test-Path $Canonical)) {
  # Try symlink first (needs Developer Mode); fall back to junction
  try { New-Item -ItemType SymbolicLink -Path $Canonical -Target $Install -ErrorAction Stop | Out-Null }
  catch { cmd /c mklink /J "$Canonical" "$Install" }
}
```

After this check passes, proceed to the welcome message below.

---

### Step 0 — Welcome + framing

```
Welcome to The AIOS. The next 15-25 minutes set up your personalized
operating system.

The AIOS turns AI into a team — a legal you, an accountant you,
a marketing you, a software engineer you. By the end of this
interview, you'll have:

  ✓ Your identity + role + voice declared
  ✓ Trust contract (INTENT.md) calibrated
  ✓ Bundles installed for what you actually do
  ✓ MCPs set up for your daily tools
  ✓ Your first /today ready to run

Three progressive stages await:
  1. Automate — Gain speed, do faster (Week 1)
  2. Amplify — Gain bandwidth, do more (Month 1)
  3. Agency — Gain autonomy, do agentic (Quarter 1+)

Ready?
```

WAIT for confirmation before proceeding.

### Step 1 — Identity + USER.md scaffold

Walk through `USER.md` section by section:

1. **Identity table** — ask the operator's primary session name. **Lead with the functional value, not the vibe:** this name becomes a shell shorthand — typing `{name}` in any terminal launches `claude --remote-control --model claude-opus-4-8[1m] --name {name}` with respawn-on-quota-swap. Saves 60+ keystrokes per launch, every time. The fun part (calling your AI "JARVIS") is the bonus, not the point.

   Phrase the question something like: *"What do you want to call your primary session? It becomes a one-word shortcut in your terminal — type that one word, you get a named claude session with all the right flags, ready to work. Default is `claude` or `assistant` (functional, gets the job done). Power users pick something personal — fictional AI names work well: JARVIS, Friday, Samantha, HAL, Cortana, TARS. Short, memorable, yours."*

   **Role string is OS-detected, not hardcoded.** Default the role to a machine-agnostic "Primary session" baseline. Only add OS-specificity ("MacBook primary", "Windows primary", etc.) if the operator explicitly signals a multi-machine setup. Single-machine operators (99% of fresh clones) see clean "Primary session — AI partner" without machine-class jargon.

2. **Anthropic accounts** — ask for primary email AND the multi-account question:

   > *"Quick gentle question — do you use more than one Anthropic account to manage the 5h/7d rate limits? (yes / no — single account)"*

   - **If no** → record primary email only. No autopilot setup needed; skip the quota-autopilot deferred-capture path entirely.
   - **If yes** (macOS only) → record primary + secondary emails in USER.md `## Anthropic accounts`, and **drop the deferred-capture marker** so the first `/today` surfaces it as a task:
     ```bash
     # File-system install (safe to run here — no auth cycling):
     cp ~/aios/hooks/claude-identity/com.aios.claude-quota-watch.plist ~/Library/LaunchAgents/ 2>/dev/null
     launchctl load ~/Library/LaunchAgents/com.aios.claude-quota-watch.plist 2>/dev/null
     mkdir -p ~/aios/vault && touch ~/aios/vault/.pending-quota-autopilot-capture
     ```
     Then tell the operator: *"Got it. I installed the watcher; the per-account login/Keychain capture happens during your first `/today` — running it now would interrupt this session. It'll be a 5-min task there, easy to skip and carry forward if you're not ready."*
   - **If yes but not macOS** → record emails for documentation but note: *"Autopilot is macOS-only (uses Keychain + launchd). On your platform the spawn wrapper still respawns sessions cleanly; you just won't get auto-rotation across accounts."*

3. **Organization → migrated to ## Companies (mounted)** — defer to Step 5 below
4. **Sources → Google accounts** — ask for primary Google email (Calendar + Tasks + Drive + Gmail)
5. **Sources → Communication** — Slack workspace? Gmail? GitHub username?
6. **Sources → Growth routines** — does the operator have a Reading or Writing routine they want to track? Defer; can configure later.

Edit USER.md inline as the operator answers. Show the diff before applying.

**After the Identity table is captured — refresh the wrapper banner.** SETUP.md Step 5 installed shell wrappers BEFORE USER.md was populated, so the primary-session shorthand fell back to the default `claude` function. Now that the operator has chosen their name (e.g. `samantha`), re-run the installer to bind the shorthand to the captured name. **OS-conditional** — pick the right installer for the operator's machine:

```bash
# macOS / Linux (zsh or bash)
bash ~/aios/hooks/claude-identity/install-wrappers.sh
```

```powershell
# Windows (PowerShell)
pwsh -File ~\aios\hooks\claude-identity\install-wrappers.ps1
```

Both installers are idempotent (timestamped backup → strip prior banner → append fresh banner with the new name → verify). Output confirms the detected name: *"✓ Primary session name: {name} (from USER.md)"*. Then tell the operator: *"Wrapper refreshed. Open a new terminal and type `{name}` — that's your shorthand now."* The shell function activates on next shell start; existing terminals can `source ~/.zshrc` (or restart pwsh) to pick it up immediately.

**Rule for this whole step:** one question at a time. The operator should feel walked by the hand, not interrogated. Use sensible defaults. Defer any action that involves cycling Claude's auth (the multi-account capture is the canonical example — always deferred to `/today`).

### Step 2 — Declared context (4 files, fast pass)

**Opening — offer the pre-fill path BEFORE the per-file questions:**

```
Before we walk through the 4 declared files one at a time — got
existing material I can pre-fill these from? Options:

  (a) URL — your personal site, LinkedIn, About page, public bio
  (b) File path — an existing About-Me doc, resume, manifesto
  (c) Paste content directly — anything you have in any format
  (d) None — interview from scratch, one question per file

(For operators with public material, a-then-refine is usually
 5x faster than asking "who are you?" from cold.)
```

If a pre-fill source is provided, Claude fetches it once and uses it to draft EACH of the 4 files (about_me, personal_voice, working_style, about_business). For each file, show the draft + offer (a) accept / (b) edit / (c) ask the original question fresh. **Be honest about source limits** — `working_style.md` rhythm (morning vs evening) is usually NOT in public material; explicitly tell the operator what was inferred vs what needs their input.

If no pre-fill source, ask the 4 questions one at a time:

1. **`about_me.md`** — *"In one paragraph: who are you, what do you do, what are you building?"*
2. **`personal_voice.md`** — *"How would a friend describe how you communicate? (warm / direct / poetic / precise / etc.)"*
3. **`working_style.md`** — *"When do you do your best creative work — morning / afternoon / evening? Any other patterns Claude should know about how you operate?"*
4. **`about_business.md`** (if applicable) — *"Are you building one or more ventures? Brief description of each."*

**Per-file skip option (load-bearing):** every file ask must offer *"or skip + I'll observe and pick it up from our first weeks together"*. This isn't a cop-out for the operator — it's a real backstop. The Tier B observation pass in `/close-day` (introduced 2026-05-23) runs the digest every close-day and proposes updates to declared/observed files when content surfaces from accumulated sessions. Operators who skip declared context at cold-start aren't permanently disadvantaged; they're trusting the observation loop to fill it in.

Skip optional files (`role-expectations.md`, `psychometric-profile.md`) unless the operator asks for them.

**Surface the psychometric-profile graduation step** — say something like: *"There's an optional 6th declared file — `psychometric-profile.md` — that captures assessment-based self-knowledge (MBTI, Strengths, Saboteurs, neurochemistry, etc.). It's the highest-leverage declared file for voice calibration when you have it — even 1-2 free assessments (Saboteurs, Quiggle, online MBTI) + a synthesis paragraph dramatically sharpen how the AI frames work, nudges, and energy. Template is at `templates/aios/psychometric-profile-template.md`. Want to start one now (~5 min for 1 lens), schedule it for a week-2 follow-up, or skip?"* Default to "schedule" — operators rarely have assessments ready at cold-start.

### Step 3 — `INTENT.md` (trust contract)

INTENT.md is the highest-leverage file for compounding trust. Walk through:

1. **Autonomy levels** — for each domain (draft messages, external emails, code commits, content publishing, calendar scheduling, etc.), ask: *"autonomous / draft / ask?"* Defaults are conservative ("draft" everywhere); operator opens up as trust grows.
2. **Just cause** — *"In one sentence: why does your work matter beyond revenue?"*
3. **Focus priorities** — *"The four AIOS pillars are Creation / Amplify / Knowledge / Superhuman. Want to customize the framing?"* Default is fine for most operators.

Don't try to fill out venture-level overrides yet — those come once the operator has mounted at least one company (Step 5).

### Step 4 — Agent bundles (informational — all 6 ship by default)

All 6 bundles ship in the AIOS clone. This step is mental-model setting + signal which bundles are HOT for the operator. **Don't ask the operator to "install" or "demote" anything — those are mechanically vague terms.** Instead, classify each bundle as HOT (with one-line reason matching this operator's declared work) or NOT-YET-HOT (with the value it WOULD bring later as an invitation).

| Bundle | HOT for this operator IF | NOT-YET-HOT framing |
|---|---|---|
| `aios/sales/` | Handles leads, writes proposals, manages a sales pipeline | "value if needed: proposal templates + lead-tracker when you start consulting on the side" |
| `aios/strategy/` | Does market research or strategic advisory | "value if needed: market-research agents + competitive-positioning frameworks" |
| `aios/finance-legal/` | Runs a business with invoicing, contracts, or compliance exposure | "value if needed: invoice templates + contract review when accounting load picks up" |
| `aios/engineering/` | Writes code, ships products, reviews PRs | "value if needed: dev session reports + code review agents when you start building" |
| `aios/communication/` | Publishes content, gives presentations, sends emails (almost everyone) | rarely NOT-HOT — default install |
| `aios/personal/` | Wants growth-companion, study-buddy, decision-journaler, etc. | rarely NOT-HOT — default install |

**No action required from the operator at this step.** Just close with: *"Nothing to install or demote — bundles ship in the clone; `/today` surfaces what's relevant based on your declared work."*

### Step 5 — Companies + collaboration spaces (informational — defer setup)

AIOS comes with two adjacent primitives for shared infrastructure beyond your personal vault. **Do NOT try to set either up during cold-start** — both require git MCP working (configured in Step 6) AND substrate choice (GitHub/Drive) AND their own interview flows (~10 min each). Setting one up mid-onboarding is a momentum-killing detour. Cover them informationally + defer.

```
The AIOS bundles two workspace primitives. We'll skip setup now —
both deserve their own beats post-cold-start.

1. /aios:company — mount your venture-context (positioning, gtm,
   pricing, brand, agents specific to a venture). Each venture lands
   at vault/00 - notes/context/ventures/{venture}/. Multi-company
   supported — you might mount Acme + your-startup + a client.

2. /aios:collaborate — scaffold shared-with-teammates workspaces
   (partner Drive folders, co-founder GitHub repos, local sync
   folders). Bidirectional content, multiple writers. Distinct
   from /aios:company (which is one-way pulled-in canonical context).

When you finish cold-start, tell me "let's mount my company" or
"let's set up a collaboration space" and we'll do it together —
each takes ~10 min on its own.
```

No questions asked at this step. Operator just acknowledges + moves to Step 6.

### Step 6 — MCP setup (the real workflow surface)

**Open with a 1-2 line executive-friendly definition** — many operators encounter "MCP" jargon-cold and need orientation:

> *"MCPs (Model Context Protocols) are how Claude connects to the real tools you use — Google Calendar, Slack, GitHub, etc. Think browser extensions, but for AI: each one teaches Claude to read and write in one specific tool. We bundle 10 with AIOS; you set up the ones you actually use."*

The AIOS bundles 10 MCPs. Operator picks which to set up now vs defer:

1. **Google Workspace** — Calendar, Tasks, Drive, Gmail, Docs, Sheets, Slides (almost every operator)
2. **Slack** — workspace OAuth (if operator uses Slack)
3. **GitHub** — PAT for repos/issues/PRs (if operator codes)
4. **Atlassian** — Jira + Confluence (if operator uses Atlassian)
5. **NotebookLM** — audio summaries (optional)
6. **Stitch** — UI generation from prompts (see Step 7 below — separate ask)
7. **Playwright** — browser automation + auto-publish (advanced, defer)
8. **Nano Banana** — Gemini image generation (cover images, visuals)
9. **PDF Generator** — branded report export (always-on)
10. **Spotify DJ** — lifestyle (optional)

**Two-phase install** — works best done in this order:

1. **Bulk dependencies:** `bash mcps/setup.sh` — creates venvs, installs Python/Node deps for every bundled MCP. Idempotent; safe to re-run.
2. **Guided auth + register:** `/aios:mcps-setup` — the canonical command for per-MCP token + zshrc + `claude mcp add` + verify. Asks "want this?" per MCP, never assumes. Use this rather than walking each `mcps/{name}-mcp/README.md` by hand.

After this step the MCP-tooling layer is operational — Claude can read your Calendar, post to Slack as you, query GitHub PRs, render PDFs, generate images, etc.

### Step 7 — Google's Stitch (UI builders only)

Dedicated ask for operators who build user interfaces. **Binary choice — no "tell me more" branch** (the prompt below explains enough; adding a third option creates decision overhead for an already-narrow audience):

```
Do you build user interfaces? (web apps, mobile apps, design systems)

If yes, Google's Stitch is worth wiring in — it's Google's AI-native
design → code pipeline. Pairs with our design-md-author agent (generates
DESIGN.md per Google's spec, then optionally uploads to Stitch for UI
screen generation from prompts + design tokens).

Install: y / n
```

If `y`:
- Run `bash mcps/setup.sh stitch` (or equivalent per the stitch-mcp README)
- Optionally install Stitch Skills marketplace: `npx plugins add google-labs-code/stitch-skills --scope project --target claude-code`
- Surface VoltAgent/awesome-design-md (82K⭐) as the inspiration repo for first-time DESIGN.md authors

If `n`: defer, move on. Stitch MCP is on disk; operator can wire it in later via `/aios:mcps-setup` if their UI work picks up.

### Step 8 — Plugins (announce + install-all-by-default)

Plugins are NOT optional in cold-start. The new operator doesn't know what each plugin does yet — making them DECIDE upfront forces knowledge they don't have. Same pattern as bundles (ship by default) and MCPs (bulk-install Phase 1): **announce the recommended set, install them, surface what landed.** Operators can disable any plugin later if they notice it as noise.

**The standard install set** (based on the universal + role-specific selection from declared context in Steps 2-4):

```
Installing the recommended plugin set for you...

  ✓ /plugin marketplace add anthropics/skills                (138K⭐)
  ✓ /plugin marketplace add anthropics/claude-plugins-official
  ✓ /plugin marketplace add obra/superpowers-marketplace
  ✓ /plugin install superpowers@superpowers-marketplace      (universal — dev methodology)
  ✓ /plugin install claude-md-management@claude-plugins-official  (universal — CLAUDE.md/USER.md health)
  + role-specific selections based on declared context (see table below)
```

**Role-specific augmentation** (read declared/observed context to decide):

| Operator signal | Add to install set |
|---|---|
| Engineering / build heavy (multi-repo codebase, GitHub presence, dev project notes) | `code-review@claude-plugins-official`, `pr-review-toolkit@claude-plugins-official`, `feature-dev@claude-plugins-official`, `security-guidance@claude-plugins-official` |
| Finance / accounting heavy (invoicing, contracts, tax work) | `npx plugins add anthropics/financial-services` (26K⭐ — 10 vertical agents) |
| Legal exposure (compliance, contracts, advisory) | `npx plugins add anthropics/claude-for-legal` (7.4K⭐) |
| Knowledge-work heavy (writing, research, study, content publishing) | `npx plugins add anthropics/knowledge-work-plugins` (12K⭐) |
| Life sciences / healthcare | `npx plugins add anthropics/life-sciences` OR `anthropics/healthcare` |

**After install, surface what landed** — list new slash commands available in the next session (e.g., `/superpowers`, `/claude-md-health`, `/code-review`, `/security-review`, `/verify`, etc.). Close with: *"You can disable any of these later via `/plugin list` if they feel like noise. Claude won't fire them unless relevant."*

**Edge case — operator says "skip plugins entirely"** before the install fires: respect it. The default is install-all-by-recommended-set, but explicit "skip" wins.

### Step 9 — Introducing you to {primary-session-name}

Auto-launch the orientation companion. **No y/skip gate** — the "skip" option there is a fake choice (operator would lose orientation; defeats the purpose). Same pattern as bundles ship by default, plugins install by default. Announce + transition + execute.

Frame it as the operator's primary-session-name (e.g., `buddai`) "wearing the onboarding-aios hat" — this is more accurate than "switching hats" because the operator continues to interact with their named session; the agent's expertise is what loads.

```
You're configured. One last hat-switch before your first /today —
I'm putting on the onboarding companion to walk you through the
whole map, framed for your altitude.

(Switching to /agent onboarding-aios now...)
```

Then auto-fire `/agent onboarding-aios`. The agent's greeting MUST extract the operator's name from `vault/00 - notes/context/declared/about_me.md` (first line typically contains "I'm {Name}"  or similar). Combine with the primary session name + the agent hat. Greeting format:

> *"Hey {operator-name-from-about_me}, {primary-session-name} here wearing the onboarding-aios agent hat. Day 0 — clone is fresh, you've configured identity, bundles are all hot, plugins installed. The next move that matters: your first /today..."*

The agent then runs its full Day-0 walkthrough (persona calibration from declared context, compounding-mechanism explanation, ONE next-step). At end, returns control to the cold-start flow for Step 10.

**Why no skip option:** the orientation walk is short (~2-3 minutes), and the operator has NO ALTERNATIVE source for the same mental map. Skipping it = the operator runs /today blind + spends the next two weeks figuring out commands from CHEATSHEET piecemeal. The 2-minute orientation is the highest-leverage moment in the whole onboarding.

### Step 10 — Run your first `/today` + schedule Day-7 check-in

After the orientation walk, close the interview with the climax move: the daily ritual + a Day-7 nudge so the operator doesn't fall off the loop after Day 1. **Companies + collaborations are NOT offered here** — they were deferred to "after cold-start completes" in Step 5's informational coverage. Operator initiates with "let's mount my company" / "let's set up a collaboration space" when ready.

```
Everything compounds from here. Time to feel it.

In the next message, run:  /aios:today

It'll read everything we just configured, pull your calendar + tasks +
Slack, propose a plan for the rest of today, and surface the daily
ritual that anchors the system. After today, the loop is:
  - morning  →  /aios:today
  - evening  →  /aios:close-day
  - sessions →  /aios:close-session

That loop is what makes Claude get smarter about YOU over time.
Skip it and the system never compounds.

I'm scheduling a Day-7 check-in — you'll get a prompt to spawn
onboarding-aios for a Week-1 review. That agent will surface what
to try next based on how you've actually been using AIOS in your
first week. (Easy to ignore if you're not in the mood; the schedule
is a nudge, not an interrupt.)

Welcome to The AIOS. 🌊
```

Then create the Day-7 `RemoteTrigger` with the prompt: *"Spawn onboarding-aios for the Week-1 check-in."*

After `/today` fires, the cold-start interview is complete. Operator's next move is whatever `/today` suggests — typically beginning the work the day is already underway with, or just absorbing the rhythm-establishing first daily note.

**Reminder for the executing Claude:** the company + collaboration setups DEFERRED at Step 5 are NOT forgotten — they're operator-initiated post-cold-start. If the operator next says *"let's mount my company"* or *"let's set up a collaboration space"*, route to `/aios:company` or `/aios:collaborate` respectively. Don't ask "did you mean...?" — the deferral phrasing in Step 5 is the canonical trigger.

## Output

Throughout the interview, the command writes to:

1. `USER.md` — identity, sources, growth routines, command personalizations
2. `vault/00 - notes/context/declared/*.md` — about_me, personal_voice, working_style, about_business
3. `INTENT.md` — autonomy levels, just cause, focus priorities
4. `vault/00 - notes/context/ventures/{company}/` — if Step 5 mounted a company

Always show diffs before writing. Operator confirms each section before applying.

## Rules

- **Never auto-fill creative content.** The operator's voice, values, just-cause — those come from them, not from defaults. Smart defaults are for SCAFFOLD only.
- **Save state between steps.** If the operator pauses mid-interview (closes the terminal, etc.), the next `/cold-start-interview` invocation should detect what was completed and offer to resume.
- **Skip aggressively.** Some operators want the full 25-minute walk; others want the 5-minute fast path. Honor: *"can we skip to MCP setup?"* — jump to Step 6 directly.
- **Always end at Step 9 with a concrete next-action.** The first `/today` is the moment the system starts compounding. Don't let the interview be the destination.
- **Document what was skipped.** At the end, surface: *"You skipped Step 3 (INTENT.md) and Step 7 (Stitch). Run `/cold-start-interview` again anytime, or fill those manually when ready."*

## Schedule

One-shot. Run immediately after cloning AIOS. Optionally re-runnable to revisit specific sections (the command detects what's already configured and asks which to update).

## See also

- [[onboarding-aios]] — Day-N AIOS orientation agent (run after Week 1, Month 1, Quarter 1 milestones)
- [[USER]] — the canonical personalization file this command writes to
- [[INTENT]] — the trust contract this command calibrates
- [[company]] — if you mount a company in Step 5
- `mcps/_index.md` — canonical MCP setup reference (consulted in Step 6)
