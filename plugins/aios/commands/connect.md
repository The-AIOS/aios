---
tags:
  - aios
  - command
  - on-demand
description: Surface unexpected bridges between unrelated domains in the vault
allowed-tools: mcp__obsidian__*, Read
---

# /connect — Bridge Builder

Find surprising connections between seemingly unrelated notes in the vault.

## When to use

Periodically (monthly is a good cadence) to find unexpected bridges between unrelated domains in the vault — patterns that only emerge when you see *everything* at once. Most valuable when you have multiple ventures or projects that feel siloed.


## Steps

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /connect` for any user overrides. Apply them to the steps below.

1. Read ALL notes across context, projects, daily notes
2. Map the distinct domains/topics — then map each domain's **neighborhood**: notes, backlinks, and tags 2-3 hops out from its hub notes (go 4+ hops for sparse domains — **depth asymmetry**: a sparse domain's connections are more valuable per link, so dig deeper there)
3. Look for bridges structurally, not just thematically: shared references, shared people, shared tags, recurring patterns — and pay special attention to **intermediary notes** (the notes that sit *between* two domains often hold the deepest insight)
4. Classify each bridge's **trend**: Converging (the domains are growing together — recent notes link more), Diverging (an old bridge fading), or Stable
5. Present only genuinely surprising connections

## Output

```
## Connections — {date}

### Bridge 1: {Domain A} ↔ {Domain B} — {Converging / Diverging / Stable}
**The connection**: {What links these}
**Evidence**: {Specific notes or quotes — name the intermediary note if one carries the bridge}
**Implication**: {What this means — could it become something?}

### Bridge 2
{Same structure}

### Bridge 3
{Same structure}

### The strongest bridge
{The single bridge most worth acting on, and why}

### Missing links
{1-3 connections that *should* exist given the neighborhoods but don't yet — each is a suggested note or conversation}

### The meta-pattern
{Pattern across the bridges themselves, if one exists}

### Concrete actions

| Insight | Action | Where | Priority |
|---------|--------|-------|----------|
| **{insight}** — {one-line} | {specific action} | [[{project or file}]] | High / Normal / Low |

{Only include insights with clear next steps. Mark already-addressed items as ✅ Done. High = unblocks something or changes a decision. Normal = enriches existing work. Low = good to do eventually.}
```


## Save to vault

After generating the report, write it to `00 - notes/logs/command-logs/connect-{YYYY-MM-DD}.md` using `mcp__obsidian__write_note` with frontmatter `{"tags": ["connect", "aios-command"], "created": "{today}"}`. Then commit and push.

## Rules
- Only genuinely surprising connections — not obvious ones
- Cross-venture bridges most valuable (e.g., main venture ↔ personal brand, technology ↔ philosophy)
- The "Implication" is key — connection without consequence is trivia
- 3-5 bridges max. Don't force what isn't there.
- Use [[wiki-links]] for all project names, context files, and ventures mentioned.
