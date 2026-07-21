---
tags:
  - aios
  - command
  - daily
description: End-of-day review — capture what shipped, what grew, and what carries forward
allowed-tools: mcp__obsidian__*, mcp__google-workspace__*, mcp__google-workspace-personal__*, Read, Bash(cd ~/aios && git:*), Bash(uv run ~/aios/hooks/pipeline-executor.py:*)
---

# /close-day — End of Day Review

You are running the user's end-of-day review by reading their vault and capturing what happened.

## When to use

Every evening at the end of the working day. Captures what shipped, routes session insights to observed context (so Claude actually gets smarter), closes the carry-loop so nothing falls through, and surfaces drift before it becomes invisible. The system's nervous-system command.


## Pre-loaded API data

Step 1 runs `uv run ~/aios/hooks/pipeline-executor.py --command close-day` which pre-loads Google Calendar events **with attachments** (today + next 7 days for cross-check), Google Tasks (open), and Slack unreads + daily recap.

**DO NOT call Google Calendar `get_events`, `list_tasks`, or Slack APIs.** The data is in the executor output.

**You STILL need `mcp__google-workspace__*` for:** fetching Google Doc content from calendar attachment `fileId`s (step 4 below). The executor lists the attachments; you fetch the doc content.

**If the executor output shows `❌ FAILED` for a specific source:** tell the user what failed and how to fix it. Use the data that did load.

## Steps

1. **Run executor + read vault** — fire these in **one parallel batch**:
   - `Bash(uv run ~/aios/hooks/pipeline-executor.py --command close-day)` — pre-loads Calendar (detailed, with attachments), Calendar next 7 days, Tasks, Slack
   - `Bash(cfg=~/aios/.aios-update; if [ -f "$cfg" ]; then repo=$(grep ^repo= "$cfg" | cut -d= -f2); h=$(grep ^hash= "$cfg" | cut -d= -f2); r=$(git ls-remote "$repo" HEAD 2>/dev/null | awk '{print $1}'); [ -z "$r" ] && { hr=$(echo "$repo" | sed -E 's#git@github\.com:#https://github.com/#'); r=$(git ls-remote "$hr" HEAD 2>/dev/null | awk '{print $1}'); }; [ -z "$r" ] && echo "aios-update: unreachable" || { [ "$h" = "$r" ] && echo "aios-update: synced" || echo "aios-update: BEHIND (local=${h:0:7} remote=${r:0:7})"; }; else echo "aios-update: no-config"; fi)` — **infrastructure freshness check** (mirror of `/today`'s morning check; SSH `ls-remote` falls back to public HTTPS so a fresh HTTPS clone with no SSH keys still resolves). Render per § Aios-update freshness rendering below — at end-of-day, the framing shifts from "before working today" to "before sarah's overnight queue (or first thing tomorrow)".
   - `Read` → `USER.md` (for dev project paths, growth routines, session cascade, organization, and `### /close-day` command personalizations)
   - `Read` → `INTENT.md` (if it exists — for focus alignment check, parked item handling in carries)
   - Read the daily note to close: list files in `01 - calendar/{YYYY-MM}/`, pick the **most recent `YYYY-MM-DD.md`** (exclude weekly plans like `W{N}-plan.md`). If it's after midnight and no note exists for today, the most recent note is yesterday's — close that one. If it already has a `## Close of Day` section, update it (merge new info, don't duplicate). **Always tell the user which date you're closing:** "Closing {date}."
   - Read `00 - notes/context/observed/session-insights.md`
   - Read `00 - notes/projects/_index.md` for the consolidated project view
2. Check what project notes were recently modified (to know which snapshots to refresh)
3. **Review calendar events from pre-loaded data.** The executor output includes descriptions and attachment metadata (fileId, mimeType, title) for each event. Common attachment types:
   - "Notes - {meeting name}" — shared meeting notes (Google Doc)
   - "Notas de Gemini" — AI-generated transcription/summary from Google Meet (Google Doc)
   - Recording files (video/mp4) — skip these, note they exist
   - Chat logs (text/plain) — fetch if available via Drive
4. **Follow linked documents** — scan the pre-loaded event descriptions and attachments for Google Docs. For each Google Doc found (MIME type `application/vnd.google-apps.document`):
   - Use the `file_id` from the executor's attachment metadata
   - Fetch the content using `mcp__google-workspace__get_doc_as_markdown` (preferred) or `mcp__google-workspace__get_doc_content`
   - Attach the fetched content to that event's notes, labeled by source (e.g., "Gemini transcription", "Meeting notes doc")
   - **Skip** non-Google-Doc attachments (recordings, Drive folders, Sheets, etc.) — just note they exist
   - If a doc fetch fails (permissions, deleted), note it and move on — don't block the review
   These fetched docs become the richest source for meeting routing.
5. **Read dev session reports** (see Dev Session Reports below)
6. **Route meeting notes** (see Meeting Notes Routing below)
7. **Cross-check calendar vs planned tasks** — use pre-loaded "Calendar next 7 days" data (see Calendar Cross-Check below)
8. **Slack daily recap** — if the pre-loaded data includes "## Slack Daily Recap", summarize the day's Slack activity (see Slack Recap below)
9. **Resolve handoff items** (see Handoff Resolution below)
10. Ask the user: "What happened today that isn't in the notes? Anything on your mind?"
11. Synthesize the review
12. **Truth-surface reconcile (ship-time truth-flip — see CLAUDE.md § Discipline).** For each ship in today's note (the `### Shipped` candidates + `[x]` items), verify its truth surface already flipped: keyed items (grep the key's definition — a live `type: roadmap` file) show ✅ + their declared `ledger:` row appended; unkeyed items show done at their project note. Any miss → flip it now and record the miss in the Observed line (a repeated miss pattern is antifragile material). Close-day is the backstop, never the primary writer.
13. **Update weekly plan progress** (see Weekly Plan Progress Update below)
14. **Sync Google Tasks** — use pre-loaded Tasks data (see Google Tasks Sync below)

## Aios-update freshness rendering

Apply the result from step 1's `.aios-update` check (BEHIND / synced / unreachable / no-config):

- **`synced`** → silent. No surface in the close-of-day section.
- **`BEHIND`** → surface as a callout at the top of the `## Close of Day` block, before the verdict line: `> 🆕 **Aios-update pending** — local hash `{h}`, upstream `{r}`. Run `/aios:update` before sarah's overnight queue (or first thing tomorrow morning) so fresh commands/templates land in her shift.` This is consequential at close-day specifically because sarah's queue is generated FROM your local state — stale local = stale handoff.
- **`unreachable`** → soft mention near the Observed section: *"aios-update check unreachable at close (offline — fine for now; /today will retry tomorrow)."* Don't escalate.
- **`no-config`** → silent (no Organization configured = single-vault user, nothing to sync).

**USER.md override:** if `USER.md` → `## Command personalizations` → `### /close-day` (or `### /today`) has an aios-update nudge suppression (e.g., for users who are upstream authors of the team repo), apply it. The check still runs; rendering is muted per the personalization.

## Output

Append to the daily note being closed (may be today or yesterday if closing after midnight):

```
---

## Close of Day

> {Two sentences max. The honest, warm, big-picture read of what this day actually was. Not a summary — a verdict. Written like a friend who watched the whole day and wants to name what happened before you forget. This is the line you'll re-read in 6 months and remember exactly how the day felt.}

### Shipped
{Did the "Today I ship" deliverable land? Be honest — yes/no + what actually happened.}
- ✅ {what shipped} or ❌ {what didn't and why}

> 🎯 {the win that matters most today and why — one line of genuine appreciation, not performative}

### Rhythm check
- **Morning — Create:** {what happened in the creative block}
- **Afternoon — Operate:** {what happened in the operational block}
- **Evening — Grow:**
  - 📖 Study: {what was studied, or "skipped — {reason}"}
  - ✍️ Content: {what was produced, or "skipped — {reason}"}

### Transfer check
- [ ] Project notes updated with today's work
- [ ] Session insights captured
- [ ] Growth edges noted (if any)
- [ ] Antifragile rules written (if corrections happened)
{Catches the "rush to commit" pattern — did today's insights reach the right place?}

### Learned
- {Key insights, realizations, or pattern shifts — not what was done, but what was understood}

### Most useful (user's reflection)
{User's verbatim answer to "What was most useful for you today?" — one line, in their words. Skip if the day was purely operational with no substantive sessions.}

### Decision journal (only if a significant decision was made today)
{Only when the user made a real decision — parked vs committed, new project, pricing, team restructure. Not for routine task decisions.}
**Decision:** {what was decided}
**Diagnosis:** {what the real challenge was}
**Options:** {what was considered}
**Reasoning:** {why this option}
**Confidence:** {%}
**Revisit if:** {what would change the mind}
**Review date:** {90 days from now}

### Carries forward
- [ ] {Items that didn't get done or need follow-up — these feed tomorrow's /today. Format: `- [ ] {task} _(carried ×N, reason: {tag}, from: {origin})_` where N = previous count + 1 (or 1 if new), `{tag}` is one of: `strategic-deferral` / `blocked-on-{who}` / `needs-challenge` / `waiting-on-date`, and `{origin}` is the provenance stamp (see § Cascade ledger — where the item first came from, so it never reads as a mystery in tomorrow's plan). Reason tags are set by the carry-triage prompt below — once tagged, /today stops re-asking.}

### Observed
- {Meta-patterns: energy, focus, what worked, what was avoided. Feed /drift.}

```

## Carry-reason triage prompt

Before writing `### Carries forward`, scan each item crossing into tomorrow. **(Consult the `sustainable-cadence` skill before pathologizing a carry:** a window-cadence or quality-gate carry is *paced* work, not drift — the count is context, not guilt. Discriminate a legitimate rhythm from genuine avoidance first.) For any carry where `N+1 ≥ 6` and there is no `reason:` tag yet (or the existing tag has become stale — e.g. `blocked-on-X` but no activity on X for 30+ days), **ask the user inline**:

```
⚠️ Carry triage — these need a reason tag before they cross tomorrow:

1. "{task A}" — carrying to ×{N+1}, no reason tagged.
   Pick: strategic-deferral / blocked-on-{who?} / needs-challenge / waiting-on-date / park

2. "{task B}" — carrying to ×{N+1}, current reason "blocked-on-Enrique" is 32 days stale.
   Retag or reaffirm: same-reason-still-valid / new-reason / park

(Reply with the number + choice, e.g. "1 strategic-deferral, 2 park". Untagged carries get ⚠️ in tomorrow's plan; tagged ones don't.)
```

Wait for the response. Then write `### Carries forward` with the updated tags applied. If the user picks `park` → move that carry to the relevant project note's Ideas section instead, and don't carry it forward. If the user doesn't respond (non-interactive close-day), keep carries untagged and let tomorrow's /today ask again — never silently tag.

**Don't ask for reasons below ×6.** A carry ×1-5 isn't a pattern yet; forcing a tag at ×2 is noise.

**Don't re-ask tagged carries.** If `_(carried ×8, reason: strategic-deferral)_` and today didn't change that context, carry it forward as `_(carried ×9, reason: strategic-deferral)_` — no prompt.

## "File answers back" check

After writing the Close of Day block, scan the day's sessions for discoveries worth filing as permanent pages — analyses, comparisons, research, frameworks, reflections, or insights that would be valuable in 3 months. These shouldn't live only in the daily note or chat history.

Prompt the user:

```
📄 **Worth filing?** Today produced insights that could be permanent pages:
- "{insight title}" → `reflections/{slug}.md`
- "{insight title}" → `ideas/{slug}.md`

File them now, or skip?
```

If yes → write the pages (with `[[wiki-links]]`, proper frontmatter, source attribution), update the relevant `_index.md`. If no → move on. If the day was purely operational with no reusable discoveries, skip the prompt silently.

**Rule:** Good answers compound when filed. Daily notes and chat history don't. The LLM does the bookkeeping; the human just says "yes, file it."

## Dev session reports

If `USER.md` → `## Sources` has a `### Dev projects` table, read `.claude/session-report-{YYYY-MM-DD}.md` (using today's date) from each project's local directory. Use the `Read` tool with absolute paths — expand `~` to the full home path (e.g., `/Users/{username}/code/{project}/.claude/session-report-2026-03-16.md`).

For each file that exists:
- **"What shipped"** → include in Close of Day > Shipped section
- **"Decisions"** → route to the matching project's Session Notes (same routing rules as meeting notes)
- **"Pendientes"** → include in Carries forward
- **"Notes"** → feed Learned + Observed sections
- **"Observed"** (if present) → route to the appropriate Tier A observed context file (`patterns.md`, `preferences.md`, `business.md`, `antifragile.md`). Snapshot before editing. This is how Tier A observations from standalone project sessions reach the vault — no context is lost even when Claude isn't running in the vault terminal.
- **"Observed (Tier B candidates)"** (if present) → DO NOT write to `growth.md` / `profile.md` / `ecosystem.md` directly from this routing. Instead, feed these candidates into the Tier B digest pass (see § Tier B observation pass below). The digest enforces the substance bar across all sessions for the day before any Tier B write fires — preventing per-session-noise amplification.

**If the summary includes a `## Project Note Updates` section:**
- **Current State:** merge into the project note's `## Current State` section (replace or complement — use judgement)
- **To-Dos:** mark `[x]` items as completed in the project note, add new `[ ]` items to the appropriate tier (High Priority, Normal, Ideas)
- **Session Notes Entry:** insert at the top of the project note's `## Session Notes` section (newest first). If the heading doesn't exist, create it.
- **Present the proposed updates to the user before applying.** Show a table:

> **Project note updates from dev sessions:**
> | Project | Changes |
> |---------|---------|
> | {project} | {1-line summary: what's updated in Current State, how many to-dos changed, session entry added} |

- **Wait for confirmation** before writing to project notes.

**Missing files:** skip silently (not every project has a session every day).
**Reports from previous days:** also check yesterday's date if yesterday's `/close-day` was not run (no close-of-day section in yesterday's daily note). For older reports, warn: "Found session report from {date} in {project} — skipping (stale). Run `/close-session` in that terminal to regenerate."

After processing, present a summary to the user:

> **Dev sessions detected:**
> - {project}: {1-line summary of what shipped}

Then continue with agent session reports.

## Agent session reports

Check for close-session reports from agent/spawned sessions. These follow the same pattern as dev session reports but originate from `spawn` or `/agent` workflows.

**Where to look:** Agent sessions spawned at the vault root write their close-session reports to `~/aios/.claude/session-report-{YYYY-MM-DD}.md` (same directory, possibly multiple reports if several agents ran). Use `Read` with absolute path. Also check for any session reports in Dev project paths that mention an agent name from `agents/_index.md` (canonical registry across all bundles) or `agents/custom/_index.md`.

**For each agent report found:**
- Route output the same way as dev session reports (shipped → Shipped, pendientes → Carries, notes → Learned)
- **Add an "Agent work" line** in the Close of Day output:
  ```
  ### Agent work
  - 🤖 [[sales-lead-hunter]]: qualified 3 leads, drafted 2 outreach emails (Gmail drafts)
  - 🤖 [[code-reviewer]]: reviewed PR #42, flagged 1 security issue
  ```
- In carries: annotate tasks that can be re-assigned to agents tomorrow with `_(→ [[agent-name]])_`

**If no agent sessions ran today:** skip this section silently.

## Stakeholder-aware meeting prep

If today's daily note has meetings whose names match stakeholder groups from venture `## Stakeholders` tables (e.g. "Founders [weekly]" → founders, "Sales Team [Sprint Review]" → sales-team, "Company [bi-weekly]" → team), auto-generate a filtered section in the close-of-day output:

```markdown
### {Group}-relevant today
{Filter projects where '{group}' is in `stakeholders[]` frontmatter. For each, one-line pulse from _index.md snapshot. Only include projects with activity or updates today.}
```

If no meetings match stakeholder groups, skip this section silently.

## Project note hygiene check

After writing the close-of-day, check line count of any project notes that were touched during this session:

- **Under 200 lines** — no action
- **200-300 lines** — append to close-of-day: "⚠️ [[project]] is at {N} lines. Consider archiving older session notes and shipped items."
- **Over 300 lines** — append to close-of-day: "🔴 [[project]] is at {N} lines — dashboard, not history book. Move shipped items to git log, trim session notes to last 5."
- **Skip projects with `exempt-line-check: true` in frontmatter.**

## Slack daily recap

If the pre-loaded data includes `## Slack Daily Recap`, use the raw messages to produce:

1. **Activity summary** — one paragraph per channel with significant activity. Skip channels where nothing notable happened. Focus on decisions, announcements, requests, and status updates — not casual chat.
2. **Pendings for you** — action items that require the user's response or follow-up. Present as a table:

> **Slack pendings detected:**
> | Channel/DM | From | What needs your response |
> |------------|------|-------------------------|
> | #{channel} | {person} | {what they need from you} |

3. **Route to projects** — if a Slack conversation clearly relates to a project, include the key point in the project's Carries forward or Session Notes (same routing as meeting notes).

If `## Slack Daily Recap` is not in the pre-loaded data (recap not configured or Slack not configured), skip this section silently.

## Session cascade actions

Read `USER.md` → `## Session cascade`. If any rules apply to your current identity, follow them — read the referenced files, execute any actions described (resolve items, update status, leave notes). Cross-reference pending items against today's shipped work.

If no session cascade is configured or nothing applies, skip silently.

## Calendar cross-check

Use the pre-loaded calendar data: "Google Calendar — Primary" (today's events) and "Google Calendar — Next 7 days" (for upcoming matches). If a personal calendar is configured, its data appears as "Google Calendar — Personal". **Do not call `get_events` — the data is already loaded.**

Compare against the planned tasks in the daily note (Rhythm section + Parking lot + Carries forward).

**Match rule:** an event matches a task if they share a person name, project name, or 2+ significant words (excluding stop words like "call", "meeting", "review", "con", "de"). Example: "Llamar a GSZ" matches "Call con GSZ" (shared: "GSZ").

**Today's events:** flag meetings that may have resolved or advanced a planned task. The user may have completed a task without reporting it.

**Next 7 days:** flag upcoming meetings that will likely resolve a pending task. This helps identify carries that don't need active follow-up because a meeting is already scheduled.

Present only confident matches (skip weak or ambiguous ones):

> **Calendar vs planned tasks:**
> | Event | Date | Possible match | Status? |
> |-------|------|---------------|---------|
> | {today's event} | Today | {planned task} | Done? Partial? |
> | {upcoming event} | {date} | {carried task} | Scheduled — will resolve in meeting |

Ask for confirmation before marking anything as shipped or removing from carries.

## Meeting notes routing

Gather meeting notes from **two sources** and merge them:
1. **Calendar event descriptions** — fetched from Google Calendar in step 5. These are notes attached directly to the event (agenda, minutes, action items, links).
2. **Daily note annotations** — any notes the user wrote under events in the Calendar section of the daily note.

If both sources have content for the same event, combine them (event description first, then daily note additions). If only one source has content, use that. For each meeting with notes:

1. **Match meetings to projects using `_index.md` snapshots first** (already loaded). Only read the full project note if the match is ambiguous or the snapshot lacks context for routing.
2. **Propose routing** — show the user a table:

| Meeting | → Project | Key items to route |
|---|---|---|
| {meeting name} | `[[project]]` | {1-line summary of what goes to the project} |
| {meeting name} | **New project: `{name}`** | {why it needs a new note} |

3. **Wait for confirmation** before writing anything
4. **After approval**, append a dated entry under the `## Session Notes` heading in each matched project note. If the heading doesn't exist, create it first (with `<!-- Running log of work sessions — newest first -->`). Insert new entries at the top (newest first):

```
### {YYYY-MM-DD} — {meeting name}
{Substance of the meeting — decisions, action items, context. Not a transcript.}
- [ ] {any follow-up tasks}
```

### Routing rules
- **Meeting notes may be in Spanish** — project entries are always written in **English**. Translate the substance, not word-for-word.
- If a meeting clearly maps to an existing project, route it there
- If no project matches, **suggest creating a new one** with a name and one-line description. Ask before creating.
- One meeting can route to multiple projects if it touched several topics.
- Keep the daily note meeting notes intact — they're the raw capture. The project entry is the processed version.

## Growth routines update

Read the `### Growth routines` section from `USER.md` → `## Sources`. For each configured routine, check if Evening — Grow produced progress today.

### If routines are configured and activity happened
For each routine that had activity:
1. Open the **Project** named in USER.md
2. Find the **Section** named in USER.md (e.g., "Reading Queue", "Writing Queue")
3. Update progress in that section based on what was done

**Present proposed changes before writing:**

> **Growth routine updates:**
> | Routine | Project | Change |
> |---------|---------|--------|
> | {streak label} | [[{project}]] | {old state} → {new state} |

Wait for confirmation before writing to project notes.

### If routines are configured but were skipped
Don't silently ignore it. Note it in the close-of-day Observed section:
- **Single miss:** "Evening Grow skipped — {routine}. One miss is human." No alarm.
- **Two consecutive misses:** "🔴 {routine} missed twice — one miss is human, two is a system alert. What's blocking it?" This is the andon cord for habits. The system cares about the SECOND miss, not the first.
This feeds `/drift` and `/today`'s nudge engine. No judgment on single misses — firm on consecutive ones.

### If USER.md has no `### Growth routines` section
Include a gentle nudge in the close-of-day: "No growth routines configured yet — even 20 minutes of reading or writing with Claude compounds. Add a `### Growth routines` section to `USER.md` → `## Sources` to start tracking streaks."

### Feed insights into project pillars
If a growth session produced actionable insights (protocols, techniques, practices), route them to the relevant project note's appropriate section. One-liners that change behavior, not study summaries. Don't duplicate — if the action is already there, skip it.

## Role log (automatic + enrichment)

Check if `00 - notes/context/declared/role-expectations.md` exists.
- If yes: scan today's daily note for activities that map to any pillar in role-expectations.md. If **any** role-relevant work happened today, **automatically** create the role log — don't wait for the user to confirm. Tell the user what you logged so they can add or correct.
- **Use exact pillar names from role-expectations.md as `## ` headings.** Read the `### {N}. {Pillar Name}` headings from the file and use them verbatim (e.g. `## Vision`, `## Alliances`, `## Representation`, `## Capital`, `## Brand`, `## Cohesion`). Do NOT invent variations like "Vision & Strategy" or "Alliances & Partnerships" or prefix with numbers. Consistent naming is critical — `/role-report` reads these headings to aggregate across days.
- Create `00 - notes/logs/role-logs/{YYYY-MM}/{today YYYY-MM-DD}-role-log.md` with activities organized by pillar (create the monthly subfolder if it doesn't exist). Also add an `## Other work` section at the bottom for anything real that happened but doesn't map cleanly to a pillar. Write each entry at the level of contribution and value — not the task description. Ask: what did this work enable, protect, or improve for the company? One line that captures that, not a list of what was done. Skip "Other work" if nothing to log there. End every role log with: `See [[role-expectations]] | [[logs/_index|Logs]] | \`aios:role-report\``
- After creating the auto-log, ask: "Anything else to add to the role log? (skip if nothing)" — this lets the user enrich with context the daily note doesn't capture.
- If no tasks during the day were relevant to any pillar: skip — don't create empty files.

## Daily task → project note sync

Before refreshing snapshots, sync today's daily note tasks back to project notes. This is the reverse flow — `/today` pulls from projects, `/close-day` pushes back.

### Checked items (mark done in project notes)
Scan today's daily note for all `- [x]` items. For each, identify the source project (from the `_(project)_` tag, or infer from the task description matching a project's to-do list). If a matching `- [ ]` item exists in the project note, mark it `- [x]`. **Exclude the `## Agents can handle` section from this scan** — it's a regenerated mirror, not a task source, so it must never be synced to project notes or carried.

### Agents-can-handle reconciliation (keep the mirror honest)
Scan the `## Agents can handle` section. For each suggestion whose canonical task is done elsewhere in the note (`[x]` or `~~struck~~`, matched by core task identity — ignore emojis, time slots, source tags), strike the suggestion line `~~…~~ ✅` if it isn't already marked. This keeps the closed note internally consistent so tomorrow's `/today` (which rebuilds the section fresh) and the Glass count never see a phantom delegatable task. Don't carry these lines forward — `/today` regenerates the section.

### Unchecked items with carry history (flag in project notes)
Scan today's daily note for all `- [ ]` items that show `_(carried ×N)_` where N ≥ 3. For each, check if the item exists in the project note's to-dos. If it does, add `⚠️` flag if not already present — this surfaces chronic carries in the project view, not just the daily note. **Tagged-reason exception:** if the carry has `reason: strategic-deferral` and is aligned with INTENT.md focus pillars, suppress the ⚠️ — it's deliberate, not drift.

### New tasks discovered during the day
If the user added tasks to the daily note that don't exist in any project note (user-added subtasks, ad-hoc items), suggest routing them:

> **New tasks to route to projects:**
> | Task | Suggested project | Action | Origin |
> |------|------------------|--------|--------|
> | {task} | [[project]] | Add to {High/Normal} to-dos | {where it came from — see provenance rule below} |

Wait for confirmation before writing to project notes.

## Cascade ledger (provenance + surfacing preview)

> The trust layer on the cascade. Before the snapshots refresh makes anything surface in tomorrow's `/today`, present ONE consolidated, legible ledger of everything cascading into project notes + everything that will surface tomorrow — each line carrying its **origin**. This is what lets the operator trust the pipeline instead of re-auditing it: nothing surfaces tomorrow that wasn't shown + traceable tonight.

**Provenance stamp (the rule).** Every item that cascades into a project note OR will surface in tomorrow's `/today` carries an inline origin tag: `_(from: {source} · {date})_`. Sources: `session-insight` (Reinforced/Emerging), a specific meeting or dev-report, an audit / `/ingest` finding, a carry from {date}, an explicit user request. **An item with no traceable origin is a bug — flag it, don't surface it silently.** (Worked example: a "Zineb fee in writing" task surfacing as `_(from: 2026-06-11 protocols audit · 6-F3)_` reads as a known suggestion, not a mystery — the difference between trust and "where did this come from?")

**The ledger — present, then confirm (ONE pass; this consolidates the per-section project-note confirmations above into a single review):**

> **📋 Cascade ledger — confirm before it surfaces tomorrow:**
>
> **Into project notes:**
> | Project | What | Origin |
> |---|---|---|
> | {project} | {new to-do / status change / session-note entry} | {origin} |
>
> **Surfacing in tomorrow's `/today`** (carries forward + newly-added project to-dos):
> | Item | Project | Origin |
> |---|---|---|
> | {task} | {project} | {origin} |
>
> **Routed into observed context** (Tier A session-insights → target files — these change how Claude reads you, not what surfaces tomorrow; shown for traceability):
> | Insight | Routed to | Origin |
> |---|---|---|
> | {Reinforced entry title} | [[{target file}]] | `_(from: session-insight · {first-seen date})_` {append `· auto-routed (2-day bound)` if it hit the untriaged bound} |
>
> Reply to confirm, or flag any line that looks wrong, orphaned, or shouldn't surface.

- **Wait for confirmation.** On confirm → proceed to the snapshots refresh (which is what makes these surface in `/today`). On a flagged line → fix or drop it *before* it cascades.
- **Why (kills the three cascade-trust failures):** *dropped ball* — the operator sees the full surfacing set and can spot the missing one; *weird tasks* — every item shows its origin; *"can't trust it so I re-check everything"* — traceability replaces re-audit. The compounding is untouched (insights still route, growth edges still get named) — it's just made **legible**.
- **Non-interactive close** (no operator present): write the ledger into the close-of-day note as a record and proceed; tomorrow's `/today` still surfaces each item with its origin tag intact.

## Project snapshots refresh

After the task sync above, refresh `00 - notes/projects/_index.md` — the consolidated view that `/today` and `/7plan` read instead of all individual project notes.

**What to update:** The `## Project Snapshots` section.

### Cold start (no `## Project Snapshots` section exists yet)

This happens on the first `/close-day` ever, or if the _index still has placeholder text. **Build the full snapshots from scratch:**

1. List all project notes in `00 - notes/projects/` (excluding `_index.md`)
2. Read all project notes (batched in groups of 10) — **payload discipline:** use `limit:40` per note. Only extract frontmatter + Current State + To-Dos. Skip architecture, session notes, decisions log, links.
3. For each project, generate a snapshot entry with:
   - **`[[project-name]]` — status** (bold link + status from frontmatter)
   - **Context paragraph** (1-3 sentences): what the project is, where it stands, what's hot/blocked. Written so `/today` and `/7plan` don't need the full note.
   - **Open to-dos**: all unchecked `- [ ]` items. `**High:**` prefix for high priority, no prefix for normal, `*Blocked:*` for blocked items, `_(N ideas in project note)_` for ideas/someday. Include carry counts if tracked: `_(carried ×N)_`.
4. Group by domain (derive from project tags or default to the venture association). Add a `### {Domain}` header per group.
5. Also create/update the project tables at the top of `_index.md` (one table per domain with Project, Type, Status columns).
6. Add timestamp: `*Last refreshed: {YYYY-MM-DD} via /close-day*`

This first run is slower (~18 project reads), but every subsequent run is fast.

### Incremental update (snapshots already exist)

1. **Determine which projects to refresh.** A project is "touched" if ANY of these are true:
   - Its files were modified today
   - It was referenced in meeting notes routed today
   - It had to-dos completed or added in the daily task → project sync above
   - It had a task in today's daily note (checked OR unchecked — any appearance counts)
2. For each touched project, read the actual project note and update its `_index.md` entry:
   - **Context paragraph** — refresh with current state
   - **Open to-dos** — sync with project note's actual to-dos (including any newly marked `[x]` or newly added items)
   - **Carry counts** — if a to-do has been unchecked in daily notes for N days, show `_(carried ×N)_`
3. For projects **not touched today**: leave their snapshot as-is (it was accurate at last refresh).
4. If a project's **status changed** (e.g. active → archived, idea → active): update both the project table at the top and the snapshot.
5. If a **new project note was created**: add it to the domain table and create a new snapshot entry.
6. Update the timestamp: `*Last refreshed: {YYYY-MM-DD} via /close-day*`
7. Use `[[wiki-links]]` for project names.

**Important:** The definition of "touched" is broader than before — it includes any project that appeared in the daily note, not just files that were modified. This ensures daily note tasks stay in sync with project snapshots.

## Weekly plan progress update

If a weekly plan exists (`01 - calendar/{YYYY-MM}/{YYYY}-W{WW}-plan.md`), update it with today's progress:
- Mark completed items from today's close-of-day as `[x]` in the weekly priorities
- Add notes to items that moved or got blocked (e.g., `→ moved to Thu`)

Show the proposed changes before writing:

> **Weekly plan updates:**
> - [x] {completed item}
> - {item} → moved to {day}

Apply after user confirms (or bundle with Google Tasks confirmation to avoid two separate prompts).

## Google Tasks sync

After writing the close-of-day section, sync task completions and carries with Google Tasks. Use the pre-loaded "Google Tasks" data from the executor for the open tasks list — **do not call `list_tasks` again.**

Use `mcp__google-workspace__manage_task` to mark tasks complete and create new carry tasks.

### Mark completed

Scan today's daily note for checked items (`- [x]`). For each, search open Google Tasks for a matching title. If found, mark as completed via `mcp__google-workspace__manage_task` (action: update, status: completed).

### Create carries

For each item in "Carries forward," check if a Google Task with a similar title already exists among open tasks. If not, create a new task with:
- **Title:** the carry item text (clean — no source tags, no wiki-links)
- **Due date:** tomorrow
- **Notes:** `Created by /close-day from daily note {date}`

### Duplicate check

Before creating, use the pre-loaded Google Tasks data (already has all open tasks). Compare each carry title against existing tasks: match if one title contains the other, or if they share 3+ significant words (excluding stop words). Example: "Llamar a GSZ" matches "Llamar a GSZ (CABA)" (containment). "Revisar presupuesto" does NOT match "Revisar contrato" (only 1 shared word). Skip creation if a match exists.

### Present changes

Show the user a summary table before executing any changes:

> **Google Tasks sync:**
> | Action | Task | Details |
> |--------|------|---------|
> | ✅ Complete | {task title} | Matched: {Google Task title} |
> | ➕ Create | {carry item} | No existing task — due {tomorrow} |
> | ⏭️ Skip | {carry item} | Already exists: {Google Task title} |

**Wait for confirmation** before making any changes to Google Tasks.

## After the review

### Observed context updates (check every close-day — never skip for speed)

Not every day produces new observations — but never skip this check. The observed context is the compound value of the vault. Update when a **relevant, significant behavioral or strategic pattern** emerges. Don't update just because the day was productive — update because something was *understood* that wasn't understood before.

> **The anti-skip principle (non-negotiable).** Close-day is the compounding ritual — the routing, the Tier-B digest, and the buffer gardening below are *where the AIOS gets smarter.* **The day's work is done, so there is no token/time opportunity cost left to optimize.** Never skip, gate, or "lighten" these passes to save tokens or feel faster — that trades the one thing we want (compounding) for a saving we explicitly don't care about, and risks stranding a routable insight on a day that merely *looked* light. The passes already **self-scale**: a quiet day finds nothing to route (the substance bars fail fast) and is naturally cheap. **Lightness is an outcome of an empty buffer, never a goal.** Run every pass, every close-day.

Candidates:
- `session-insights.md` — scan and garden the observation buffer (reinforce, add, route, clean up). Emerging → Reinforced → Routed lifecycle; ≤10 Emerging, ≤5 Reinforced. **See Tier A routing enforcement below — Reinforced entries with `Route to:` tags must be routed inline, not deferred.**
- `growth.md` — new growth edge or confirmed pattern (Tier B — see digest pass below)
- `patterns.md` — new behavioral or decision-making pattern
- `business.md` — strategic insight about ventures or relationships
- `profile.md` — new identity/background information surfaced (Tier B — see digest pass below)
- `ecosystem.md` — new relationship or network dynamics (Tier B — see digest pass below)
- `preferences.md` — new working preference discovered (tool, format, communication style)
- `vault-routine.md` — cadence adjustment needed (e.g., a command was too frequent/infrequent, a routine isn't landing)

### Tier A routing enforcement (Reinforced session-insights → target files, autonomous)

**Why this step exists:** the session-insights lifecycle is *Emerging → Reinforced → Routed (to target file) → removed from buffer*. The buffer canibalizes target files when Reinforced entries linger with `Route to:` tags but the routing step never executes — observed in chuy's vault 2026-05-23 catch-up where 5 Reinforced entries sat 11-49 days marked "Ready to route on next /close-day or /emerge" while patterns/preferences/antifragile/business missed the additions. Same failure mode as Tier B drift; different layer.

The substance bar for Tier A routing is already passed by the time an entry reaches Reinforced — Reinforced means 2+ sessions of evidence with target file identified. The remaining work is mechanical: snapshot target file, write the entry, remove from buffer.

**Fire this enforcement after the normal session-insights gardening, BEFORE the Tier B observation pass** (Tier A routing feeds Tier B's digest material).

For each entry in `## Reinforced` section of `session-insights.md`:

1. **Check for `Route to:` tag** — every Reinforced entry should have one (added when promoted from Emerging). If missing, the entry hasn't actually been triaged. Apply the **two-close-day bound** (a Reinforced entry never survives a second close-day untriaged — closes the "linger forever" gap that re-creates the 11-49 day backlogs):
   - **First close-day untriaged:** leave it in Reinforced, stamp `<!-- UNTRIAGED-SINCE {date} -->` on the entry, and surface in close-day output: *"⚠️ Reinforced entry '{title}' missing Route to: tag — needs triage; will auto-route next close-day if still untriaged."*
   - **Second consecutive close-day (entry already carries an `UNTRIAGED-SINCE` stamp):** the bar is already passed (Reinforced = 2+ sessions of evidence) — the only thing missing is a human-picked target, and waiting longer just strands the lesson. **Infer the best target file** from the entry's content (the same Tier A targets: `patterns` / `preferences` / `business` / `antifragile`), route it autonomously per step 2, and surface the inference so the operator can redirect: *"🔁 Auto-routed untriaged Reinforced entry '{title}' → [[{inferred-target}]] (untriaged since {date}, 2-day bound). Flag if it belongs elsewhere — the snapshot is reversible."* This makes the bound **mechanical, not aspirational** — promotion Emerging→Reinforced stays human judgment, but once Reinforced, an entry always reaches a target within two close-days.

2. **If `Route to:` tag is present** — route autonomously, same posture as Tier B digest writes:
   - Snapshot target file(s) per the mandatory snapshot rule
   - Write the entry to each target file under the appropriate section (use the entry's content + evidence + cross-references to existing sections)
   - **Remove the entry from `## Reinforced` using the surgical excision helper** (do NOT hand-edit multi-line buffer blocks — it's fragile and risks corrupting the compounding file):
     ```bash
     uv run ~/aios/hooks/route-insight.py "$HOME/aios/vault/00 - notes/context/observed/session-insights.md" \
       --match "<unique substring of the entry's ### heading>" \
       --marker "<!-- ROUTED {date} (Tier A): {title} → [[{target}]]. Removed from buffer post-route. -->"
     ```
     The helper is snapshot-first + validate-after: it excises exactly one `### ` entry (refuses on no/ambiguous match), leaves the marker as the trail, verifies the entry is gone + the file is intact, and restores from snapshot on any mismatch. One reliable op per entry — never improvise a script.

3. **If the entry routes to multiple targets** (common — e.g., `Route to: [[patterns]] AND [[preferences]] AND [[antifragile]]`): write to all targets in the same pass. The substance bar already validated cross-tier relevance when the entry was promoted to Reinforced.

4. **What NOT to do:**
   - Don't defer to `/emerge` ("we'll route on next /emerge") — that's exactly the deferral pattern that caused the 11-49 day backlogs. /emerge handles cross-cadence cleanup (resolved edges, contradicted patterns), not routine routing of Reinforced entries.
   - Don't re-apply the substance bar — Reinforced status IS the bar passed. Re-checking is just friction that delays routing.
   - Don't ask operator approval per entry — autonomous write, same posture as antifragile.md on a system catch. The operator reads the routing trail in commit messages + the `<!-- ROUTED -->` comments.

5. **Surface the Tier A routing result in close-day output:**

   ```
   ### Tier A routing
   - {N} Reinforced entries routed → {list of target files touched}
   - {M} Reinforced entries deferred (missing Route to: tag — needs triage)
   - {K} Emerging entries reinforced today, awaiting next reinforcement before routing
   ```

   If `M > 0` (untriaged Reinforced entries), include a one-line nudge: *"Triage the missing Route to: tags before next close-day so the routing pipeline doesn't back up."*

This step makes the Reinforced→Routed transition **load-bearing in every close-day**, the same way `antifragile.md` writes are load-bearing on every user correction. The lifecycle stops being aspirational; it becomes mechanical.

### Tier B observation pass (growth / profile / ecosystem — proactive digest, NOT timer-driven)

**Why this step exists:** files like `growth.md`, `profile.md`, `ecosystem.md` are observations about the *operator*, not about today's work. They live one synthesis layer above `session-insights.md`. Without an explicit pass, they go cold while `session-insights.md` + `antifragile.md` accumulate growth-shaped content that never reaches its proper home. The compounding promise breaks silently.

This step makes Tier B updates work the same way `session-insights.md` gardening already does: **autonomous Claude observation, fired every close-day, governed by a substance bar — not by an approval prompt or a timer.** When real Tier B content surfaces, Claude writes it directly (same posture as `antifragile.md` on a system catch). When nothing surfaces that meets the bar, Claude logs that honestly and moves on. The staleness number resets when *real* observation lands, not when noise is manufactured to keep the file warm.

**Fire this pass after session-insights gardening, before snapshotting other observed files.**

For each Tier B file (`growth.md`, `profile.md`, `ecosystem.md`):

1. **Read feed-in sources** (file-specific):
   - `growth.md` ← recent `antifragile.md` entries (last 7 days — note: growth content sometimes lands in antifragile by mistake) + Reinforced entries in `session-insights.md` with self-shape (about the operator changing, not about work mechanics) + close-day `### Observed` sections from the last 5 daily notes
   - `profile.md` ← cross-session identity signals in `session-insights.md` (consistent personality trait surfaced across 2+ sessions per CLAUDE.md trigger rule) + "## Core identity threads" candidates from recent daily notes
   - `ecosystem.md` ← recent `business.md` additions (venture relationship shifts) + new people/connections named in the last 7 days of daily notes + **relationship-shift lines in project notes changed in the window** (`git diff` of `vault/00 - notes/projects/*` over the last 7 days; scan the diff for person/org names — this is where shifts actually land and silently bypass a 7-day daily-note scan) + **`USER.md` relationship tables** (the Forum / agent-DID identity table, `## Companies (mounted)`, Sources/collaborators) + **`profile.md` relationship threads** added since ecosystem's last `updated:` date. **`ecosystem.md` is a derived aggregate (a relationship map), not a stream of atomic facts — so it also needs the periodic full-map re-derivation in the aggregate sub-step below, which atomic event-routing structurally cannot deliver.**

2. **Run the substance bar** — observation only fires when it passes ALL four tests:
   - **Timeline test** — will this observation matter in 90 days? (not just a today-mood)
   - **Uniqueness test** — is this NOT already named in the target Tier B file? (paraphrasing existing content is noise; novel synthesis is signal). **Exception — aggregate redraws:** this test does NOT apply to a full-map re-derivation of `ecosystem.md` (or a `profile.md` identity re-synthesis). A map's value is the synthesis and the *relationships between* nodes, not the novelty of any single node — re-synthesizing nodes that already exist elsewhere is precisely the point of a redraw. Applying the atomic uniqueness test to a map redraw is the bug that let ecosystem decay silently.
   - **Evidence test** — does this connect to 2+ sessions or a clear cross-source pattern? (one-off observations live in `session-insights.md`, not Tier B)
   - **Essentiality test** — if removed in 90 days, would the file lose something real? (essential = write; replaceable = don't)

3. **If passes the bar → WRITE.** Claude observes autonomously. No approval prompt. Same posture as `antifragile.md` on a system catch. Snapshot the file first (per the mandatory snapshot rule), then write the observation. Use [[wiki-links]] where natural.

4. **If nothing passes the bar → DON'T WRITE.** Don't manufacture content to keep the file warm. The staleness counter keeps ticking; that's honest data, not failure.

4b. **Aggregate re-derivation (ecosystem, and partly profile) — periodic + holistic, NOT atomic.** Steps 1–4 are *atomic-append*: they capture new points, one event at a time. But `ecosystem.md` is a **derived aggregate** — a relationship map — and a map cannot be kept current by point-appends alone (a redraw re-synthesizes nodes that already exist elsewhere, so the atomic uniqueness test rejects it, and shifts filed to project notes / `USER.md` / `profile.md` never trigger a redraw at all). So on top of the atomic pass, an aggregate file gets a **full-map re-derivation** whenever the staleness alarm (below) marks it past its aggregate threshold (**21 days**): re-read the entire relationship graph across *every* widened feed-in surface (project-note changes + `USER.md` tables + `profile.md` threads + `business.md`) and **redraw the map wholesale**, then reset `updated:`. Log the mode in the digest — *atomic-append* (event-triggered, steps 1–4) vs *aggregate-rederive* (periodic, holistic). The natural home for a *scheduled* monthly re-derivation is `/aios:compact` or an `/aios:housekeeping` bucket; until that lands, the staleness alarm makes close-day the reliable backstop that guarantees the redraw happens rather than waiting on a cadence command.

5. **Surface the digest result in close-day output** (always, regardless of write/no-write):

   ```
   ### Tier B digest
   - growth.md       — last touched {N} days ago. Digest: {wrote 1 entry | nothing passed substance bar | already current}
   - profile.md      — last touched {N} days ago. Digest: {result}
   - ecosystem.md    — last touched {N} days ago. Digest: {result}
   ```

   This is the trail data — operator sees the digest fired AND its outcome, so silent drift can't hide.

   **Staleness alarm (streak-independent — replaces the old ">30d AND 3-in-a-row" escalation).** Read the `updated:` frontmatter of every `observed/*.md` file and compute days-since. Flag any file past its threshold — **21 days for aggregate Tier B files (`ecosystem.md`; `profile.md` insofar as it's an identity synthesis), 30 days for all other observed files** — *regardless of any digest streak*: *"⚠️ ecosystem.md is {N}d stale (threshold 21d) — run the aggregate re-derivation now (redraw the map wholesale per step 4b), or add an explicit 'map current, verified {date}' digest line if it's genuinely unchanged."* This alarm depends only on the file's own `updated:` stamp — **not** on the digest trail existing. The retired rule required un-persisted streak state (a count of consecutive "nothing passed" digests that lives only in the trail lines); when the pass silently stopped emitting the trail, the streak could never reach 3, so the alarm structurally never fired. The dumb `updated:`-based check is the reliable-over-clever backstop. The same alarm also surfaces at `/today` (see `today.md`), so a stale aggregate is caught at both ends of the day.

**What this step does NOT do:**
- Doesn't gate writes on operator approval (that's Ruinous Empathy disguised as care; CLAUDE.md → Anti-values catches this)
- Doesn't try to replicate `/emerge`'s cleanup pass (resolved edges, contradicted patterns — that's bi-weekly cadence, longer horizon)
- Doesn't write to Tier A files (patterns, business, preferences — those have their own routing protocol, well-functioning)
- Doesn't write `antifragile.md` (Claude's system-rule layer; event-triggered on corrections, separate flow)

**Connection to other commands:** `/close-session` captures Tier B candidates in its session-report's `Observed` section but does NOT write Tier B files directly — close-session lacks the cross-session view needed for the substance bar. `/close-day` is where the synthesis lands because it has the full daily + session reports context. `/emerge` (bi-weekly) revisits at a longer horizon for cleanup. `/drift` (weekly) uses `ecosystem.md` for declared-vs-actual gaps. Three altitudes, each clear.

**This pass is load-bearing in every close-day** — exact parity with the Tier A routing-enforcement step above (which is load-bearing "the same way `antifragile.md` writes are load-bearing on every user correction"). The `### Tier B digest` block is a **required close-day output**, not an optional nicety: it emits one line per Tier B file (`growth` / `profile` / `ecosystem`), each stating last-touched-days + outcome (`wrote` / `nothing passed` / `already current` / `re-derived` / `verified current`). **The close does not complete without it** — if the day's close-of-day lacks a `### Tier B digest` block, self-reject and complete the pass before commit (see the Self-update verification checklist). This hard gate exists because the pass had been *soft* (prose + a "when warranted" checklist line) and silently stopped firing across a run of close-days — six ran with zero digest emitted — which also disabled the old streak-based alarm, since the streak it counted lives only in the (now-absent) trail. Restoring the trail is what restores the safety net; the gate is what guarantees the trail.

### Emerging-cap enforcement (the upstream buffer leak — additive pass)

**Why this step exists:** Tier A routing made the **Reinforced → Routed** transition load-bearing. But the `## Emerging` layer had no enforcement — entries never expired and weren't force-reviewed, so the buffer bloated (observed 2026-06-15: ~31 Emerging against a ≤10 cap) while relying on `/emerge` (bi-weekly) to catch up. This pass closes the *upstream* leak the same way Tier A closed the downstream one: enforcement every close-day, not deferred.

> **Additive-only guardrail (do NOT touch the proven path).** This pass operates **exclusively on the `## Emerging` layer.** It does not alter, reorder, or gate the Reinforced→Routed pass, the Tier-B digest, or any observed-context write above — those have been compounding with great value and stay exactly as-is. Emerging-cap is a separate, additive step.

**Fire this AFTER Tier A routing + the Tier B digest** (so same-day promotions + Tier-B consumption have already happened), and BEFORE the snapshot/commit. Run only when `Emerging > 10`:

1. **Reinforce** — for each Emerging entry that got a **2nd instance today** (a session block / meeting / observation that confirms it), promote it to `## Reinforced` with a `Route to:` tag. If it's clearly route-ready now, route it this pass via the Tier-A helper; otherwise it routes next close-day.
2. **Expire** — for each remaining Emerging entry, apply the **inverse substance bar** (an entry expires only if ALL hold): (a) **age** — older than ~2 weeks / unreferenced across the last several close-days (don't expire fresh entries that haven't had a chance to reinforce); (b) **no 2nd instance** ever landed; (c) **wouldn't matter in 90 days** (fails the timeline test); (d) **not essential** — nothing real is lost. Expire via the surgical helper with an EXPIRED trail marker:
   ```bash
   uv run ~/aios/hooks/route-insight.py "$HOME/aios/vault/00 - notes/context/observed/session-insights.md" \
     --match "<unique substring of the entry's ### heading>" \
     --marker "<!-- EXPIRED {date}: never reinforced, fails inverse substance bar (age + no-2nd-instance + not-90-day-relevant). -->"
   ```
   **This is judgment, not automation** — Claude decides *which* entries expire; the helper only does the safe excision. When unsure whether an entry is stale-or-slow-burning, **keep it** (with a one-line reason in the close-day output) — under-expiring is cheap, wrongly deleting a slow-burn insight is not.
3. **Cap restored** — after the pass, `## Emerging` is **≤ 10**, OR every still-over-cap entry is explicitly surfaced with its disposition (promoted / expired / kept-with-reason). The andon cord: if the pass can't get under cap honestly, it says so rather than force-expiring real signal.

**Surface the result in close-day output:**
```
### Emerging-cap
- Emerging: {before} → {after} (cap 10)
- Promoted → Reinforced: {list} · Expired: {list} · Kept-with-reason: {list + why}
```

### Snapshot before editing (mandatory)

**Before modifying any observed context file**, archive the previous version:

1. Copy the current file to `00 - notes/logs/observed-snapshots/{YYYY-MM}/{YYYY-MM-DD}-{filename}.md` (create the monthly subfolder if needed)
   - If you already edited the file, use `git show HEAD:"vault/00 - notes/context/observed/{file}"` to recover the previous version
   - **Skip snapshots for stub files** — if an observed file contains only frontmatter and seed text (no real observations yet), there is nothing to archive. Start snapshotting once the file has actual content.
2. After archiving, edit the live observed file
3. For `session-insights.md`: this is an observation buffer, not a log. Scan existing Emerging/Reinforced entries — reinforce matches from today, route Reinforced insights to target files, add new observations, drop stale items. Snapshot only when the document changes. See `session-insights.md` header for the full lifecycle.

This creates a timeline of how observations evolve — valuable for `/trace`, `/drift`, and long-term growth tracking.

### Self-update verification

Before commit, walk the CLAUDE.md Session End rules to confirm the observed-context updates above weren't skipped. The compounding promise of the AI-OS lives in routing, not logging.

- [ ] Snapshotted observed-context files I modified (per CLAUDE.md → "Session End → Snapshot before editing")
- [ ] Updated `session-insights.md` per CLAUDE.md → "Self-Update → Observed Context Rules" — Emerging / Reinforced / Routed lifecycle; ≤10 Emerging, ≤5 Reinforced
- [ ] **Emitted the `### Tier B digest` block (HARD GATE — the close does not complete without it).** One line per Tier B file (`growth` / `profile` / `ecosystem`), each stating last-touched-days + outcome. If the close-of-day lacks this block, self-reject and run the Tier B observation pass before commit. This is load-bearing parity with the Tier A routing step — not a "when warranted" nicety.
- [ ] **Checked the observed-context staleness alarm** — read every `observed/*.md` `updated:` frontmatter; flagged any past its threshold (21d aggregate Tier B, 30d others), *independent of any digest streak*. For a stale aggregate file, ran the full-map re-derivation (step 4b) or logged an explicit "map current, verified {date}" line.
- [ ] Updated other observed files when warranted (per CLAUDE.md → "Observed Context Rules" — patterns / preferences / business / ecosystem / growth / profile)
- [ ] Wrote to `antifragile.md` if the user corrected me OR I caught my own system-level mistake (per CLAUDE.md mandatory triggers)
- [ ] Asked "What was most useful?" if the day was substantive (per CLAUDE.md Session End step 4); verbatim answer captured in the close-of-day `### Most useful` field

If any unchecked, complete it now before commit.

**Logging is not routing.** Don't commit until each insight from this day lives in `session-insights.md` (or routed onward to its target observed file). The daily-note "Learned" / "Observed" sections are holding cells, not destinations. The AI-OS compounds on routing — capture-only is stranded.

### Commit and push

```bash
cd ~/aios && git add -A && git commit -m "Close day {date}" && git push
```

## Rules
- **Shipped is binary.** Don't soften "didn't ship" into "made progress." Honesty compounds.
- **Rhythm check reflects reality.** If Evening — Grow was skipped 3 days in a row, say it. That's data for /drift.
- Don't just list what happened — extract the insight underneath
- Be honest about what was avoided (feeds /drift)
- Keep it brief. This is capture, not analysis.
- "Carries forward" items become tomorrow's carried tasks — nothing gets silently dropped
- Use `[[wiki-links]]` for project names, context files, and ventures mentioned in session-insights entries and daily note content. This keeps the graph connected.
