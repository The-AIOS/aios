---
tags:
  - aios
  - command
  - weekly
description: Weekly strategic plan across all ventures based on what's most alive right now
allowed-tools: mcp__obsidian__*, mcp__google-workspace__*, mcp__google-workspace-personal__*, Read, Bash(cd ~/aios && git:*)
---

# /7plan — Weekly Strategic Plan

You are generating the user's weekly strategic plan by reading their full vault context.

## When to use

Sunday or Monday morning to draft the week's strategic plan across all active ventures + projects + commitments. Reads observed context, project state, and calendar to surface what matters most this week. The compass-set for the week.


## Progress tracking

Before doing anything else, create a task list so the user can see where you are. Use `TaskCreate` for each step:

| Task | activeForm |
|------|-----------|
| Load context (vault + calendar + tasks + projects) | Loading context |
| Write weekly plan | Writing weekly plan |
| Commit and push | Committing and pushing |

Mark each task `in_progress` when you start it and `completed` when done.

## Steps — Target: 4 messages

### Message 1 — Bootstrap + load tools (one parallel batch)
Fire these calls in **one message**:
- `Read` → `USER.md` (for Sources config and `### /7plan` command personalizations)
- `Read` → `INTENT.md` (if it exists — focus informs week priorities, parked items excluded)
- `mcp__obsidian__read_note` → `00 - notes/projects/_index.md`
- `mcp__obsidian__list_directory` → `00 - notes/projects/`
- `ToolSearch` `select:mcp__google-workspace__get_events`
- `ToolSearch` `select:mcp__google-workspace__list_tasks`
- `ToolSearch` `select:mcp__obsidian__read_multiple_notes`
- Personal calendar (if configured in USER.md Sources): `ToolSearch` `select:mcp__google-workspace-personal__get_events`

Load only what's configured — skip tools for sources not configured in USER.md.

### Message 2 — Mega parallel batch: everything in one message
Fire ALL of these as direct parallel tool calls:

**Vault reads (Read tool):**
- All declared context: `00 - notes/context/declared/` (about_me, personal_voice, working_style, about_business)
- All observed context: `00 - notes/context/observed/` (all files)
- This week's daily notes from `01 - calendar/{YYYY-MM}/` (and previous month folder if the week spans months)
- Existing daily notes for the upcoming week (Mon–Fri) — to check which ones already exist and have user edits

**Project context:**
- **If `_index.md` has `## Project Snapshots` with content:** use it as the single source. Don't read individual project notes.
- **If no snapshots exist:** fall back to reading all project notes (batched in groups of 10).

**API calls (in the same parallel batch):**
- Google Calendar: `mcp__google-workspace__get_events` — full week (Mon 00:00 – Sun 23:59, timezone from USER.md Sources). If a personal calendar is configured, read it too and merge chronologically. Tag personal events with [personal]. Skip calendars marked as "Skip".
- Google Tasks: `mcp__google-workspace__list_tasks` — `show_completed=false`, `due_max` = Sunday 23:59, task list ID from USER.md Sources

### Message 3 — Synthesize + write weekly plan (no read calls)
From the data already loaded — process everything in memory:
- **Stage→mix check (consult the `team-archetypes` skill):** for each active project, name its lifecycle stage (pre-PMF / growing / scaling) and flag where the week's planned work doesn't match the stage-appropriate archetype mix — e.g. planning new features (Builder) on a post-PMF product that actually needs growth (Grower) or simplification (Sweeper). Surface any mismatch under *This week's challenge*.
1. Synthesize into the 7-day plan and write to `01 - calendar/{YYYY-MM}/{YYYY}-W{WW}-plan.md`
2. After writing, ask: **"Want me to create daily note skeletons for the week?"**
   - If yes → create daily notes (see **Daily Notes Generation** below), then commit
   - If no → commit directly. `/today` will create each day's note fresh each morning.

### Message 4 — Commit + push
- `cd ~/aios && git add -A && git commit -m "Weekly plan W{WW}" && git push`

## Output

Present in the response AND write to `01 - calendar/{YYYY-MM}/{YYYY}-W{WW}-plan.md` with frontmatter `{"tags": ["weekly", "plan", "vault"], "created": "{today}"}`:

```
# Week {number} Plan — {date range}

## What's most alive right now
{1-2 sentences on the dominant energy/direction across all ventures}

## This week's challenge
**Diagnosis:** {what's actually hard this week — the real constraint, not the to-do list}
**Guiding policy:** {the approach — what we'll prioritize and what we'll sacrifice}

## The bet (durable — carries across weeks)
**Focus:** {THE one bet the next several weeks ladder up to — carried verbatim from last week's plan unless deliberately changed. If changing it, say what changed and why. A bet that changes weekly is churn, not focus.}
**Review:** {when this bet gets re-examined — e.g. "end of Q2" or "after X ships"}
**Leverage domains:** {3-5 durable domains of concentrated skill/asset investment (e.g. governed-agents narrative, institutional trust, publishing flywheel) — the through-lines weekly priorities should serve. Carried week to week; pruned rarely.}

{Read last week's plan for this section first. Default is CARRY, not regenerate — this layer exists precisely so the weekly reset doesn't churn the multi-week thesis. New operators (no prior plan): derive the first bet from INTENT.md focus priorities + active projects, and mark it "(first bet — calibrate over 2-3 weeks)".}

## Weekly priorities by venture

{Read all active projects from 00 - notes/projects/. Group by `venture` frontmatter field (first value in array = primary group). If venture field is missing, fall back to tag/venture guess. If no ventures exist at all, generate one section per project.}

### {Venture/Domain or Project Name}
- [ ] {2-3 specific actions} — **Lead:** {specific predictive action this week, not the outcome}
- Why: {brief strategic reason}

{Repeat for each venture group (or project if no ventures). No separate "Tooling" section — tool projects belong to their venture (e.g. aios-tooling → ventures it serves).

**Lead measures vs lag measures:** Each priority should have a lead measure — the specific, influenceable action that predicts the outcome. Not "close the deal" (lag) but "3 discovery conversations" (lead). Not "ship the feature" (lag) but "2 hours of focused coding" (lead).}

## B- this week (intentional)
- {area} — {why it's ok to coast here}
- {area} — {why it's ok to coast here}
{Name 1-2 areas receiving B- effort this week. This protects the wildly important goal and counters the tendency to give everything A+ effort. Saying "B- here" makes the A+ priorities achievable.}

## Key decisions this week
- {Decisions that need to be made, with context}

## What to protect
- {Time/energy that should be guarded}

## Flywheel check
- Strongest link: {which ecosystem connection is working}
- Weakest link: {which needs attention}

## One question for the week
{A strategic question to hold}
```

## Daily Notes Generation (optional — only if user says yes)

Create a daily note for each weekday (Mon–Fri) using `mcp__obsidian__write_note`. Saturday/Sunday only if they have events or tasks. **Cross-month weeks:** if the week spans two months (e.g. Mar 30 – Apr 5), ensure the next month's calendar folder exists before writing — use `Bash(mkdir -p ~/aios/vault/01\ -\ calendar/{YYYY-MM})` for the new month.

**Before creating a daily note, check if it already exists.** If it does, **skip it** — don't overwrite. `/today` will handle updates each morning. Only create notes for days that don't have one yet.

Each daily note uses the **same base structure** as `/today` output — same frontmatter `{"tags": ["daily", "plan", "vault"], "created": "{date}"}`, same sections (Calendar, Today I ship, Rhythm, Radar, Parking lot, Horizon, Energy note) — minus the live-state sections that `/today` generates fresh each morning (Claude's take, command suggestion, observed nudge).

How to distribute content across days:
- **Calendar:** each day gets its meetings from all configured Google Calendars, merged chronologically. Personal events tagged with [personal] if multiple accounts.
- **Today I ship:** one deliverable per day, derived from weekly priorities
- **Rhythm:** tasks sorted into Morning/Afternoon/Evening blocks, adapted to that day's meeting density. Source: Google Tasks (by due date) + weekly priorities distributed across the week.
- **Radar, Parking lot, Horizon, Energy note:** follow `/today` rules
- **Carries:** Monday gets carries from the most recent close-day (search backwards from Friday through the previous week). Other days start clean — `/today` will add carries each morning from the previous day's close-day.

What to **skip** in daily notes created by `/7plan` (these are generated fresh by `/today` each morning):
- Claude's take (daily opener)
- Command suggestion (💡)
- Observed nudge (🔍)

These sections depend on live state and are more valuable when generated the morning of, not projected days in advance.

Rules for daily notes:
- Max 3-5 items per Rhythm block — the day must feel achievable
- Heavy meeting days get fewer tasks
- One deep-work item per day max
- If a day has no meetings and no tasks, still create the note with open blocks marked for deep work

## Rules
- **NEVER use the Agent tool.** Use direct tool calls only — `Read`, `mcp__obsidian__*`, `mcp__google-workspace__*`, etc. Agents add minutes of latency and can silently block.
- **Never re-read files.** All data is loaded in Message 2. Message 3 is pure analysis + write.
- **Minimize tool-call messages.** Target: 4 messages total. Every additional round-trip adds latency.
- Maximum 15 items total in the weekly plan. Fewer is better.
- Name tensions explicitly: if ventures compete for time, say so
- The "flywheel check" is the most important section
- Don't plan more than one deep-work item per day
- Commit and push after writing (weekly plan + all daily notes in one commit)
