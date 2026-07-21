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

**Primary — the Glass "Close all" button.** Opens a **multi-select picker** (like "go with agents") of every live Claude session. **All are checked by default EXCEPT your active session** (flagged `⟵ active — you're here`, off by default). **Working sessions** (busy — the amber dot, read from `~/.claude/sessions/<pid>.json`) are flagged `🟡 working` so you can uncheck them (`sendText` *queues* `/close-session`, so a busy session finishes its task then closes — it is never interrupted). You confirm the set; Glass sends `/close-session` to each checked session's terminal.

**CLI — this command.** Argument-driven:
- **`/close-all`** (no args) → every active named session **except the one running this command**. Enumerate: `pgrep -fl "claude .*--remote-control --name"`; drop your own session's name; confirm the list before sending.
- **`/close-all name-a name-b`** → **only** the named sessions (e.g. `/close-all chuy-lens content-writer`).
- **`--close-day`** → after the selected sessions finish, run `/close-day` once **in this (main) session** to consolidate.
- **`--kill`** → after each **selected, non-self** session finishes its capture (watch it return to idle — never mid-capture), `spawn-kill {name}` it. **Never** kills this session or any unselected one.
- Send **`/close-session --auto`** (non-interactive — infers its label, skips the prompts, so it completes and idles) to each selected session over the Remote-Control channel the `spawn` wrapper set up, **sequentially, not in parallel** (that path is clipboard-mediated; parallel sends race — see `feedback_spawn_sequential_not_parallel`). Each session self-closes (own report / merge-appends its own block + `aios-commit`s its own work). If no Remote-Control send exists in your setup, tell the operator to use the Glass picker.

**Then:** run **`/close-day`** (once) to consolidate — it harvests every `.claude/session-report-{date}-*.md` (the `-*` catches all per-session files) and writes the day's one narrative.

## Rules
- **Never close the session running `/close-all`** — drop it from the set (CLI) / default it unchecked (Glass).
- **Never write the daily note from here.** `/close-all` only triggers; sessions capture themselves; `/close-day` is the sole note-writer.
- **Working sessions aren't interrupted** — `/close-session` queues after the current task. Uncheck them if you'd rather they finish untouched.
- **Sequential** over Remote-Control (parallel = clipboard race). The Glass picker drives terminals directly, so it has no such constraint.
- **Idempotent per session** — a session already closed just re-writes its own report/block; no cross-effect (the per-session filename + the locks guarantee it, exactly like a `/close-all` — see the note-append + aios-commit design).
