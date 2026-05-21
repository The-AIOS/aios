---
tags:
  - vault-commands
  - command
  - biweekly
description: Promote half-formed ideas from recent daily notes into standalone permanent notes
allowed-tools: mcp__obsidian__*, Read
---

# /graduate — Promote Ideas to Permanent Notes

Scan recent daily notes for ideas worth their own note, then create standalone files for each.

## Steps

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /graduate` for any user overrides. Apply them to the steps below.

1. List and read all daily notes from the last 14 days in `01 - calendar/{YYYY-MM}/` (and previous month if needed)
2. Scan for ideas that:
   - Are stated as more than a passing thought
   - Recur across multiple days or sessions
   - Have clear connections to other vault notes
   - Deserve development beyond their current one-liner form
3. For each qualifying idea, check if a note for it already exists in `00 - notes/ideas/`
4. Create a new note for each new graduating idea

## Output

For each graduated idea, write to `00 - notes/ideas/{kebab-case-title}.md` with frontmatter `{"tags": ["idea", "graduated", "vault"], "created": "{today}", "source": "graduated from daily notes"}`:

```
# {Idea Title}

## The claim
{One crisp sentence: the core idea in its strongest form}

## Why it matters
{2-3 sentences: what problem it solves, what opportunity it represents, or what it illuminates}

## Context
{Where did this come from? Which daily note, session, or project surfaced it?}

## Connections
{Wiki-links to related notes in the vault}
- [[{related note}]] — {how it connects}

## Open questions
- {What's still unresolved about this idea?}

## Next step
{The single most obvious next action if this idea is worth pursuing}
```

## After writing

Present a summary in the response:
```
## Graduated today — {date}

{n} ideas promoted to permanent notes:
- **{Title}** → `00 - notes/ideas/{slug}.md`
- ...

{n} ideas skipped (already exist or too undeveloped):
- {Brief note on what was skipped and why}
```

Then commit and push: `cd ~/aios && git add -A && git commit -m "Graduate ideas {date}" && git push`

## Rules

- Quality over quantity — 2 well-formed notes beat 8 half-baked ones
- The claim must be a claim, not a topic. "Trust is becoming infrastructure" not "Trust"
- Don't graduate task items or project to-dos — only ideas
- If an idea appears in only one note and isn't clearly developed, skip it
- Keep "Open questions" honest — unresolved tension is what makes an idea alive
