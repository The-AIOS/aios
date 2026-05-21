# START HERE

Welcome to your AI-OS. This is your personal operating system for thinking with Claude — a vault that gets smarter about *you* the more you use it. It's also team-shared infrastructure: the commands, MCPs, and hooks come from a central team repo, but your personal context stays in your own private fork.

> **TL;DR — what you do today:**
> 1. Run `SETUP.md` (Claude does the heavy lifting — including forking to your private repo)
> 2. Fill in 4 files about yourself (`about_me`, `personal_voice`, `working_style`, `INTENT.md`)
> 3. Run `/aios:today` to see your first daily plan

If you've never used this kind of system before, that's fine — Claude walks you through every step. You don't need to read the docs first.

---

## You just cloned AIOS — what now?

You're holding the framework. This file is your post-clone walkthrough. (For the *why* of AIOS — philosophy, three progressive stages, agentic culture, what compounds — see [README.md](./README.md).)

**Three steps to a working personalized vault:**

1. Run `SETUP.md` (Claude-driven, ~10 min) — installs MCPs, configures your private vault, wires up tools
2. Run `/aios:cold-start-interview` (~20 min) — fills in your identity, declared context, INTENT.md trust contract, agent bundle preferences, MCP auth
3. Run `/aios:today` (~5 min) — your first daily plan. The rhythm starts here.

Steps 1-2 happen once. Step 3 becomes your morning ritual.

---

## The three-repo model

The AIOS uses three layers of repos, each with a different concern:

| Repo | What it holds | You write to it? |
|---|---|---|
| **Your personal vault** (`origin` — private) | Declared context, observed context, daily notes, project notes — everything personal | **Yes** — every session ends with `git push` |
| **The AIOS framework** (`The-AIOS/aios` — public) | Shared infrastructure (commands, hooks, MCPs, plugins, skills, agent bundles, templates) | **No** — pulls only via `/aios:update`. Updates from upstream flow to everyone on AIOS. |
| **Company venture-context repo(s)** (`{org}/venture-context` — per company you mount) | Company-specific shared knowledge (about, positioning, GTM, pricing, design.md, brand.md, CLAUDE.md operating manual, primitives, culture) | Depends on access — write permission lives in GitHub/Drive. From the AIOS side it's **pulled only** via `/company --sync`. |

**Multi-company support:** you can mount **0, 1, or many** companies. An independent consultant might mount their own ChuyCepeda venture AND a client's company. A Sovra employee mounts just Sovra. A non-business operator mounts none. The model adapts.

**This separation is intentional:**
- Your personal observations never leak upstream
- Framework improvements flow to everyone on AIOS via `/aios:update`
- Each mounted company stays in its own canonical home; your vault is the mirror

SETUP + `/cold-start-interview` wire all three layers — you don't have to think about it.

---

## The two-step setup

### Step 1 — Run `SETUP.md` (Claude-driven)

Open any terminal. Type:

```
cd ~/obsidian && claude
```

Then in Claude:

```
Set up my AI-OS from https://github.com/The-AIOS/aios
```

Claude reads `SETUP.md` and handles the rest:
- Clones the AIOS framework to `~/obsidian` (if you haven't yet)
- Installs MCPs, plugins, and CLI tools (auto-detects what's already installed)
- Creates **your** private GitHub repo for personal content and switches `origin` to it
- Tracks the AIOS framework via `.vault-update` so `/aios:update` can pull future updates
- Configures `USER.md` skeleton — `/cold-start-interview` fills it in next
- Pushes your personal vault to your new private remote

You confirm decisions. Claude executes.

**~10 minutes. You drink coffee. The system installs.**

### Step 2 — Run `/cold-start-interview` (15-25 minutes)

Once SETUP completes, the system has the *infrastructure*. Now it needs *you*. Open a fresh Claude session in `~/obsidian` and run:

```
/aios:cold-start-interview
```

Claude walks you through (in this order):

| Section | What it captures | Time |
|---|---|---|
| Identity | Your named sessions, primary Anthropic account, sources (Calendar/Tasks/Slack/Gmail) | 3 min |
| Declared context | 4 files in `vault/00 - notes/context/declared/`: about_me, personal_voice, working_style, about_business | 8 min |
| INTENT.md | Trust contract — autonomy levels, just cause, focus priorities | 5 min |
| Agent bundles | Which of the 6 bundles apply to your work (sales/strategy/finance-legal/engineering/communication/personal) | 1 min |
| Mount a company (optional) | If you have a venture-context repo, mount it via `/company --create` or `/company --mount` | 5 min |
| MCP setup | Google Workspace, Slack, GitHub, Atlassian, NotebookLM, Stitch (if UI builder), Playwright, Nano Banana, PDF Generator | 5-10 min |
| Optional Anthropic plugins | financial-services, claude-for-legal, knowledge-work-plugins (based on your role) | 1 min |
| First `/today` | The daily ritual that anchors the system | 1 min |

**Tip:** Don't aim for perfect. Aim for enough that Claude can start being useful tomorrow. You'll refine these files over weeks as Claude observes how you actually work.

### Step 3 — Mount your company (or skip)

If you have a venture-context repo (your own company, a client, an advisory engagement), `/cold-start-interview` (Step 2) mounts it via `/company`. If you skipped — or want to add more companies later — run:

```
/aios:company
```

Mount with `--mount {url}` (using a URL teammate shared with you), or create fresh with `--create` (interview-driven scaffold from [The-AIOS/company-template](https://github.com/The-AIOS/company-template)).

---

## Day 1 — Your first daily plan

Once context is set up, run:

```
/aios:today
```

Claude reads:
- Your declared context (you)
- Your calendar (Google)
- Your open tasks (Google Tasks)
- Your unread Slack
- Your projects in `vault/00 - notes/projects/`

And writes a one-page plan for the day to `vault/01 - calendar/{YYYY-MM}/{date}.md`.

That's the rhythm. Every morning: `/today`. Every evening: `/close-day`. Friday: `/weekly-learnings`.

---

## What grows over time

The vault starts thin and is designed to compound:

- **Week 1**: Claude knows what you've told it. Plans are functional but generic.
- **Week 2**: `vault/00 - notes/context/observed/` starts filling in. Claude notices patterns.
- **Month 1**: `/drift` surfaces what you're avoiding. `/emerge` surfaces ideas implied by your notes but never written.
- **Month 3**: Daily plans feel personalized. Claude knows your blindspots and energy patterns.
- **Month 6**: The system has a real read on who you are. `/ghost` can write in your voice. `/challenge` can steel-man your current thinking.
- **Year 1**: A record of who you were becoming.

This isn't a productivity app. It's a thinking partner with persistence.

---

## Staying in sync

Two commands keep your vault current with upstream sources:

| Command | When | What it does |
|---|---|---|
| `/aios:update` | When `CHANGELOG.md` (in The-AIOS/aios) shows new entries you haven't applied | Pulls AIOS framework updates (commands, MCPs, hooks, templates, agents, skills) from The-AIOS/aios. Surgical — won't touch your personal content. |
| `/company --sync {name}` | When a mounted company's venture-context updates (positioning, GTM, pricing, brand) | Pulls updates from that company's repo/folder. Approve the diff, then you have the latest. Use `--sync-all` to refresh every mounted company at once. |

Run them when prompted (or weekly as part of `/7plan`). Both are safe — they only read from upstream, never push.

If you customize how a command behaves, put it in `USER.md` → `## Command personalizations`. That section survives `/aios:update`. Don't edit command files directly — they get overwritten on the next sync.

---

## (Optional) Quota autopilot — multi-account rotation

If you run two or more Anthropic accounts to manage 5h/7d rate limits, the bundled `hooks/claude-identity/` autopilot rotates between them automatically and respawns active Claude sessions on the new account. macOS-only (uses Keychain + launchd). Single-account setup? Skip — the scripts stay dormant.

To set up: in any Claude session, say *"set up the quota autopilot"*. Claude reads `hooks/claude-identity/README.md` and walks you through 7 steps.

---

## When you get stuck

- **For setup issues** — re-read `SETUP.md` or ask Claude `"What went wrong with my setup?"`
- **For vault structure questions** — read `CLAUDE.md` (Claude reads this every session — you can too)
- **For command behavior** — read `plugins/aios/commands/{command-name}.md` for any command
- **For day-to-day operating** — `CHEATSHEET.md` is the scannable index for launching sessions, the daily loop, capture/export shortcuts, personalization, multi-account quota management
- **For deep system understanding** — `TOOLS.md` is the human-readable map of every tool, command, agent, and MCP

If a command isn't doing what you expect, the answer is almost always: **Claude can read this file, you can too**.

---

## What's next after Day 1

Once `/today` is running smoothly, here's the order things tend to come online:

1. **Daily rhythm** — `/today` morning, `/close-day` evening (week 1)
2. **Weekly rhythm** — `/7plan` Monday, `/weekly-learnings` Friday (week 2)
3. **Mount your company(ies)** — `/company` to mount any venture-context repos relevant to your work (week 1)
4. **First personal venture** (if you have one outside any mounted company) — copy `templates/about_venture-template.md` into `vault/00 - notes/context/ventures/{your-venture-name}/about_venture.md`
5. **First project** — copy `templates/project-template.md` into `vault/00 - notes/projects/{project-name}.md` (week 2-3)
6. **Observed context fills in** — `session-insights.md`, `patterns.md`, `growth.md` (organic, weeks 2-4)
7. **First strategic command** — `/drift` (Wednesday), `/emerge` (mid-month), `/ideas` (when curious) (month 1)
8. **First content** — `/ghost` to draft in your voice, `/learned` to distill insights into publish-ready content (month 2+)
9. **First collaboration** (when you're ready to share work with someone else) — `/collaborate` scaffolds a shared substrate-pluggable space (Drive for non-coder collaborators, GitHub for code-adjacent, local for testing) with a content-identical mirror in your vault. Same routing rituals, option-2 preservation on re-mount. The bridge from "AI-first individual" to "AI-first collaboration." (month 2+)
10. **Stay current** — `/aios:update` when CHANGELOG shows new entries (or when `/today` flags BEHIND in the morning)

Each command is its own readme. Read them when you're curious. Don't try to use them all at once.

---

## A note before you start

Don't try to use everything at once. The system is designed to reveal itself gradually:

- **Week 1:** master Step 3 (`/aios:today` + `/aios:close-day`). One ritual, twice a day. Everything else compounds from this.
- **Week 2-4:** add `/aios:7plan` Mondays, `/aios:drift` mid-week, `/aios:weekly-learnings` Fridays.
- **Month 2+:** discover the strategic commands (`/aios:emerge`, `/aios:connect`, `/aios:ghost`) as you need them.

For the philosophy underneath, see [README.md](./README.md). For the full command menu, see [TOOLS.md](./TOOLS.md). For specific command behavior, read the `.md` file for that command in `plugins/aios/commands/`.

Welcome.

---

*The AIOS framework lives at [The-AIOS/aios](https://github.com/The-AIOS/aios) (public template). Your personal vault is a private fork; your mounted companies live in their own repos. Last updated: 2026-05-21.*
