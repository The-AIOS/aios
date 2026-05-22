---
tags:
  - aios
  - command
  - on-demand
description: Scan the vault and generate a full idea report — things to build, write, explore, and connect
allowed-tools: mcp__obsidian__*, Read
---

# /ideas — Idea Report

Scan the user's full vault and generate a grounded idea report based on actual patterns, interests, and open threads.

## When to use

When you need inspiration — a grounded report of things to build, write, explore, or connect, all traced back to vault evidence. Run when feeling creatively blocked or before strategic planning.


## Steps

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /ideas` for any user overrides. Apply them to the steps below.

1. Read ALL observed context: `00 - notes/context/observed/` (ecosystem, business, patterns, growth, session-insights)
2. Read ALL declared context: `00 - notes/context/declared/` (about_me, personal_voice, about_business)
3. Read ALL project notes: `00 - notes/projects/`
4. Read recent daily notes from `01 - calendar/{YYYY-MM}/`
5. Synthesize into an idea report — ground every idea in vault evidence

## Output

Present in the response only (no file written):

```
## Idea Report — {date}

### Tools to build
{Ideas for software, automations, or systems — grounded in real gaps or recurring friction visible in the vault}
- **{Idea}** — {why it makes sense now, what need it addresses}

### Things to write
{Content ideas grounded in what the user is actually thinking about — blog posts, essays, LinkedIn pieces, course modules}
- **{Title/angle}** — {what insight it's based on, why now}

### People to connect with
{Types of people or specific names mentioned in notes who would unlock something}
- **{Who/type}** — {what the connection could produce}

### Topics to investigate
{Subjects appearing repeatedly that deserve deeper exploration}
- **{Topic}** — {why it keeps surfacing, what question it's pointing at}

### The one idea I'd start with
{The single highest-leverage idea from this list and why}

### Concrete actions

| Insight | Action | Where | Priority |
|---------|--------|-------|----------|
| **{insight}** — {one-line} | {specific action} | [[{project or file}]] | High / Normal / Low |

{Only include insights with clear next steps. Mark already-addressed items as ✅ Done. High = unblocks something or changes a decision. Normal = enriches existing work. Low = good to do eventually.}
```


## Save to vault

After generating the report, write it to `00 - notes/logs/command-logs/ideas-{YYYY-MM-DD}.md` using `mcp__obsidian__write_note` with frontmatter `{"tags": ["ideas", "aios-command"], "created": "{today}"}`. Then commit and push.

## Rules

- Every idea must trace back to something in the vault — no generic suggestions
- "Things to write" should be calibrated to the user's actual voice and audience (read personal_voice.md + about_me.md)
- Flag cross-venture ideas explicitly — the most interesting ones serve more than one venture
- "People to connect with" can be archetypes if no names appear ("a government CTO in LATAM" is valid)
- Keep the list tight: 3-5 items per category maximum
- The "one idea I'd start with" should be genuinely surprising — not the obvious one
- Use [[wiki-links]] for all project names, context files, and ventures mentioned.
