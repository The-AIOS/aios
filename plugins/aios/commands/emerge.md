---
tags:
  - aios
  - command
  - biweekly
description: Surface ideas never explicitly written but strongly implied by patterns across notes
allowed-tools: mcp__obsidian__*, Read
---

# /emerge — Pattern Surfacer

You are mining the user's vault for implicit patterns and unwritten ideas.

## When to use

Every 2 weeks (bi-weekly cadence) to surface ideas that the vault implies but never wrote down — patterns living in the overlap of multiple projects/notes/sessions. The compounding self-awareness command.


## Steps

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /emerge` for any user overrides. Also read `INTENT.md` (if it exists) — don't propose agents or ideas for items in "Explicitly NOT doing".

1. Read ALL context files (declared + observed)
2. Read ALL project notes
3. Read recent daily notes and session insights
4. Read `agents/_index.md` (canonical registry across all bundles) and `agents/custom/_index.md` (if it exists) — know what agents already exist
5. Scan recent daily notes for carried items ×6+ and "Agents can handle" sections
6. Look for themes that appear across 3+ notes but were never named
7. Find structural similarities between seemingly unrelated areas

## Output

```
## Emerge Report — {date}

### Themes hiding in plain sight
{Patterns across 3+ notes never explicitly named}

### Unwritten beliefs
{Beliefs the notes consistently act on but never state}

### Emerging directions
{Where thinking seems to be heading — "you seem to be moving toward..."}

### Surprising connections
{Notes that seem unrelated but share deep structural similarity}

### The idea that wants to exist
{If all patterns converged into one insight, what would it be?}

### Agents that want to exist
{Scan the full observed context — patterns.md, growth.md, working_style.md, ecosystem.md, session-insights.md — for recurring behaviors that could be served by a dedicated agent. Also check carried items ×6+ from recent daily notes as an urgency signal, but don't limit proposals to carried items.

For each proposed agent:
- **{agent name}** — {why this agent would help, grounded in observed patterns}
  Evidence: {specific patterns, growth edges, working style traits, or carried items that support this}

  Create it? → scaffolds to `agents/custom/{name}.md` from [[agent-template]]

Only propose agents that don't duplicate existing ones (check both registries). Only propose when a pattern clearly maps to a repeatable task an agent could own. If no agents want to exist, say so — don't force it.}

### Concrete actions
{After all insights are surfaced, distill them into a single actionable table. For each insight that has a clear next step:

| Insight | Action | Where | Priority |
|---------|--------|-------|----------|
| **{insight name}** — {one-line summary} | {specific action to take} | [[{project or file}]] | High / Normal / Low |

Rules for the table:
- Only include insights that have a clear, specific action. Not every insight needs one.
- "Where" = the project note, file, or context where the action lands. Use [[wiki-links]].
- "Priority" = High (unblocks something or changes a strategic decision), Normal (enriches existing work), Low (good to do eventually).
- If an insight is already addressed, mark as ✅ Done.
- High-priority items should be routed to the relevant project's to-dos after the user reviews the emerge log.}
```

## Save to vault

After generating the report, write it to `00 - notes/logs/command-logs/emerge-{YYYY-MM-DD}.md` using `mcp__obsidian__write_note` with frontmatter `{"tags": ["emerge", "aios-command", "patterns"], "created": "{today}"}`. Then commit and push.

## Contradiction scan

Before generating the creative output, cross-check observed context files against each other and against the last 7 daily notes. Look for:

- **Stale patterns:** `patterns.md` says X, but the last 3+ sessions show the opposite. Flag: "⚠️ Contradiction: [[patterns]] says '{old claim}' but recent evidence suggests '{new behavior}'. Update or note as evolved?"
- **Outdated business assumptions:** `business.md` states a metric or strategy that project notes have superseded.
- **Growth edges resolved:** `growth.md` names a gap that recent sessions show has been closed. Flag for celebration + update.
- **Ecosystem shifts:** `ecosystem.md` describes a connection that no longer holds, or misses a new one.

Present contradictions in a dedicated section of the output:

```
## ⚠️ Contradictions detected

| File | Existing claim | Current evidence | Suggested action |
|------|---------------|-----------------|-----------------|
| [[patterns]] | "{old}" | "{new}" | Update / Keep / Note as evolved |
```

If no contradictions found, skip the section silently. Don't fabricate issues.

## Rules
- This is the most creative command. Let patterns speak.
- Quote specific notes when showing evidence
- "The idea that wants to exist" should feel like a genuine discovery
- Don't force connections. If nothing emerges, say so.
- Look especially at intersections between ventures
- Agent proposals must be grounded in observed context — not generic productivity suggestions. The agent should address a pattern specific to this user.
- Use [[wiki-links]] for all project names, context files, and ventures mentioned.
