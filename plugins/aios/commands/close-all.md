---
tags:
  - aios
  - command
  - daily
description: Broadcast /close-session to selected sessions — the "wrap up now" fan-out
argument-hint: "[session-name ...] [--close-day] [--kill]  (no names = every session except this one)"
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

## It's a selector, not a nuke

`/close-all` **never closes the session it runs in**, and both surfaces let you pick *which* sessions to close — so it can't accidentally end the session you're working in or a session mid-task you want left alone.

**Primary — the Glass "Close all" button.** Opens a **multi-select picker** (like "go with agents") of every live Claude session in the window. It iterates the session **registry** (real status + pid) and resolves each to its terminal by **pid-ancestry** — so each row shows the true running-card **status dot** (🟢 idle · 🟡 working · 🔵 needs-input · 🔴 error), not a name guess (a terminal's display name often differs from the session name, which is why a name-keyed lookup rendered every dot grey). **Every session is checked by default** — including your active + primary; uncheck any you want left open. Your primary is flagged `primary`. Two **optional** post-actions (default off): **run /close-day** (consolidates once, in your **primary** session — opens/reveals it if it isn't live) and **kill the terminals** (disposes every **selected** terminal **except your primary**). `sendText` *queues* `/close-session --auto`, so a busy session finishes its task then closes — never interrupted. **Kill = the trash-icon path** (`term.dispose()` SIGHUPs claude + the respawn loop + the shell), scoped to **selected-minus-primary**, and only AFTER each finishes capturing (busy→idle watch) — NOT `spawn-kill` in a stray terminal (that only killed the claude process, leaving the terminal open).

**CLI — this command.** Argument-driven:
- **`/close-all`** (no args) → every active named session **except the one running this command**. Enumerate: `pgrep -fl "claude .*--remote-control --name"`; drop your own session's name; confirm the list before sending.
- **`/close-all name-a name-b`** → **only** the named sessions (e.g. `/close-all chuy-lens content-writer`).
- **`--close-day`** → after the selected sessions finish, run `/close-day` once **in this (main) session** to consolidate.
- **`--kill`** → after each **selected, non-self** session finishes its capture (watch it return to idle — never mid-capture), `spawn-kill {name}` it. **Never** kills this session or any unselected one.
- Send **`/close-session --auto`** (non-interactive — infers its label, skips the prompts, so it completes and idles) to each selected session over the Remote-Control channel the `spawn` wrapper set up, **sequentially, not in parallel** (that path is clipboard-mediated; parallel sends race — see `feedback_spawn_sequential_not_parallel`). Each session self-closes (own report / merge-appends its own block + `aios-commit`s its own work). If no Remote-Control send exists in your setup, tell the operator to use the Glass picker.

**Then:** run **`/close-day`** (once) to consolidate — it harvests every `~/aios/.claude/session-report-{date}-*.md` (the canonical dir; the `-*` catches all per-session files) and writes the day's one narrative.

## Rules
- **The primary is never killed** — every session is checked by default (Glass) / the CLI drops the session it runs in; the kill post-action spares only your primary (buddai, via `primaryName()`), even when it's selected to close. Closing a session (append + idle) ≠ killing it (dispose terminal).
- **Never write the daily note from here.** `/close-all` only triggers; sessions capture themselves; `/close-day` is the sole note-writer.
- **Working sessions aren't interrupted** — `/close-session` queues after the current task. Uncheck them if you'd rather they finish untouched.
- **Sequential** over Remote-Control (parallel = clipboard race). The Glass picker drives terminals directly, so it has no such constraint.
- **Idempotent per session** — a session already closed just re-writes its own report/block; no cross-effect (the per-session filename + the locks guarantee it, exactly like a `/close-all` — see the note-append + aios-commit design).
