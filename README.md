# The AIOS — AI as a Team, Not a Tool

> Everyone is building an AIOS. We built **The AIOS**.

<details>
<summary><strong>📍 Reading this as Claude?</strong> (Operator pointed you at this repo — click for your action sequence)</summary>

You're the executor — the human reads alongside, you do the heavy lifting. Sequence:

1. **Setting up for the first time?** → read [SETUP.md](./SETUP.md), follow the "Reading this as Claude?" block at its top
2. **Operator says "I'm lost" or "what is this?"** → invoke [`/agent onboarding-aios`](./agents/aios/personal/onboarding-aios.md) — that agent knows the full doc map (this README, SETUP, CHEATSHEET, FORTRESS, START-HERE, USER.md, INTENT.md, CLAUDE.md, plus CONTRIBUTING.md at repo root + the org-level SECURITY) and routes the operator to the right place without overwhelming them
3. **Operator already set up, needs daily ritual?** → `/aios:today` (morning) · `/aios:close-day` (evening) · `/aios:close-session` (per task) — this is the compound loop
4. **Anything else** → [CLAUDE.md](./CLAUDE.md) is the behavioral contract (session rituals, agentic culture, the 10 principles); [TOOLS.md](./TOOLS.md) is the full menu of commands/agents/skills/MCPs; [CHEATSHEET.md](./CHEATSHEET.md) is the day-to-day operating index

</details>

---

## Get started (the 30-second version)

**Have Claude Code installed?** Open any terminal and say:

```
Set up my AI-OS from https://github.com/The-AIOS/aios
```

Claude reads [SETUP.md](./SETUP.md), clones the framework, walks every choice.

**Don't have Claude Code yet?** → [SETUP.md → Prerequisites](./SETUP.md#prerequisites) for OS-specific install (~5-20 min). Then come back and run the line above.

**Want the deeper "what is this and why?" before installing?** → keep reading, or read the full **[Operating Manual](https://www.the-aios.com/#manual)** — 17 sections from first principles to 24/7 containment, online or as a PDF.

---

## What it is + who it's for

The AIOS turns AI into a team — a legal you, an accountant you, a marketing you, a software engineer you. You can run them all and be their orchestrator, or let one AI co-worker run the rest as your chief of staff who never sleeps and absorbs the coordination overhead with the best agentic culture.

For anyone navigating AI-overwhelming days — senior executives, builders, founders, operators. AI alone multiplies confusion. The AIOS gives you the structure (prompt, context, intent, collaboration, second brain) where clarity emerges, then allows you to amplify yourself and your team with AI co-workers.

If you want to make the most of AI without losing what makes you irreplaceable — and without IP/PII risk — **this is for you**.

---

## Three progressive stages, all compounding

Each stage builds on the last. Each next stage returns ~10× the leverage.

- **Week 1: Automate — *Gain speed, do faster*.** Daily plans, drafts, syntheses — 30 minutes becomes 30 seconds.
- **Week 2: Amplify — *Gain bandwidth, do more*.** Agents draft proposals, write in your voice, research while you sleep — you stop being the bottleneck.
- **Month 1: Agency — *Gain autonomy, do agentic*.** AI co-workers act on your behalf with judgment, within trust boundaries you've defined.

---

## Four principles, all load-bearing

- **Amplify intelligence, not artificial.** Human + AI beats human alone or AI alone.
- **Context, not prompts.** Prompts are the artifact most people optimize. Context is the substrate that determines what those prompts can do.
- **Trust earned over time.** Autonomy compounds with judgment — like a good A-player on a real team.
- **Portable, not proprietary.** The AIOS is the layer; the LLM is interchangeable. Plug Claude (recommended), Gemini, or your best model.

---

## What makes The AIOS different

The phrase "AI operating system" is everywhere now — most are second-brain wrappers with a `CLAUDE.md` and a few prompts. And the strongest builders keep arriving at the same architecture independently: filesystem as context, plain Markdown, no RAG. That convergence validates the foundation — the difference is the layer above it: **The AIOS is *governed* (the INTENT.md trust contract), *multiplayer* (personal × team × company topologies), and *substrate-agnostic* — not a deeper single-player engine, but the operating system your whole circle runs.**

Five things make this operationally distinct:

**1. Three-layer context that compounds.** Most setups ship declared context only. The AIOS adds *observed context* — Claude writes its own observations about your patterns, growth edges, blind spots — AND *intent* (a trust contract that encodes judgment, not just knowledge). After a month, the AI knows things about you that aren't in any file you wrote.

**2. Daily rituals that are load-bearing, not optional.** `/today`, `/close-day`, `/close-session` aren't quick-start commands you can skip. They're the system's nervous system — routing session insights to observed context (so Claude actually gets smarter), closing the carry-loop (so nothing falls through), surfacing drift before it becomes invisible. *Logging is not routing* — the framework is built on the routing.

**3. Substrate-pluggable collaboration.** When two people share work, most setups say "fork the repo" or "share a Drive folder." The AIOS treats storage as a plugin — `/collaborate` scaffolds a shared workspace on Drive for non-coder collaborators, GitHub for code-adjacent work, or local folders for testing. Same command, same artifacts, same routing into your daily plan.

**4. Self-correcting via antifragile.** When the system breaks — a wrong assumption, a brittle prompt, a missed edge case — the rule gets written *immediately* into `antifragile.md`. Not in a retro, not in a backlog. The fix becomes a permanent behavioral change at the moment of failure. Every break upgrades the system.

**5. Agentic culture from human↔AI to AI↔AI.** Agents follow the same operating principles as the operator. When you spawn `accountant`, it follows the same routing rituals (`/close-session` bridges its work back to your vault). The 10 principles of intelligence collaboration ([CLAUDE.md § Operating Principles](./CLAUDE.md)) apply across the whole agentic surface: human↔AI, AI↔AI, AI↔substrate. *There are no bad agents, only bad operators.*

The system is informed by 36 books on leadership, teamwork, and organizational behavior — synthesized into 10 principles and 19 operational changes. Every command, every behavioral rule, every escalation trigger traces back to a specific insight from a specific author. Full thesis: [The Agentic Culture](https://chuycepeda.substack.com/p/the-agentic-culture-team-management).

---

## The compound effect

On day one, Claude knows what you've told it. After a week, it knows how you operate. After a month, it can spot when you're drifting from your own stated priorities. After six months, it can show you how your thinking has evolved. After a year, it's a record of who you were becoming.

This isn't a productivity hack. It's compounding self-awareness.

The vault quietly captures things that change how you work and live:

- **Business ideas you didn't know you had.** `/emerge` reads across your projects + daily notes + patterns and surfaces ideas that live in the overlap. The startup concept that connects your consulting work to your side project. The product feature hiding in three separate client conversations. No single session would find them — they require seeing everything at once.
- **Growth edges that make you better.** `growth.md` holds honest observations about where you're growing and where you're avoiding growth. Not to judge — because that specific, honest reflection is what turns an AI tool into a genuine partner. The kind that says *"you've rescheduled this four times — what's really blocking you?"*
- **Working style insights that save you hours.** Claude learns when you do your best creative work, what drains you, how you make decisions under pressure, what you procrastinate on and why. Daily plans work *with* your energy, not against it.
- **Strategic connections across everything you're building.** `/connect` finds bridges between unrelated domains in your vault. The pattern in your healthcare project that applies to your fintech idea. The lesson from last quarter's failed launch that's relevant to today's pitch.
- **A voice that sounds like you.** `/ghost` answers questions, drafts messages, and writes content in your actual voice — because it's learned your tone, your rhythms, your way of framing ideas from months of context.

None of this requires extra work. The context builds as a natural byproduct of your sessions. You do the thinking. The vault does the remembering.

---

## Extend your AIOS — bring your company, your team, your tools

The framework ships canonical infrastructure (commands, agents, skills, MCPs, hooks, plugins, templates) that's identical for every operator. **What makes the framework yours is the extension layer.** Two patterns, both first-class — and the complete how-to-extend reference (every infra type × the three layers, with exactly how to add each) is **[`EXTENSION-MAP.md`](./EXTENSION-MAP.md)**:

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
├── CHANGELOG.md             ← What changed in shared infra, when, and what to do (read by /aios:update)
├── AGENTS.md                ← Portable operating contract for non-Claude tools (Codex/Cursor/Aider)
├── EXTENSION-MAP.md         ← How to extend AIOS: bundled/custom/company model per infra type + how to add each
└── LICENSE-AUDIT.md         ← Open-core license boundary (GPL · vendored-upstream · private vault · company)
```

**Architecture principle:** Everything shared lives in the repo and is identical for all users. Everything personal lives in `USER.md` (your command personalizations), `INTENT.md` (your autonomy rules), and `vault/` (your daily life content).

---

## The canonical setup sequence

If the [30-second version at the top](#get-started-the-30-second-version) was enough, you're already running. If you want the full step-by-step:

**Step 1 — `SETUP.md` (Claude-driven, ~10 min).** Open any terminal with Claude Code installed and say: *"Set up my AI-OS from `https://github.com/The-AIOS/aios`"*. Claude clones the framework, installs MCPs, configures your private vault, and walks you through every choice.

**Step 2 — `/aios:cold-start-interview` (~20 min).** Walks identity, declared context, `INTENT.md` trust contract, agent bundle install choices, MCP setup, optional plugins, and your first `/aios:today`.

**Day 1 onward:** `/aios:today` morning · `/aios:close-day` evening · `/aios:close-session` per task. That's the rhythm. The system compounds from there.

See [SETUP.md](./SETUP.md) for prerequisites + the canonical 11-step flow · [START-HERE.md](./START-HERE.md) for the post-clone walkthrough framing + the three-repo model AIOS uses · [TOOLS.md](./TOOLS.md) for the full menu of commands, agents, skills, and bundled MCPs · the full **[Operating Manual](https://www.the-aios.com/#manual)** (www.the-aios.com/#manual) for the complete design language + behavioral contract in one document.

---

## What's inside

Once set up, your vault comes with **24 commands, task agents across 6 bundles, bundled skills across 4 source folders, bundled MCPs, and standalone tools** — all accessible by describing what you need. See [TOOLS.md](./TOOLS.md) for the full menu.

The 10 bundled MCPs (Obsidian, Google Workspace, Slack, GitHub, Atlassian, NotebookLM, Playwright, Nano Banana, PDF Generator, Spotify DJ, Stitch) authenticate independently of your Anthropic OAuth grant, survive account switches, and live in the vault — policy: **local over remote**. See [`mcps/_index.md`](./mcps/_index.md) for the canonical list, auth requirements, and add-a-new-MCP pattern.

---

## Credits

Built on the ideas of [internetVin's Obsidian Commands](https://internetvin.com/Obsidian+Commands), evolved into a three-layer context system (declared + observed + intent) with agents, skills, team sync, and an agentic culture informed by 36 books on leadership and teamwork — packaged as a portable Claude Code plugin.

Additional influences:
- **[Andrej Karpathy's LLM Wiki](https://github.com/karpathy/llm-wiki)** — the LLM-builds-and-maintains-persistent-wikis pattern (instead of re-deriving knowledge via RAG). The AIOS vault IS a personal wiki: the LLM does the bookkeeping (cross-referencing, updating, contradiction-flagging); the human curates sources and asks the right questions. His insight on "filing good answers back" became the `/ingest` command + the "file answers back" convention in `/close-session` and `/close-day`.
- **[Jack Dorsey & Roelof Botha — "From Hierarchy to Intelligence"](https://block.xyz/inside/from-hierarchy-to-intelligence)** — Block's thesis that AI can replace organizational coordination, not just augment it. Their four-layer architecture (Capabilities → World Models → Intelligence → Interfaces) maps structurally to the AIOS (tools → context → agents → interface).

---

*Amplify yourself and your team — with AI co-workers. Not zero people. Compounded people.*
