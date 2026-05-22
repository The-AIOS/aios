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
  ln -s "$INSTALL_PATH" "$CANONICAL" && echo "path-portability: created ~/aios → $INSTALL_PATH"
fi
```

**On CONFLICT** (the `~/aios` path exists and points elsewhere): surface this to the operator immediately and ask whether to back up the existing path (`mv ~/aios ~/aios.backup-$(date +%Y%m%d)`) or skip the symlink (operator commits to running the framework from a non-default path, knowing some references will need manual translation). **Default: do not auto-resolve conflicts** — operator decides.

**On Windows PowerShell** (where `ln -s` isn't available natively), use:
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
Welcome to AIOS. The next 15-25 minutes set up your personalized
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

1. **Identity table** — ask the operator's primary session name (default: `claude` or `assistant`; power users pick something custom)
2. **Anthropic accounts** — ask for primary email AND the multi-account question:

   > *"Quick gentle question — do you use (or plan to use) more than one Anthropic account to manage the 5h/7d rate limits? (yes / no — single account)"*

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

**Rule for this whole step:** one question at a time. The operator should feel walked by the hand, not interrogated. Use sensible defaults. Defer any action that involves cycling Claude's auth (the multi-account capture is the canonical example — always deferred to `/today`).

### Step 2 — Declared context (4 files, fast pass)

For each of these files in `vault/00 - notes/context/declared/`, ask ONE question and draft based on the answer. Operator refines if needed.

1. **`about_me.md`** — *"In one paragraph: who are you, what do you do, what are you building?"*
2. **`personal_voice.md`** — *"How would a friend describe how you communicate? (warm / direct / poetic / precise / etc.)"*
3. **`working_style.md`** — *"When do you do your best creative work — morning / afternoon / evening? Any other patterns Claude should know about how you operate?"*
4. **`about_business.md`** (if applicable) — *"Are you building one or more ventures? Brief description of each."*

Skip optional files (`role-expectations.md`, `psychometric-profile.md`) unless the operator asks for them.

### Step 3 — `INTENT.md` (trust contract)

INTENT.md is the highest-leverage file for compounding trust. Walk through:

1. **Autonomy levels** — for each domain (draft messages, external emails, code commits, content publishing, calendar scheduling, etc.), ask: *"autonomous / draft / ask?"* Defaults are conservative ("draft" everywhere); operator opens up as trust grows.
2. **Just cause** — *"In one sentence: why does your work matter beyond revenue?"*
3. **Focus priorities** — *"The four AIOS pillars are Creation / Amplify / Knowledge / Superhuman. Want to customize the framing?"* Default is fine for most operators.

Don't try to fill out venture-level overrides yet — those come once the operator has mounted at least one company (Step 5).

### Step 4 — Agent bundle install

Show the 6 bundles + scope (1 line each). Ask which apply.

| Bundle | Install if you... | Default |
|---|---|---|
| `aios-sales/` | Handle leads, write proposals, manage a sales pipeline | ✓ if applicable |
| `aios-strategy/` | Do market research or strategic advisory | ✓ if applicable |
| `aios-finance-legal/` | Run a business with invoicing, contracts, or compliance exposure | ✓ if applicable |
| `aios-engineering/` | Write code, ship products, review PRs | ✓ if applicable |
| `aios-communication/` | Publish content, give presentations, send emails (almost everyone) | ✓ default install |
| `aios-personal/` | Want growth-companion, study-buddy, decision-journaler, etc. | ✓ default install |

Operator picks. All 6 bundles ship in the AIOS template by default — this step doesn't add files, it just sets the operator's mental model for what's available + suggests demoting unused bundles to ignore in `/today` Radar.

### Step 5 — Mount your first company (optional but recommended)

Ask: *"Do you have a company / venture context to mount? (your own company, a client, an advisory engagement)"*

If yes → invoke `/company` flow:

- *"Create a new company-context repo, or mount an existing one?"*
- If create → walks `/company --create` (interview-driven scaffold per the [Layer 1-5 template](./company.md))
- If mount → ask for the URL (GitHub repo or Drive folder), runs `/company --mount {url}`

If no → skip. Operator can run `/company` later.

### Step 6 — MCP setup (the real workflow surface)

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

### Step 7 — Stitch optional integration (UI builders only)

This is the dedicated ask for operators who build user interfaces:

```
Do you build user interfaces? (web apps, mobile apps, design systems)

If yes, Stitch is worth wiring in. It's Google's AI-native design → code
pipeline, and it integrates with our design-md-author agent (which generates
DESIGN.md per Google's spec, then optionally uploads to Stitch for UI generation).

Install: y / n / tell me more
```

If `y`:
- Run `bash mcps/setup.sh stitch` (or equivalent per the stitch-mcp README)
- Optionally install Stitch Skills marketplace: `npx plugins add google-labs-code/stitch-skills --scope project --target claude-code`
- Surface VoltAgent/awesome-design-md (82K⭐) as the inspiration repo for first-time DESIGN.md authors

If `tell me more`:
- Show: *"Stitch generates UI screens from text prompts and DESIGN.md tokens. Pairs with our `design-md-author` agent. The combination: author your brand's DESIGN.md once → generate matching screens on demand. Useful if you're shipping any user-facing product."*

If `n`: defer, move on.

### Step 8 — Optional Anthropic + community plugins (recommended installs)

Based on what the operator told us in Steps 2-4, suggest plugins from Anthropic's official marketplace + the broader community. The recommendation engine cross-references the operator's declared role + ventures + work patterns and surfaces the highest-leverage plugins they don't have yet.

**Universal recommendations (suggest for almost everyone):**

- **Superpowers** (obra/superpowers — 201K⭐) — *"Complete software development methodology for coding agents."* Installs as `/plugin install superpowers@claude-plugins-official`. The third-party plugin with the highest leverage for any operator who codes. Already partially absorbed into our `skills/` folder (brainstorming, writing-plans, systematic-debugging, etc.) — installing the marketplace plugin gets ongoing updates + the full methodology.
- **claude-md-management** (`anthropics/claude-plugins-official`) — comprehensive CLAUDE.md + USER.md health check. We've reimplemented its patterns inline in `/housekeeping` Bucket 17, but the official plugin adds interactive tooling. Install via `/plugin install claude-md-management@claude-plugins-official`.

**Role-specific recommendations:**

- **If engineering / build heavy** → `/plugin install code-review@claude-plugins-official` + `pr-review-toolkit@claude-plugins-official` + `feature-dev@claude-plugins-official` + `security-guidance@claude-plugins-official`. Augments our aios-engineering bundle.
- **If finance / accounting heavy** → `npx plugins add anthropics/financial-services` (26K⭐) — 10 vertical agents (month-end-closer, gl-reconciler, model-builder, kyc-screener, valuation-reviewer, statement-auditor, pitch-agent, market-researcher, meeting-prep-agent, earnings-reviewer)
- **If legal exposure** → `npx plugins add anthropics/claude-for-legal` (7.4K⭐) — suite of legal-workflow plugins
- **If knowledge-work heavy** (writing, research, study) → `npx plugins add anthropics/knowledge-work-plugins` (12K⭐)
- **If life sciences / healthcare** → `npx plugins add anthropics/life-sciences` OR `anthropics/healthcare`

**Marketplace browse (always offer):**

```bash
/plugin marketplace add anthropics/skills     # canonical Agent Skills marketplace (138K⭐ — anthropics/skills)
/plugin marketplace add anthropics/claude-plugins-official    # 35+ official plugins
/plugin marketplace add obra/superpowers-marketplace          # Superpowers + related plugins
```

**Recommendation rules:**

- **Don't push.** If the operator says "skip plugins" or "I'll explore later", honor that. The default install is zero — every plugin is opt-in.
- **One install per beat.** Don't ask "should I install all 4?" — confirm each separately so the operator can see what's being added.
- **After install, surface the slash command.** *"Superpowers installed. Try `/superpowers` in your next session to see what landed."*
- **If knowledge-work-heavy** → suggest `npx plugins add anthropics/knowledge-work-plugins` (12K⭐)
- **Always** → mention `anthropics/skills` (138K⭐) — the canonical Agent Skills marketplace; browse via `/plugin marketplace add anthropics/skills`

Operator picks which to install now vs defer. None are required.

### Step 9 — Wear the onboarding hat (`/agent onboarding-aios`)

Before the first `/today`, put the orientation companion in front of the operator so they understand *where they are* and *what they have*:

```
You're set up. Before we run your first plan — let me put on the
"onboarding companion" hat so you understand the whole map.

In the next message I'll switch hats with /agent onboarding-aios.
That agent knows the full AIOS structure: the org (The-AIOS),
this repo's README + CHEATSHEET + FORTRESS + START-HERE, USER.md
personalization power, the self-update loop via /today and
/close-session, the org's SECURITY/CONTRIBUTING playbooks. It's
your standing companion for orientation — anytime later you
feel lost, just say "I'm lost" or "what should I try next" and
Claude routes here.

OK to switch hats? (yes / skip — I'll explore solo)
```

If yes → invoke `/agent onboarding-aios` and let it do the full orientation walk. The operator now has the AIOS mental map in conversation.

### Step 10 — (Optional) Mount or create a company

After the orientation walk:

```
You're operator-ready. Two optional setups before your first /today:

1. Companies — do you have a venture-context repo / Drive folder
   to mount? Or want to scaffold a new one? /company handles both.
   GitHub substrate is highly recommended ✅ (see /company docs).

   Examples: your own venture, a client you work with, your
   employer's shared context.

   Want to set up a company now? (yes / not yet)
```

If yes → invoke `/aios:company` (no args — it routes to create or mount based on what the operator says). If not yet → continue.

### Step 11 — (Optional) Set up a collaboration space

```
2. Collaboration — do you have a shared/collaborative space to
   mount or create? /collaborate scaffolds a substrate-pluggable
   shared workspace (Drive for non-coders, GitHub for code-adjacent,
   local folder for testing) and mirrors it into your vault.

   Examples: a partner-org Drive, a co-founder's GitHub repo, a
   local sync folder you share with a teammate.

   Want to set up a collaboration space now? (yes / not yet)
```

If yes → invoke `/aios:collaborate`. If not yet → continue.

### Step 12 — Run your first `/today`

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

Welcome to AIOS. 🌊
```

### Step 13 — Schedule the Day-7 check-in

After the operator finishes their first `/today`, surface:

> *"Want me to remind you on Day 7 to run `spawn onboarding-aios` for a Week-1 check-in? That agent surfaces what to try next based on how you've actually been using AIOS."*

If yes, create a `RemoteTrigger` for Day 7 with the prompt: *"Spawn onboarding-aios for the Week-1 check-in."*

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
