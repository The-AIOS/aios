# AGENTS.md — portable operating contract

> **What this is.** A tool-agnostic subset of this vault's operating contract, for any coding agent or tool that reads `AGENTS.md` (Codex, Cursor, Aider, and the growing `AGENTS.md` convention). It is a **hedge** — the canonical, complete contract for Claude Code is [`CLAUDE.md`](./CLAUDE.md), and where the two differ, **`CLAUDE.md` wins**. This file carries only the portable, agent-relevant rules; it deliberately omits Claude-specific machinery (the `spawn` wrapper, MCP policy, identity/greeting, slash commands, self-update rituals).
>
> Keep this file **derived** — when a rule below changes in `CLAUDE.md`, update it here too, or drop it. Don't let the portable subset drift into a competing source of truth.

---

## The belief

The quality of context the operator gives an agent determines what it can do for them. This is a personal operating system, not a scratchpad: context **compounds** across sessions. Before acting, load context — don't start from zero.

## Load context first (session start)

This repo is a personal knowledge vault. Before substantive work:

1. Read the operator's **declared context** — every file in `vault/00 - notes/context/declared/` (who they are, how they think/decide, their ventures).
2. Read the **observed context** — every file in `vault/00 - notes/context/observed/` (what the system has learned working with them).
3. If present, read `INTENT.md` (the trust contract — what's autonomous vs. needs review) and `USER.md`.

## What this system is NOT (anti-values — refuse these even when convenient)

- **Not a to-do list** — it's a thinking partner.
- **Not a journal** — feelings belong in observed context only when they reveal a pattern, never vented into daily notes.
- **Not a CRM** — people are here because they matter to the work.
- **No sycophancy** — Radical Candor over Ruinous Empathy. Never soften an observation to uselessness. Performative agreement is lying.
- **No complexity for its own sake** — planning without shipping is avoidance disguised as productivity.

## File placement — route before you write

Place a file by **the question you'll ask to retrieve it later**, not by where it came from. Date-stamped ≠ log.

| The file is… | Home |
|---|---|
| Written by a script/system (heartbeats, snapshots) | `vault/00 - notes/logs/` — and *only* this |
| Raw input the operator didn't author (PDFs, transcripts) | `vault/02 - assets/` |
| A deliverable that ships to an audience (+ its source) | `vault/03 - export/{type-or-venture}/` |
| A time-bound narrative (what happened today) | `vault/01 - calendar/` daily note |
| Compounding — re-read for meaning | `vault/00 - notes/reflections/` (or the project note; `ideas/` if a seed) |
| About who the operator is / how to work with them | `vault/00 - notes/context/` |

**Rule of 3:** when 3+ files of the same species accumulate, create a semantic subfolder (plain-noun name; species, not dates) and move them in. Update any `_index.md` in a folder you change.

## Wiki-linking

Every note uses `[[wiki-links]]` for project names, context files, and ventures (Obsidian graph — no isolated nodes). Use `[[target|Display Text]]` for aliases. Don't link common words — only project names, people with project notes, context files, and venture names.

## Git & commit conventions

- **[Conventional Commits](https://www.conventionalcommits.org):** `<type>(<scope>): <description>` — subject < 72 chars, imperative, no period. Types: `feat`·`fix`·`docs`·`refactor`·`perf`·`test`·`chore`·`build`·`ci`·`style`. Body = WHY. Footer = `BREAKING CHANGE:` when applicable.
- **De-personalization (mandatory):** never name people in commit/CHANGELOG narrative — reference by PR number (`#4`), describe *what* changed, not *who* found it.
- **Never commit secrets.** Ship `.template` files and `.gitignore` the reals. If push-protection fires, reset and re-commit clean — never bypass.
- Commit/push only when the operator asks. If on the default branch, branch first.

## Ship-time truth-flip

Every tracked item has exactly one **truth surface** that answers "is this done?" — usually its project note. The session that ships an item updates that surface **in the same session**, not later. Derived surfaces (daily notes, dashboards, indexes) only *reference* the truth surface — they never accumulate competing status.

## Execution discipline

- **Match the literal signal.** Follow explicit instructions, declared preferences, and literal text as written. Don't override based on inference about what the operator "really" wants. If you feel the urge to soften, defer, or stub-instead-of-finish, re-read their actual words.
- **Deliverables land standalone.** Put any requested output in its own message or a file — never as text wedged between tool calls in the same turn (it can silently drop on some surfaces).
- **File paths in messages are absolute**, with `path:line` for a specific line, so the operator can cmd/ctrl-click to open them (a relative path is dead text; not every link handler expands `~`). Keep paths relative inside shell commands, commit messages, and files you write for someone else — and use `[[wiki-links]]` inside vault notes.
- **State intent before significant initiative.** For non-routine action: *"I intend to [action] because [reasoning]. Confirm or redirect."* Not for routine reads/edits or explicit requests.
- **Time estimates = actual AI execution time**, never human-equivalent effort. An agent reads in milliseconds and writes in single calls — give the real minutes, no "45 min of work" framing.

## Comprehension debt

The operator must be able to defend, debug, or decide on what ships under their name. When an agent ships work the operator didn't author, **surface the surface area** (what shipped) and offer to walk them through it — don't wave it through. Keep autonomous loops on machine-checkable changes; architecture and judgment calls stay operator-in-the-chair.

---

*Full contract, Claude-specific infrastructure, and the ten principles of intelligence collaboration behind these rules: [`CLAUDE.md`](./CLAUDE.md).*
