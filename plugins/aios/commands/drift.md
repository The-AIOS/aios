---
tags:
  - aios
  - command
  - weekly
description: Identify topics, projects, or commitments being quietly avoided based on gaps in notes
allowed-tools: mcp__obsidian__*, Read
---

# /drift — Avoidance Detector

You are scanning the user's vault to find what's being quietly avoided or neglected.

## When to use

Mid-week or when something feels off — the avoidance detector. Honest scan of what's being quietly avoided based on gaps in notes. Trust this one to surface things you've been not-naming.


## Steps

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /drift` for any user overrides. Also read `INTENT.md` (if it exists) — items in "Explicitly NOT doing" are intentionally parked, not drifting. Don't flag them.

1. Read ALL project notes from `00 - notes/projects/` — check status and to-do items
2. Read `00 - notes/context/observed/session-insights.md` — patterns over time
3. Read recent daily notes from `01 - calendar/{YYYY-MM}/` (current month) and `01 - calendar/{YYYY-MM-1}/` (previous month if needed)
4. Read `00 - notes/context/observed/ecosystem.md` — declared priorities vs. actual activity
5. Cross-reference what's declared important vs. what's actually getting worked on

## Output

```
## Drift Report — {date}

### Drift by venture
{Group drifting projects by `venture` frontmatter. E.g. "Sovra: 3 projects drifting. ChuyCepeda: 2 projects drifting." This makes the report actionable per-meeting — founders care about Sovra drift, personal review cares about ChuyCepeda drift.}

### Projects with no recent activity
{Projects with "active" status but no recent work or mentions}

### Commitments mentioned but not acted on
{Things from sessions or notes that were "next steps" but never happened}

### Patterns of avoidance
{Themes in what gets consistently deprioritized — always the same type of work? Always the same venture?}

### The uncomfortable question
{One direct question about the most significant drift}

### Suggested actions
- {1-3 specific things to do about the most important drifts}

### Concrete actions

| Insight | Action | Where | Priority |
|---------|--------|-------|----------|
| **{insight}** — {one-line} | {specific action} | [[{project or file}]] | High / Normal / Low |

{Only include insights with clear next steps. Mark already-addressed items as ✅ Done. High = unblocks something or changes a decision. Normal = enriches existing work. Low = good to do eventually.}
```


## Save to vault

After generating the report, write it to `00 - notes/logs/command-logs/drift-{YYYY-MM-DD}.md` using `mcp__obsidian__write_note` with frontmatter `{"tags": ["drift", "aios-command"], "created": "{today}"}`. Then commit and push.

## Rules
- Be direct but respectful. The value is honesty.
- Focus on things that MATTER but are being avoided — not just undone tasks
- Look for patterns: is it always creative work? Administrative? A specific venture?
- The "uncomfortable question" should be genuinely uncomfortable
- Distinguish intentional deprioritization from unconscious avoidance
- Use [[wiki-links]] for all project names, context files, and ventures mentioned.
