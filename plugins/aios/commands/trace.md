---
tags:
  - aios
  - command
  - on-demand
argument-hint: "<topic to trace>"
description: Track how thinking about a specific idea changed over time through notes
allowed-tools: mcp__obsidian__*, Read
---

# /trace — Thinking Tracker

The user provides a topic. Track how thinking about it evolved across the vault.

## When to use

When revisiting a topic and you want to see how your thinking has evolved — across daily notes, reflections, and projects. Especially valuable on Day 90+ when there's enough vault density for the trace to show real evolution (not just one mention).


## Steps

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /trace` for any user overrides. Apply them to the steps below.

1. Parse the topic from the user's argument
2. Search ALL notes for mentions of the topic
3. Order mentions chronologically
4. Identify where thinking shifted and what caused it
5. **Compounding view:** formulate the natural question behind the topic (e.g. topic "pricing" → *"how should I price engagements?"*), then answer it at **three snapshots** of the vault. Rules that keep it honest:
   - **Question validation:** skip the view for stable-factual questions (answers that don't improve with context) — say so instead.
   - **Snapshot selection:** pick the two earlier points at *inflection moments* (where relevant context roughly doubled — a project landing, a venture mounting, a study arc), not arbitrary dates. Third snapshot = today.
   - **Anachronism guard:** each answer may use ONLY what existed in the vault at that time. Check yourself afterward.
   - **Equal length (hard constraint):** all three answers the same length — isolates quality improvement from volume inflation.
   - **Null result is a result:** if the answers didn't meaningfully improve, that IS the finding — name it, don't fabricate progress.

## Output

```
## Trace: "{topic}"

### Timeline
| Date | Source | What was said/decided |
|------|--------|----------------------|
| {date} | {note} | {key point} |

### Inflection points
{Moments where thinking clearly shifted — what happened?}

### The arc
{One paragraph: how thinking evolved from start to now}

### Current position
{Where the thinking stands today}

### What might shift next
{Based on trajectory, where might this go?}

### Compounding view
**The question:** {the natural question behind the topic}
**Answered with the vault as of {snapshot 1 — inflection date}:** {N sentences — only what was knowable then}
**Answered with the vault as of {snapshot 2 — inflection date}:** {same length}
**Answered with the vault today:** {same length}
**Where it improved:** {specificity / actionability / personal relevance / cross-domain connections — name which dimensions moved and what caused each jump}
**What compounded:** {one line — the proof the system works. If nothing meaningfully improved, say that instead.}

### Concrete actions

| Insight | Action | Where | Priority |
|---------|--------|-------|----------|
| **{insight}** — {one-line} | {specific action} | [[{project or file}]] | High / Normal / Low |

{Only include insights with clear next steps. Mark already-addressed items as ✅ Done. High = unblocks something or changes a decision. Normal = enriches existing work. Low = good to do eventually.}
```


## Save to vault

After generating the report, write it to `00 - notes/logs/command-logs/trace-{topic}-{YYYY-MM-DD}.md` using `mcp__obsidian__write_note` with frontmatter `{"tags": ["trace", "aios-command"], "created": "{today}"}`. Then commit and push.

## Rules
- Only meaningful mentions, not every passing reference
- Inflection points are the most valuable output
- If thinking hasn't evolved, say so — stasis is worth naming
- Use [[wiki-links]] for all project names, context files, and ventures mentioned.
