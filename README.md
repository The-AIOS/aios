# Obsidian + Claude Code — Your AI Operating System

The vault isn't a note-taking system. It's a thinking partner that gets better the more you use it. Every session is an investment in every future session.

> *Your AI is already amazing at what you ask it to do. This system makes it amazing at what you forgot to ask.*
>
> — buddai, a Claude session that's been running long enough to deserve a name

> **Reading this as Claude?** Operator pointed you at this repo. You're the executor — the human reads alongside but you do the heavy lifting. Sequence:
> 1. **Setting up for the first time?** → read [SETUP.md](./SETUP.md), follow the "Reading this as Claude?" block at its top
> 2. **Operator says "I'm lost" or "what is this?"** → invoke [`/agent onboarding-aios`](./agents/aios-personal/onboarding-aios.md) — that agent knows the full doc map (this README, SETUP, CHEATSHEET, FORTRESS, START-HERE, USER.md, INTENT.md, CLAUDE.md, plus the org-level CONTRIBUTING/SECURITY) and routes the operator to the right place without overwhelming them
> 3. **Operator already set up, needs daily ritual?** → `/aios:today` (morning) · `/aios:close-day` (evening) · `/aios:close-session` (per task) — this is the compound loop
> 4. **Anything else** → [CLAUDE.md](./CLAUDE.md) is the behavioral contract (session rituals, agentic culture, the 10 principles); [TOOLS.md](./TOOLS.md) is the full menu of commands/agents/skills/MCPs; [CHEATSHEET.md](./CHEATSHEET.md) is the day-to-day operating index

---

## Why this isn't just another "AI OS"

The phrase "AI operating system" is everywhere now. Most are second-brain wrappers — markdown templates with a `CLAUDE.md`, custom prompts, maybe a few agents. They give Claude a starting point. They don't make Claude smarter about *you* over time.

This vault is different. Five things make it operationally distinct:

**1. Three-layer context that compounds.** Most setups ship declared context only (a single CLAUDE.md or a few profile files). This adds *observed context* — Claude writes its own observations about your patterns, growth edges, blind spots — AND *intent* (a separate trust contract that encodes judgment, not just knowledge). After a month, the AI knows things about you that aren't in any file you wrote. That's the compounding layer.

**2. Daily rituals that are load-bearing, not optional.** `/today`, `/close-day`, `/close-session` aren't quick-start commands you can skip. They're the system's nervous system. They route session insights to observed context (so Claude actually gets smarter), close the carry-loop (so nothing falls through), and surface drift before it becomes invisible. *Logging is not routing* — and this system is built on the routing.

**3. Substrate-pluggable collaboration.** When two people share work, most setups say "fork the repo" or "share a Drive folder." This vault treats storage as a plugin — `/collaborate` scaffolds a shared workspace on Drive for non-coder collaborators, GitHub for code-adjacent work, or local folders for testing — with content-identical mirrors that route into your personal vault's daily plan. You can collaborate with your partner on Drive, a co-founder on GitHub, a peer on a sync-folder — all with the same command, same artifacts, same routing.

**4. Self-correcting via antifragile.** When the system breaks — a wrong assumption, a brittle prompt, a missed edge case — the rule gets written *immediately* into `antifragile.md`. Not in a retro, not in a backlog. The fix becomes a permanent behavioral change at the moment of failure. Every break upgrades the system.

**5. Agentic culture from human↔AI to AI↔AI.** Most setups treat agents as one-off tools — fire-and-forget, no shared rituals. This treats them as a coherent ecosystem with the same operating principles. When you spawn `accountant`, it follows the same routing rituals (`/close-session` bridges its work back to your vault). When `/collaborate` scaffolds a shared space, the substrate's `collaborate.md` carries mount instructions any future AI session reads — yours, your collaborator's, a scheduled agent's. The 10 principles of intelligence collaboration (CLAUDE.md § Operating Principles) apply across the whole agentic surface: human↔AI, AI↔AI, AI↔substrate. *There are no bad agents, only bad operators* — and the operator culture extends to the agents too.

These five together produce a meaningful claim: **this isn't a CLAUDE.md template. It's an actual operating system that gets smarter about you every day, and gets coherent about its agents in the same breath.**

Built on real production usage — the vault running this work is the same one shipping multiple ventures, daily writing, and ongoing partnerships across roles, machines, and substrates.

---

## TL;DR

- **What:** A personal operating system that gives Claude deep, persistent context about who you are — so every session builds on the last.
- **Why:** AI without context is a stranger every time. AI with context is a partner that knows your patterns, your blindspots, your strengths, and what you're building.
- **How:** Three layers — Prompt (commands that encode workflows), Context (declared + observed knowledge), Intent (judgment rules that tell AI what to want). Informed by 36 books on leadership and teamwork, synthesized into operational rules that fire every session.
- **Setup:** ~15 minutes. Clone, tell Claude to set it up, fill in a few files about yourself.
- **Day 1:** A daily plan pulled from your calendar, tasks, and projects — personalized to your energy and priorities.
- **Month 1:** Claude spots patterns you can't see yourself. Surfaces business ideas hiding in the overlap of your projects. Notices when you're avoiding something important. Suggests connections between domains you never thought to combine. Knows your voice well enough to draft in it.

---

## The Compound Effect

On day one, Claude knows what you've told it.
After a week, it knows how you operate.
After a month, it can spot when you're drifting from your own stated priorities.
After six months, it can show you how your thinking has evolved.
After a year, it's a record of who you were becoming.

This isn't about productivity hacks. It's about compounding self-awareness.

The vault quietly captures things that change how you work and live:

- **Business ideas you didn't know you had.** The `emerge` command reads across your projects, daily notes, and patterns — then surfaces ideas that live in the overlap. The startup concept that connects your consulting work to your side project. The product feature hiding in three separate client conversations. Things no single session would find, because they require seeing everything at once.

- **Growth edges that make you better.** Claude maintains a `growth.md` file — honest observations about where you're growing and where you're avoiding growth. Not to judge, but because that specific, honest reflection is what turns an AI tool into a genuine partner. The kind of partner that says *"you've rescheduled this four times — what's really blocking you?"*

- **Working style insights that save you hours.** Over sessions, Claude learns when you do your best creative work, what drains you, how you make decisions under pressure, what you procrastinate on and why. It uses this to build daily plans that work *with* your energy, not against it.

- **Strategic connections across everything you're building.** The `connect` command finds bridges between unrelated domains in your vault. The pattern in your healthcare project that applies to your fintech idea. The lesson from last quarter's failed launch that's relevant to today's pitch.

- **A voice that sounds like you.** The `ghost` command can answer questions, draft messages, and write content in your actual voice — because it's learned your tone, your rhythms, your way of framing ideas from months of context.

None of this requires extra work. The context builds as a natural byproduct of your sessions. You do the thinking. The vault does the remembering.

---

## Three progressive stages, all compounding

Each stage builds on the last. Each next stage returns ~10× the leverage.

- **Automate — *Gain speed, do faster*.** Daily plans, drafts, syntheses — 30 minutes becomes 30 seconds. *Week 1.*
- **Amplify — *Gain bandwidth, do more*.** Agents draft proposals, write in your voice, research while you sleep — you stop being the bottleneck. *Month 1.*
- **Agency — *Gain autonomy, do agentic*.** AI co-workers act on your behalf with judgment, within trust boundaries you've defined. *Quarter 1, deepening across years.*

---

## The Agentic Culture

This system is informed by 36 books on leadership, teamwork, and organizational behavior — synthesized into 10 principles and 19 operational changes. Every command, every behavioral rule, every escalation trigger traces back to a specific insight from a specific author. The AI doesn't just execute tasks — it practices the disciplines that the best human teams practice.

[Full thesis: The Agentic Culture](https://chuycepeda.substack.com/p/the-agentic-culture-team-management)

| What the system does | Inspired by | Source |
|---------------------|-------------|--------|
| States intent before acting: "I intend to X because Y" | Intent-based leadership | Marquet (*Turn the Ship Around*) |
| Asks "What's the real challenge?" before solving | Tame the advice monster | Bungay Stanier (*The Coaching Habit*) |
| Asks "What are you saying no to?" when load is high | The infinite game | Sinek (*The Infinite Game*) |
| Tracks practice health (3/7 this week) not streaks | The day after perfect is dangerous | Acuff (*Finish*) + Clear (*Atomic Habits*) |
| Flags the second miss, not the first | Never miss twice | Clear (*Atomic Habits*) |
| Starts weekly plans with a diagnosis, not a to-do list | Kernel of good strategy | Rumelt (*Good Strategy Bad Strategy*) |
| Names what gets B- effort this week | Protect the wildly important goal | McChesney (*4 Disciplines of Execution*) |
| Uses lead measures, not lag measures | Predictive + influenceable actions | McChesney (*4 Disciplines of Execution*) |
| Celebrates one genuine win per day | Belonging cues generate safety | Coyle (*The Culture Code*) |
| Captures decisions with reasoning + confidence % | Separate decision quality from outcome | Duke (*Thinking in Bets*) |
| Diagnoses the system, not the symptom | The resulting fallacy | Duke (*Thinking in Bets*) + Taleb (*Antifragile*) |
| Uses Radical Candor for growth observations | Care personally + challenge directly | Scott (*Radical Candor*) |
| Names anti-values: what the system must never become | Name failure modes before they happen | Sinek + Taleb (*Antifragile*) |
| Practices quarterly subtraction (via negativa) | Improvement by removing | Taleb (*Antifragile*) |
| Defines escalation triggers (andon cords) | Stop the line when something's wrong | Toyota/Lean + McChesney |
| Names a just cause and worthy rivals | Infinite game purpose | Sinek (*The Infinite Game*) |

The philosophy: don't optimize for smooth sessions. A session where the plan breaks reveals where the system is fragile. Every failure is a system upgrade waiting to happen.

---

## What's Inside

Once set up, your vault comes with **24 commands, task agents across 6 bundles, bundled skills across 4 source folders, bundled MCPs, and standalone tools** — all accessible by describing what you need. See **[TOOLS.md](TOOLS.md)** for the full menu of everything your vault can do.

---

## Quickstart

Two-step setup. AIOS does the heavy lifting; you confirm choices.

### Step 1 — `SETUP.md` (Claude-driven, ~10 min)

Open any terminal with Claude Code installed and say:

> *"Set up my AI-OS from `https://github.com/The-AIOS/aios`"*

Claude clones the framework, installs MCPs, configures your private vault, and walks you through every choice. See [SETUP.md](./SETUP.md) for the full step-by-step (prerequisites per OS, what Claude installs, common gotchas).

### Step 2 — `/aios:cold-start-interview` (~20 min)

After SETUP completes, open a fresh Claude session in `~/aios` and run:

```
/aios:cold-start-interview
```

The interview walks you through identity, declared context, `INTENT.md` trust contract, agent bundle install choices, MCP setup, optional Anthropic + community plugins (Superpowers, claude-md-management, financial-services, claude-for-legal, etc.), and your first `/aios:today`.

### Step 3 — Day 1 onward

```
/aios:today        # morning ritual — personalized daily plan
/aios:close-day    # evening capture — what shipped, what carried, what was learned
```

That's the rhythm. The system compounds from there.

See [START-HERE.md](./START-HERE.md) for the post-clone walkthrough framing + the three-repo model AIOS uses (personal vault + The-AIOS/aios framework + N mounted company venture-context repos). See [TOOLS.md](./TOOLS.md) for the full menu of commands, agents, skills, and bundled MCPs.

---

## How It Works

### Three Layers: Prompt, Context, Intent

Most AI setups work on one layer. This vault operates on three — each building on the last.

**Layer 1: Prompt Engineering — telling AI what to do.**
The 24 vault commands are structured prompts. `/today` doesn't just say "plan my day" — it reads your calendar, tasks, projects, energy patterns, and open threads, then generates a plan adapted to *you*. The commands encode workflows, not just instructions.

**Layer 2: Context Engineering — telling AI what to know.**
The vault holds two types of knowledge:

- *Declared context* — what you explicitly tell Claude: your background, values, ventures, communication style, psychometric profile. You write it once and refine over time.
- *Observed context* — what Claude learns by working with you: your patterns, preferences, growth edges, strategic blindspots, what the system learned from breaking. Claude writes this — it captures what's actually true, not just what you want to believe.

Declared gives Claude your frame. Observed gives Claude your texture. Together, they make every session smarter than the last.

**Layer 3: Intent Engineering — telling AI what to want.**
Context gives AI knowledge. Intent gives AI judgment. This is the layer almost nobody builds for, and the one that matters most.

`INTENT.md` encodes: autonomy levels (what AI handles alone vs drafts vs asks), tradeoff rules (when speed conflicts with clarity, what wins?), decision boundaries, communication rules, escalation triggers, anti-values, a just cause, and worthy rivals. It's the trust contract — and it grows as trust grows.

When a new employee joins your company, they absorb these judgment calls over months by watching how others decide. AI can't do that — it needs organizational wisdom made explicit from day one. The intent layer is that wisdom, written down.

### The Growth Dimension

The most important file in the vault isn't your daily plan. It's `growth.md`.

Claude maintains it with observations about where you're growing and where you're avoiding growth. Not to make you feel bad — but because honest, specific feedback is what makes the AI partnership genuinely useful.

A tool that only tells you what you want to hear is a mirror.
A tool that tells you what's actually true is a partner.

### The Self-Correcting System

`antifragile.md` is where the vault learns from breaking. When a user corrects the AI ("don't do this again"), or the system catches its own mistake, the rule gets written immediately — not at session end, not in a retro. The fix becomes a permanent behavioral change. The system doesn't just avoid past mistakes — it gets stronger from them.

### The Ideas That Get Lost

Day-to-day life moves fast. You're executing, reacting, shipping. The connections between what you're building, what you're learning, and who you're becoming get harder to see the busier you are.

The `emerge` and `ideas` commands read across your entire vault — declared identity, observed patterns, active projects, calendar notes — and surface the ideas that live in the overlap. The ones no single session would find, because they require seeing everything at once.

The AI doesn't just remember. It connects. And sometimes, what it connects changes something.

---

## Extend your AIOS — bring your company, your team, your tools

The framework ships canonical infrastructure (commands, agents, skills, MCPs, hooks, plugins, templates) that's identical for every operator. **What makes the framework yours is the extension layer.** Two patterns, both first-class:

**`custom/`** — your personal extensions. Every infra layer has a `custom/` subfolder reserved for *your* additions: agents you build, skills you write, plugins you scaffold, hooks you wire, templates you author, MCPs you vendor. The framework's `/aios:update` never touches anything inside `custom/` — your extensions survive every framework update. Build whatever you need; AIOS just absorbs it.

**`<company>/` namespacing** — venture-distributed infrastructure. When you mount a company via [`/aios:company`](./plugins/aios/commands/company.md), the AIOS nests its agents, skills, plugins, hooks, MCPs, and templates under that company's namespace — `agents/<company>/`, `skills/<company>/`, `plugins/<company>/<plugin>/`, etc. Onboard a teammate to your shared company context **in one prompt**: they run `/aios:company --mount {your-repo-url}` and inherit the entire infrastructure layer your team has built. Same canonical architecture, multiplied by every company you mount.

```
agents/    skills/    plugins/    hooks/    mcps/    templates/
    ↓          ↓          ↓          ↓          ↓          ↓
  aios-*    aios/      aios/      *.py     *-mcp/    *.md       ← framework (always shipped)
  custom/   custom/    custom/    custom/  custom/   custom/    ← your personal layer
  <co>/     <co>/      <co>/<p>/  <co>/    <co>/     <co>/      ← every mounted company's layer
```

Equally true for [`/aios:collaborate`](./plugins/aios/commands/collaborate.md) — collaborative spaces (Drive folders, GitHub repos, local sync folders) get scaffolded with the same `space-<collaborator>` project-note pattern and mirror into your daily ritual. Different scope, same extensibility principle.

> **Want to onboard your team in one prompt?** See [The-AIOS/company-template](https://github.com/The-AIOS/company-template) — the canonical scaffold for a venture-context repo. Includes 10 context files (positioning, personas, primitives, gtm, offerings, pricing, culture, design, brand, about-venture) plus 6 optional infra folders (agents/ · plugins/ · hooks/ · mcps/ · skills/ · templates/) ready to receive your team's contributions. One mount, one prompt, every teammate's Claude session inherits the full context layer.

---

## Repository Architecture

```
~/aios/
├── vault/                   ← Your operator content (notes, calendar, exports, backups)
│   ├── 00 - notes/
│   │   ├── context/
│   │   │   ├── declared/    ← You write: identity, voice, working style, business, role, psychometrics
│   │   │   ├── observed/    ← Claude writes: patterns, growth, preferences, antifragile, session insights
│   │   │   └── ventures/    ← Deep reference docs per venture (about_venture.md + positioning, personas, etc.)
│   │   ├── projects/        ← One note per project, with to-dos and session notes
│   │   ├── ideas/           ← Permanent notes promoted from daily captures
│   │   ├── reflections/     ← Book study notes, deep dives, conversation transcripts
│   │   └── logs/            ← Activity logs, role logs, observed context snapshots
│   ├── 01 - calendar/       ← Daily plans + weekly reviews (auto-generated)
│   ├── 02 - assets/         ← Vault-internal assets
│   ├── 03 - export/         ← Writing drafts, proposals, research, social content, PDFs
│   └── 04 - backups/        ← User backups (empty by default)
├── .claude-plugin/
│   └── marketplace.json     ← Marketplace manifest (the-aios marketplace)
├── plugins/                 ← Claude Code plugins
│   ├── aios/                ← framework: the aios plugin (/aios:* slash commands)
│   │   ├── .claude-plugin/plugin.json
│   │   └── commands/        ← The slash commands (source of truth)
│   ├── custom/              ← your personal extensions (survive /aios:update)
│   └── <company>/<plugin>/  ← company-distributed (via /aios:company --sync)
├── agents/                  ← Task agents
│   ├── aios-*/              ← framework: 6 bundles (sales · strategy · finance-legal · engineering · communication · personal)
│   ├── custom/              ← your personal extensions
│   └── <company>/           ← company-distributed
├── skills/                  ← Skills (auto-loaded by Claude Code)
│   ├── aios/                ← framework: AIOS-built
│   ├── anthropic/           ← framework: vendored from anthropics/skills (Apache-2.0)
│   ├── superpowers/         ← framework: vendored from obra/superpowers (MIT)
│   ├── custom/              ← your personal extensions
│   └── <company>/           ← company-distributed
├── hooks/                   ← Pipeline scripts + statusLine + UserPromptSubmit
│   ├── *.{py,sh,ps1}        ← framework: pipeline-executor, markitdown, inject-datetime
│   ├── claude-identity/     ← framework: quota autopilot (multi-account rotation, macOS)
│   ├── custom/              ← your personal extensions
│   └── <company>/           ← company-distributed
├── mcps/                    ← Vendored MCP servers
│   ├── *-mcp/               ← framework: 10 bundled (see mcps/_index.md for the canonical list)
│   ├── custom/              ← your personal extensions
│   └── <company>/           ← company-distributed
├── templates/               ← Starting templates for context, projects, agents, ventures
│   ├── *.md                 ← framework-bundled templates
│   ├── custom/              ← your personal templates
│   └── <company>/           ← company-distributed
├── START-HERE.md            ← First-time orientation (what is this, what to do post-clone)
├── CLAUDE.md                ← How Claude works with this vault (behavioral rules, session rituals, agentic culture)
├── INTENT.md                ← Trust contract (autonomy levels, tradeoffs, escalation triggers)
├── USER.md                  ← Your personal config (identity, sources, mounted companies, command overrides)
├── README.md                ← This file (value-prop + framework overview)
├── SETUP.md                 ← Step-by-step install (Claude reads this when you say "set up my AI-OS")
├── CHEATSHEET.md            ← Day-to-day operating index (launch/spawn, daily loop, capture/export, personalization)
├── TOOLS.md                 ← Full menu of every command, agent, skill, MCP, and standalone tool
├── FORTRESS.md              ← Advanced: two-machine architecture for 24/7 autonomous agents
└── CHANGELOG.md             ← What changed in shared infra, when, and what to do (read by /aios:update)
```

**Architecture principle:** Everything shared lives in the repo and is identical for all users. Everything personal lives in `USER.md` (your command personalizations), `INTENT.md` (your autonomy rules), and `vault/` (your daily life content).

---

## Bundled Integrations

Same infrastructure for everyone. Personalized surface for each person. Policy: **local over remote** — bundled authenticates independently of your Anthropic OAuth grant, survives account switches, and lives in the vault. Run `/mcps-setup` to walk through each one opt-in.

### Bundled (10 vendored in `mcps/` + Obsidian via npm)

| Integration | What it connects |
|---|---|
| **Obsidian** | Vault read/write — the OS core (installed via `npx @mauricio.wolff/mcp-obsidian`) |
| **Google Workspace** | Calendar, Tasks, Drive, Docs, Sheets, Slides, Gmail (single OAuth) |
| **Slack** | Posts AS YOU via Chrome-extracted token (read/send/search/react). Bot-token fallback available. |
| **GitHub** | Repos, issues, PRs, files, branches, workflows |
| **Atlassian** | Jira issues + Confluence pages (wrapper keeps token out of `~/.claude.json`) |
| **NotebookLM** | Turn vault content or research into audio overviews / podcasts |
| **Playwright** | Headless browser automation with saved Chrome cookies — publish, scrape, screenshot, test UIs |
| **Nano Banana** | Gemini 2.5 Flash image generation (cover art, visuals, mockups) |
| **PDF Generator** | Markdown/HTML → branded PDF via pandoc + Chrome headless (no auth) |
| **Spotify DJ** | Playback control — play, pause, next, volume, search |
| **Stitch** | Google AI-native design → production HTML (supports DESIGN.md seeding) |

See `mcps/_index.md` for the canonical list, auth requirements, and add-a-new-MCP pattern.

> **Looking for an integration that's not bundled** (Monday, Figma, Vercel, Supabase, etc.)? Those exist as claude.ai-hosted remote connectors — operators install them via the Claude UI, separately from the framework. The MCP Policy (see [`CLAUDE.md`](./CLAUDE.md) → § MCP Policy) prefers bundled equivalents when one exists, since claude.ai-hosted MCPs break on account switch. If a service you need has no bundled equivalent, that's a bundling candidate — flag it in [`mcps/_index.md`](./mcps/_index.md).

---

## Credits

Built on the ideas of [internetVin's Obsidian Commands](https://internetvin.com/Obsidian+Commands), evolved into a three-layer context system (declared + observed + intent) with agents, skills, team sync, and an agentic culture informed by 36 books on leadership and teamwork — packaged as a portable Claude Code plugin.

Additional influences that shaped the architecture:
- **[Andrej Karpathy's LLM Wiki](https://github.com/karpathy/llm-wiki)** — the pattern of LLMs building and maintaining persistent wikis instead of re-deriving knowledge via RAG. The AI-OS vault IS a personal wiki: the LLM does the bookkeeping (cross-referencing, updating, contradiction-flagging), the human curates sources and asks the right questions. Karpathy named the pattern; we'd been building it independently. His insight on "filing good answers back" as permanent pages became the `/ingest` command and the "file answers back" convention in `/close-session` and `/close-day`.
- **[Jack Dorsey & Roelof Botha — "From Hierarchy to Intelligence"](https://block.xyz/inside/from-hierarchy-to-intelligence)** — Block's thesis that AI can replace organizational coordination, not just augment it. Their four-layer architecture (Capabilities → World Models → Intelligence → Interfaces) maps structurally to the AI-OS (tools → context → agents → interface). The philosophical tension — humans governing vs AI coordinating — is the question the agentic layer plan holds for v3.
