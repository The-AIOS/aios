---
tags:
  - aios
  - command
  - daily
description: Broadcast /close-session to every active session — the "wrap up now" fan-out
allowed-tools: Bash(pgrep:*), Bash(ls:*), Read
---

# /close-all — Close-Session Broadcast

You are firing a **broadcast**, not a consolidation. `/close-all` tells **every active session to wrap itself up** — it runs `/close-session` in each one. It is NOT a coordinator and it never writes the daily note; each session captures *itself*, and `/close-day` (run separately, once) consolidates.

> **The three, sharply:**
> - **`aios-commit`** — the commit *primitive*; every commit goes through it (race-safe attribution).
> - **`/close-all`** (this) — a *broadcast*: fires `/close-session` in every active session. A command **and** a Glass button.
> - **`/close-day`** — the *consolidator*, run once: harvests the per-session reports → writes the one daily note.

## Why it's race-safe (the design)

Each `/close-session` the broadcast fires writes to a **different place** — a **vault** session merge-appends its block into today's note under a per-file lock (so N land in turn, zero clobber), and a **project/worker** session writes its own `.claude/session-report-{date}-{session}.md`. So there is no shared file two things fight over. Every commit underneath is `aios-commit` (mutex + scoped staging + throwaway-index plumbing). Scenario 2 (many sessions closing at once) is dissolved, not locked around.

## How to broadcast

**Primary — the Glass "Close all" button.** Glass owns the terminal handles: it iterates every live Claude terminal and sends `/close-session` to each. One click wraps the whole fleet. This is the intended UX.

**CLI — this command.** When run in a terminal (no Glass), enumerate the active named sessions and send each the `/close-session` command over the Remote-Control channel the `spawn` wrapper set up:

1. List active sessions: `pgrep -fl "claude .*--remote-control --name"` → the running named sessions (name is on the command line).
2. Send `/close-session` to **each** named session over its Remote-Control channel. **Sequentially, not in parallel** — the spawn/remote-control path is clipboard-mediated and parallel sends race (see `feedback_spawn_sequential_not_parallel`). One at a time; each session self-closes (writes its own report / merge-appends its own block + `aios-commit`s its own work).
3. If no Remote-Control send is available in your setup, tell the operator: *"Use the Glass 'Close all' button, or run `/close-session` in each terminal — each self-closes safely (per-session reports + aios-commit)."*

**Then:** the coordinating session runs **`/close-day`** to consolidate — it harvests every `.claude/session-report-{date}-*.md` (the `-*` catches all the per-session files) and writes the day's one narrative.

## Rules
- **Never write the daily note from here.** `/close-all` only triggers; sessions capture themselves; `/close-day` is the sole note-writer for the consolidation.
- **Sequential broadcast** over Remote-Control (parallel = clipboard race). The Glass button doesn't have this constraint (it drives terminals directly).
- **Idempotent per session.** A session already closed just re-writes its own report/block — no cross-effect.
