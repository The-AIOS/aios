---
tags:
  - vault-commands
  - command
  - daily
description: Generate a grounded daily plan from recent notes, open threads, and priorities
allowed-tools: mcp__obsidian__*, mcp__google-workspace__*, mcp__google-workspace-personal__*, Read, Bash(cd ~/aios && git:*), Bash(gh:*), Bash(date:*), Bash(uv run ~/aios/hooks/pipeline-executor.py:*)
---

# /today — Daily Plan

You are generating today's daily plan for the vault owner by reading their Obsidian vault.

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
- `Bash(cfg=~/aios/.vault-update; if [ -f "$cfg" ]; then repo=$(grep ^repo= "$cfg" | cut -d= -f2); h=$(grep ^hash= "$cfg" | cut -d= -f2); r=$(git ls-remote "$repo" HEAD 2>/dev/null | awk '{print $1}'); [ -z "$r" ] && echo "vault-update: unreachable" || { [ "$h" = "$r" ] && echo "vault-update: synced" || echo "vault-update: BEHIND (local=${h:0:7} remote=${r:0:7})"; }; else echo "vault-update: no-config"; fi)` — **infrastructure freshness check.** Reads `.vault-update`, asks team repo for current HEAD via `git ls-remote`, compares hashes. Returns one of: `synced` (no action), `BEHIND ...` (team repo has new commits), `unreachable` (network/auth issue), `no-config` (no Organization in USER.md). Surface the result per § Vault-update freshness rendering below.
- `Bash(prev=$(find ~/aios/vault/01\ -\ calendar -maxdepth 2 -type f 2>/dev/null | grep -E '/[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$' | grep -v "$(date +%Y-%m-%d)" | sort -r | head -1); if [ -z "$prev" ]; then echo "close-day-precondition: no-prior-note"; elif grep -q "^## Close of Day" "$prev" 2>/dev/null; then echo "close-day-precondition: closed ($(basename "$prev" .md))"; else echo "close-day-precondition: MISSING ($(basename "$prev" .md)) — must run /close-day first"; fi)` — **close-day precondition check.** Detects whether the most recent daily note BEFORE today has the `## Close of Day` heading. Returns one of: `closed (date)` (previous note closed — proceed normally), `MISSING (date)` (skipped close-day — guard fires per § Close-of-day precondition rendering below, BEFORE Message 1b runs), `no-prior-note` (first run / fresh vault — proceed normally).
- `Read` → `USER.md` (if it exists — for Sources config, `### /today` command personalizations, and organization settings)
- `Read` → `INTENT.md` (if it exists — for autonomy levels, focus weighting, parked item suppression, tradeoff rules)
- `mcp__obsidian__read_note` → `00 - notes/projects/_index.md`
- `Read` → `agents/_index.md` (canonical registry across all bundles — top-level infra, not in Obsidian vault path)
- `Read` → `agents/custom/_index.md` (if it exists — operator's custom agents)
- `mcp__obsidian__list_directory` → `00 - notes/projects/`

This gives you: USER.md personalizations, the actual weekday, what sources are configured, the project list, whether the team's shared infrastructure has updates pending, and whether the previous daily note has been closed (cascade integrity guard).

**Vault-update freshness rendering (in synthesis, Message 2):**
- **`synced`** → silent. No surface in the daily note.
- **`BEHIND`** → surface **prominently** at the very top of the daily note, before Claude's take, as a callout: `> 🆕 **Vault has updates pending** — local hash `{h}`, team repo `{r}`. Run `/aios:update` before working today to pull fresh commands, templates, settings.` This is high-priority — pulling stale infra into a long session creates rebase pain later.
- **`unreachable`** → soft mention in Energy note or as a one-liner near the bottom: *"vault-update check unreachable today (network/auth — fine for now)."* Don't escalate.
- **`no-config`** → silent (no Organization configured = single-vault user, nothing to sync).

**Close-of-day precondition rendering (handled in Message 1a, BEFORE Message 1b vault reads):**
- **`closed`** → silent. Proceed to Message 1b normally.
- **`no-prior-note`** → silent (first run, no prior note to close). Proceed normally.
- **`MISSING`** → **guard fires.** Skipping /close-day breaks the cascade chain (daily note → project notes → `_index.md` snapshots → observed context). Without the cascade, today's plan reads stale data. Surface to user and run /close-day on the previous note BEFORE proceeding with /today's vault reads:
  
  > *"Previous daily note ({date}) wasn't closed. Running /close-day on it first — this cascades carries to project notes, refreshes `_index.md` snapshots, and routes any captured insights to observed context. Without this cascade, today's plan would read stale data. Then I'll continue with /today's normal flow.*
  >
  > *Some prompts may reference older context if the previous note is from days ago — answer to the best of memory; close-day is forgiving."*
  
  Then invoke `Skill(aios:close-day)` and **wait for it to complete.** /close-day naturally picks "the most recent daily note that doesn't have ## Close of Day" — which is the same note this guard detected. After /close-day finishes (the previous note now has the heading + the cascade landed), proceed with Message 1b. **Do not skip** — the cascade is critical for /today's accuracy. /today's value compounds on cascade integrity; without it, AIOS stops compounding (carries don't reach project-notes, snapshots stale, observed context never receives the day's insights, self-update integrity breaks).

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
- Sync trackers (for freshness check): check `USER.md` → `## Companies (mounted)` for mounted-company table. For each row, read its tracker file (e.g. `.sovra-sync` in `vault/00 - notes/context/ventures/sovra/`). Plus `.vault-update` at repo root for the AIOS framework freshness.
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
- Extract carry-forwards: all unchecked `- [ ]` items from the **most recent daily note** (loaded in Message 1b — NOT yesterday's date, but the actual last note found). Search **ALL sections** — Rhythm, Parking lot, Horizon, Carries forward, AND the Close of Day `### Carries forward` subsection (inside `## Close of Day`). These are two different locations: the plan's carries and the close-day's carries. Both must be scanned. **Dedup across sections:** the same item often appears in both Rhythm/Evening and Parking lot (e.g. Boundless in Evening Grow AND in Parking lot as a forced decision). Match by core task name (ignore emojis, prefixes like 🔴, time slots, decision prompts, source tags). Keep the highest carry count and the most actionable version. Track carry count: if an item already shows `_(carried ×N)_`, increment N. **ZERO TOLERANCE for dropped items:** every unique unchecked item from the previous note must appear somewhere in today's note (Rhythm, Parking lot, or Horizon). After placing all items, do a final count: if `previous_unique_carries > today_carries`, something was dropped — find it and add it. Nothing gets silently dropped — if the most recent note is 3 days ago, those carries still surface.
- **Smart carry triage** — a carried item without a decision is just guilt on a list. Apply thresholds. **Check for a `reason:` tag before escalating** — carry format is `_(carried ×N, reason: {tag})_` where `{tag}` is one of: `strategic-deferral`, `blocked-on-{who}`, `needs-challenge`, `waiting-on-date`. A tagged reason means the user has already triaged this carry — respect it, don't re-escalate on count alone.
  - **×1-2:** Normal — show in Rhythm or Parking lot as usual. No reason tag needed yet.
  - **×3-5:** Flag with ⚠️ — still alive but needs attention. Reason tag optional.
  - **×6-9 without reason:** **Ask for reason, don't force a decision yet:** "⚠️ {task} carried ×{N}, no reason tagged. Pick: `strategic-deferral` / `blocked-on-{who}` / `needs-challenge` / `waiting-on-date` / `park`. Close-day will lock it in."
  - **×6-9 with reason:** Keep in Parking lot, show reason tag. No escalation needed — the reason explains why it's still alive.
  - **×10+ with stale reason** (e.g. `blocked-on-X` but no activity on X for 30+ days) OR **×10+ no reason after being asked:** **Escalate hard:** "🔴 {task} carried ×{N}, reason `{tag}` stale / missing. Either the reason is wrong (retag) or this should park. No more silent carries."
  - **×10+ with fresh reason:** Respect it. A ×17 tagged `strategic-deferral` that INTENT.md confirms as a parked focus is intentional prioritization, not avoidance. Show as `_(carried ×17, strategic-deferral)_` without escalation icon.
  - Place triage decisions at the top of Parking lot, not buried in Rhythm. The user should see them immediately.
- **Stale project snapshot refresh:** For any project flagged as stale in Message 1b (snapshot >7 days old), read just the `## To-Dos` section from the project note and update the `_index.md` snapshot. This prevents to-dos from going invisible in untouched projects.
- Count streaks (consecutive days of study, writing, shipping)
- Count drift counters (days an item has been carried)
- Determine the **command suggestion of the day** (see Command Discovery Engine below)
- Identify one **observed nudge** (see Observed Nudges below)
- Synthesize a **daily opener** — radically candid, grounded in observed context
- Identify the **one thing to ship**
- Sort all tasks into energy blocks: Morning (create), Afternoon (operate), Evening (grow)
- Write the daily note (preserving user edits if note already exists — keep checked items, meeting notes, user-added subtasks)

### Message 3 — Commit + push
- `cd ~/aios && git add -A && git commit -m "Daily plan {date}" && git push`

## First run handling

Detect first run by checking: `about_me.md` still has template placeholders (`{{full name}}`, `{{date}}`), AND no previous daily notes exist in the calendar folder. Don't rely on project count — the repo may ship with reference projects.

If first run:
- The daily opener should acknowledge this is a fresh start: "Day one. Everything compounds from here."
- Skip the Radar table (no user projects to show — ignore archived reference projects)
- Skip "Today I ship" (no context to derive it from)
- Skip the command suggestion and nudge (no observed context to draw from)
- Instead, present a simple "Getting Started" section:
  - [ ] Fill in `USER.md` — sources, organization, identity
  - [ ] Fill in `about_me.md` — even 5 bullets make a difference
  - [ ] Fill in `working_style.md` — how you think, decide, and prefer to work
  - [ ] Create your first project note in `00 - notes/projects/`
  - [ ] Run `/aios:today` again after filling in context
- Still use pre-loaded Calendar and Tasks data from the executor (these work immediately)

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

**Exemption — watch-mode projects:** active projects whose single priority is explicitly "watch / await external response" (e.g. waiting Mario's review, watching for Anthropic follow-up, awaiting Zi's response, blocker: external) are exempt from the nudge. Their priority IS the watch posture; they don't need a Rhythm window. Detection: project note's Active priority section contains "watch" / "waiting" / "blocker: external" language. When uncertain, ask Chuy inline.

**Cap nudges at 3 per day** — surface the longest-Radar-only-stretches first. More than 3 = noise; user starts skipping.

**Nudge placement:** append to `## Energy note` block (so it lands as a system-level observation, not as a tactical task that needs a checkbox).

## Energy note
{A warm, grounded reminder about how to spend energy today. Reference actual calendar density — if it's a heavy meeting day, acknowledge it. If there's open space, name the opportunity. Think "take care of yourself buddy" energy — honest, caring, practical. Not productivity advice — human advice. End with a close-day prompt in italics — one question tied to "Today I ship."}
```

## Rules
- **Payload discipline:** Never read a full file when a section suffices. For daily notes, search for the heading you need (`### Carries forward`, `### Evening — Grow`, `- [ ]`) then read from that offset. For observed context, split batches and use `limit` per file. For project context, use `_index.md` snapshots — only drill into a note when the snapshot lacks detail. **Safety guarantee:** carry-forward extraction must search for ALL unchecked items across ALL sections (Rhythm, Parking lot, Horizon, Carries forward, AND the Close of Day carries subsection), not just one heading. If smart read returns suspiciously few carries (0 items from a note that had 15+ tasks), fall back to full read — never silently return empty carries. **After writing the note, verify:** count unchecked items from previous note vs placed items in today's note. If any are missing, append them to Horizon before committing.
- **NEVER use the Agent tool.** Use direct tool calls only — `Read`, `mcp__obsidian__*`, etc. Agents are heavyweight subprocesses that add minutes of latency and can silently block.
- **NEVER call Google Calendar, Tasks, or Slack APIs.** The pipeline executor pre-loads this data. If it's missing or failed, tell the user to fix the executor — don't call the APIs yourself.
- **Never re-read files.** All vault data is loaded in Messages 1a+1b. Message 2 is pure analysis + write. No additional Read or MCP read calls after Message 1b.
- **Minimize tool-call messages.** Target: 4 messages total — (1a) bootstrap, (1b) vault reads, (2) analyze + write note, (3) commit. Every additional round-trip adds ~5-10s of latency. The entire command should complete in under 60 seconds.
- The daily opener must be grounded in observed context — never generic. If it could apply to anyone, it's not good enough.
- **"Today I ship" is sacred.** One deliverable. Not two, not "make progress on." One thing that's done by end of day. If the user's day has 3+ competing priorities, name the ONE and explicitly note what's deferred: "Today I ship X. NOT Y or Z — those are tomorrow." The deferral is the discipline.
- **Rhythm sections: 3-5 items each for Morning and Afternoon, adaptive to calendar density.** Heavy meeting day → lean toward 3. Open blocks → up to 5. Overflow goes to Parking lot. The day must feel achievable, not overwhelming.
- Evening — Grow is always present. If the user has growth routines configured in USER.md Sources, show them with streak counters. If not, plant the seed — don't force it.
- Be specific, not aspirational. "Finalize GDrive folder structure and commit" not "Work on Drive organization."
- Surface unresolved items from previous days — don't let things drift silently
- **Keep it to one screen.** If today's plan needs scrolling, it's too much.
- Use `[[wiki-links]]` for any project names mentioned.
- Source tags: _(project)_, _(carried ×N, reason: {tag})_, _(google tasks)_, _(suggested)_, _(overdue task)_
- **Carry-reason tags** (set by close-day, displayed by today): `strategic-deferral` (important but not now), `blocked-on-{who}` (waiting on external), `needs-challenge` (should I push harder?), `waiting-on-date` (time-gated). Once tagged, count alone stops triggering escalation.
- **🤖 Proactive execution labels:** When writing tasks in Rhythm, Parking lot, or Horizon, add a 🤖 emoji before any task that Claude can execute directly with available tools (send messages, write docs, update boards, research, etc.). **Agent matching:** if the agents index was loaded (Message 1a), match delegatable tasks against the agent registry by domain + keywords. Annotate matched tasks with the agent: `🤖 {task} _(→ agent: [[sales-lead-hunter]])_`. After the Energy note, add a one-liner: `🤖 **{N} tasks agents can handle** — say "go" to spawn them, pick specific ones, or /agent {name} to wear the hat yourself.` This makes the proactive execution visible without cluttering the note with a separate section.
- **Show dependency trees.** When a task is blocked, nest the blocker underneath it with indentation. The reader should see what unblocks what at a glance. Example:
  ```
  - [ ] Ship feature _(project)_
  	- [ ] blocked by API integration
  		- [ ] Complete API setup _(suggested)_
  ```
- After writing the note, commit and push: `cd ~/aios && git add -A && git commit -m "Daily plan {date}" && git push`

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

| Condition | Suggest | Example line |
|-----------|---------|-------------|
| 7+ days since last `/7plan` | `/7plan` | "No weekly plan in 8 days. The week is steering you." |
| 14+ daily notes, no `/graduate` run | `/graduate` | "14 days of ideas piling up. Promote the best ones." |
| 14+ daily notes, no `/emerge` run | `/emerge` | "The vault knows things you haven't written yet." |
| Growth edges changed in last 3 days | `/trace` | "Your growth edge shifted. See how the thinking evolved." |
| 5+ active projects with overlapping themes | `/connect` | "15 projects, some rhyming. Find the bridge." |
| Strong content in recent daily notes | `/learned` | "This week's insights are publish-ready. Distill them." |
| Big decision mentioned in daily note or project | `/challenge` | "Steel-man your thinking before you commit." |
| Content/writing task in today's plan | `/ghost` | "Need to write in your voice? Let the vault do it." |
| 15th of the month (default mid-month rhythm) | `/housekeeping` | "Mid-month. Time to tidy the vault." |
| Parking-lot carries > 15 items | `/housekeeping` | "{N} open carries. The vault is heavy — merge / drop / reassign." |
| Active project count > 12 | `/housekeeping` | "{N} active projects. Worth a merge/archive pass?" |
| 3+ project snapshots stale > 14 days | `/housekeeping` | "3 snapshots haven't been touched in 2 weeks." |
| `/close-day` project-hygiene nudge fired 3+ times in a week | `/housekeeping` | "Project notes trending long. Housekeeping?" |
| Orphaned notes growing OR broken wiki-links detected | `/housekeeping` | "Vault link health — some notes are islands." |
| Role log has 2+ weeks of entries | `/role-report` | "Enough data for a role report. Draft one." |
| 1st of the month (and previous month has uncompacted logs) | `/compact` | "New month. Compact last month's snapshots — digest + zip." |
| Any mounted-company tracker > 7 days stale (per USER.md `## Companies (mounted)`) | `/company --sync {name}` or `/company --sync-all` | "Context for {N} mounted compan{y/ies} stale > 7 days. 30 seconds to refresh." |
| `.vault-update` synced date > 14 days ago | `/aios:update` | "Team shipped updates 2 weeks ago. Check what's new." |
| INTENT.md `Updated:` date > 14 days ago | nudge (not a command) | "Your intent hasn't been updated in {N} days. Has your trust level changed? Review INTENT.md." |

### Rules for suggestions
- **One per day, max.** Never two.
- **Never generic.** "Try /drift" is bad. "Day 5 of sales materials avoidance — /drift will name what you're avoiding" is good.
- **Rotate.** Don't suggest the same command two days in a row, even if the trigger still applies.
- **Skip if not ready.** If the vault doesn't have enough content for a command to produce value, don't suggest it. Empty vault + `/emerge` = bad experience.
- **First two weeks:** Stick to day-based triggers (Monday/Wednesday/Friday). Don't overwhelm new users with state-based suggestions until the vault has depth.

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
