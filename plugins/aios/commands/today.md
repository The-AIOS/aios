---
tags:
  - aios
  - command
  - daily
description: Generate a grounded daily plan from recent notes, open threads, and priorities
allowed-tools: mcp__obsidian__*, mcp__google-workspace__*, mcp__google-workspace-personal__*, Read, Bash(cd ~/aios && git:*), Bash(gh:*), Bash(date:*), Bash(uv run ~/aios/hooks/pipeline-executor.py:*)
---

# /today — Daily Plan

You are generating today's daily plan for the vault owner by reading their Obsidian vault.

## When to use

Every morning as the foundational ritual. Reads vault context + Calendar + Tasks + Slack and generates today's plan — personalized to your energy, your projects, your trust contract. The heartbeat of the daily loop.


## Pre-loaded API data

Message 1a runs `uv run ~/aios/hooks/pipeline-executor.py --command today` which pre-loads Google Calendar events (all configured accounts), Google Tasks (open), and Slack unreads. The output starts with `# Pre-loaded API Data`.

**DO NOT call Google Calendar, Google Tasks, or Slack APIs.** The data is in the executor output. Use it directly for the Calendar section, task merging, Horizon, and Slack triage.

**If the executor output shows `❌ FAILED` for a specific source:** tell the user what failed and how to fix it (the error message includes the fix). Use the data that did load. Do not call failed APIs yourself.

**If the executor crashes entirely:** the output will say `❌ Pipeline executor crashed`. Tell the user to check `~/aios/hooks/pipeline-executor.log`. Do not attempt to call the APIs yourself.

## Progress tracking

In your first message (Message 1a), also create a task list so the user can see where you are. Use `TaskCreate` for each step:

| Task | activeForm |
|------|-----------|
| Load vault context + projects | Loading context |
| Synthesize and write daily note | Writing daily note |
| Commit and push | Committing and pushing |

Mark each task `in_progress` when you start it and `completed` when done.

## Steps — Target: 4 messages, under 60 seconds

### Message 1a — Bootstrap (one parallel batch)
Fire these calls in **one message**:
- `Bash(uv run ~/aios/hooks/pipeline-executor.py --command today)` — **runs the pipeline executor.** Pre-loads Google Calendar, Tasks, and Slack data. Output is the `# Pre-loaded API Data` section. If it fails, the output will say what went wrong.
- `Bash(date +"%A, %B %d, %Y")` — **derive the weekday explicitly.** Store this and reference it throughout (day-specific logic like Wednesday drift check, Friday learnings). Never guess the weekday from context.
- `Bash(cfg=~/aios/.aios-update; if [ -f "$cfg" ]; then repo=$(grep ^repo= "$cfg" | cut -d= -f2); h=$(grep ^hash= "$cfg" | cut -d= -f2); r=$(git ls-remote "$repo" HEAD 2>/dev/null | awk '{print $1}'); [ -z "$r" ] && echo "vault-update: unreachable" || { [ "$h" = "$r" ] && echo "vault-update: synced" || echo "vault-update: BEHIND (local=${h:0:7} remote=${r:0:7})"; }; else echo "vault-update: no-config"; fi)` — **infrastructure freshness check.** Reads `.aios-update`, asks team repo for current HEAD via `git ls-remote`, compares hashes. Returns one of: `synced` (no action), `BEHIND ...` (team repo has new commits), `unreachable` (network/auth issue), `no-config` (no `.aios-update` tracker found — single-vault user). Surface the result per § Vault-update freshness rendering below.
- `Bash(prev=$(find ~/aios/vault/01\ -\ calendar -maxdepth 2 -type f 2>/dev/null | grep -E '/[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$' | grep -v "$(date +%Y-%m-%d)" | sort -r | head -1); if [ -z "$prev" ]; then echo "close-day-precondition: no-prior-note"; elif grep -q "^## Close of Day" "$prev" 2>/dev/null; then echo "close-day-precondition: closed ($(basename "$prev" .md))"; else echo "close-day-precondition: MISSING ($(basename "$prev" .md)) — must run /close-day first"; fi)` — **close-day precondition check.** Detects whether the most recent daily note BEFORE today has the `## Close of Day` heading. Returns one of: `closed (date)` (previous note closed — proceed normally), `MISSING (date)` (skipped close-day — guard fires per § Close-of-day precondition rendering below, BEFORE Message 1b runs), `no-prior-note` (first run / fresh vault — proceed normally).
- `Bash([ -f ~/aios/vault/.pending-quota-autopilot-capture ] && echo "pending-setup: quota-autopilot-capture" || echo "pending-setup: none")` — **deferred-setup check.** SETUP §11 leaves this marker when the operator opted into multi-account autopilot but the capture dance (login/logout/Keychain) was deferred (running it during setup would have broken that session). If marker present → surface as the FIRST task in today's Rhythm (see § Pending-setup rendering below). Operator can complete it today or carry forward; the daily plan tolerates either choice.
- `Bash(for venture in ~/aios/vault/00\ -\ notes/context/ventures/*/; do tracker="$venture/.$(basename "$venture")-sync"; [ -f "$tracker" ] || continue; repo=$(grep ^repo= "$tracker" | cut -d= -f2); h=$(grep ^hash= "$tracker" | cut -d= -f2); [ -z "$repo" ] && continue; r=$(git ls-remote "$repo" HEAD 2>/dev/null | awk '{print $1}'); name=$(basename "$venture"); [ -z "$r" ] && echo "company-$name: unreachable" || { [ "$h" = "$r" ] && echo "company-$name: synced" || echo "company-$name: BEHIND (local=${h:0:7} remote=${r:0:7})"; }; done)` — **per-company freshness check.** Iterates over every mounted company in `vault/00 - notes/context/ventures/*/`, reads its `.{company}-sync` tracker, asks the remote for HEAD via `git ls-remote`, compares. Returns one line per mounted company: `company-{name}: synced` / `BEHIND ...` / `unreachable` / (skipped if no tracker). Surface per § Company freshness rendering below — parallels the vault-update check but covers venture-context drift, not framework drift.
- `Read` → `USER.md` (if it exists — for Sources config, `### /today` command personalizations, and organization settings)
- `Read` → `INTENT.md` (if it exists — for autonomy levels, focus weighting, parked item suppression, tradeoff rules)
- `mcp__obsidian__read_note` → `00 - notes/projects/_index.md`
- `Read` → `agents/_index.md` (canonical registry across all bundles — top-level infra, not in Obsidian vault path)
- `Read` → `agents/custom/_index.md` (if it exists — operator's custom agents)
- `mcp__obsidian__list_directory` → `00 - notes/projects/`

This gives you: USER.md personalizations, the actual weekday, what sources are configured, the project list, whether the team's shared infrastructure has updates pending, and whether the previous daily note has been closed (cascade integrity guard).

**Vault-update freshness rendering (handled in Message 1a, BEFORE Message 1b vault reads):**
- **`synced`** → silent. Proceed to Message 1b normally.
- **`BEHIND`** → **check the operator's auto-update preference first.** Read `USER.md` → `## Settings` → **Automatic updates**. If it's `no`, do NOT auto-fire — surface the nudge-only callout (*"Vault is BEHIND (local `{h}`, remote `{r}`) — run `/aios:update` when you're ready. (Auto-update is off in your USER.md Settings.)"*) at the top of the daily note and proceed to Message 1b. If it's `yes` (or the setting is absent → **default yes**), **proactively fire `/aios:update` BEFORE Message 1b.** Surface to user inline first:

  > *"Vault is BEHIND — local hash `{h}`, team repo `{r}`. Running `/aios:update` now to pull fresh commands / templates / settings before today's plan. After the update lands, I'll continue with /today. If you'd rather skip and pull later, say "skip update" inline."*

  Then invoke `Skill(aios:update)` and **wait for it to complete.** Pulling stale infra into a long session creates rebase pain later AND today may reference content the operator hasn't pulled yet (commands, templates, etc.). After /aios:update finishes (tracker advanced + any new infra landed), proceed with Message 1b vault reads. **Do not skip** — same cascade-integrity reasoning as the close-day precondition. If the user explicitly says "skip update" inline, fall back to the old nudge-only behavior (a callout at top of daily note) and continue.
- **`unreachable`** → soft mention in Energy note or as a one-liner near the bottom: *"vault-update check unreachable today (network/auth — fine for now)."* Don't escalate. Proceed to Message 1b.
- **`no-config`** → silent (single-vault user, nothing to sync). Proceed to Message 1b.

**Company freshness rendering (handled in synthesis, Message 2 — does NOT block Message 1b like vault-update does):**

For each `company-{name}: BEHIND` line returned by the per-company freshness check, surface a soft callout in the daily plan (top section, before Calendar). One bullet per behind-company:

> 🆕 **`{name}` context has updates** — local `{h}`, remote `{r}`. Run `/aios:company --sync {name}` to pull. After the sync, you'll be offered a brief change-digest from `onboarding-{name}` (skippable).

`unreachable` companies get a quieter single-line mention in Observed section (not a callout). `synced` companies stay silent. If 0 companies are mounted → entire section omitted.

**Why this is offered, not auto-fired** (unlike the `/aios:update` BEHIND case which auto-runs): company-context updates aren't structurally load-bearing for today's plan the way framework updates are. /today reads the company's content from the vault, not from the remote, so stale company-context only means the operator's context is N days old — not that /today itself will break. The operator can decide whether to sync now or carry forward. The framework-level auto-fire is for command/skill/template freshness (load-bearing for today's session); company-context freshness is for venture content (load-bearing for venture-specific work, not for /today's structural correctness).

**Close-of-day precondition rendering (handled in Message 1a, BEFORE Message 1b vault reads):**
- **`closed`** → silent. Proceed to Message 1b normally.
- **`no-prior-note`** → silent (first run, no prior note to close). Proceed normally.
- **`MISSING`** → **guard fires.** Skipping /close-day breaks the cascade chain (daily note → project notes → `_index.md` snapshots → observed context). Without the cascade, today's plan reads stale data. Surface to user and run /close-day on the previous note BEFORE proceeding with /today's vault reads:
  
  > *"Previous daily note ({date}) wasn't closed. Running /close-day on it first — this cascades carries to project notes, refreshes `_index.md` snapshots, and routes any captured insights to observed context. Without this cascade, today's plan would read stale data. Then I'll continue with /today's normal flow.*
  >
  > *Some prompts may reference older context if the previous note is from days ago — answer to the best of memory; close-day is forgiving."*
  
  Then invoke `Skill(aios:close-day)` and **wait for it to complete.** /close-day naturally picks "the most recent daily note that doesn't have ## Close of Day" — which is the same note this guard detected. After /close-day finishes (the previous note now has the heading + the cascade landed), proceed with Message 1b. **Do not skip** — the cascade is critical for /today's accuracy. /today's value compounds on cascade integrity; without it, AIOS stops compounding (carries don't reach project-notes, snapshots stale, observed context never receives the day's insights, self-update integrity breaks).

**Pending-setup rendering (handled in synthesis, Message 2):**

When the deferred-setup check returns `pending-setup: quota-autopilot-capture` → add a **🔧 Pending setup** task as the FIRST item in the Rhythm section (above all other deliverables). Frame it as a deliberate task with two options, not a blocker:

> *"🔧 **Pending setup — Quota autopilot capture** (multi-account login dance). During your setup, we installed the file-system pieces (launchd agent, plist) but deferred the per-account login/logout/Keychain capture because running it during setup would have broken that session. This is the safer moment.*
> 
> *Two options:*
> - *(A) Do it now (~5 min) — I'll walk you through `hooks/claude-identity/README.md` § Setup: login per account → Keychain capture → swap-back to primary → verify via `claude-switch`. Marker auto-removes when done.*
> - *(B) Carry forward — keep the marker for tomorrow's /today. Stays surfaced until completed."*

Operator picks one. If A → invoke the autopilot setup walkthrough (Skill or direct read of `hooks/claude-identity/README.md` § Setup). On completion, delete the marker: `Bash(rm -f ~/aios/vault/.pending-quota-autopilot-capture)`. If B → leave the marker, render it as a top-of-Rhythm item every subsequent /today run.

**Why this pattern (briefly):** the autopilot's safety-net launchd watcher + statusLine cache writer work the moment the universal hooks are installed — they don't require capture. Capture only unlocks the AUTO-SWAP step (rotating Anthropic accounts when one nears its cap). Until capture, the watcher logs "no rotation configured" benignly. So the deferred-capture pattern is functionally safe: the operator's autopilot is half-built, watching but not swapping, until they choose to complete capture.

If USER.md has no `## Sources` section, use defaults: vault projects only (no API data without sources config).

### Message 1b — Vault reads (one parallel batch, informed by 1a)

**If `_index.md` has a `## Project Snapshots` section with content:** use it as the single source for project context + to-dos. No need to read individual project notes.

**If `_index.md` has no snapshots** (empty template, placeholder text, or section missing): fall back to reading all project notes from the directory listing, batched in groups of 10. This is the cold-start path — the first `/close-day` run will generate the snapshots and all future `/today` runs will be fast.

Fire ALL of these as direct parallel tool calls in **one single message**:

**Vault reads (Read tool) — apply payload discipline throughout:**

**Observed context — all in the same parallel batch, but use `limit:50` per file:**
- `growth.md`, `profile.md`, `patterns.md`, `session-insights.md`, `ecosystem.md`, `business.md`, `vault-routine.md`
- /today only needs the latest observations, not full history. If a file's key content is truncated, do a second targeted read for the missing section.

**Daily notes:**
- **Most recent daily note** (NOT hardcoded to yesterday's date): list files in `01 - calendar/{YYYY-MM}/` and pick the latest file that matches the `YYYY-MM-DD.md` pattern (exactly 10-char date prefix) and is before today. **Exclude** weekly plans (`W{N}-plan.md`, `W{N}-summary.md`) and any other non-daily files. If no daily note exists in the current month, check the previous month. This handles weekends, holidays, and any gap. **Critical — this is where carry-forwards come from. If this file isn't found, carried items are silently dropped.**
  - **Smart read:** Don't read the full note. Search (`Grep`) for `### Carries forward`, `### Tomorrow priorities`, and `- [ ]` to find all unchecked items. Read from each heading with `offset` + `limit`. **Safety net:** if the search returns suspiciously few carries (0 items from a note that had 15+ tasks in its Rhythm), fall back to reading the full note — never silently return empty carries.
- Today's daily note (if it exists — created by `/7plan` or a previous `/today` run — to detect and preserve user edits)
- This week's plan: `01 - calendar/{YYYY-MM}/{YYYY}-W{WW}-plan.md` (if it exists) — read with `limit:60` (priorities are always in the first half)

**Trackers + growth:**
- Sync trackers (for freshness check): check `USER.md` → `## Companies (mounted)` for mounted-company table. For each row, read its tracker file (e.g. `.{company}-sync` in `vault/00 - notes/context/ventures/{company}/`). Plus `.aios-update` at repo root for the AIOS framework freshness.
- **Growth routines:** If USER.md has a `### Growth routines` section (under `## Sources`), note the project names and section names listed. The project snapshot in `_index.md` (already loaded in Message 1a) should have enough detail. Only read the full project note if the snapshot lacks the specific queue/list data needed. **Never read the full project note by default** — growth project notes can be 15K+ tokens.

**Project context:**
- **If snapshots were loaded in Message 1a** (the fast path): the `_index.md` already has everything. **Do NOT read individual project notes.** Only drill into a specific note if a calendar event or Google Task references a project and the snapshot lacks detail.
- **Staleness check:** Scan the `_index.md` timestamp per project snapshot. If any active project snapshot is older than 7 days, flag it: "⚠️ [[project]] snapshot is {N} days stale — refreshing." Read just the `## To-Dos` section from that project note (search heading + offset, not full note) and update the snapshot in Message 2. This prevents to-dos from going invisible in untouched projects.
- **If no snapshots exist** (cold-start path): read all project files discovered in Message 1a directory listing, batched in groups of 10. **Only extract what `/today` needs:** frontmatter `status`, `## Current State` (or `## Overview` first paragraph), and `## To-Dos`. Skip architecture, decisions log, session notes, links.

**This is the only data-gathering message.** After this, no more Read or MCP read calls. API data (Calendar, Tasks, Slack) comes from the pre-loaded context — not from tool calls.

### Message 2 — Analyze + write (minimal reads only for stale snapshots)
From the data already loaded — process everything in memory:

**If today's note already exists (created by `/7plan`):**
- Switch to **update mode** — don't overwrite, enhance:
  - **Preserve:** checked items (`- [x]`), user-added subtasks, meeting notes, manual edits
  - **Refresh:** Calendar (meetings may have moved), Google Tasks (new/completed)
  - **Add:** carry-forwards from yesterday's close-day
  - **Generate fresh:** Claude's take, command suggestion, observed nudge, energy note — these weren't in the `/7plan` version
  - **Merge tasks:** if `/7plan` already placed tasks in Rhythm blocks, keep them. Add new tasks from Google Tasks or carries. Dedup rule: match by task title (case-insensitive, ignore source tags like `_(project)_` or `_(google tasks)_`). If a task from Google Tasks or carries matches one already in Rhythm, skip it.

**If today's note doesn't exist (no `/7plan` was run):**
- Create from scratch as a **fallback** — full `/today` behavior. If a weekly plan (`W{WW}-plan.md`) exists, use its priorities to inform "Today I ship" and task distribution across Rhythm blocks.

**In both cases, also run:**
- Use the project snapshots from `_index.md`: **active** → extract to-dos for Rhythm + Radar. **idea** → Radar bottom. **archived/deprioritized** → skip or minimal mention.
- **If first run** (no project notes exist) and kickstart sources are configured: offer to import projects from external sources. Wait for user approval before creating.
- **INTENT.md parked items check:** Before processing carries, read INTENT.md `## Explicitly NOT doing`. Any carried item that matches a parked entry is **removed entirely** — no carry, no count, no mention, no escalation. This runs BEFORE the carry logic below.
- **Extract carry-forwards: ZERO TOLERANCE for dropped items.** Scan all unchecked `- [ ]` across ALL sections of the most-recent daily note — Rhythm, Parking lot, Horizon, Carries forward, AND the Close of Day `### Carries forward` subsection. Dedup by core task name (ignore emojis, time slots, source tags); keep highest carry count + most actionable version. After writing today's note, verify: every unique unchecked item from the previous note must appear somewhere (Rhythm / Parking lot / Horizon). If `previous_unique_carries > today_carries`, find what dropped and add it. Carries that have been silent 3+ days still surface.
- **Smart carry triage** — a carry without a decision is guilt on a list. Carry format: `_(carried ×N, reason: {tag})_` where tag ∈ `strategic-deferral` / `blocked-on-{who}` / `needs-challenge` / `waiting-on-date`. A tagged carry has been triaged — respect it; count alone doesn't escalate.

| Count | No reason tag | With reason tag |
|---|---|---|
| ×1-2 | Normal — show in Rhythm or Parking lot | (n/a — no tag yet) |
| ×3-5 | ⚠️ flag — still alive, needs attention | OK — show tag |
| ×6-9 | **Ask** inline: pick a tag (close-day locks in) | OK — keep in Parking lot |
| ×10+ | 🔴 **Escalate** — retag or park, no more silent carries | Respect (incl. ×17 strategic-deferral) — show tag, no escalation icon |
| ×10+, stale tag (no activity on blocker for 30+ days) | 🔴 escalate — retag or park | (same — stale ≠ fresh) |

Place triage decisions at the top of Parking lot, not buried in Rhythm.

- **Target-aware carry display** (opt-in). Carries can optionally include a `target:` metadata field — the actual deadline, distinct from the carry's age. Format: `_(carried ×N, target: 2026-05-15)_` or `_(carried ×N, target: 2026-W19)_`. When rendering:
  - **`target:` present + PAST target** → display `🔴 X days past target — {task} _(carried ×N, target: ...)_` — count days from target, not creation. Real urgency.
  - **`target:` present + BEFORE target** → display `📅 due in X days — {task} _(carried ×N, target: ...)_` — informational, **no escalation regardless of carry count**. The item is on schedule per its own deadline.
  - **`target:` absent** → display `_(carried ×N, no target)_` neutrally — escalation rules above (×3 ⚠️, ×6 ask reason, ×10+ force decide) apply to explicit-target items only, not raw age.

  Add `target:` only when there's a real deadline (external commitment, dependency, calendar event, scheduled W-plan slot). Don't invent fake deadlines.

- **Horizon hiding** (>14 days). Long-horizon `waiting-on-date` carries should NOT clutter daily notes when their target is far out — they belong in project notes + `_index.md` snapshots only, re-entering the daily flow as the date approaches:
  - **`target` ≤ 14 days out** → carry surfaces in daily note Parking lot (or Rhythm if the date matches today/this-week)
  - **`target` > 14 days out** → carry is **hidden from daily notes entirely**. The item stays alive in: (1) the relevant project note's to-do list, (2) the project's `_index.md` snapshot. It re-enters the daily note flow when the target crosses the 14-day horizon.
  - **`/close-day` companion rule**: when triaging carries, if a carry has `waiting-on-date: YYYY-MM-DD` with target >14 days out, route it to the project note's to-do list (not "Carries forward" in the daily note). The carry is "filed" rather than "carried" — same persistence, different surface.

- **Window-cadence carries are not drift.** Carries with the triad — explicit far-out `target` + tagged reason (e.g. `blocked-on-X-with-energy`) + window-cadence pacing (recurring slots toward the target, e.g. Fri/Sat 6 hrs/wk toward a Q3 ship) — are properly paced, NOT drift. Count is the audit trail of windows-not-yet-used. Display neutrally: `_(carried ×N, target: YYYY-Qn, sequenced via {window})`. NO 🎯 / 🔴 / decide-or-park language. NO growth-edge invocation. The carry-without-deciding escalation applies to UNTAGGED, no-target, no-window carries only.
- **Stale project snapshot refresh:** For any project flagged as stale in Message 1b (snapshot >7 days old), read just the `## To-Dos` section from the project note and update the `_index.md` snapshot. This prevents to-dos from going invisible in untouched projects.
- Count streaks (consecutive days of study, writing, shipping)
- Count drift counters (days an item has been carried)
- Determine the **command suggestion of the day** (see Command Discovery Engine below)
- Identify one **observed nudge** (see Observed Nudges below)
- Synthesize a **daily opener** — radically candid, grounded in observed context
- Identify the **one thing to ship**
- Sort all tasks into energy blocks: Morning (create), Afternoon (operate), Evening (grow)
- Write the daily note (preserving user edits if note already exists — keep checked items, meeting notes, user-added subtasks)
- **Post-write clean pass** (run silently before commit; fix issues, don't ask):
  1. **Dedup across sections.** Scan Rhythm + Parking + Horizon + Sarah-results (if present) + Energy note for the same task appearing in more than one place. Match by core task name (ignore emojis, source tags, carry counts). If a task is in Rhythm AND Parking → keep only Rhythm. If a review item is in Sarah's results AND Parking → keep only the Rhythm/Evening placement.
  2. **Drop check (carries).** Re-count unique unchecked `- [ ]` items from the previous note. Count unique items placed in today's note. If `previous_unique > today_placed`, something was dropped — find it and add to Parking before committing.
  3. **Due-today task check (fresh tasks, NOT just carries).** Step 2 guards *previous-note carries* — it does NOT guard *fresh* tasks due today. Cross-reference the pre-loaded executor's Google Tasks where `due == today` against what actually landed in the note. **Every due-today task must appear somewhere** — Rhythm, Parking lot, or Agents-can-handle (ingests + delegatable work → Agents-can-handle). For each due-today task absent from the note, place it before committing. Don't let a narrative-heavy day (big backfill, long Shipped section) crowd out the mechanical task merge. (Caught 2026-05-28: two due-today ingests + a wrapper task fell through because the drop check only scanned previous-note carries — a fresh due-today task that isn't also a calendar event had no safety net.)
  4. **Review items.** Every "needs review" flag (📋, `→ review`, `/tmp/...` file reference) should have a corresponding task in Rhythm or Evening. If absent, add one.
  5. Note any fixes inline in the commit message: `Daily plan {date} (clean pass: merged X, restored Y, recovered N due-today tasks)`.

### Message 3 — Commit + push
- `cd ~/aios && git add -A && git commit -m "Daily plan {date}" && git push`

## First run handling

Detect first run by checking: `about_me.md` still has template placeholders (`{{full name}}`, `{{date}}`), AND no previous daily notes exist in the calendar folder. Don't rely on project count — the repo may ship with reference projects.

**If first run, hand off to the onboarding agent.** A blank daily plan with a setup checklist is the wrong first experience — the operator deserves a guided walkthrough, not a self-service todo list. The `onboarding-aios` agent exists precisely for this; it knows the journey, the principles, the doc map, and what to surface at Day 0.

The first-run daily note becomes minimal — an opener + a single explicit pointer to the onboarding agent:

```
# {date} — Day One

> *Day one. Everything compounds from here.*

This is your first `/aios:today` run, so there's no context yet — no declared context, no projects, no observed patterns. That's exactly what the onboarding agent is for.

## Recommended next step

Spawn the onboarding session — it'll walk you through:
- Filling in declared context (`about_me`, `working_style`, etc.) — the foundation Claude reads every session
- Creating your first project (or importing existing work)
- Optional: mount a company context (`/aios:company`) or scaffold a collaboration space (`/aios:collaborate`)
- Understanding the daily/weekly/monthly cadence so the compound starts

To begin: **`spawn onboarding-aios "Walk me through Day 1 — I just installed AIOS."`** (opens in a new terminal/tab) — or invoke as an agent from this session if you'd rather stay here.

## Calendar (pre-loaded)

{Today's events from the executor, if any — Calendar + Tasks data works immediately even without vault context.}
```

**Why hand off instead of inline checklist:** the onboarding agent is calibrated to ask one question at a time, adapt to what the operator already has filled, surface the right next thing per their position in the journey (Prompt → Context → Intent → Collaboration → Second Brain → AI Company), and offer the right primitive at the right moment (`/aios:company` if they're operating in a venture, `/aios:collaborate` if they're co-creating, plain projects otherwise). A static checklist can't do that. The handoff also makes the agent discoverable from the first ritual the operator ever runs.

**If kickstart sources are configured in USER.md** (Google Workspace, Slack, GitHub for project imports): mention this as an option the onboarding agent will surface — don't auto-import on first run without the operator's affirmation.

**Still write the daily note** (don't skip the write because it's Day 1). The operator's first daily note is a meaningful artifact — they'll re-read it later as the start of their compound. Calendar + Tasks pre-loaded data still goes into the note.

## Output

Write the plan to `01 - calendar/{YYYY-MM}/{today's date YYYY-MM-DD}.md` using `mcp__obsidian__write_note` with frontmatter `{"tags": ["daily", "plan", "vault"], "created": "{today}"}`.

Structure:
```
# {date} — Daily Plan

## Claude's take

> {A single radically candid, motivational, or reframing line drawn from observed context. Not generic inspiration — grounded in what Claude actually knows about this person from growth, patterns, profile, and ecosystem. Could be a nudge toward something being avoided, a reminder of a strength that's relevant today, or a reframe that connects dots. Different every day.}
>
> {One sentence — short, philosophical, warm. Grounded in today's context but resonates beyond it. The kind of line you'd underline in a book. Not advice, not a pep talk. A truth that lands. Different every day.}

> 💡 **`/aios:{command}`** _{brief description of what the command does}_ — {one line explaining why today, grounded in vault state}

> 🔍 **Nudge:** {task name} — {pattern-aware insight with [[wiki-links]] to observed files like [[patterns]], [[growth]], or [[session-insights]]. The reader can click through to see what Claude has observed about them.}

## Calendar
{Today's meetings and time-bound events from all configured Google Calendars, merged chronologically. If multiple accounts are configured, tag personal events with [personal] to distinguish from work events. Skip all-day non-task events. Skip calendars marked as "Skip" in USER.md Sources. Format: HH:MM – HH:MM — Event name. If no events, write "No events today."}

## Slack triage
{Scan the pre-loaded Slack data (unreads + daily recap) for anything that needs the user's attention. Two checks:

1. **Unreads:** If there are unread conversations, list each with a one-line summary and whether it needs a response. If no unreads, say "Sin unreads."
2. **Action items from recap:** Scan the daily recap for messages that require the user to do something — questions directed at them, requests, decisions pending their input, approvals needed. Extract each as a one-liner with the person who needs the response. If nothing needs action, say "Sin action items pendientes."

If both checks are clean, collapse to a single line: "✅ Sin unreads ni action items pendientes en Slack."

If there ARE action items, add them as tasks in the appropriate Rhythm block with tag `_(slack)_`. This ensures nothing from Slack gets lost.}

## Today I ship
**→ {The single most important deliverable for the day}**
_{Why this matters or what it unblocks — one line}_

## Rhythm

### Morning — Create {time range based on calendar gaps}
{Deep work, creative tasks, strategic thinking. 3 items max. This is the protected creative window before meetings take over.}
- [ ] {task} _(source)_
- [ ] {task} _(source)_

### Afternoon — Operate {time range based on calendar gaps}
{Meetings, follow-ups, operational tasks, communications. 3 items max. Work with the energy, not against it.}
- [ ] {task} _(source)_
- [ ] {task} _(source)_

### Evening — Grow
{Read the `### Growth routines` section from USER.md → `## Sources`. For each configured routine:
- Show the routine's **Streak label** as the task name
- Show the **Time** from USER.md
- Extract the next item from the named **Section** in the named **Project**'s snapshot (in `_index.md`). If the snapshot lacks detail, read only that section from the project note with `limit`.
- Add streak counter: count consecutive days where close-day's "Evening — Grow" shows that streak label completed (not "skipped").

Example output (if USER.md has Reading + Writing routines):
- [ ] **Study** (19:00): {book title} {next chapter} 🔥 Day {N} _({project})_
- [ ] **Content** (20:00): {post title} — {status} 🔥 Day {N} _({project})_

If USER.md has no `### Growth routines` section: include one gentle line: "No growth routine yet — even 20 minutes of reading or writing with Claude compounds. Add routines to USER.md → Sources to track them here."

**USER.md override:** If `USER.md` has a `### /today` section under `## Command personalizations`, read it and apply any Evening Grow overrides (e.g. hardcoded routines, non-negotiable blocks, custom time slots).}

## Parking lot
{Carried items from yesterday + today's overflow, in one place. Every carried item shows `_(carried ×N, reason: {tag})_` — the count is the audit trail, the reason is the triage. Items without a carry count are new today (overflow from Rhythm or backlog). Order: escalations first (🔴 stale/untagged ×10+), then untagged warnings (⚠️ ×6-9 asking for reason), then tagged carries (no escalation — the reason justifies them), then normal carries, then new overflow. No cap — every carried item must land here if it wasn't placed in Rhythm. This section IS the receipt that nothing was dropped.}
- [ ] 🔴 {task} _(carried ×N, reason stale)_ — **DECIDE: retag / park**
- [ ] ⚠️ {task} _(carried ×N, no reason)_ — **PICK:** `strategic-deferral` / `blocked-on-{who}` / `needs-challenge` / `waiting-on-date` / `park`
- [ ] {task} _(carried ×N, strategic-deferral)_
- [ ] {task} _(carried ×N, blocked-on-Enrique)_
- [ ] {task} _(new today, overflow)_

**Horizon (this week):**
{Google Tasks due within the next 7 days (not today), grouped by date. One line per date.}
- {Mon D}: {task1}, {task2} _(prep: {what to do before})_

## Agents can handle
🤖 **{N} tasks agents can handle:**
{List each delegatable task with its matched agent. Only tasks that an agent could realistically execute with available tools.}
- 🤖 {task} _(→ agent: [[agent-name]])_

Say "go with agents" to spawn them all, or `/agent {name}` to wear the hat yourself in this session.

## Radar

| Venture | Project | Pulse |
|---------|---------|-------|
{One row per project from 00 - notes/projects/. Group by `venture` frontmatter field (first value in array = primary group). If venture field is missing, fall back to tag/venture guess. Include ONLY `status: active` projects (the daily-Radar set) + `status: idea` at the bottom. **Skip `status: maintenance` AND `status: archived`** — maintenance projects hide from the default Radar pulse (they surface only when activity warrants, via `/housekeeping` Radar Health Audit). Each active project gets a one-line pulse:
- **Active projects:** what needs attention today, or "on track" / "blocked by X" / "waiting on Y"
- **Idea projects:** where it's at — one line to keep seeds visible
Use [[wiki-links]] for project names.}

### Radar→Rhythm nudge (system rule)

After writing the Radar table, scan the past 7 daily notes (`vault/01 - calendar/{YYYY-MM}/{YYYY-MM-DD}.md`) to detect active projects that have NOT appeared in any Rhythm block during that window. For each detected:

> ⚡ **Radar→Rhythm gap:** [[project-X]] has been on the Radar for N days without landing in a Rhythm block. **Schedule a window this week, OR demote honestly to `status: maintenance`.** Active without Rhythm presence = drift disguised as awareness.

**Detection rule:**
- Active project = `status: active` in its project note frontmatter
- Rhythm-block presence = the project's `[[wiki-link]]` OR a clearly-routed task line tagged `_(project-slug)_` appearing in any of the last 7 daily notes' Morning / Afternoon / Evening blocks (not the Radar table itself, not the Parking lot, not the Carries forward — those don't count as Rhythm presence)

**Exemption — watch-mode projects:** active projects whose single priority is explicitly "watch / await external response" (e.g. awaiting a partner's review, waiting on a counterparty's reply, blocker: external) are exempt from the nudge. Their priority IS the watch posture; they don't need a Rhythm window. Detection: project note's Active priority section contains "watch" / "waiting" / "blocker: external" language. When uncertain, ask the operator inline.

**Cap nudges at 3 per day** — surface the longest-Radar-only-stretches first. More than 3 = noise; user starts skipping.

**Nudge placement:** append to `## Energy note` block (so it lands as a system-level observation, not as a tactical task that needs a checkbox).

## Energy note
{A warm, grounded reminder about how to spend energy today. Reference actual calendar density — if it's a heavy meeting day, acknowledge it. If there's open space, name the opportunity. Think "take care of yourself buddy" energy — honest, caring, practical. Not productivity advice — human advice. End with a close-day prompt in italics — one question tied to "Today I ship."}
```

## Rules

**Performance:**
- **Payload discipline:** never read a full file when a section suffices. Daily notes: `Grep` for the heading (`### Carries forward`, `### Evening — Grow`, `- [ ]`) then read from offset. Observed context: `limit` per file. Project context: use `_index.md` snapshots first; drill into a note only if the snapshot lacks detail.
- **Never re-read files** after Message 1b. Message 2 is pure analysis + write.
- **Target: 4 messages total** — bootstrap, vault reads, analyze + write, commit. Under 60s end-to-end.
- **NEVER use the Agent tool.** Direct tool calls only (`Read`, `mcp__obsidian__*`, etc.) — Agents add minutes of latency.
- **NEVER call Google Calendar / Tasks / Slack APIs.** Pre-loaded by the pipeline executor. If it failed, tell the user to fix it — don't fall back to API calls.

**Content discipline:**
- **Daily opener:** grounded in observed context, never generic. If it could apply to anyone, rewrite.
- **"Today I ship" is sacred:** one deliverable, not "make progress on." If the day has 3+ competing priorities, name the ONE explicitly + note what's deferred ("Today I ship X. NOT Y or Z."). The deferral IS the discipline.
- **Rhythm: 3-5 items each Morning/Afternoon**, adaptive to calendar density. Heavy meeting day → 3. Open blocks → up to 5. Overflow → Parking lot. The day must feel achievable.
- **Evening — Grow is always present.** Growth routines from USER.md Sources with streak counters; if none configured, plant the seed gently.
- **Specific, not aspirational.** "Finalize GDrive folder structure and commit" beats "Work on Drive organization."
- **Keep it to one screen.** If today's plan needs scrolling, it's too much.

**Conventions:**
- `[[wiki-links]]` for any project names mentioned.
- Source tags: `_(project)_`, `_(carried ×N, reason: {tag})_`, `_(google tasks)_`, `_(suggested)_`, `_(overdue task)_`.
- Carry-reason tags: `strategic-deferral` (important but not now), `blocked-on-{who}` (external), `needs-challenge` (should I push harder?), `waiting-on-date` (time-gated). Once tagged, count alone stops escalating.
- **🤖 Proactive execution:** prefix tasks Claude can execute with available tools. Match against `agents/_index.md` (loaded in Message 1a) by domain + keywords; annotate `🤖 {task} _(→ agent: [[agent-name]])_`. After Energy note, add: `🤖 **{N} tasks agents can handle** — say "go" to spawn them, pick specific ones, or /agent {name} to wear the hat.`
- **Dependency trees:** when a task is blocked, nest the blocker beneath it with indentation.
- **After writing, commit + push** — `cd ~/aios && git add -A && git commit -m "Daily plan {date}" && git push`.

## Command Discovery Engine

One command suggestion per day, placed after the daily opener as a blockquote. Never the same command two days in a row. The suggestion must be grounded in vault state — never generic.

### Day-based triggers (default rhythm)

| Day | Command | Why |
|-----|---------|-----|
| Monday | `/7plan` | Start the week with strategic orientation |
| Wednesday | `/drift` | Mid-week honest check — what's being avoided? |
| Friday | `/weekly-learnings` | Compile the week before it fades |

### State-based triggers (override day-based when relevant)

These take priority when the vault signals something specific:

| Condition | Suggest |
|-----------|---------|
| 7+ days since last `/7plan` | `/7plan` |
| 14+ daily notes, no `/graduate` run | `/graduate` |
| 14+ daily notes, no `/emerge` run | `/emerge` |
| Growth edges changed in last 3 days | `/trace` |
| 5+ active projects with overlapping themes | `/connect` |
| Strong content in recent daily notes | `/learned` |
| Big decision mentioned in daily note or project | `/challenge` |
| Content/writing task in today's plan | `/ghost` |
| `/housekeeping` triggers (any of): 15th of month · parking-lot carries >15 · active projects >12 · 3+ snapshots stale >14 days · project-hygiene nudge fired 3+/wk · orphaned notes or broken wiki-links | `/housekeeping` |
| Role log has 2+ weeks of entries | `/role-report` |
| 1st of the month + previous month has uncompacted logs | `/compact` |
| Any mounted-company tracker >7 days stale | `/aios:company --sync {name}` (or `--sync-all`) |
| `.aios-update` synced date >14 days ago | `/aios:update` |
| INTENT.md `Updated:` date >14 days ago | (nudge only, not a command — *"Has your trust level changed? Review INTENT.md."*) |

Example phrasing should be specific to today's vault state — never generic. *"Day 5 of sales-materials avoidance — /drift will name what you're avoiding"* beats *"Try /drift."*

### Rules for suggestions
- **One per day, max.** Never two.
- **Never generic.** "Try /drift" is bad. "Day 5 of sales materials avoidance — /drift will name what you're avoiding" is good.
- **Rotate.** Don't suggest the same command two days in a row, even if the trigger still applies.
- **Skip if not ready.** If the vault doesn't have enough content for a command to produce value, don't suggest it. Empty vault + `/emerge` = bad experience.
- **First two weeks:** Stick to day-based triggers (Monday/Wednesday/Friday). Don't overwhelm new users with state-based suggestions until the vault has depth.
- **No fabricated specifics in the description.** The `_{brief description}_` must not invent counts, names, or facts the vault doesn't state — e.g. don't write *"across all four pillars"* unless the context actually defines four. Describe generically (*"across your ventures"*, *"across your pillars"*) or use the real number from context (`role-expectations.md` pillars, mounted ventures). Downstream surfaces (AIOS Glass renders this line verbatim as a nudge) amplify whatever you write — a made-up number becomes a visible lie. Honors the no-fabricated-specifics rule.

## Observed Nudges

One nudge per day — a standalone blockquote placed after the command suggestion at the top of the note. This is what makes the system feel alive — it notices things before you do.

### How it works
- Pick the ONE task that most benefits from self-awareness (usually the one being avoided or the one with a growth edge)
- Write as a standalone blockquote with the 🔍 emoji. Include `[[wiki-links]]` to the observed context file referenced (e.g. `[[patterns]]`, `[[growth]]`, `[[session-insights]]`) so the reader can click through and see what Claude has observed about them
- The nudge should be honest but warm — a friend pointing something out, not a performance review
- The task itself stays clean in the Rhythm section with just its source tag — the nudge lives at the top, not embedded in the task

### Examples
```
> 🔍 **Nudge:** SALES MATERIALS at day 5 of drift — [[patterns]]: you avoid unglamorous ops when creative energy is high. 30 min. Just start.
> 🔍 **Nudge:** Boundless study 🔥 day 4 streak — [[growth]]: evening discipline is your newest edge. Protect it.
> 🔍 **Nudge:** Foundations landing page carried ×3 — what's the real blocker? Name it at close-day.
```

### Rules for nudges
- **One per day, max.** More than one feels like nagging.
- **Only when grounded.** Must reference an actual pattern or observation from observed context. Never fabricate.
- **Skip if observed context is empty.** First-week users don't get nudges — there's nothing to draw from yet.

## Streak and Drift Counters

When displaying tasks in Rhythm sections:
- **Streaks:** Add `🔥 Day N` after tasks that have been completed consecutively (study, writing, shipping). Count from recent daily notes.
- **Drift counters:** Add `⚠️ Day N` on Parking lot items that have been carried forward N+ days without being touched. Start showing at day 3+.
- **Carried items:** Show count AND reason tag: `_(carried ×3, reason: blocked-on-Enrique)_` instead of just `_(carried)_`. Reason tags are set by close-day's triage prompt when crossing ×6 — once tagged, today stops re-asking.
