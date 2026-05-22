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

## Steps

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /trace` for any user overrides. Apply them to the steps below.

1. Parse the topic from the user's argument
2. Search ALL notes for mentions of the topic
3. Order mentions chronologically
4. Identify where thinking shifted and what caused it

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
