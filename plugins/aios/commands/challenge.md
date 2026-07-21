---
tags:
  - aios
  - command
  - on-demand
argument-hint: "<position to challenge>"
description: Steel-man — argue against your current thinking on a topic using vault evidence
allowed-tools: mcp__obsidian__*, Read
---

# /challenge — Steel Man

The user will provide a position to challenge. Build the strongest possible counter-argument using evidence from the vault.

## When to use

When the operator has formed a position, decision, or thesis and wants to genuinely stress-test it — not validation, adversarial thinking in service of clarity. Before big decisions, when conviction feels too easy, when assumptions need pressure.


## Steps

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /challenge` for any user overrides. Apply them to the steps below.

1. Parse the position from the user's argument
2. Read relevant context and project notes for the topic
3. Find the strongest arguments FOR the current position (steel-man it first)
4. Build the strongest possible argument AGAINST it using vault evidence — **(consult the `leverage-points` skill:** the strongest counter is often *"you're intervening at a low-leverage point"* — the goal is right but the chosen lever [a parameter, a buffer] won't move it; name the higher-leverage place instead)
5. Surface blind spots and untested assumptions

## Output

```
## Challenge: "{position}"

### Your current case (as I understand it)
{Strongest version of the current position}

### The counter-case
{Strongest argument against, from vault evidence and strategic logic}

### Blind spots
- {Assumptions not being tested}
- {Risks not acknowledged}
- {Data points being underweighted}

### What would change your mind?
{Specific conditions that would make the counter-case win}

### My honest read
{Claude's actual assessment — not a diplomatic hedge}

### Concrete actions

| Insight | Action | Where | Priority |
|---------|--------|-------|----------|
| **{insight}** — {one-line} | {specific action} | [[{project or file}]] | High / Normal / Low |

{Only include insights with clear next steps. Mark already-addressed items as ✅ Done. High = unblocks something or changes a decision. Normal = enriches existing work. Low = good to do eventually.}
```


## Save to vault

After generating the report, write it to `00 - notes/logs/command-logs/challenge-{topic}-{YYYY-MM-DD}.md` using `mcp__obsidian__write_note` with frontmatter `{"tags": ["challenge", "aios-command"], "created": "{today}"}`. Then commit and push.

## Rules
- Steel-man BOTH sides
- Use actual vault evidence — reference specific notes and data
- The counter-case should be genuinely uncomfortable
- "My honest read" should be an actual opinion
- This is adversarial thinking in service of clarity
- Use [[wiki-links]] for all project names, context files, and ventures mentioned.
