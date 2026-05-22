---
tags: [context, claude-observed, routine, aios-commands]
created: 2026-03-02
updated: 2026-04-30
type: claude-context
---
# Vault Routine — When to Run What

> The cadence that turns individual commands into a compounding system. The value isn't any single command — it's the rhythm.

> **Task convention — `target:` metadata** (added 2026-04-30):
> When a task has a real deadline — external commitment, dependency, calendar event, sequenced W-plan slot — include `target:` in the source-tag inline metadata. Format: `- [ ] task _(target: 2026-05-15, project)_` or `_(target: 2026-W19)_`. When the task carries forward, the carry display becomes deadline-aware (red if past target, informational if before, neutral age if no target).
> When a task does NOT have a real deadline — ambient work, books, content backlog, exploration — leave `target:` absent. Don't invent fake deadlines to feel productive; that's discipline-as-theater. The system tracks age non-pejoratively when no target exists.
> See `USER.md` → `### /today` → *Target-aware carry display* for rendering rules; `### /close-day` → *Carry-creation: target capture* for capture rules.

---

## Daily (2–3 min each)

### Morning → `/today`
`aios:today`

Run before anything else. Reads recent notes, open project threads, and yesterday's unresolved items. Writes a one-screen daily plan to `01 - calendar/{YYYY-MM}/{date}.md`.

**Don't skip this.** It's the ritual that makes everything else possible. A day without `/today` is a day the vault doesn't know about.

### Evening → `/close-day`
`aios:close-day`

Run before closing Claude Code. Captures what happened, what was learned, what's unresolved. Appends to today's daily note and updates observed context files where relevant.

**The discipline:** Even a 2-sentence close is better than nothing. The vault compounds from capture, not from perfect entries. Before major observed context rewrites, snapshots are saved — see [[observed-snapshots/README|observed-snapshots]].

---

## Weekly

### Sunday evening or Monday morning → `/7plan`
`aios:7plan`

Reshapes the next 7 days around what's actually alive across all ventures. Not a task list — a strategic orientation. Writes to `01 - calendar/{YYYY-MM}/{year}-W{week}-plan.md`.

### Any day mid-week → `/drift`
`aios:drift`

The honest check. What's being quietly avoided? What commitments have been mentioned but not acted on? Run this when something feels off, or weekly as part of the Sunday review.

### End of week → `/weekly-learnings`
`aios:weekly-learnings`

Consolidates the week's daily notes into a single summary. Raw material for `/learned` when you're ready to publish.

---

## Bi-weekly (every 2 weeks)

### `/graduate`
`aios:graduate`

Scans the last 14 days of daily notes for half-formed ideas worth a permanent note. Promotes them to `00 - notes/ideas/`. Run when the daily notes feel dense with undeveloped thoughts.

### `/emerge`
`aios:emerge`

Surfaces ideas that are strongly implied across multiple notes but never explicitly written. Reveals what the vault is thinking that you haven't said yet. Best run after a productive stretch of sessions.

### `/connect`
`aios:connect`

Cross-domain bridges. Find unexpected connections between ventures, projects, or ideas that aren't explicitly linked. Best run when multiple ventures are active simultaneously — the intersections are where the leverage is.

---

## Monthly (1st of the month)

### `/compact`
`aios:compact`

Digests the previous month's observed context snapshots and role logs into readable summaries, then zips the individual files. Keeps the vault lean as it grows — without losing raw data.

**Auto-suggested** by `/today`'s command discovery engine on the 1st of each month.

---

## As needed — pull these when the moment calls

| Command | When to pull it |
|---------|-----------------|
| `aios:ideas` | When you want a grounded idea report — tools, content, connections |
| `aios:ghost` | Before writing a LinkedIn post, email, or anything that needs to sound like you |
| `aios:challenge` | Before a major decision. When a belief feels settled. |
| `aios:trace` | When an idea keeps returning and you want to understand why |
| `aios:connect` | When stuck on one venture — cross-domain bridges often unlock it |
| `aios:learned` | When you want to turn recent insights into publishable content |
| `aios:housekeeping` | Mid-month (or when carries ×15+, projects 12+, stale snapshots) — proposals to merge/archive/drop/dedup/refresh |
| `aios:role-report` | When you have 2+ weeks of role logs — quarterly performance narrative |
| `aios:company --sync` | Before creating any company-scoped content (decks, proposals, docs). `/today` nudges you if any mounted company is >7 days stale. |
| `aios:update` | When The-AIOS/aios ships new commands, templates, or settings. `/today` nudges you if `.aios-update` synced >14 days ago. |

---

## The underlying logic

The daily commands (`today` + `close-day`) build the raw material.
The weekly commands (`7plan` + `drift` + `weekly-learnings`) consolidate and orient.
The bi-weekly commands (`graduate` + `emerge`) surface what the system is learning.
The monthly command (`compact`) keeps the vault lean as it compounds.
The as-needed commands (`ghost` + `ideas` + `challenge`) are leverage on demand.

**The flywheel:** capture → consolidate → surface → act → capture again.

Every entry makes the next session smarter. Every session makes the next week clearer.

---

---

*See `commands/_index.md` for the full command reference.*
*See [[_index|Observed Context Index]] for all Claude context files.*
*See [[working_style#Vault color system]] for the vault color palette.*
