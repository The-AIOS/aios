---
tags:
  - aios
  - command
  - biweekly
description: Promote half-formed ideas from recent daily notes into standalone permanent notes
allowed-tools: mcp__obsidian__*, Read
---

# /graduate — Promote Ideas to Permanent Notes

Scan recent daily notes for ideas worth their own note, then create standalone files for each.

## When to use

Every 2 weeks (or whenever the daily-note parking lot feels heavy) to promote half-formed ideas into standalone permanent notes. The capture-loop's compounding step.


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
5. **Make lens (publish-ripeness):** after graduating notes, run a second pass over BOTH the new graduates AND existing `ideas/` notes: which are ripe to become *published output* — and in what form? Detect ripeness via five signals (search queries, not vibes):
   - **Density** — mentioned repeatedly across multiple days; material has accumulated
   - **Originality** — diverges from conventional thinking (search: "most people think", "wrong about", "actually")
   - **Narrative** — a documented arc or transformation (search: "realized", "changed my mind", "turning point")
   - **Tension** — unresolved questions with substance on multiple sides (search: "on one hand", "paradox", "tradeoff")
   - **Resonance** — external validation already happened (conversations, feedback, someone asked for it)

   A candidate needs claim + evidence + an audience who'd care. Recommend **multiple natural forms** per candidate, not one prescription: post (single insight) · deck/talk (framework with stages) · product/template (reusable artifact) · thread (listicle energy) · series (arc too big for one piece). Max 3 candidates — ripeness, not inventory; ruthlessly honest scores beat flattering ones.

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

### Make-ripe (publish candidates)
- **{Title}** → recommended form: {post / deck / product / thread} — {one line: the claim + who'd care}
{Max 3. Omit section if nothing is genuinely ripe — forced candidates erode trust in the lens.}
```

Then commit and push: `cd ~/aios && ~/aios/hooks/aios-commit --vault -m "Graduate ideas {date}"`

## Rules

- Quality over quantity — 2 well-formed notes beat 8 half-baked ones
- The claim must be a claim, not a topic. "Trust is becoming infrastructure" not "Trust"
- Don't graduate task items or project to-dos — only ideas
- If an idea appears in only one note and isn't clearly developed, skip it
- Keep "Open questions" honest — unresolved tension is what makes an idea alive
