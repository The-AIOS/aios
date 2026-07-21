---
tags:
  - aios
  - command
  - daily
description: End-of-session capture — detects vault vs project terminal, writes to the right place
allowed-tools: mcp__obsidian__*, Bash(~/aios/hooks/aios-commit:*), Bash(~/aios/hooks/aios-note-append:*), Bash(cd ~/aios && git:*), Bash(pwd), Bash(ls *), Bash(cat *), Read
---

# /close-session — Session Capture

You are running a session capture. This command auto-detects where you're running and behaves accordingly:

- **Mode A (vault session):** You're in `~/aios` or Obsidian MCP is available → append a session block to today's daily note
- **Mode B (project terminal):** You're in a code repo → write a session report file locally for `/close-day` to pick up

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /close-session` for any user overrides.

## When to use

When finishing a focused work session — agent session, dev session, ad-hoc spawn. Lightweight capture that bridges back to the daily note + project notes. Feeds the next /close-day. Run it whenever the work has a clear stopping point.

## Non-interactive `--auto` mode (used by `/close-all`)

When invoked as `/close-session --auto` (the `/close-all` broadcast fires this in each selected session), run with **no prompts** so the session self-closes cleanly and returns to **idle** (which is what lets `/close-all`'s optional "kill after" fire safely — only *after* the capture is done):

- **Infer** the label from the conversation (`{HH:MM} | {topic}`) — do NOT ask to confirm it.
- **Skip every step that waits for user input** — no *"Session label — correct?"*, no *"What was most useful?"*, no *"Worth filing?"*. (A broadcast has no one present to answer N prompts.)
- **Keep every step that captures / commits** — Mode A merge-appends its block via `aios-note-append`; Mode B writes its per-session report; the commit is `aios-commit`.
- **Under `--auto`, DEFER all observed-context routing to `/close-day` (single-writer) — do NOT run the direct Tier A writes in steps 6–7.** A broadcast can close several *vault* sessions at once, and the daily-note lock does **not** protect the observed files (`session-insights.md`, `patterns.md`, `preferences.md`, `business.md`, `antifragile.md`) — those steps read-scan-edit-write, so two parallel closes clobber each other (last-writer-wins). Instead, **capture** each observation as a candidate in the block — Tier A → `**Observed (Tier A candidates):**`, Tier B → `**Observed (Tier B candidates):**` — commit only the block, and let `/close-day` route them as the sole writer. **Nothing is lost:** routing moves from per-session to the consolidator, exactly as Mode B workers already defer via their reports. This is *why* parallel closing can't "make a mess" — under a broadcast there is exactly **one** observed-context writer (close-day), so no clobber, no trip, and no staleness (close-day always routes). (Interactive single `/close-session` still writes Tier A inline — no concurrency there → no race → immediate value.)
- **Finish promptly** — completion → idle is the contract `--auto` exists to honor.

The rest of this command is the **interactive** (manual `/close-session`) flow. Under `--auto`, skip each input-waiting step, run each capture/route/commit step.


## Mode detection

Run `pwd` to check the current working directory.

- If cwd is `~/aios` (or any path containing `/obsidian`) **OR** the `mcp__obsidian__read_note` tool is available → **Mode A**
- Otherwise → **Mode B**

Announce the detected mode: "Detected: **vault session** — writing to daily note" or "Detected: **project terminal** ({project name}) — writing session report"

---

## Mode A — Vault Session

**Goal:** Append a structured session block to today's daily note so `/close-day` has structured input. Takes under 60 seconds.

### Steps

0. **Truth-surface reconcile (ship-time truth-flip — see CLAUDE.md § Discipline).** For everything this session shipped, verify its truth surface already flipped: keyed items (grep the key's definition — a live `type: roadmap` file) show ✅ + their declared `ledger:` row appended; unkeyed items show done at their project note. Any miss → flip it now and note the miss in the session block. Close-session is the backstop, never the primary.
1. Read today's daily note from `01 - calendar/{YYYY-MM}/{today YYYY-MM-DD}.md`
2. Read `00 - notes/context/observed/session-insights.md` — check current content for snapshotting
3. Infer a session label from the conversation: current time (HH:MM) + a 2–4 word topic. Present it to the user for confirmation: "Session label: **{HH:MM} | {Topic}** — correct, or adjust?"
4. Wait for user response on label
5. **Append the session block via the race-safe helper — never write the note directly** (a concurrent `/close-all` fires several vault sessions at once; a direct read-append-write would clobber). Write the block (format below) to a temp file, then:
   ```bash
   ~/aios/hooks/aios-note-append \
     --note "$HOME/aios/vault/01 - calendar/{YYYY-MM}/{YYYY-MM-DD}.md" \
     --before "## Close of Day" \
     -m "session: {HH:MM} {Topic}" \
     --block-file /tmp/aios-session-block.$$.md
   ```
   The helper takes a **per-file lock + merge-appends**: under the lock it re-reads the *latest* note and inserts the block before `## Close of Day` (or at the end if that marker is absent — omit `--before` then), then commits the note via `aios-commit`. So N sessions closing at once each land their block **in turn** — ordered, zero clobber, all visible immediately. (Then `rm` the temp block file.)
6. Update `session-insights.md` (observation buffer — not a log):
   - **Scan existing entries first:**
     - Does this session **reinforce** an Emerging insight? → move it to Reinforced with the new date
     - Does this session **contradict** an existing insight? → remove it
     - Is a Reinforced insight ready to **route** (clear evidence, target file identified)? → write to target observed file (snapshot it first), remove from session-insights
     - Is there a **stale** Emerging insight you're making room for? → drop it
   - **Then add** new pattern-level observations from this session to Emerging (with date + evidence + route-to target)
   - **Snapshot** session-insights only if the document actually changed (not every session)
   - **Cap:** Emerging ≤10, Reinforced ≤5. Adding forces reviewing.
   - Session summaries (what happened, wins) belong in the daily note block above — session-insights holds only distilled observations.
7. **Update observed context files when warranted** — same rules as close-day. Scan the session for:
   - New behavioral pattern confirmed (2+ sessions of evidence) → `patterns.md`
   - New preference discovered → `preferences.md`
   - Strategic insight about ventures → `business.md`
   - System failure or user correction → `antifragile.md`
   Snapshot before editing **and set the edited file's `updated:` frontmatter to today** (the snapshot-and-stamp rule — CLAUDE.md § Session End; the staleness alarm reads that stamp). Not every session produces observations — but never skip this check for speed. The observed context is the compound value of the vault.

   **Tier B files (growth / profile / ecosystem) — capture candidates, do NOT write directly.** These files live one synthesis layer above session-insights — observations about the operator (not about work mechanics). A single session lacks the cross-session view needed to clear the substance bar (timeline + uniqueness + evidence + essentiality tests). Instead:
   - Note Tier B candidates in this session's daily-note block under `**Observed (Tier B candidates):**` — e.g. *"possible growth edge: re-secuenciar > apurar el cierre, 3rd instance this month"*. One line each. Date + evidence. No write to growth/profile/ecosystem.md.
   - `/close-day` runs the digest across all sessions, the daily note, and recent antifragile/session-insights, then writes to Tier B files when the substance bar passes (see `/close-day` § Tier B observation pass for the bar + per-file feed-in sources).
   - **Why this split:** close-session is single-session scope; close-day has cross-session + daily synthesis context. Writing Tier B from close-session would amplify per-session noise (same insight surfacing 3 times across 3 close-sessions, written 3 times). Close-day consolidates the signal.
8. **Comprehension ledger** — guard the operator's understanding against what the agents shipped (CLAUDE.md § VI → "Comprehension debt"). Scan this session for changes the operator did *not* author themselves: commits by spawned workers / other agent sessions, files written by background subagents, anything `/aios:update` or an autonomous loop changed. **If there are none, skip this step silently** (the operator authored everything → no debt to surface). If there are:

   **a. Recap first — bullet the surface area.** Lead with a tight enumerated list of *everything* that shipped this session — one line per item: *what* shipped · *what it does* · *where it lives* (file / PR / repo / URL). **This recap is mandatory and comes before the offer.** The operator can't ask about what they don't know shipped — an offer with no list is the exact failure mode ("you don't know what you don't know"). Group by surface if it's a lot (vault / canonical / site / external).

   **b. Then offer, don't quiz:**

   > *"☝️ That's everything that shipped this session. Want me to walk you through any of it? The bar isn't reading every line — it's that you understand what shipped well enough to defend, debug, or decide on it later. Anything you'd like me to explain?"*

   Walk through whatever the operator asks about (the *why* + failure modes, not a line reading). What they decline to grasp goes into the session block's `**Comprehension:**` field and an `**Open threads:**` carry — marked *un-grasped*, not *done* — so `/close-day` can resurface it. The debt is the operator's (they're the one who owns the system in a room); your job is to keep it low, never to wave agent output through on their behalf. Full mechanism: the `comprehension-debt` skill.

9. **Self-update verification** — before commit, walk the CLAUDE.md Session End rules to confirm step 7 wasn't skipped. The compounding promise of the AI-OS lives in routing, not logging.

   - [ ] Snapshotted observed-context files I modified **AND set each one's `updated:` to today** (per CLAUDE.md → "Session End → Snapshot before editing, stamp after")
   - [ ] Updated `session-insights.md` per CLAUDE.md → "Self-Update → Observed Context Rules" — Emerging / Reinforced / Routed lifecycle; ≤10 Emerging, ≤5 Reinforced
   - [ ] Updated other observed files when warranted (per CLAUDE.md → "Observed Context Rules" — patterns / preferences / business / ecosystem / growth / profile)
   - [ ] Wrote to `antifragile.md` if the user corrected me OR I caught my own system-level mistake (per CLAUDE.md mandatory triggers)
   - [ ] Asked "What was most useful?" if the session was substantive (>30 min, meaningful work — per CLAUDE.md Session End step 4); verbatim answer captured in the session block's `**Most useful:**` field

   If any unchecked, complete it now before commit.

   **Logging is not routing.** Don't commit until each insight from this session lives in `session-insights.md` (or routed onward to its target observed file). The daily-note "What I learned" is a holding cell, not a destination. The AI-OS compounds on routing — capture-only is stranded.

10. **Commit any observed-context you touched via `aios-commit`** (the note block was already committed by `aios-note-append` in step 5). **NEVER `git add -A`** — in a concurrently-written vault it sweeps other sessions' + the human's in-flight files into your commit (scrambled attribution). Commit only the paths you changed:
   ```bash
   ~/aios/hooks/aios-commit -m "session: {date} {topic}" -- \
     "vault/00 - notes/context/observed/session-insights.md" {any other files you edited}
   ```
   `aios-commit` stages ONLY the given paths via a throwaway index (working tree untouched), self-scans for secrets, and pushes with defer-on-offline. It is the one sanctioned commit path — it replaces `git add -A` everywhere.

### Session block format (Mode A)

Append this to the daily note:

```
---

## Session — {HH:MM} | {Topic}

> {One sentence characterization — not a summary, a frame. What was this session really about?}

**Wins:**
- {Binary deliverables — shipped/decided/unblocked, not "worked on"}

**Learned:**
- {Pattern-level insight, not task-level}

**Most useful:** {User's verbatim answer to "What was most useful for you in this session?" One line, in their words. Skip if not asked — quick session, no substantive work.}

**Open threads:**
- [ ] {Unfinished items — these feed next session or close-day carries. Write "None" if the session closed cleanly. Don't fabricate threads to fill the field.}

**Comprehension:** {Of the agent-authored changes this session (work the operator didn't write themselves), what the operator now understands well enough to own — and what they declined to walk through (rolls forward as comprehension debt, not done). Write "All operator-authored" if nothing was agent-shipped this session. The bar is understanding (defend/debug/decide), not line-by-line reading. Don't fabricate. See the `comprehension-debt` skill.}

**Observed (Tier A candidates):**
- {**Under `--auto` only** (deferred routing — see § Non-interactive `--auto` mode): one-line captures of Tier A observations this session would otherwise have written inline — session-insights entries, confirmed patterns, preferences, business/venture insights, antifragile corrections. `/close-day` routes these as the single writer (Tier A → the target file, snapshot first). Format: `{observation} → {target file} _(evidence)_`. Interactive closes write Tier A inline and put "Routed inline" here. Skip the field entirely if nothing surfaced. Don't fabricate.}

**Observed (Tier B candidates):**
- {One-line capture of any growth / profile / ecosystem candidates surfaced this session — observations about the OPERATOR (not work mechanics). Skip the field entirely if nothing surfaced. Don't fabricate to fill it. Examples: "possible growth edge: re-secuenciar > apurar (3rd instance this month)" / "ecosystem shift: Lucas Jolias is now in advisor-grade orbit, not weekly-collab" / "profile signal: integrative work AND presentation work compound together, naming the integrative posture as identity-level" — these become feed-in for /close-day's Tier B digest later, which decides whether they pass the substance bar to write.}

**Energy:** {One honest word — sharp, scattered, fading, deep flow}
```

### "File answers back" check

After writing the session block, scan the conversation for discoveries worth filing as permanent pages — analyses, comparisons, connections, research, frameworks, or insights that would be valuable in 3 months. These shouldn't disappear into chat history.

Prompt the user:

```
📄 **Worth filing?** This session produced {N} insights that could be permanent pages:
- "{insight title}" → `reflections/{slug}.md`
- "{insight title}" → `ideas/{slug}.md`

File them now, or skip?
```

If yes → write the pages (with `[[wiki-links]]`, proper frontmatter, source attribution to this session), update the relevant `_index.md`. If no → move on. If the session was purely operational (commits, fixes, task management) with no reusable discoveries, skip the prompt silently.

**Rule:** This is Karpathy's key insight — good answers compound when filed. Chat history doesn't. The LLM does the bookkeeping; the human just says "yes, file it."

---

## Mode B — Project Terminal (Session Bridge)

**Goal:** Write a structured session report to the **single canonical harvest dir `~/aios/.claude/`** (NOT the current repo's `.claude/`). `/close-day` scans that one dir and routes content to the vault — so a session in *any* repo lands where close-day looks, with **zero dependency on the repo being registered** in USER.md's Dev-projects table. (This is the seam-2 fix: an unregistered repo's report used to be written in-repo and never harvested — stranding it. One canonical dir dissolves that.)

### Steps

1. Determine the project name from the repo (read `package.json` name, or `CLAUDE.md` title, or folder name)
2. **Date rule:** If the current time is between midnight and 7:00 AM, ask the user which date the report belongs to — late-night sessions usually belong to the previous day. After 7:00 AM, use today's date.
3. Infer session content from the conversation
4. Write the report to **`~/aios/.claude/session-report-{YYYY-MM-DD}-{project}-{session}.md`** — `{project}` is a filesystem-safe slug of the repo name (from step 1), `{session}` is `$CLAUDE_AGENT_NAME` (fallback: a short session-id or pid if unset). **Both suffixes are load-bearing at a shared dir:** `{project}` keeps two *different* repos' sessions from colliding in the one harvest dir, and `{session}` keeps a `/close-all` broadcast's N workers in the *same* repo from clobbering each other. Write it to `~/aios/.claude/` **even though the session runs in another repo** — that's the whole point: one dir close-day always scans, no registration needed. (`~/aios/.claude/` is fully gitignored, so the report never leaks into any repo's git.) Then commit your session's own scoped work via `~/aios/hooks/aios-commit -m "..." -- <paths>` (never `git add -A`).
5. Confirm: "Session report written to `~/aios/.claude/session-report-{date}-{project}-{session}.md`. `/close-day` will pick it up tonight."

### Session report format (Mode B)

```markdown
---
project: {project name from repo}
date: {YYYY-MM-DD}
duration: {estimated hours}
---

## What shipped
- {completed items — be specific}

## Decisions
- {decisions made, with rationale}

## Pendientes
| # | Pendiente | Prioridad |
|---|-----------|-----------|
| 1 | {task}    | Alta/Media/Baja |

## Notes
{Free context — insights, problems found, patterns noticed, blockers}

## Most useful
{User's verbatim answer to "What was most useful for you in this session?" One line, in their words. Skip if not asked.}

## Observed
<!-- Optional: patterns, preferences, or growth edges noticed about the user during this session.
     /close-day routes these to the appropriate observed context file.
     Leave empty if nothing significant was observed. -->

## Observed (Tier B candidates)
<!-- Optional: one-line captures of growth / profile / ecosystem candidates surfaced this session —
     observations about the OPERATOR, not about work mechanics. Single sessions lack the cross-session
     view to clear the substance bar, so we capture here and /close-day decides whether to write to
     growth.md / profile.md / ecosystem.md via its Tier B digest pass.
     Skip entirely if nothing surfaced. Don't fabricate. Examples:
     - "possible growth edge: re-secuenciar > apurar (3rd instance this month)"
     - "ecosystem shift: {person} now in advisor-grade orbit, not weekly-collab" -->


## Comprehension
<!-- Of the changes shipped this session the operator did NOT author (agent / subagent / loop / aios:update output):
     what they understand well enough to own, and what's still un-grasped (carries forward as comprehension debt).
     Write "All operator-authored" if nothing was agent-shipped. The bar is understanding (defend/debug/decide), not
     line-by-line reading. See the comprehension-debt skill. Skip the offer silently if the operator authored everything. -->


## Project Note Updates
{Proposed changes to the vault project note. /close-day applies these.}

### Current State
{What changed — replaces or complements the Current State section in the project note. Only include what's new or different.}

### To-Dos
{Mark completed items and add new ones. Use the same tiers as the project note: High Priority, Normal, Ideas.}
- [x] {completed items from this session}
- [ ] {new items discovered during this session}

### Session Notes Entry
{Ready-to-insert entry for the ## Session Notes section of the project note. Written in English.}

### {YYYY-MM-DD} — {brief session title}
{Substance of the session — what was done, key decisions, outcomes. Not a transcript.}
- [ ] {follow-up tasks}
```

### Mode B rules
- **All reports land in the one canonical dir `~/aios/.claude/`** — never the running repo's `.claude/`. That single location is what makes harvest coverage complete: close-day scans it and nothing strands, regardless of which repo the session ran in.
- One report **per (project, session)** — the `-{project}-{session}` suffix. `{project}` prevents two *different* repos colliding in the shared dir; `{session}` lets a `/close-all` fire N workers in the *same* repo without clobbering. If the *same* session runs `/close-session` twice on one date, overwrite its own file.
- These files are gitignored — never commit them. `~/aios/.claude/` is already fully gitignored in the vault (`.claude/` line in `.gitignore`), so no per-repo `.gitignore` entry is needed anymore.
- Be specific: names, numbers, error messages
- Write in the same language the session was conducted in
- Include enough context for someone reading this without the session history
- **`## Observed` is optional but valuable.** If you noticed a genuine pattern, preference, or growth edge during the session, write it. `/close-day` routes it to the right observed context file. Don't force it — not every session produces an observation. But don't skip it just because you're in a standalone terminal — those observations would otherwise be lost.

---

## Rules (both modes)

- **Wins are binary.** Shipped or didn't. Decided or didn't. "Made progress on" is not a win.
- **Learned is mandatory.** Every session teaches something. If nothing was learned, name what was avoided.
- **Comprehension over reading (when agents shipped).** If agents shipped work this session that the operator didn't author, surface it and *offer* to explain — the goal is the operator understanding what shipped well enough to defend/debug/decide, not having read every line. Un-grasped agent output carries forward as comprehension debt, never as done. Skip silently when the operator authored everything. See CLAUDE.md § VI + the `comprehension-debt` skill.
- **All fields present, but emptiness is honest.** The block/report is a contract — `/close-day` parses it. Don't skip sections, but write "None" for fields that genuinely have no content (open threads when the session closed cleanly, wins on a pure-thinking session, most useful when the question wasn't asked). Fabricated content is worse than honest emptiness — it pollutes downstream pipelines (`/today` carries, observed-context patterns, Google Tasks).
- **Multiple sessions per day expected.** Mode A: each gets its own `## Session —` heading. Mode B: overwrites the same file.
- Use `[[wiki-links]]` for all project names, venture names, and context file references.
- Keep it tight. This is capture, not reflection. `/close-day` does the synthesis.
