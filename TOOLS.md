# TOOLS.md — What Your Vault Can Do

> Everything here is available right now. You don't need to memorize commands or file paths — just describe what you want and your Claude session will pick the right tool. This file is the menu, sorted alphabetically for fast lookup.

---

## Commands

Say `/aios:{name}` or just describe what you need. Claude matches intent to command.

| Command | What it does | When to use | Output |
|---------|-------------|-------------|--------|
| `/aios:7plan` | Weekly strategic plan across all ventures | Sunday or Monday morning | Weekly plan note + daily notes Mon–Fri |
| `/aios:agent` | Load a specialist's expertise into the current session | When you need a focused hat for the current convo | Persona engaged inline (no new tab) |
| `/aios:challenge` | Steel-man the opposite of your current thinking | Before big decisions or commitments | Counter-argument + decision-influencing read |
| `/aios:close-day` | End-of-day review + capture what shipped | Every evening | Close-of-day block appended to today's daily note + project updates routed |
| `/aios:close-session` | Lightweight session capture | When finishing a focused work session mid-day | Session report saved to `.claude/session-report-{date}.md` |
| `/aios:cold-start-interview` | First-touch setup for a freshly-cloned vault | Once, right after `git clone` (re-runnable per section) | USER.md + INTENT.md + declared context + bundle/MCP install choices |
| `/aios:collaborate` | Scaffold a shared Collaboration Space (Drive / GitHub / local) | When sharing work with one or more collaborators | Mounted space + first project + router note. Subcommands: `--add-project`, `--status`, `--dry-run` |
| `/aios:compact` | Digest + zip last month's snapshots and logs | First of the month | Monthly digest file + archived snapshots/role-logs |
| `/aios:company` | Mount or sync company venture-context (multi-substrate, multi-company) | Weekly (`--sync-all`); on first mount; when scaffolding a new venture | Mounted venture folders at `vault/00 - notes/context/ventures/{name}/`. Subcommands: `--create`, `--mount`, `--sync`, `--sync-all`, `--status`, `--invite`, `--dry-run` |
| `/aios:connect` | Find unexpected bridges between unrelated vault domains | When projects feel siloed | Cross-reference report with project links |
| `/aios:drift` | Honest check — what's being quietly avoided? | Mid-week or when something feels off | Avoidance audit with named carries + parking-lot review |
| `/aios:emerge` | Surface patterns implied by the vault but never written | Every 2 weeks | Pattern proposals to route into observed context |
| `/aios:ghost` | Answer a question in the vault owner's voice | When drafting content, proposals, or pitches | Voice-matched draft response |
| `/aios:graduate` | Promote half-formed ideas from daily notes to permanent notes | Every 2 weeks | New entries in `vault/00 - notes/ideas/` |
| `/aios:housekeeping` | Vault hygiene — merges, archives, carry drops, index refresh, link repair, upstream-sync freshness | Monthly, or when vault feels heavy (carries ×15+, projects 12+, stale snapshots) | Proposals table; operator approves before writes |
| `/aios:ideas` | Grounded idea report — things to build, write, explore | When you need inspiration grounded in your context | Ranked idea list with source attribution |
| `/aios:ingest` | Process any source (URL, PDF, transcript, paste) into the vault | When you find something worth keeping | Summary page at `reflections/ingests/` + cross-references + action items in project notes |
| `/aios:learned` | Distill insights into a publish-ready report | After a substantive period worth reflecting on | HTML + PDF at `vault/03 - export/reports/learned/` |
| `/aios:mcps-setup` | Guided MCP setup — tokens, registration, verification | First-time setup or when adding a new MCP | Each MCP registered in `~/.claude/settings.json` + smoke-tested |
| `/aios:role-report` | Period report based on your role pillars | Monthly or quarterly | HTML + PDF at `vault/03 - export/reports/role/` |
| `/aios:today` | Generate today's daily plan from full vault context | Every morning | Daily note at `vault/01 - calendar/{YYYY-MM}/{YYYY-MM-DD}.md` |
| `/aios:trace` | Track how thinking about an idea evolved over time | When revisiting a topic | Timeline of belief shifts with source snippets |
| `/aios:update` | Pull latest AIOS framework updates from `The-AIOS/aios` | When CHANGELOG flags new entries to consume | Updated framework files + State→Ask→Act walkthrough per pending entry |
| `/aios:weekly-learnings` | Compile the week's insights into a branded report | Friday | HTML + PDF at `vault/03 - export/reports/weekly/Week{N}-AI-OS.{html,pdf}` |

**Operator extensions:** your own `/<plugin>:{command}` lives in your own plugin at `plugins/custom/<your-plugin>/commands/`. See [CHEATSHEET.md](./CHEATSHEET.md) → Personalization for the pattern.

**Daily rhythm at a glance:**
- **Morning:** `/aios:today`
- **End of work session:** `/aios:close-session` (optional)
- **Evening:** `/aios:close-day`
- **Weekly:** `/aios:7plan` (Mon) · `/aios:weekly-learnings` (Fri)
- **Bi-weekly:** `/aios:drift` · `/aios:graduate` · `/aios:emerge`
- **Monthly:** `/aios:compact` · `/aios:housekeeping`
- **Quarterly:** `/aios:role-report`

---

## Agents

Say `spawn {name}` to launch a named tab dedicated to that role, or `/agent {name}` to wear the hat in the current session.

| Agent | What it does | Bundle |
|-------|-------------|--------|
| `accountant` | Financial analysis, bookkeeping, tax prep, SaaS metrics | finance-legal |
| `brand-monitor` | Track mentions, competitors, industry news | communication |
| `bug-triager` | Classify issues by severity, propose priority | engineering |
| `code-documenter` | Generate/update README, CLAUDE.md, inline docs | engineering |
| `code-reviewer` | Review code for security, quality, patterns | engineering |
| `company-analyst` | Acquired-style deep dives — history, strategy, moat | strategy |
| `compliance-checker` | Review documents against legal/regulatory requirements | finance-legal |
| `consultant` | Strategic advisory, frameworks, recommendations | strategy |
| `content-scheduler` | Plan and queue content calendar from vault insights | communication |
| `content-writer` | Draft posts for LinkedIn, X, Substack in your voice | communication |
| `email-drafter` | Draft professional emails matching voice + context | communication |
| `invoice-tracker` | Track pending invoices, flag overdue | finance-legal |
| `journal-prompter` | Generate reflection prompts from sessions + patterns | personal |
| `lawyer` | Legal review, contract analysis, compliance | finance-legal |
| `market-researcher` | McKinsey-style market intelligence (Porter's Five Forces, etc.) | strategy |
| `meeting-prepper` | Prepare context-rich briefings for meetings | communication |
| `onboarding-aios` | Knows the whole AIOS map; walks you through it when lost | personal |
| `report-drafter` | Draft status reports and board updates | communication |
| `sales-crm-updater` | Sync deal updates to Monday/CRM | sales |
| `sales-lead-hunter` | Explore leads, qualify, score, draft outreach | sales |
| `sales-proposal-writer` | Draft proposals from project notes + catalog | sales |
| `security-engineer` | Threat modeling, secure-code review, incident response | engineering |
| `study-buddy` | Pre-read chapters, prepare briefs, facilitate study | personal |
| `technical-cofounder` | Build products end-to-end — discovery → shipping | engineering |

**By bundle:** see `agents/_index.md` for the canonical registry (6 bundles + `custom/`). Operator-built agents live at `agents/custom/{name}.md` and survive `/aios:update`. Company-distributed agents land at `agents/{company}/` via `/aios:company --sync`.

**Example:** `spawn lawyer "review NDA at ~/code/contracts/2026-03-mutual-nda.docx"` opens a new tab with the lawyer hat pre-loaded and the task primed as the first prompt.

---

## Skills

Skills auto-load — you don't invoke them by name. Describe what you want and Claude picks the right one.

### Coding & engineering
| Skill | Trigger phrase |
|-------|---------------|
| `code-review-excellence` | "Review this code thoroughly" |
| `karpathy-coding` | "Follow Karpathy's principles" — think before coding, simplicity first, surgical changes |
| `systematic-debugging` | "Help me debug this systematically" |
| `test-driven-development` | "Let's write tests first" |

### Content & design
| Skill | Trigger phrase |
|-------|---------------|
| `brand-guidelines` | "Apply brand styling to this" |
| `canvas-design` | "Create a poster / visual design" |
| `doc-coauthoring` | "Let's co-write this document" |
| `frontend-design` | "Build a landing page / component / dashboard" |

### Documents & files
| Skill | Trigger phrase |
|-------|---------------|
| `docx` | "Create a Word document" / "Edit this .docx" |
| `pdf` | "Create a PDF" / "Fill this PDF form" / "Merge these PDFs" |
| `pptx` | "Create a presentation" / "Edit these slides" |
| `xlsx` | "Create a spreadsheet" / "Analyze this Excel file" |

### Obsidian-specific
| Skill | Trigger phrase |
|-------|---------------|
| `defuddle` | "Clean this web page into markdown" |
| `json-canvas` | "Create a visual canvas / diagram / map" |
| `obsidian-bases` | "Create a Bases view for my projects" |
| `obsidian-cli` | "Open this note in Obsidian" / "Run an Obsidian command" |
| `obsidian-markdown` | "Write proper Obsidian markdown" — wikilinks, callouts, properties |

### Planning & process
| Skill | Trigger phrase |
|-------|---------------|
| `brainstorming` | "Let's brainstorm before building" |
| `executing-plans` | "Execute this plan with checkpoints" |
| `verification-before-completion` | "Verify everything works before we ship" |
| `writing-plans` | "Help me plan the implementation" |

**Source folders:** `skills/aios/` (AIOS-built) · `skills/anthropic/` (vendored from `anthropics/skills`) · `skills/superpowers/` (vendored from `obra/superpowers`) · `skills/custom/` (your own — survives `/aios:update`). Browse `skills/_index.md` for the full registry. Additional skills (canvas-design, docx, pdf, pptx, xlsx) ship via Anthropic's `document-skills@anthropic-agent-skills` plugin — install via `/plugin install`.

---

## Standalone tools

These run independently from the terminal — no command or skill required.

### `claude-identity` — multi-account quota autopilot (macOS)

Rotates between two or more Anthropic accounts when the 5h or 7d rate limit nears the cap, then respawns active sessions on the new account so transcripts continue uninterrupted. A launchd agent watches every 60 seconds.

```bash
~/aios/hooks/claude-identity/claude-identity.sh whoami    # current + next in rotation
~/aios/hooks/claude-identity/claude-identity.sh switch    # rotate to the next account
~/aios/hooks/claude-identity/claude-identity.sh list      # all accounts + saved-state
```

Setup is opt-in and walked through by `/aios:cold-start-interview` + the SETUP.md §11 split-install flow. Hard prerequisites: macOS + ≥ 2 Anthropic accounts. Full reference: `hooks/claude-identity/README.md`.

### `markitdown` — convert any file to markdown

Converts PDF, Word, Excel, PowerPoint, images, audio (with transcription), YouTube URLs, EPUB, HTML, CSV, JSON, XML, ZIP → clean markdown.

```bash
python3 ~/aios/hooks/markitdown-convert.py input.pdf              # prints to stdout
python3 ~/aios/hooks/markitdown-convert.py input.pdf output.md    # saves to file
python3 ~/aios/hooks/markitdown-convert.py meeting.mp3 transcript.md
python3 ~/aios/hooks/markitdown-convert.py budget.xlsx data.md
```

Or just say *"convert this PDF to markdown"* — Claude knows. Also integrated into `/aios:ingest` automatically.

### `pdf-generator` — branded PDFs from markdown or HTML

Powers the branded reports from `/aios:weekly-learnings`, `/aios:learned`, `/aios:role-report`. Available as a bundled MCP (`mcp__pdf-generator__markdown_to_pdf` and `mcp__pdf-generator__html_to_pdf`). Pipeline: markdown → HTML (with inline CSS) → Chrome headless → PDF.

### `pipeline-executor` — Calendar + Tasks + Slack pre-loader

Used internally by `/aios:today` and `/aios:close-day` to batch-load Google Calendar, Tasks, and Slack data in one call. You don't need to run it manually, but you can:

```bash
uv run ~/aios/hooks/pipeline-executor.py --command today       # for /today shape
uv run ~/aios/hooks/pipeline-executor.py --command close-day   # for /close-day shape
```

---

## Infrastructure map

Where everything lives:

| Folder | What's inside | How it's used |
|--------|--------------|---------------|
| `agents/` | Task agents in 6 bundles (`aios-sales/` · `aios-strategy/` · `aios-finance-legal/` · `aios-engineering/` · `aios-communication/` · `aios-personal/`) + `agents/custom/` (operator) + `agents/{company}/` (company-distributed) | Spawned via `spawn {name}` or invoked via `/aios:agent {name}` |
| `hooks/` | Pipeline scripts (`pipeline-executor.py`, `markitdown-convert.py`) + `claude-identity/` quota autopilot + event hooks (`inject-datetime`) | Called by commands, by `launchd` (autopilot), or via `python3` directly |
| `mcps/` | Bundled MCP servers — Google Workspace, Slack, GitHub, Atlassian, NotebookLM, Playwright, Stitch, Nano Banana, PDF Generator, Spotify DJ | Auto-connected via `~/.claude/settings.json` after `/aios:mcps-setup` |
| `plugins/` | Claude Code plugins — `plugins/aios/` (this framework) + `plugins/custom/<your-plugin>/` (operator) + `plugins/<company>/<plugin>/` (company-distributed) | Auto-loaded when enabled in `~/.claude/settings.json` |
| `skills/` | Skills in 4 source folders — `aios/` · `anthropic/` · `superpowers/` · `custom/` | Auto-loaded by Claude Code at session start |
| `templates/` | Reference templates for vault scaffolding + `templates/custom/` for operator extensions | Copied by commands and operators as starting points |

---

## Advanced — two-machine architecture

If you want 24/7 autonomous agents — overnight shifts, scheduled cron agents, work continuing while you're away — AIOS ships a two-machine architecture pattern: a primary MacBook + an always-on Mac mini. Six defensive layers (network isolation, ecosystem lockdown, SSH hardening, permission gates, one-way data flow, recovery mechanisms).

📘 **See [`FORTRESS.md`](./FORTRESS.md)** for the full setup — Claude reads it end-to-end and walks both machines through the configuration. Hard prerequisites: macOS on both, second machine on AC power with stable network.

---

## Using AIOS with other LLMs

The canonical surface is Claude Code (the framework is named for Anthropic's plugin model). But the *content* is plain markdown — LLM-agnostic by design.

**Portable across LLMs:** every command's instructions (in `plugins/aios/commands/*.md`), every skill's `SKILL.md` (follows [Anthropic's open Skills spec](https://github.com/anthropics/skills)), every template, every agent definition, every observed-context routing rule. MCPs (`mcps/`) are protocol-level — any MCP-capable LLM connects directly.

**Claude-specific (replaceable):** `spawn` wrapper (uses `claude --remote-control --name`), the `/aios:*` slash invocation syntax (Claude Code's `<plugin>:<command>` convention), plugin marketplace + cache paths (`~/.claude/plugins/...`).

**For Gemini CLI / Cursor / Cline / other agentic IDEs:** point your LLM at `plugins/aios/commands/` as a custom command directory (most IDE-integrated agents allow this in config). For one-off use, paste a command's content into the conversation: *"follow the instructions in `plugins/aios/commands/today.md`, treating my vault root as `~/aios/`."* The structure transfers; only the invocation syntax changes.

---

*This file ships with the framework. When you run `/aios:update`, you get the latest tools automatically.*
