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

A guided conversation — ~5 minutes to working, deeper setup on request — that turns a freshly-cloned AIOS template into your personalized vault. Walks you through identity (`USER.md`), declared context (`about_me`, `personal_voice`, `working_style`, `INTENT.md`), bundle install choices (which of the 6 agent bundles you need), connector setup, optional Anthropic plugins, and your first `/today` run.

> **When to run:** immediately after `git clone git@github.com:The-AIOS/aios.git ~/aios` (or equivalent). Run once. If you skip it, the system still works — you'll just spend more time figuring things out yourself.


> **Never infer the operator's identity from a framework file.** Every vault ships the same
> `CLAUDE.md`, `README.md` and templates, so anything found in them belongs to the framework's
> author, not to the person you are interviewing. A setup session once offered a newcomer the
> author's Substack as a candidate for their own site — it asked rather than assumed, which was
> right, but it should not have been a candidate at all. Identity comes from what the operator
> tells you and from `context/declared/`, nowhere else.

## When to use

Immediately after the first clone of an AIOS vault — turns the freshly-cloned template into the operator's personalized vault. A guided conversation, not a form. Opens by offering a **~5-minute Core** (identity, declared context, a light INTENT.md, then the operator's first `/today`) or the **full tour** (Core plus agent bundles, companies, plugins, the desktop app). Core runs Steps 0-3, 10, 11 — Step 10 fires the first `/today`, Step 11 then offers connectors one service at a time. Depth Steps 4, 5, 8, 8.5, 9 are offered on request, at any point, including weeks later. Nothing is removed; the timing moved. Run once; re-runnable to revisit any section.


## Detection

The command is safe to run multiple times — it detects what's already configured and skips. But the most useful first invocation is on a vault where:

- `USER.md` still has template placeholders (`{{full name}}`, `{{your-email}}`)
- `vault/00 - notes/context/declared/about_me.md` is the template scaffold (not filled in)
- No daily notes exist yet in `vault/01 - calendar/`
- `agents/custom/_index.md` registry is empty

If all of those are TRUE → fresh vault → run the full interview. If some are filled → ask the operator which sections they want to revisit.

## Steps

### Pre-step — Silent setup (runs before the welcome; the operator sees none of this)

Three things happen before you say hello. **None of them is a question**, and none produces output the
operator has to read. If any fails, note it and carry on — a first-timer must never open on an error.

**(a) Which door did they come through?** Detect it, because the wording of several later steps depends
on it and getting it wrong is its own friction:

```bash
# App-path if the AIOS App is installed AND announced itself; terminal-path otherwise.
if [ -f "$HOME/.aios/surfaces/app.json" ] || [ -d "/Applications/AIOS.app" ] \
   || [ -d "$HOME/AppData/Local/Programs/AIOS" ] || [ -d "/opt/AIOS" ]; then
  ENTRY=app
else
  ENTRY=terminal
fi
```

- `ENTRY=app` → **they never ran SETUP.md.** The app was their installer. Never mention SETUP.md to
  them, never send them to it, and treat the wrapper install at Step 1 as a *first* install.
- `ENTRY=terminal` → they followed SETUP.md to get here. The Step 1 wrapper install is a *refresh*, and
  referring to SETUP.md is fair game because they have already read it.

This is the canonical half of the routing rule: **a first-timer arriving through the app must never be
linked into the 654-line manual.** SETUP.md stays the reference for the manual path and is not changed.

**(b) Register the vault connector, silently.** The AIOS edits notes through an Obsidian MCP. It is
**infrastructure, not a connector** — a published npm package, no tokens, no account, nothing to
decide — so it is never a question and never appears in the Step 11 list:

```bash
# Idempotent: skip if already registered. No tokens, no prompts, no output the operator must read.
claude mcp list 2>/dev/null | grep -q '^obsidian:' \
  || claude mcp add obsidian -- npx @mauricio.wolff/mcp-obsidian@latest "$INSTALL_PATH/vault" 2>/dev/null \
  || true
```

If it fails, say nothing and continue — vault writes still work through the filesystem; this only makes
them cleaner. **Never ask the operator about it.** (`A2`: on a fresh install, vault edits work and the
operator was never consulted.)

**(c) Path portability.** Run this check **once** to ensure the framework's hardcoded `~/aios/` references resolve to the actual install:

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

**Voice for this whole command — read this before you speak.** You are not running a form. You are
having a conversation with someone who may never have opened a terminal on purpose, and this is the
moment they decide whether the AIOS is for them. Lead with what becomes *possible*, not with a
checklist of artifacts. Give them explicit permission to interrupt and to not understand something —
that single sentence converts a first-timer's fear into a question, and a question is something you
can answer. Never make them feel behind. **The word "MCP" does not appear anywhere before the
connectors pass at Step 11** — the word is **"connectors"**, and even that waits until they have
seen the system work.

Say something in this spirit — your words, not a script:

```
Hello! Welcome to The AIOS.

This is a framework for getting far more out of AI than a chat window
gives you. The idea is simple: you shouldn't need to be technical, or
write clever prompts, to do genuinely ambitious work.

What that looks like in practice — the AIOS ships with a team of agents
already built. They draft and polish real documents, run deep research,
build presentations, handle legal and finance reading, and yes, write
and ship software for you, with no engineering knowledge required on
your side.

I'm going to guide you through setting this up — a conversation rather
than an install. Nothing to download, nothing technical, no commands to
type. Interrupt me whenever you like. If something I say doesn't land,
just ask; questions are welcome here and they make the setup better.

What we're really doing here is teaching me about you. That's the part
that compounds: every session, the AIOS knows more about how you work,
and starts doing things you didn't think to ask for.

Two ways to start:

  A quick start  — about five minutes of questions, then you'll see it
                   working on your actual day.
  The full tour  — same start, plus the deeper setup: your agent team,
                   companies, plugins, the graphical app.

Either way nothing is lost — the full tour is one sentence away
whenever you want it, and I'll offer it again at the end.

Which sounds better?
```

WAIT for their answer.

**Tier the flow from their answer — this is `A3`, and it exists because "this interview is super long" was the #2 measured friction.**

| Tier | Steps | Feels like |
|---|---|---|
| **Core** (default) | Pre-step → 0 → **1 (trimmed)** → 2 → **3-light** → 10 → **11 (connectors)** | ~5 minutes of questions, then the system working on their real day |
| **Depth** (on request, any time) | Core **plus** 4 · 5 · 8 · 8.5 · 9 | The full orientation walk |

**Depth is de-mandated, not deferred.** Nothing in it is withheld or postponed to another day — it is one sentence away at any moment, including mid-Core (*"actually, show me the whole thing"*), and Step 11 offers it again. An operator who picks Core and never asks has lost **no capability**: every deferred item is either offered later in this same session or reachable by a command they will be told about.

### Step 1 — Identity + USER.md scaffold

Walk through `USER.md` section by section:

1. **Identity table** — ask the operator's primary session name. **Lead with the functional value, not the vibe:** this name becomes a shell shorthand — typing `{name}` in any terminal launches `claude --remote-control --model claude-opus-5[1m] --name {name}` with respawn-on-quota-swap. Saves 60+ keystrokes per launch, every time. The fun part (calling your AI "JARVIS") is the bonus, not the point.

   Phrase the question something like: *"What do you want to call your primary session? It becomes a one-word shortcut in your terminal — type that one word, you get a named claude session with all the right flags, ready to work. Default is `claude` or `assistant` (functional, gets the job done). Power users pick something personal — fictional AI names work well: JARVIS, Friday, Samantha, HAL, Cortana, TARS. Short, memorable, yours."*

   **Role string is OS-detected, not hardcoded.** Default the role to a machine-agnostic "Primary session" baseline. Only add OS-specificity ("MacBook primary", "Windows primary", etc.) if the operator explicitly signals a multi-machine setup. Single-machine operators (99% of fresh clones) see clean "Primary session — AI partner" without machine-class jargon.

2. **Their email** — one question, in plain words: *"What email should I use for you?"* Record it as the primary account in `USER.md`. Nothing else here.

   > **RE-TIMED, not removed — the multi-account rate-limit question moves to the Day-7 check-in.**
   > It used to sit here, at minute two, phrased *"do you use more than one Anthropic account to manage
   > the 5h/7d rate limits?"* — with a `launchctl` install behind it. It was the **most expert-coded
   > moment in the interview**, and a first-timer cannot answer it: on day one they have not hit a cap,
   > so the question has no meaning yet. It is the one deferral whose need genuinely takes a week to
   > appear, which is why it is the **only** item routed to Day 7 rather than to Step 11 today.
   > Step 10 already schedules that check-in; the payload is specified there.

**That is the whole of Core Step 1 — two questions.** Everything below belonged to Step 1 and has been
re-timed. **Read the destination, not just the removal:** each item is offered later *in this same
session* (Step 11), or in the Depth tier, or at the Day-7 check-in. Nothing is dropped.

| Was asked here | Now asked | Why there |
|---|---|---|
| Organization / company | **Depth Step 5** (or `/aios:company` any time) | Already deferred before this change; unchanged |
| *"Primary Google email — Calendar + Tasks + Drive + Gmail"* | **Step 11**, after the first `/today` | A connector question wearing plain words. It is unanswerable until they have *seen* the empty calendar — then it answers itself |
| *"Slack workspace? Gmail? GitHub username?"* | **Step 11**, after the first `/today` | The **#1 measured freak-out**: asked what they use before they know what any of it is for |
| Growth routines (Reading / Writing) | **Depth Step 9**, or whenever a routine comes up | Was already marked *"defer; can configure later"* — it was being asked *and* deferred, which is the worst of both |

Edit USER.md inline as the operator answers. Show the diff before applying.

**After the Identity table is captured — bind the shorthand to their name.**

> **Two entry paths, and the wording must not assume either.** An operator who came through
> **SETUP.md** already has wrappers installed (SETUP.md Step 5 ran before `USER.md` existed, so the
> shorthand fell back to the default `claude` function) — for them this is a *refresh*. An operator who
> came through **the AIOS App** never ran SETUP.md at all — for them this is the *first* install, and
> calling it a "re-run" is confusing at best. The Pre-step detects which path they are on; use the word
> that matches. Never mention SETUP.md to an App-path operator: **the app is their installer**, and
> routing a first-timer into a 654-line manual is the opposite of this command's job.

Run it silently and report the outcome in one line — do not show them the command unless they ask.
**OS-conditional** — pick the right installer for the operator's machine:

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

AIOS comes with two adjacent primitives for shared infrastructure beyond your personal vault. **Do NOT try to set either up during cold-start** — both require git connector working (configured in Step 6) AND substrate choice (GitHub/Drive) AND their own interview flows (~10 min each). Setting one up mid-onboarding is a momentum-killing detour. Cover them informationally + defer.

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

### Steps 6 + 7 — moved, not removed → see **Step 11 (connectors)**

> **This is the heart of `AI-122`.** MCP setup and the Stitch question used to live here, on the
> critical path, *before the operator had seen a single thing work*. Step 6 opened by **defining the
> word "MCP"** — which is the tell: if a step has to explain its own vocabulary before it can ask its
> question, it is in the wrong place in the conversation.
>
> **Nothing here was deleted.** The definition, all ten services and their value props, and the entire
> guided auth flow are preserved and now run at **Step 11**, immediately after the first `/today` — the
> moment the operator has *watched their calendar come up empty*, which is the only moment the question
> "want me to connect your calendar?" answers itself. The Stitch ask becomes conditional rather than
> universal (it was already written that way for the `n` case).
>
> **Why later-today and not Day-7:** the value is legible the instant the ritual runs, and the
> motivation the ritual creates expires. A week-later offer is a removal with a polite sentence on top.

### Step 8 — Plugins (announce + install-all-by-default)

Plugins are NOT optional in cold-start. The new operator doesn't know what each plugin does yet — making them DECIDE upfront forces knowledge they don't have. Same pattern as bundles (ship by default) and connectors (bulk-install Phase 1): **announce the recommended set, install them, surface what landed.** Operators can disable any plugin later if they notice it as noise.

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

### Step 8.5 — Install AIOS Glass — the graphical front door

**Install it as part of setup — walk them through it, don't soft-offer-and-skip.** Glass is a core surface of the AIOS, not an optional extra. Same posture as Step 9 and the bundle/plugin installs: the default is *do it now, together* — there's no fake "skip / later" gate (skipping it leaves a new operator, especially a non-terminal one, without the surface that makes the AIOS usable — exactly the gap that strands them). **What it is:** a docked panel inside the IDE that turns the AIOS into a point-and-click surface — run rituals, launch/spawn agents, browse skills + commands, mount companies, manage spaces, all without typing terminal commands. *Glass, not engine* — it triggers the existing rituals through Claude, reimplements nothing.

Walk them through it now (don't just name it — installing isn't opening):
1. Extensions view (`⌘⇧X` / `Ctrl+Shift+X`) → search **"AIOS Glass"** → **Install** (auto-installs the **Foam** dependency + auto-updates) → reload the window.
2. **Open it:** click the **`AIOS Glass`** item in the **bottom status bar** (or `⌘⇧P` → *AIOS Glass: Open Panel*). This trips up first-timers — confirm they see the panel.
3. **Move it to the secondary (right) side bar** so it sits beside their editor (`⌘⌥B` to toggle the secondary side bar, then drag the AIOS Glass view over). Now panel + files + terminals are all visible at once.

**Calibration (use the persona from `onboarding-aios`/declared context) — this tunes the *pace*, not *whether*:** for **`exec` / `knowledge` / non-terminal** operators, slow down and confirm each step lands (this is the surface that decides whether they use the AIOS or bounce off the terminal — do NOT let them skip it). For **`software`** operators, move faster (terminal-comfortable), but still install it — the agent-orchestrator + spaces surfaces are worth it. Stock Microsoft VS Code users sideload the `.vsix` — full install incl. CLI + troubleshooting: [aios-glass INSTALL.md](https://github.com/The-AIOS/aios-glass/blob/main/INSTALL.md). Full walkthrough also in `START-HERE.md` → Step 4. Only honor an explicit, insistent "skip" — and flag that they'll be operating without the front door.

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

It'll read everything you just told me and propose a plan for the rest
of your day.

One thing to expect: some sections will come up empty — your calendar,
your tasks. That's simply because I'm not connected to those yet, and
connecting them is the very next thing we do, once you've seen the shape
of it.

After today, the loop is:
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

Go ahead — run it, read what it gives you, and I'll be right here.
```

Mention the Day-7 check-in in one line here — it is reassurance, not a closing move. **Never sign off in a step that hands off:** a goodbye here is the same defect as the old "interview is complete" line, because an operator who believes they are finished does not continue to Step 11. The farewell now lives at the true close. Then create the Day-7 `RemoteTrigger`. **Its payload now carries the one genuinely week-later item**, so
the deferral is a scheduled thing rather than a forgotten one:

> *"Spawn onboarding-aios for the Week-1 check-in. Cover: what has actually been useful this week; the
> Depth-tier steps not yet run (agent bundles, companies, plugins, Glass); any connectors still
> unconnected; and — if they have been hitting Claude's 5h/7d caps — whether a second Anthropic account
> and the quota autopilot are worth setting up now (macOS only). Ask that last one **only** if the caps
> have actually bitten; on day one it was meaningless, and if it still is, skip it."*

**Set the expectation BEFORE they run it — this ordering is load-bearing.** The copy above warns that
the calendar will be empty. Without that warning, `/today` looks broken and Step 11 opens by
apologising for a failure the previous step promised would not happen; with it, the emptiness is a
*preview of the next step* and Step 11 lands as the fix that was already announced. Same information,
opposite emotional read — and this was caught by walking the flow rather than by reading the steps.

**⚠️ The interview does NOT end here.** This line used to read *"after `/today` fires, the cold-start
interview is complete"* — and that sentence is precisely what turned deferral into deletion. Let them
read the plan `/today` produced, let the empty calendar register, **then continue to Step 11**. The
operator's own next move comes after that.

Old wording, kept for the record: operator's next move is whatever `/today` suggests — typically beginning the work the day is already underway with, or just absorbing the rhythm-establishing first daily note.

**Reminder for the executing Claude:** the company + collaboration setups DEFERRED at Step 5 are NOT forgotten — they're operator-initiated post-cold-start. If the operator next says *"let's mount my company"* or *"let's set up a collaboration space"*, route to `/aios:company` or `/aios:collaborate` respectively. Don't ask "did you mean...?" — the deferral phrasing in Step 5 is the canonical trigger.

### Step 11 — Connectors (right after the first `/today`, same conversation)

**This step is why the interview does not end at Step 10.** The old line *"After `/today` fires, the
cold-start interview is complete"* is what would have turned this whole redesign into a feature
removal: an operator told "you're done" does not come back for connectors, and the AIOS then ships
without their calendar, their Slack, or their repos — with the operator never learning those powers
existed. So the interview **continues**, in the same breath, using what they just saw.

**Open with the evidence in front of them, not with a concept:**

```
There it is — and the empty calendar I mentioned.

That's the last piece, and it's the one that changes how much I can
actually do for you. Connected, I read your real calendar and tasks
every morning, pull what needs your attention out of Slack, and can
work against your repos. Nothing changes about how you talk to me —
there's just more of your world in the room.

We do these one at a time, and only the ones you want. Each takes
about a minute: I open the right page, you click approve, I check it
worked. You never see or handle a token.

Want to start with your calendar?
```

**Then hand off to `/aios:mcps-setup`** — do not reimplement its flow here. That command already does
exactly the right thing and says so in its own Step 1 (*"Do NOT bulk-install anything"*): one service
at a time, an opt-in question before each, dependencies installed **only after** a yes, the token page
opened with `open <url>`, a real API call to validate, credentials written to a managed `~/.zshrc`
block, and **tokens never echoed back** (receipt confirmed by character count). Hand off *actively* —
invoke it — rather than naming a command and hoping they run it later.

**What is available, in the operator's language.** Say "connectors", never "MCP", and lead with what
each one *does for them*:

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

**Order it by what they told you.** They gave you their email at Step 1 — start with Google Workspace,
since Calendar and Tasks are what the daily ritual reads. Then Slack if they mentioned a team, GitHub
if they mentioned code. Skip silently past anything they don't recognise; a service they've never heard
of is not a gap in their setup.

**Stitch is conditional, not universal.** Ask about it only if their answers have involved building
user interfaces. Otherwise it stays available via `/aios:mcps-setup` and is never mentioned — asking
every operator *"do you build user interfaces?"* spends a question on a `no` roughly 95% of the time.

**And close by re-opening the door to Depth:**

```
That's you set up. From tomorrow the rhythm is just:
  morning → /aios:today     evening → /aios:close-day

Two things still waiting whenever you want them, no rush:
  • The full tour — your agent team, companies, plugins, the app.
    Say "show me the full tour" any time, today or next month.
  • More connectors — /aios:mcps-setup adds any of the others,
    one at a time, same as we just did.

I'll check in with you in a week to see what's actually been useful.

Welcome to The AIOS. 🌊
```

**Acceptance for this step:** an operator who answers "no thanks" to every connector still finishes
with a working AIOS, and an operator who says yes to two finishes with exactly those two working —
never ten installed, never a bulk download, never a terminal command they had to type.

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
- **Skip aggressively — and the tier offer at Step 0 is now the default expression of this.** Some operators want the full walk; others want the 5-minute fast path. Honor: *"can we skip to MCP setup?"* — jump to Step 6 directly.
- **Always end at Step 11 with a concrete next-action.** The first `/today` is the moment the system starts compounding. Don't let the interview be the destination.
- **Document what was skipped.** At the end, surface: *"You skipped Step 3 (INTENT.md) and Step 7 (Stitch). Run `/cold-start-interview` again anytime, or fill those manually when ready."*

## Schedule

One-shot. Run immediately after cloning AIOS. Optionally re-runnable to revisit specific sections (the command detects what's already configured and asks which to update).

## See also

- [Operating Manual](https://www.the-aios.com/#manual) (www.the-aios.com/#manual) — the full system in one document (17 sections, online or PDF); the deepest single read for an operator who wants the whole picture
- [[onboarding-aios]] — Day-N AIOS orientation agent (run after Week 1, Month 1, Quarter 1 milestones)
- [[USER]] — the canonical personalization file this command writes to
- [[INTENT]] — the trust contract this command calibrates
- [[company]] — if you mount a company in Step 5
- `mcps/_index.md` — canonical connector reference (consulted in Step 11)
