# CHEATSHEET.md — How to Operate

> Quick-reference for new AIOS users. Scan to find what you need; click through to the deeper doc when you want context.
>
> **This is a subset, on purpose.** It carries the commands you reach for by rhythm — daily, weekly, when something happens. [TOOLS.md](./TOOLS.md) is the complete menu, and it lists every command, agent, skill and connector with its arguments. If something is missing here, look there before assuming it does not exist.
>
> **First-week instinct:** don't try to use every command on day 1. Master §1 + §2 (launch + daily loop). Add the rest when you feel the need for it.
>
> **If you use the AIOS App, most of this is optional.** The App runs these commands for you — this file is what you reach for when you want to know *what it just did*, or to do something the buttons don't cover yet. Nothing here is required reading to operate your AIOS.

---

## §0 — If you're using the AIOS App

Everything below this section is a terminal command. The App runs those commands for you, so this
is the translation: what each control actually does, and which ritual it is underneath.

> **Deliberately concept-level, not a button tour.** The App ships on its own release cycle, so a
> table of labels here would go stale silently — the failure this file has already had once. What
> is stable is what the surfaces *are*; where a label is load-bearing it is named, and for anything
> version-specific the App's own README is the source.

### The three ways to start something

| Control | What it is | Underneath |
|---|---|---|
| **Ask AIOS anything you need** | A one-off question. Nothing is named, nothing joins Running. | A scratch session — the fastest path when you just want an answer. |
| **Launch assistant** | Your **primary session**, named after the assistant you chose during setup. | Exactly the shell shorthand §1 describes — this is the button version of typing that one word. |
| **Resume** | Reattaches to a session that already exists rather than starting a second one. | `claude --resume` / `spawn <name>` on an existing name. |

### Sessions vs terminals — the distinction that matters most

A **session** is a named Claude session. It appears in **Running**, it can be resumed later, it can
be closed with `/close-session`, and its name is what lets the framework match an agent profile and
route its capture to the right project. A **terminal** is just a shell — useful, but anonymous:
nothing tracks it, nothing resumes it, and closing it captures nothing.

If you want the work to be remembered, start a **session**. Reach for a terminal when you want to
run a command and watch it, not when you want to do work worth keeping.

### Reading the panel

Top to bottom, each card answers one question:

- **Daily** — the three rituals: *Plan my day* (`/today`), *Close session* (`/close-session`),
  *Close the day* (`/close-day`). These are the same commands as §2, same behaviour.
- **Calendar** — your month, with today marked. **A mark on a day means a daily note exists for
  it** — that is how you tell `/today` actually wrote one, without opening the file. The note itself
  lands in `vault/01 - calendar/{YYYY-MM}/{YYYY-MM-DD}.md`; click through to read it.
- **Quick** — frequent tasks, agents, skills and commands, each with a count. Nothing here is
  App-only; it is a picker over what §3–§6 list.
- **Running** — every live session and terminal. This is the registry, so it is also the honest
  answer to *"is that still going?"*
- **Health** — the ongoing twin of Setup. Every row that can fail carries its own fix.
- **Connectors** — the services your AIOS can reach, and the state of each. Anything that needs
  more than a click opens a guided session rather than handing you a document. From a terminal the
  same job is `/aios:mcps-setup`, which walks tokens, registration and verification one service at
  a time.

### What you still do in a terminal

Almost nothing, day to day. The cases that remain: running a command the buttons do not cover yet,
and reading output while it happens. Both are one click — the App opens a terminal you can watch,
which is why every fix it runs is visible rather than silent.

---

## §1 — Start here (launching a session)

**First: which door did you come through?** This section is written for a terminal, and the AIOS
now has two front doors. Take the row that matches you and skip the rest — reading a table of shell
commands is not a prerequisite for using this.

| If you use… | Launching a session is… | The rest of §1 |
|---|---|---|
| **The AIOS App** | the **Launch assistant** button, or any card in the pulse | Optional. The App runs these commands for you, in a terminal you can watch. Come back when you want a *second* named worker at the same time. |
| **A code editor + AIOS Glass** | the panel's session controls | Same — the panel wraps the same commands. |
| **A terminal** | the table below | All of it applies. |

> **Why say this at all.** Every row below is a shell command, and the operator most likely to open
> this file is the one who just installed the App and has never typed `cd`. Opening their
> quick-reference with `cd ~/aios && claude` teaches them the AIOS is a terminal product that
> happens to have an app — which is backwards, and is the same friction `AI-122` removed from the
> setup flow. The commands are not going anywhere; they are just no longer the first thing.

How to launch, name, and resume sessions **from a terminal**.

| You want to... | Command | Notes |
|---|---|---|
| Launch a session in the vault | `cd ~/aios && claude` | Loads CLAUDE.md + USER.md + observed context |
| Open a named worker session | `spawn <name> "<task>"` | New terminal tab/window, named identity, task pre-loaded |
| Open a named session, no task | `spawn <name>` | Sends `"Start session."` as the first prompt |
| Spawn an ad-hoc worker (no name) | `spawn` | Generates a memorable adj-animal handle (e.g. `amber-otter`) + prints a tip surfacing available specific agents. Great when you want a fresh session and don't need a meaningful name yet. |
| Resume a named worker | `spawn <name>` again | Wrapper detects existing session, reattaches |
| Resume any past session | `claude --resume` | Pick from the list of recent sessions |
| Kill a spawned worker cleanly | `spawn-kill <name>` | Atomic process-group kill + closes the Terminal window (macOS). Avoids orphan Claude processes + Terminal's "terminate?" modal. Doesn't affect IDE-integrated terminals (the IDE manages those). |
| Override model for spawned workers | `export CLAUDE_MODEL='claude-sonnet-4-6'` (or any model) in `~/.zshrc` | Wrapper **defaults to `claude-opus-5[1m]` (1M context Opus)** since AIOS leans on context engineering. Override for cheaper Sonnet sessions, 3P providers, or non-1M Opus. Note: `/config` and `/model` are session-scoped — they DON'T propagate to spawned children. The wrapper's `--model` flag does. |
| Install the spawn wrapper | `bash ~/aios/hooks/claude-identity/install-wrappers.sh` | One-time setup. Idempotent — safe to re-run. Installs `spawn`, `spawn-kill`, `_claude_with_respawn`, plus a shell function named after your primary session (read from USER.md → ## Identity; falls back to `primary` if no identity declared yet — re-run after editing USER.md to rename). |
| Mount your company context | `/aios:company --mount {url}` | One-time per company. Pulls venture context (positioning, gtm, pricing, primitives, etc.) into `vault/00 - notes/context/ventures/{name}/` + registers in `USER.md → ## Companies (mounted)`. Works for a company you own OR one you collaborate on. |
| Create a NEW company context repo | `/aios:company --create` | Interview-driven scaffold from [`The-AIOS/company-template`](https://github.com/The-AIOS/company-template). Lands at `{org}/{company}-context`. Includes 10 canonical context files + 6 optional infra folders (agents/plugins/hooks/MCPs/skills/templates) for company-distributed shipment. |
| Refresh mounted company context | `/aios:company --sync {name}` (or `--sync-all`) | Pulls remote → vault for the named company. Run when contributors push updates. |
| Scaffold a shared **collaboration space** | `/aios:collaborate` | Substrate-pluggable shared OS with a stable group of collaborators (Drive for non-coders, GitHub for code-adjacent, local for testing). Creates `collaborate.md` (protocol) + `README.md` + first project + a router note in your vault. Subcommands: `--add-project`, `--status`, `--dry-run`. |
| Add a project to an existing collab space | `/aios:collaborate --add-project` | Adds a new project under an existing collaboration space (same substrate). |
| Run Claude without spawn | `claude --remote-control --name <name>` | Bypasses wrapper; not recommended |

**Why use `spawn` over raw `claude`:** the wrapper sets `$CLAUDE_AGENT_NAME` so CLAUDE.md can match an agent profile (`agents/<name>.md`), greet you in character, and route close-session reports back to the right project. Raw `claude` works but loses the identity-aware behavior.

**Where session transcripts live:** `~/.claude/projects/<vault-path-slug>/*.jsonl` — one file per session. Useful when you want to grep across past conversations.

See: [SETUP.md](./SETUP.md) for first-machine install · [CLAUDE.md](./CLAUDE.md) → § Spawning Sessions for the full wrapper spec.

---

## §2 — The Daily Loop

The minimum every-day rhythm. **`/today` is the orchestrator** — running it closes the compound loop even if you forgot the steps in between.

| Command | When | What it does |
|---|---|---|
| **`/today`** | Every morning | **Required.** Loads context + pulls calendar/tasks/Slack + writes today's plan. **Checks the previous daily note for `## Close of Day`** — if missing, auto-invokes `/close-day` first. **Checks aios-update freshness** — surfaces a callout if the shared template/team repo has new infra. Commits + pushes the plan. |
| **`/close-session`** | Whenever a piece of work reaches a stopping point — several times a day is normal | Captures what that session shipped, learned and left open, and commits the vault. **This is the ritual that feeds `/close-day`**: without it the evening capture is reconstructing your day from the notes instead of reading it. In the App it is the **Close session** button on the Daily card. |
| `/close-day` | Every evening, OR auto-invoked by `/today` next morning | Captures Close of Day (verdict, shipped, decisions, carries, observed patterns) and routes signals to observed-context + project notes. Skip-tolerant — `/today` catches missing close-day. |
| `/aios:update` | When `/today` surfaces a BEHIND callout | Pulls fresh infra from the shared template/team repo. On-demand, not scheduled. |

**Why this is the compound loop, mechanically:** yesterday's close-day routes signals to the right files (growth.md, session-insights.md, project notes, antifragile.md). Today's `/today` reads those refreshed files. The system gets smarter because the routing happened — observed-context grew, patterns confirmed, project state advanced. **You only need to remember `/today`** — it's the heartbeat that keeps everything else honest. Forget `/close-day`? `/today` catches it. Forget `/aios:update`? `/today` reminds you.

**At session end, run `/close-session`** — it captures the session *and* commits and pushes the vault, which is why it is in the table above rather than described here as a chore. This paragraph used to say "tell Claude to commit and push", which is the command's own job written out by hand: the table listed `/today`, `/close-day` and `/aios:update`, skipped the one ritual that runs several times a day, and then explained how to do it manually. If you are mid-session and just want the push, saying "commit and push" still works — the AI handles the syntax, you name the intent. **The vault is only as portable and safe as its last push.**

See: [CLAUDE.md](./CLAUDE.md) → § II. Rituals · `plugins/aios/commands/today.md` · `plugins/aios/commands/close-session.md` · `plugins/aios/commands/close-day.md` · `plugins/aios/commands/update.md`

---

## §2.5 — Beyond daily (the wider rhythm)

The daily loop is the heartbeat, but it is not the whole cadence — and this file used to stop at
daily, which left `7plan` and `compact` with no home and no signal that a longer rhythm exists.

| Cadence | Command | What it is for |
|---|---|---|
| **Weekly** | `/aios:7plan` | The week's strategy — what actually matters over the next seven days, not a list of tasks. |
| **Weekly** | `/aios:drift` | The avoidance detector: what you keep carrying without doing, and why. |
| **Weekly** | `/aios:weekly-learnings` | Consolidates the week's captures into something you would actually re-read. |
| **Bi-weekly** | `/aios:graduate` | Promotes daily ideas that survived into permanent notes. |
| **Bi-weekly** | `/aios:emerge` | Surfaces patterns you have not named yet — the ones implied across notes rather than written down. |
| **Monthly** | `/aios:compact` | Digests and archives the previous month, and bounds the files that grow without limit. |

**None of these are required, and skipping one costs you nothing that day.** They are the difference
between a vault that stores and a vault that compounds — which is why they are worth knowing exist,
even in the weeks you do not run them.

**Want the full tour of what you have?** The setup interview offers it at the end and promises it
stays available — that promise is real: say **"show me the full tour"** in any session, or press
**Show me the full tour** in the App when setup is complete. Either one runs
`/aios:cold-start-interview`, which detects that your Core is already done and runs the depth half
only — your identity and context are not re-asked.

See: [CLAUDE.md](./CLAUDE.md) → § V. Vault Commands for the full cadence · [TOOLS.md](./TOOLS.md) for every command with its arguments.

---

## §3 — The Capture Loops (when something happens)

Where does X go when you notice it? One row per signal type.

| What just happened | Where it goes | How |
|---|---|---|
| **Idea** (worth keeping but not actioning) | Daily note Parking lot → eventually `vault/00 - notes/ideas/` | Add to today's Parking lot. Run `/graduate` periodically to promote the best ones to permanent notes. |
| **Reflection** (longer thought, deserves its own page) | `vault/00 - notes/reflections/<slug>.md` | Just write it. Use `/ideas` if you want Claude to suggest framing/structure first. |
| **Growth signal** (you avoided something, or you shifted) | `vault/00 - notes/context/observed/growth.md` | Don't write directly. Mention it in conversation; `/close-day` or session-end ritual routes it. |
| **Decision** (a real choice with reasoning) | Today's daily note Decision Journal | Add during `/close-day` if it's substantial. Major decisions get reasoning + confidence + revisit-date. |
| **Pattern correction** (Claude did something wrong, fix forever) | `vault/00 - notes/context/observed/antifragile.md` | The moment correction happens — don't wait for end of session. Adds a numbered entry. |
| **Insight to test** (might be true, not sure yet) | `vault/00 - notes/context/observed/session-insights.md` → Emerging | Two-stage buffer: Emerging → Reinforced → routed to target file. CLAUDE.md § III explains the lifecycle. |

**Rule of thumb:** if you're unsure where it goes, write it in the daily note and let `/close-day` route it. The daily note is the safest fallback.

**Where do files live? (the placement router, human version).** The vault's numbered folders are semantic zones — place by *the question you'll ask later*, not by where the file came from: machine/script output → `00/logs/` (only that) · raw inputs you didn't author (PDFs, transcripts) → `02 - assets/` · anything that ships to an audience (plus its HTML source) → `03 - export/` · what-happened-today → `01 - calendar/` · thinking you'll re-read → `00/reflections/` · who-you-are → `00/context/`. When 3+ files of one species pile up loose, give them a semantic subfolder (noun-named — dates go in filenames). Custom rooms (a cookbook, an archive) are welcome under `00 - notes/` — just give them an `_index.md`. Full rules: CLAUDE.md § IV → File Placement Router; `/housekeeping` audits drift.

See: [CLAUDE.md](./CLAUDE.md) → § Observed Context Rules · `plugins/aios/commands/graduate.md` · `plugins/aios/commands/ideas.md`

---

## §4 — The Export Loops (when you need a shareable artifact)

Generate the shareable thing.

| You want... | Command | Output location |
|---|---|---|
| **Weekly summary** (the week's narrative + PDF) | `/weekly-learnings` | `vault/01 - calendar/<YYYY-MM>/<YYYY>-W<NN>-summary.md` + `vault/03 - export/reports/weekly/Week<NN>-AI-OS.{html,pdf}` |
| **Monthly learnings** (insights distilled across the period) | `/learned` | `vault/01 - calendar/<YYYY-MM>/learned-<period>.md` + optional branded PDF in `vault/03 - export/reports/learned/` |
| **Role activity report** (for stakeholders) | `/role-report` | `vault/03 - export/reports/role/<period>-role-report.{html,pdf}` |

**All three commands accept a period argument** — a named period (`month`, `Q1 2026`, `March`, `last 3 months`, `this week`) or an explicit date range (`2026-03-01 to 2026-03-28`). Run without arguments and each picks a sensible default + asks for confirmation. `/weekly-learnings` additionally auto-fires monthly/quarterly/semester/year reports on the last Friday of each period — no argument needed.

See: [TOOLS.md](./TOOLS.md) · `plugins/aios/commands/weekly-learnings.md` · `plugins/aios/commands/learned.md`

---

## §5 — Make it yours (personalization)

The substrate is shared; the personalization is yours.

| Surface | What it controls | Edit it when... |
|---|---|---|
| **`USER.md`** → `## Identity` | Named sessions and their greeting styles | You want a different greeting tone, or you add a second machine |
| **`USER.md`** → `## Sources` | Where Claude pulls data (Google accounts, Slack workspace, Growth routines) | First-week setup; revisit when sources change |
| **`USER.md`** → `## Command personalizations` → `### /<command>` | Override any command's default behavior — adds rules, changes section order, adapts logic | A command does almost-what-you-want, except for one thing |
| **`INTENT.md`** → `## Autonomy levels` | Per-domain trust: `autonomous` / `draft` / `ask` | When you notice the AI is ready for more trust (or you want to pull back) |
| **`vault/00 - notes/context/declared/about_me.md`** | Who you are, what you build, what you don't negotiate | First-week priority. Even 5 bullets transforms output quality. |
| **`vault/00 - notes/context/declared/working_style.md`** | How you think, decide, prefer to work | Same — first week. Compound returns weekly. |

**Starter override pattern:** open `USER.md`, find `### /<command>`, add a rule under a bold sub-heading. Claude reads it before every run of that command. Common first overrides: customize `/today` Evening — Grow routines, add growth routines under Sources, set up Slack triage rules in `### /close-day`.

**Promotion path:** if a rule in your USER.md proves useful enough that it should be default for everyone, `/housekeeping` Bucket 13 surfaces it as a "promotion candidate" — propose moving it from `USER.md` → `plugins/aios/commands/<name>.md` for everyone. That's the upstream feedback loop.

### Don't touch — these get overwritten by `/aios:update`

The shared template ships infra that's the same for every user. Editing these locally means your edits vanish on the next `/aios:update` pull.

**Touch-not (shared template):**
- Root-level docs: `README.md`, `START-HERE.md`, `SETUP.md`, `TOOLS.md`, `CLAUDE.md`, `CHEATSHEET.md`, `INTENT.md` template
- `plugins/aios/commands/` — the bundled aios plugin's slash commands
- `.claude-plugin/marketplace.json` — marketplace manifest
- `plugins/aios/.claude-plugin/plugin.json` — aios plugin manifest
- `hooks/` — pipeline scripts + identity wrappers
- `mcps/` — bundled MCP servers
- `skills/` — reusable skill capabilities
- `templates/` — file templates
- `plugins/<other-bundled>/` — any other bundled plugins (currently just `aios`)

**Yours to edit (personal layer):**
- `USER.md` (never synced — your personalization)
- `INTENT.md` (your trust contract — the template ships defaults, your edits stay)
- `vault/00 - notes/context/declared/*` — `about_me.md`, `working_style.md`, `personal_voice.md` (first-week priority)
- `vault/00 - notes/context/observed/*` — Claude writes these; you read + occasionally correct
- `vault/00 - notes/projects/*` — your projects
- `vault/01 - calendar/*` — daily notes, weekly plans
- `agents/custom/*` — your personal agents (override shared agents of the same name)
- `plugins/custom/<your-plugin>/` — your own Claude Code plugins (with their own commands, agents, skills)
- `vault/00 - notes/ideas/`, `vault/00 - notes/reflections/`, `vault/03 - export/writing/` — your content

**If you want to upstream a change** to a touch-not file (improvement worth sharing with everyone), the path is: prototype it in USER.md → let it stabilize 60+ days → `/housekeeping` Bucket 13 surfaces it as a promotion candidate → propose it for `plugins/aios/commands/<name>.md` or the relevant shared file. That's how end-user discoveries flow back into the template.

See: [CLAUDE.md](./CLAUDE.md) → § I. Operating Principles · [INTENT.md](./INTENT.md) template

---

## §5.5 — Tracker map (where each sync command pulls from)

Two sync commands, two tracker shapes. Knowing this prevents the "where is this command looking?" confusion.

| Command | Pulls FROM | Source of truth (URL) | Tracker file(s) | What it syncs |
|---|---|---|---|---|
| `/aios:update` | `The-AIOS/aios` (framework canonical) | `.aios-update` at repo root → `repo=` field | **One file**: `.aios-update` (with `repo=`, `hash=`, `synced=`) | Bundled framework infra — commands, agents, skills, hooks, MCPs, templates, root docs |
| `/aios:company` | Per-company venture-context repos (one per mounted company) | `USER.md` → `## Companies (mounted)` table → `Source` column per row | **N files** — one `.{company}-sync` tracker INSIDE each venture folder (e.g., `vault/00 - notes/context/ventures/acme-co/.acme-co-sync`) | Per-company venture-context content (positioning, primitives, gtm, pricing) + optional company-distributed infra (`agents/{company}/`, `plugins/{company}/`, etc.) |

**Why the asymmetry:**
- The framework is **universal** — one upstream for everyone. Single tracker, single repo.
- Companies are **operator-specific** — each operator mounts 0, 1, or many. Per-company trackers + USER.md table to enumerate them.

**Read order when troubleshooting "why isn't this syncing":**
1. For framework updates: cat `.aios-update` → check `repo=` matches expected; check `hash=` vs `git ls-remote {repo} HEAD`
2. For company updates: read `USER.md` → `## Companies (mounted)` → for the company in question, find its `Venture folder` → cat the `.{company}-sync` file in there

---

## §6 — Multi-account quota management

Anthropic rate limits are per-account (5h sliding window + 7d budget). Multiple accounts multiply throughput. Two switching modes — pick the one that fits the situation.

### Soft switch (when you're at the keyboard)

```bash
claude-switch <email>     # jump directly to a specific account
claude-switch             # rotate to next account in USER.md list
```

You decide *when* the switch happens. No mid-conversation surprise. Use this when:
- You're starting a long session and want to commit to one account
- A quota warning fired and you want to control the cutover before it forces itself
- You want to verify the switch landed cleanly (the wrapper confirms post-switch)

### Auto-switch (when you're away)

The watcher hook (`hooks/claude-identity/`) monitors quota usage. When the active account crosses ~95%, it auto-rotates to the next account in the USER.md list. Sessions resume on the new account; long-running work continues uninterrupted.

Beautiful when:
- An overnight agent session is running and you're asleep
- A long task is mid-execution and you can't manually intervene

Anxiety-inducing when:
- You're actively typing and the switch happens mid-thought

**Rule of thumb:** **soft-switch when you're at the keyboard, auto-switch when you're away.** Run a soft-switch at the start of an active session to lock in a known account; let auto-switch be the safety net for unattended work.

### Setup

```yaml
# In USER.md
## Anthropic accounts
1. `primary@example.com` — main account
2. `overflow@example.com` — overflow account
3. `agent@example.com` — overnight/agent account
```

Rotation order = list order. `claude-switch` (no args) walks the list. `claude-switch <email>` jumps to a specific entry.

**Important:** no `claude.ai`-hosted MCPs on any account — they break on switch. Use bundled `mcps/*` only. See [CLAUDE.md](./CLAUDE.md) → § MCP Policy.

---

## When you get stuck

| Symptom | Try this first |
|---|---|
| Claude doesn't know who you are | Fill `vault/00 - notes/context/declared/about_me.md` + `working_style.md` |
| Command does almost-what-I-want | Add an override in `USER.md` → `### /<command>` |
| Session feels slow / context-bloated | Start a fresh session — pre-loaded context will pick up the latest snapshots |
| Quota warning while typing | `claude-switch <next-account-email>` immediately, before auto-switch fires |
| A command edit isn't taking effect | The runtime cache might be stale — see `/housekeeping` Bucket 11 (plugin cache verification) |
| Lost track of where something lives | This file is the index. `TOOLS.md` is the deeper catalog. |
| Unsure which model should do a task | See [`MODEL-ROUTING.md`](./MODEL-ROUTING.md) — the four `--tier` rungs, the non-Claude boundary, judge independence |
| Wondering how contained you actually are | [`FORTRESS.md`](./FORTRESS.md) § The containment ladder — six rungs; ask a session *"which rung am I on?"*. Rungs 1-2 are free and carry most of the value |
| Want 24/7 agents on a Mac mini | See [`FORTRESS.md`](./FORTRESS.md) — two-machine architecture, network isolation, SSH hardening, recovery |
| Truly lost / fresh-clone confused | `/agent onboarding-aios` — Claude wears the orientation hat, walks you through the full doc map |

---

*This file is the operating index. The deeper docs (`README.md`, `SETUP.md`, `START-HERE.md`, `CLAUDE.md`, `TOOLS.md`, `FORTRESS.md`, `MODEL-ROUTING.md`, `INTENT.md`, `USER.md`) carry the substance — and the full **[Operating Manual](https://www.the-aios.com/#manual)** (www.the-aios.com/#manual) gathers the whole design language + behavioral contract into one readable document (online or PDF). Use this file to find the right surface fast. When in doubt, spawn `onboarding-aios` — it knows the whole map.*
