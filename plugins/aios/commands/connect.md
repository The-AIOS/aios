---
tags:
  - vault-commands
  - command
  - on-demand
description: Surface unexpected bridges between unrelated domains in the vault
allowed-tools: mcp__obsidian__*, Read
---

# /connect — Bridge Builder

Find surprising connections between seemingly unrelated notes in the vault.

## Steps

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /connect` for any user overrides. Apply them to the steps below.

1. Read ALL notes across context, projects, daily notes
2. Map the distinct domains/topics
3. Look for thematic, structural, or conceptual bridges
4. Present only genuinely surprising connections

## Output

```
## Connections — {date}

### Bridge 1: {Domain A} ↔ {Domain B}
**The connection**: {What links these}
**Evidence**: {Specific notes or quotes}
**Implication**: {What this means — could it become something?}

### Bridge 2
{Same structure}

### Bridge 3
{Same structure}

### The meta-pattern
{Pattern across the bridges themselves, if one exists}

### Concrete actions

| Insight | Action | Where | Priority |
|---------|--------|-------|----------|
| **{insight}** — {one-line} | {specific action} | [[{project or file}]] | High / Normal / Low |

{Only include insights with clear next steps. Mark already-addressed items as ✅ Done. High = unblocks something or changes a decision. Normal = enriches existing work. Low = good to do eventually.}
```


## Save to vault

After generating the report, write it to `00 - notes/logs/command-logs/connect-{YYYY-MM-DD}.md` using `mcp__obsidian__write_note` with frontmatter `{"tags": ["connect", "vault-command"], "created": "{today}"}`. Then commit and push.

## Rules
- Only genuinely surprising connections — not obvious ones
- Cross-venture bridges most valuable (e.g., main venture ↔ personal brand, technology ↔ philosophy)
- The "Implication" is key — connection without consequence is trivia
- 3-5 bridges max. Don't force what isn't there.
- Use [[wiki-links]] for all project names, context files, and ventures mentioned.
