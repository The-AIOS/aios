# TOOLS.md — What Your Vault Can Do

> Everything here is available to you right now. You don't need to memorize commands or file paths — just describe what you want and your Claude session will use the right tool. This file is your menu.

---

## Commands

Say `/aios:{name}` or just ask for what you need — Claude matches intent to command.

| Command | What it does | When to use |
|---------|-------------|-------------|
| `/today` | Generate today's daily plan from vault context | Every morning |
| `/close-day` | End-of-day review + capture what happened | Every evening |
| `/close-session` | Lightweight session capture | When finishing a work session |
| `/7plan` | Weekly strategic plan across all ventures | Sunday/Monday |
| `/weekly-learnings` | Compile the week's insights + branded PDF | Friday |
| `/drift` | Honest check — what's being quietly avoided? | Mid-week or when something feels off |
| `/graduate` | Promote half-formed ideas from daily notes to permanent notes | Every 2 weeks |
| `/emerge` | Surface patterns implied by the vault but never written | Every 2 weeks |
| `/compact` | Digest + zip previous month's snapshots and logs | First of the month |
| `/ideas` | Grounded idea report — things to build, write, explore | When you need inspiration |
| `/ghost` | Answer a question in the vault owner's voice | When drafting content or proposals |
| `/challenge` | Steel-man — argue against your current thinking | Before big decisions |
| `/trace` | Track how thinking about an idea evolved over time | When revisiting a topic |
| `/connect` | Find unexpected bridges between unrelated domains | When projects feel siloed |
| `/learned` | Distill insights into a publish-ready report + PDF | After a rich period |
| `/housekeeping` | Vault housekeeping — proposals to merge, archive, drop carries, refresh indexes, repair links | Monthly, or when the vault feels heavy (carries ×15+, projects 12+, stale snapshots) |
| `/role-report` | Quarterly report based on your role pillars | Quarterly |
| `/ingest` | Process any source into the vault — extract, file, cross-reference | When you find something worth keeping |
| `/agent` | Load an agent's expertise into the current session | When you need a specialist |
| `/collaborate` | Scaffold a shared Collaboration Space (Drive/GitHub/local) — `--add-project`, `--status`, `--dry-run` | When you want to share work with one or more collaborators on a substrate-pluggable foundation |
| `/company` | Mount/sync company venture-context (multi-substrate, multi-company). Subcommands: `--create`, `--mount`, `--sync`, `--sync-all`, `--status`, `--invite`, `--dry-run` | Weekly (`--sync-all`) |
| `/cold-start-interview` | First-touch setup for a freshly-cloned AIOS vault — walks identity, context, MCPs, agent bundles, optional plugins, first /today | One-shot (or revisit-able) |
| `/aios:update` | Pull latest AIOS framework updates from The-AIOS/aios | When notified |
| `/mcps-setup` | Guided MCP setup — tokens + zshrc + register + verify | First-time setup or when adding a new MCP |

---

## Agents

Say `spawn {name}` to launch a dedicated session, or `/agent {name}` to wear the hat yourself.

| Agent | What it does | Example |
|-------|-------------|---------|
| `sales-lead-hunter` | Explore leads, qualify, score, draft outreach | "spawn sales-lead-hunter" |
| `sales-proposal-writer` | Draft proposals from project notes + catalog | "spawn sales-proposal-writer" |
| `sales-crm-updater` | Sync deal updates to Monday/CRM | "spawn sales-crm-updater" |
| `market-researcher` | McKinsey-style market intelligence analysis | "spawn market-researcher" |
| `accountant` | Financial analysis, bookkeeping, tax prep | "spawn accountant" |
| `lawyer` | Legal review, contract analysis, compliance | "spawn lawyer" |
| `consultant` | Strategic advisory, frameworks, recommendations | "spawn consultant" |
| `technical-cofounder` | Build products end-to-end — discovery → shipping | "spawn technical-cofounder" |
| `code-reviewer` | Review code for security, quality, patterns | "spawn code-reviewer" |
| `code-documenter` | Generate/update README, CLAUDE.md, inline docs | "spawn code-documenter" |
| `bug-triager` | Classify issues by severity, suggest priority | "spawn bug-triager" |
| `content-writer` | Draft posts for LinkedIn, X, Substack in your voice | "spawn content-writer" |
| `content-scheduler` | Plan and queue content calendar from vault insights | "spawn content-scheduler" |
| `brand-monitor` | Track mentions, competitors, industry news | "spawn brand-monitor" |
| `meeting-prepper` | Prepare context-rich briefings for meetings | "spawn meeting-prepper" |
| `report-drafter` | Draft status reports and board updates | "spawn report-drafter" |
| `email-drafter` | Draft professional emails matching voice + context | "spawn email-drafter" |
| `invoice-tracker` | Track pending invoices, flag overdue | "spawn invoice-tracker" |
| `compliance-checker` | Review documents against legal/regulatory requirements | "spawn compliance-checker" |
| `study-buddy` | Pre-read chapters, prepare briefs, facilitate study | "spawn study-buddy" |
| `journal-prompter` | Generate reflection prompts from sessions + patterns | "spawn journal-prompter" |
| `company-analyst` | Acquired-style deep dives — history, strategy, moat | "spawn company-analyst" |

> **Personal agents** live in `06 - agents/my-agents/`. Create yours — same format, same matching.

---

## Skills

Skills auto-load — you don't invoke them directly. Just describe what you want and Claude uses the right skill. Here are the ones worth knowing about:

### Coding & Engineering
| Skill | What to say |
|-------|-------------|
| `karpathy-coding` | "Follow Karpathy's principles" — think before coding, simplicity first, surgical changes, goal-driven |
| `code-review-excellence` | "Review this code thoroughly" |
| `test-driven-development` | "Let's write tests first" |
| `systematic-debugging` | "Help me debug this systematically" |

### Content & Design
| Skill | What to say |
|-------|-------------|
| `frontend-design` | "Build a landing page / component / dashboard" |
| `canvas-design` | "Create a poster / visual design" |
| `doc-coauthoring` | "Let's co-write this document" |
| `brand-guidelines` | "Apply brand styling to this" |

### Documents & Files
| Skill | What to say |
|-------|-------------|
| `pdf` | "Create a PDF" / "Fill this PDF form" / "Merge these PDFs" |
| `docx` | "Create a Word document" / "Edit this .docx" |
| `pptx` | "Create a presentation" / "Edit these slides" |
| `xlsx` | "Create a spreadsheet" / "Analyze this Excel file" |

### Obsidian-Specific
| Skill | What to say |
|-------|-------------|
| `obsidian-markdown` | "Write proper Obsidian markdown" — wikilinks, callouts, properties |
| `obsidian-bases` | "Create a Bases view for my projects" |
| `json-canvas` | "Create a visual canvas / diagram / map" |
| `obsidian-cli` | "Open this note in Obsidian" / "Run an Obsidian command" |
| `defuddle` | "Clean this web page into markdown" |

### Planning & Process
| Skill | What to say |
|-------|-------------|
| `brainstorming` | "Let's brainstorm before building" |
| `writing-plans` | "Help me plan the implementation" |
| `executing-plans` | "Execute this plan with checkpoints" |
| `verification-before-completion` | "Verify everything works before we ship" |

> **Bundled skills across 4 source folders** — `skills/aios/` (AIOS-built) · `skills/anthropic/` (vendored from anthropics/skills) · `skills/superpowers/` (vendored from obra/superpowers) · `skills/custom/` (your own). Plus more via Anthropic's `document-skills@anthropic-agent-skills` plugin (canvas-design, docx, pdf, pptx, xlsx, etc. — not bundled here because they're either proprietary or asset-heavy). Browse `skills/` for the full list of bundled ones.

---

## Standalone Tools

These run from the terminal, independent of any command or skill.

### MarkItDown — Convert any file to markdown

Converts PDF, Word, Excel, PowerPoint, images, audio, YouTube, EPUB → clean markdown.

```bash
# Basic usage
python3 hooks/markitdown-convert.py input.pdf                    # prints to stdout
python3 hooks/markitdown-convert.py input.pdf output.md          # saves to file

# Examples
python3 hooks/markitdown-convert.py quarterly-report.pdf report.md
python3 hooks/markitdown-convert.py client-deck.pptx slides.md
python3 hooks/markitdown-convert.py meeting-recording.mp3 transcript.md
python3 hooks/markitdown-convert.py budget.xlsx data.md
```

Or just tell your Claude: **"convert this PDF to markdown"** — it knows about markitdown.

Also integrated into `/ingest`: say `/ingest myfile.pdf` and the conversion happens automatically.

### Pipeline Executor — Pre-load Calendar + Tasks + Slack

Used internally by `/today` and `/close-day`. You don't need to run it manually, but you can:

```bash
uv run hooks/pipeline-executor.py --command today      # loads Calendar, Tasks, Slack
uv run hooks/pipeline-executor.py --command close-day   # loads Calendar (detailed), Tasks, Slack
```

### PDF Generator — Branded reports

Used by `/weekly-learnings`, `/learned`, `/role-report` to generate branded PDFs. The pipeline: markdown → HTML (with inline CSS) → Chrome headless → PDF.

### Claude-Identity — Multi-account quota autopilot (macOS only)

Rotates between two or more Anthropic accounts when the 5h or 7d rate limit nears the cap, then respawns active Claude Code sessions on the new account so transcripts continue uninterrupted. A launchd agent watches every 60 seconds; you don't need to run anything once it's loaded.

```bash
# inspect / rotate manually (after first-time setup)
~/aios/hooks/claude-identity/claude-identity.sh whoami    # current + next in rotation
~/aios/hooks/claude-identity/claude-identity.sh switch    # rotate to the next account
~/aios/hooks/claude-identity/claude-identity.sh list      # all accounts + saved-state
```

Setup is opt-in and walks through `/aios:update` — see the `2026-04-25 — hooks/claude-identity` entry in `CHANGELOG.md` for the interactive walkthrough (your Claude session asks how many accounts you have, captures each, customizes the launchd Label, wires statusLine). Full reference + lessons learned in `hooks/claude-identity/README.md`. Hard preconditions: macOS + ≥ 2 Anthropic accounts.

---

## Infrastructure Map

| Folder | What's inside | How it's used |
|--------|--------------|---------------|
| `plugins/aios/commands/` | 24 vault commands inside the `aios` plugin | Invoked via `/aios:{name}` |
| `skills/` | Bundled skills across 4 source folders (aios · anthropic · superpowers · custom) | Auto-loaded by Claude Code at session start |
| `hooks/` | Pipeline scripts (executor, markitdown) + `claude-identity/` quota autopilot | Called by commands, directly via `python3`, or by launchd (autopilot) |
| `mcps/` | Bundled MCP servers (Google Workspace, Obsidian, Slack, Playwright, NotebookLM, PDF Generator, etc.) | Auto-connected via settings.json |
| `plugins/` | Claude Code plugins — `aios` (this framework's slash commands) + operator `custom/` + company-namespaced `<company>/<plugin>/` | Auto-loaded when enabled in settings |
| `agents/` | Task agents across 6 bundles (sales · strategy · finance-legal · engineering · communication · personal) + custom/ | Spawned via `spawn {name}` or `/agent {name}` |

---

## Using AIOS with other LLMs

The canonical surface is Claude Code (this framework is named for Anthropic's plugin model — `.claude-plugin/`, `aios@the-aios`). But the *content* of the system is plain markdown, deliberately LLM-agnostic.

**Commands** live at `plugins/aios/commands/*.md` as readable markdown — no Claude-Code-specific syntax inside, just instructions. Any LLM that can read files from disk can use them.

**For Gemini CLI / Cursor / Cline / other agentic IDEs:**
- Point the LLM at `plugins/aios/commands/` as the command source folder. Most IDE-integrated agents allow custom command directories via config — set yours there.
- For one-off use, paste a command's content into the conversation: "follow the instructions in `plugins/aios/commands/today.md`, treating my vault root as `~/aios/`."
- The plugin manifests (`.claude-plugin/marketplace.json`, `plugins/aios/.claude-plugin/plugin.json`) are Claude Code's plugin-loader scaffolding — other LLMs ignore them. They don't interfere.
- Skills (`skills/*/SKILL.md`) follow [Anthropic's open Skills spec](https://github.com/anthropics/skills) — already cross-LLM compatible.
- MCPs (`mcps/`) are protocol-level, not Claude-specific. Any MCP-capable LLM (Claude, Gemini via custom adapters, Cursor) can connect to them.

**What's Claude-specific:**
- `spawn` wrapper (uses `claude --remote-control --name`) — operator launch glue, not framework logic
- `/aios:*` slash invocation (Claude Code's `<plugin>:<command>` syntax) — other LLMs invoke by reading the command file directly
- Plugin marketplace + cache paths (`~/.claude/plugins/...`) — Claude Code runtime, not framework state

**What's portable:**
- Every command's logic (instructions, MCP calls, file edits, decision rules)
- Every skill's SKILL.md
- Every template, every agent definition
- Every observed-context routing rule

If you're using a non-Claude LLM, your daily ritual is: read `plugins/aios/commands/today.md` (or whichever command you want) → execute its steps → use whatever filesystem-access primitives your LLM provides instead of Claude Code's tools. The structure transfers.

---

## Advanced setup — two-machine architecture

If you want 24/7 autonomous agents — overnight shifts, scheduled cron agents, work continuing while you're away from the keyboard — AIOS ships a complete two-machine architecture pattern: a primary MacBook (day-to-day driver) + a Mac mini (always-on agent host). Six defensive layers: network isolation, ecosystem lockdown, SSH hardening, permission gates, one-way data flow, recovery mechanisms.

📘 **See [`FORTRESS.md`](./FORTRESS.md)** for the full setup manual — Claude reads it end-to-end and walks both machines through the configuration. Hard prerequisites: macOS on both, second machine on AC power with stable network.

---

*This file ships with the vault. When you run `/aios:update`, you get the latest tools automatically.*
