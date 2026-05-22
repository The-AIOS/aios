---
tags:
  - context
  - claude-observed
  - antifragile
  - self-correcting
created: '2026-03-31'
updated: '2026-03-31'
type: claude-context
---
# Antifragile — What the System Learns From Breaking

> This is the only observed file where Claude writes about Claude. Not about the user — about the system itself. Every failure is a system upgrade waiting to happen.
>
> **When to write here:**
> 1. **User corrects you** — "don't do this again", "that was wrong", "you keep making this mistake", "remember this for next time." Write it IMMEDIATELY. This is the primary trigger.
> 2. **You catch your own mistake** — something breaks, gets skipped, silently fails. The FIX isn't just correcting the output but changing how the system works.
> Don't log every mistake. Log the ones that reveal where the system is fragile.
>
> **What NOT to write here:** User corrections about preferences (those go in `preferences.md`), behavioral patterns (those go in `patterns.md`), or task-specific fixes (those go in project notes). This file is for **system-level learnings** — the kind that prevent entire categories of failure.
>
> **How to use it:** Read this file at session start (CLAUDE.md Step 2 — observed context). Before executing any command, scan for relevant rules. The goal: never make the same system-level mistake twice.
>
> **Rule:** Never delete entries. If a rule becomes obsolete, add a new entry that supersedes it with context on why it changed. The evolution is the value.

---

## Patterns of fragility (what breaks and why)

<!-- Add entries here as the system learns. Format:

### N. Short description (date)
**What happened:** What went wrong.
**Why it broke:** The root cause — not the symptom.
**System fix:** What changed so it never happens again.
**Category:** [PROCESS] / [ARCH] / [TOOL] / [CODE] / [DATA] / [OTHER]
-->

---

## Meta-patterns (what the failures have in common)

<!-- As entries accumulate, group them into meta-patterns. These are the deeper lessons —
the root causes that explain multiple failures at once. -->
