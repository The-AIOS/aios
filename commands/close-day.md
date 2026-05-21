---
tags:
  - vault-commands
  - command
  - daily
description: End-of-day review — capture what shipped, what grew, and what carries forward
allowed-tools: mcp__obsidian__*, mcp__google-workspace__*, mcp__google-workspace-personal__*, Read, Bash(cd ~/obsidian && git:*), Bash(uv run ~/obsidian/hooks/pipeline-executor.py:*)
---

# /close-day — End of Day Review

You are running the user's end-of-day review by reading their vault and capturing what happened.

## Pre-loaded API data

Step 1 runs `uv run ~/obsidian/hooks/pipeline-executor.py --command close-day` which pre-loads Google Calendar events **with attachments** (today + next 7 days for cross-check), Google Tasks (open), and Slack unreads + daily recap.

**DO NOT call Google Calendar `get_events`, `list_tasks`, or Slack APIs.** The data is in the executor output.

**You STILL need `mcp__google-workspace__*` for:** fetching Google Doc content from calendar attachment `fileId`s (step 4 below). The executor lists the attachments; you fetch the doc content.

**If the executor output shows `❌ FAILED` for a specific source:** tell the user what failed and how to fix it. Use the data that did load.

## Steps

1. **Run executor + read vault** — fire these in **one parallel batch**:
   - `Bash(uv run ~/obsidian/hooks/pipeline-executor.py --command close-day)` — pre-loads Calendar (detailed, with attachments), Calendar next 7 days, Tasks, Slack
   - `Bash(cfg=~/obsidian/.vault-update; if [ -f "$cfg" ]; then repo=$(grep ^repo= "$cfg" | cut -d= -f2); h=$(grep ^hash= "$cfg" | cut -d= -f2); r=$(git ls-remote "$repo" HEAD 2>/dev/null | awk '{print $1}'); [ -z "$r" ] && echo "vault-update: unreachable" || { [ "$h" = "$r" ] && echo "vault-update: synced" || echo "vault-update: BEHIND (local=${h:0:7} remote=${r:0:7})"; }; else echo "vault-update: no-config"; fi)` — **infrastructure freshness check** (mirror of `/today`'s morning check). Render per § Vault-update freshness rendering below — at end-of-day, the framing shifts from "before working today" to "before sarah's overnight queue (or first thing tomorrow)".
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
12. **Update weekly plan progress** (see Weekly Plan Progress Update below)
13. **Sync Google Tasks** — use pre-loaded Tasks data (see Google Tasks Sync below)

## Vault-update freshness rendering

Apply the result from step 1's `.vault-update` check (BEHIND / synced / unreachable / no-config):

- **`synced`** → silent. No surface in the close-of-day section.
- **`BEHIND`** → surface as a callout at the top of the `## Close of Day` block, before the verdict line: `> 🆕 **Vault-update pending** — local hash `{h}`, team repo `{r}`. Run `/aios:update` before sarah's overnight queue (or first thing tomorrow morning) so fresh commands/templates land in her shift.` This is consequential at close-day specifically because sarah's queue is generated FROM your local state — stale local = stale handoff.
- **`unreachable`** → soft mention near the Observed section: *"vault-update check unreachable at close (network/auth — fine for now; /today will retry tomorrow)."* Don't escalate.
- **`no-config`** → silent (no Organization configured = single-vault user, nothing to sync).

**USER.md override:** if `USER.md` → `## Command personalizations` → `### /close-day` (or `### /today`) has a vault-update nudge suppression (e.g., for users who are upstream authors of the team repo), apply it. The check still runs; rendering is muted per the personalization.

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
- [ ] {Items that didn't get done or need follow-up — these feed tomorrow's /today. Format: `- [ ] {task} _(carried ×N, reason: {tag})_` where N = previous count + 1 (or 1 if new), and `{tag}` is one of: `strategic-deferral` / `blocked-on-{who}` / `needs-challenge` / `waiting-on-date`. Reason tags are set by the carry-triage prompt below — once tagged, /today stops re-asking.}

### Observed
- {Meta-patterns: energy, focus, what worked, what was avoided. Feed /drift.}

```

## Carry-reason triage prompt

Before writing `### Carries forward`, scan each item crossing into tomorrow. For any carry where `N+1 ≥ 6` and there is no `reason:` tag yet (or the existing tag has become stale — e.g. `blocked-on-X` but no activity on X for 30+ days), **ask the user inline**:

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
- **"Observed"** (if present) → route to the appropriate observed context file (`patterns.md`, `preferences.md`, `growth.md`, etc.). Same rules as the "Observed context updates" section below: check always, update when warranted, snapshot before editing. This is how observations from standalone project sessions reach the vault — no context is lost even when Claude isn't running in the vault terminal.

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

**Where to look:** Agent sessions spawned at the vault root write their close-session reports to `~/obsidian/.claude/session-report-{YYYY-MM-DD}.md` (same directory, possibly multiple reports if several agents ran). Use `Read` with absolute path. Also check for any session reports in Dev project paths that mention an agent name from `agents/_index.md` (canonical registry across all bundles) or `agents/custom/_index.md`.

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
Scan today's daily note for all `- [x]` items. For each, identify the source project (from the `_(project)_` tag, or infer from the task description matching a project's to-do list). If a matching `- [ ]` item exists in the project note, mark it `- [x]`.

### Unchecked items with carry history (flag in project notes)
Scan today's daily note for all `- [ ]` items that show `_(carried ×N)_` where N ≥ 3. For each, check if the item exists in the project note's to-dos. If it does, add `⚠️` flag if not already present — this surfaces chronic carries in the project view, not just the daily note. **Tagged-reason exception:** if the carry has `reason: strategic-deferral` and is aligned with INTENT.md focus pillars, suppress the ⚠️ — it's deliberate, not drift.

### New tasks discovered during the day
If the user added tasks to the daily note that don't exist in any project note (user-added subtasks, ad-hoc items), suggest routing them:

> **New tasks to route to projects:**
> | Task | Suggested project | Action |
> |------|------------------|--------|
> | {task} | [[project]] | Add to {High/Normal} to-dos |

Wait for confirmation before writing to project notes.

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

Candidates:
- `session-insights.md` — scan and garden the observation buffer (reinforce, add, route, clean up)
- `growth.md` — new growth edge or confirmed pattern
- `patterns.md` — new behavioral or decision-making pattern
- `business.md` — strategic insight about ventures or relationships
- `profile.md` — new identity/background information surfaced
- `ecosystem.md` — new relationship or network dynamics
- `preferences.md` — new working preference discovered (tool, format, communication style)
- `vault-routine.md` — cadence adjustment needed (e.g., a command was too frequent/infrequent, a routine isn't landing)

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
- [ ] Updated other observed files when warranted (per CLAUDE.md → "Observed Context Rules" — patterns / preferences / business / ecosystem / growth / profile)
- [ ] Wrote to `antifragile.md` if the user corrected me OR I caught my own system-level mistake (per CLAUDE.md mandatory triggers)
- [ ] Asked "What was most useful?" if the day was substantive (per CLAUDE.md Session End step 4); verbatim answer captured in the close-of-day `### Most useful` field

If any unchecked, complete it now before commit.

**Logging is not routing.** Don't commit until each insight from this day lives in `session-insights.md` (or routed onward to its target observed file). The daily-note "Learned" / "Observed" sections are holding cells, not destinations. The AI-OS compounds on routing — capture-only is stranded.

### Commit and push

```bash
cd ~/obsidian && git add -A && git commit -m "Close day {date}" && git push
```

## Rules
- **Shipped is binary.** Don't soften "didn't ship" into "made progress." Honesty compounds.
- **Rhythm check reflects reality.** If Evening — Grow was skipped 3 days in a row, say it. That's data for /drift.
- Don't just list what happened — extract the insight underneath
- Be honest about what was avoided (feeds /drift)
- Keep it brief. This is capture, not analysis.
- "Carries forward" items become tomorrow's carried tasks — nothing gets silently dropped
- Use `[[wiki-links]]` for project names, context files, and ventures mentioned in session-insights entries and daily note content. This keeps the graph connected.
