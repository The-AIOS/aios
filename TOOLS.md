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
| `aios-builder` | Scaffold + register a new AIOS element (agent/skill/command/plugin/hook/MCP) under `custom/` — compliant and actually loaded | engineering |
| `brand-monitor` | Track mentions, competitors, industry news | sales |
| `bug-triager` | Classify issues by severity, propose priority | engineering |
| `code-documenter` | Generate/update README, CLAUDE.md, inline docs | engineering |
| `code-reviewer` | Review code for security, quality, patterns | engineering |
| `company-analyst` | Acquired-style deep dives — history, strategy, moat | strategy |
| `compliance-checker` | Review documents against legal/regulatory requirements | finance-legal |
| `consultant` | Strategic advisory, frameworks, recommendations | strategy |
| `content-scheduler` | Plan and queue content calendar from vault insights | communication |
| `content-writer` | Draft posts for LinkedIn, X, Substack in your voice | communication |
| `crisis-mode` | Emergency / incident-response framing — calm, structured, actionable | personal |
| `deck-builder` | End-to-end slide-deck construction via `batch_update_presentation` — design discovery → outline → nano-banana imagery → live Google Slides build → human polish handoff | communication |
| `decision-journaler` | Structured decision capture (verdict / diagnosis / options / reasoning / confidence / revisit-if) | personal |
| `design-md-author` | Author `DESIGN.md` per Google Labs spec (visual design system + tokens) — pairs with Stitch MCP | communication |
| `email-drafter` | Draft professional emails matching voice + context | communication |
| `growth-companion` | Growth-focused conversational companion — surfaces growth edges, holds you accountable without judging | personal |
| `invoice-tracker` | Track pending invoices, flag overdue | finance-legal |
| `journal-prompter` | Generate reflection prompts from sessions + patterns | personal |
| `lawyer` | Legal review, contract analysis, compliance | finance-legal |
| `market-researcher` | McKinsey-style market intelligence (Porter's Five Forces, etc.) | strategy |
| `meeting-prepper` | Prepare context-rich briefings for meetings | communication |
| `onboarding-aios` | Knows the whole AIOS map; walks you through it when lost | personal |
| `protocol-steward` | Governance, open-source strategy, licensing + trademark posture for open protocols/standards — lead without vendor-capture | strategy |
| `report-drafter` | Draft status reports and board updates | communication |
| `sales-crm-updater` | Sync deal updates to Monday/CRM | sales |
| `sales-lead-hunter` | Explore leads, qualify, score, draft outreach | sales |
| `sales-proposal-writer` | Draft proposals from project notes + catalog | sales |
| `security-engineer` | Threat modeling, secure-code review, incident response | engineering |
| `study-buddy` | Pre-read chapters, prepare briefs, facilitate study | personal |
| `technical-cofounder` | Build products end-to-end — discovery → shipping | engineering |

**By bundle:** see `agents/_index.md` for the canonical registry (6 bundles + `custom/`). Operator-built agents live at `agents/custom/{name}.md` and survive `/aios:update`. Company-distributed agents land at `agents/{company}/` via `/aios:company --sync`.

**Example:** `spawn lawyer "review NDA at ~/code/contracts/2026-03-mutual-nda.docx"` opens a new tab with the lawyer hat pre-loaded and the task primed as the first prompt.

**Killing a spawned worker:** `spawn-kill {name}` cleanly terminates the worker — atomic process-group kill + closes the Terminal window (macOS). Avoids the orphan-Claude + "terminate?" modal pitfalls of SIGTERM or Cmd+W. Both `spawn` and `spawn-kill` are installed by `hooks/claude-identity/install-wrappers.sh`.

---

## Skills

Skills auto-load — you don't invoke them by name. Describe what you want and Claude picks the right one. Each entry below shows the source folder so you know what ships out-of-box vs what comes from a marketplace plugin.

### Coding & engineering
| Skill | Source | Trigger phrase |
|---|---|---|
| `api-design-principles` | `skills/aios/` | "How should I shape this API?" |
| `architecture-patterns` | `skills/aios/` | "What architecture fits this problem?" |
| `database-migration` | `skills/aios/` | "Write a safe migration for this schema change" |
| `error-handling-patterns` | `skills/aios/` | "Where should I handle errors here?" |
| `karpathy-coding` | `skills/aios/` | "Follow Karpathy's principles" — think before coding, simplicity first, surgical changes |
| `python-best-practices` | `skills/aios/` | "Write idiomatic Python here" |
| `react-nextjs-patterns` | `skills/aios/` | "Build this Next.js / React feature" |
| `tailwind-design-system` | `skills/aios/` | "Style this with Tailwind tokens" |
| `prompt-engineering-patterns` | `skills/aios/` | "Improve this prompt" |
| `deep-research` | `skills/aios/` | "What should we write / build / do next?" — multi-source research that returns ranked what/why/how proposals |
| `orchestration-ladder` | `skills/aios/` | "Should this be one agent, a parallel fan-out, or a workflow?" |
| `systematic-debugging` | `skills/superpowers/` | "Help me debug this systematically" |
| `test-driven-development` | `skills/superpowers/` | "Let's write tests first" |
| `code-review-excellence` | marketplace plugin | "Review this code thoroughly" — install via `/plugin install code-review@claude-plugins-official` |

### Content & design
| Skill | Source | Trigger phrase |
|---|---|---|
| `algorithmic-art` | `skills/anthropic/` | "Generate code-based art / generative visuals" |
| `brand-guidelines` | `skills/anthropic/` | "Apply Anthropic brand styling" — for AIOS contributions |
| `canvas-design` | `document-skills` plugin | "Create a poster / visual design" |
| `claude-api` | `skills/anthropic/` | "Build a Claude API integration" |
| `doc-coauthoring` | `skills/anthropic/` | "Let's co-write this document" |
| `frontend-design` | `skills/anthropic/` | "Build a landing page / component / dashboard" |
| `internal-comms` | `skills/anthropic/` | "Draft a company-internal comms message (3P update, FAQ, etc.)" |
| `slack-gif-creator` | `skills/anthropic/` | "Make an animated GIF for Slack" |
| `theme-factory` | `skills/anthropic/` | "Apply a theme to this artifact / slide deck / doc" |
| `data-presentation` | `skills/aios/` | "How should I present this data?" — chart selection, table layout |
| `infographic-builder` | `skills/aios/` | "Make an infographic / one-pager / visualize this note or report" — themed self-contained HTML |

### Documents & files (all via Anthropic's `document-skills` plugin — `/plugin install`)
| Skill | Trigger phrase |
|---|---|
| `docx` | "Create a Word document" / "Edit this .docx" |
| `pdf` | "Create a PDF" / "Fill this PDF form" / "Merge these PDFs" |
| `pptx` | "Create a presentation" / "Edit these slides" |
| `xlsx` | "Create a spreadsheet" / "Analyze this Excel file" |

### Obsidian-specific
| Skill | Source | Trigger phrase |
|---|---|---|
| `json-canvas` | `skills/aios/` | "Create a visual canvas / diagram / map" |
| `obsidian-bases` | `skills/aios/` | "Create a Bases view for my projects" |
| `obsidian-cli` | `skills/aios/` | "Open this note in Obsidian" / "Run an Obsidian command" |
| `obsidian-markdown` | `skills/aios/` | "Write proper Obsidian markdown" — wikilinks, callouts, properties |
| `defuddle` | marketplace plugin | "Clean this web page into markdown" — install via Anthropic skills marketplace |

### Planning & process
| Skill | Source | Trigger phrase |
|---|---|---|
| `brainstorming` | `skills/superpowers/` | "Let's brainstorm before building" |
| `executing-plans` | `skills/superpowers/` | "Execute this plan with checkpoints" |
| `verification-before-completion` | `skills/superpowers/` | "Verify everything works before we ship" |
| `writing-plans` | `skills/superpowers/` | "Help me plan the implementation" |

### Meta / framework
| Skill | Source | Trigger phrase |
|---|---|---|
| `mcp-builder` | `skills/anthropic/` | "Build a new MCP server" |
| `skill-creator` | `skills/anthropic/` | "Create / edit a skill" / "Optimize a skill's description" |

### Compliance
| Skill | Source | Trigger phrase |
|---|---|---|
| `accessibility-compliance` | `skills/aios/` | "Check this for accessibility (WCAG, ARIA, contrast)" |
| `pci-compliance` | `skills/aios/` | "Audit this for PCI compliance" |

**Source folders:** `skills/aios/` (AIOS-built — 24 skills) · `skills/anthropic/` (vendored from `anthropics/skills` — 11 skills) · `skills/superpowers/` (vendored from `obra/superpowers` — 14 skills) · `skills/custom/` (your own — survives `/aios:update`). Total bundled: 49. Browse `skills/_index.md` for the full registry.

**Marketplace skills** (NOT in `skills/`, install via `/plugin install`): `canvas-design`/`docx`/`pdf`/`pptx`/`xlsx` (via `document-skills` plugin) · `code-review-excellence` (via `code-review@claude-plugins-official`) · `defuddle` (via Anthropic skills marketplace) · `superpowers` full marketplace (`obra/superpowers-marketplace`).

---

## MCPs

The 10 bundled MCP servers — each connects Claude to a real tool you use. Auto-connect via `~/.claude/settings.json` after you run `/aios:mcps-setup` (which walks token + register + verify per MCP).

| MCP | What it gives Claude | When you'd use it | Auth |
|---|---|---|---|
| **Google Workspace** | Calendar (read events), Tasks (read/write), Drive (read/write Docs/Sheets/Slides), Gmail (drafts + search), Contacts | Read by `/aios:today` + `/aios:close-day` for calendar + tasks; used by `deck-builder` agent for Slides composition | OAuth (your Google account) |
| **Slack** | DMs + channels: read, send, react, threads. Daily-recap pre-fetch for `/aios:today` + `/aios:close-day`'s Slack triage section | When `/today` surfaces unreads, when you draft messages via `email-drafter`-style agents, when ingest pulls Slack threads | OAuth (workspace per operator) |
| **GitHub** | Repos, issues, PRs, search, file contents, branch ops. Used by `code-reviewer`, `bug-triager`, `pr-review-toolkit` agents | Any code work touching repos you have access to | PAT (read+repo+workflow scopes typical) |
| **Atlassian** | Jira (issues, sprints, boards, transitions) + Confluence (pages, search, comments) | Engineering teams using Atlassian; integrates with project status surfacing in `/today` | API token |
| **NotebookLM** | Create notebooks, add sources, generate audio summaries + study guides + briefing docs. Full programmatic API beyond what NotebookLM UI exposes | Long-form research synthesis, podcast-style audio from your written corpus | Google OAuth |
| **Stitch** | AI-native UI screen generation from text prompts + DESIGN.md tokens. Apply design systems, create projects, list screens, edit. Pairs with `design-md-author` agent | UI/UX work where you want Claude to author DESIGN.md once then generate matching screens on demand | Google account (Stitch beta access) |
| **Playwright** | Browser automation: navigate, click, fill, screenshot, scrape. Use sparingly — heavy ops | Auto-publish flows (LinkedIn, X), end-to-end testing, scraping a site that has no API | None (browser binary) |
| **Nano Banana** | Gemini-based image generation. Cover images, illustrations, brand-fit visuals | Used by `deck-builder` for slide imagery; useful for any agent that needs custom visuals | Google API key |
| **PDF Generator** | Markdown → HTML (with inline CSS) → Chrome headless → PDF. Branded reports per design tokens | Powers `/aios:weekly-learnings`, `/aios:learned`, `/aios:role-report` branded exports | None (Chrome binary) |
| **Spotify DJ** | Playback control + search + current track + queue management | Lifestyle — no AIOS command depends on it. Music while you work, via Claude | OAuth |

**Setup pattern:** `/aios:mcps-setup` walks each MCP one at a time — "want this?", token capture, `claude mcp add` registration, smoke-test verification. Skip any MCP you don't use; they sit on disk until you change your mind. Per-MCP README at `mcps/{name}-mcp/README.md` has the auth specifics + advanced options.

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

### `inject-datetime` — UserPromptSubmit hook (real clock in every prompt)

Adds a `<system-time>` block to every user prompt before Claude reads it. Eliminates the "Claude infers wrong weekday/time from conversation history" failure mode — without this hook, Claude can drift on the actual day across long sessions, schedule on stale assumptions, or get the year wrong.

```bash
~/aios/hooks/inject-datetime.sh      # macOS / Linux (Git Bash on Windows too)
~/aios/hooks/inject-datetime.ps1     # PowerShell
```

You don't invoke this manually. It's wired into `~/.claude/settings.json` as a `UserPromptSubmit` hook (see SETUP.md §10 for the JSON snippet). Fires on every prompt you submit; load-bearing for any time-sensitive reasoning Claude does.

---

## Infrastructure map

Where everything lives:

| Folder | What's inside | How it's used |
|--------|--------------|---------------|
| `agents/` | Task agents in 6 bundles (`aios/sales/` · `aios/strategy/` · `aios/finance-legal/` · `aios/engineering/` · `aios/communication/` · `aios/personal/`) + `agents/custom/` (operator) + `agents/{company}/` (company-distributed) | Spawned via `spawn {name}` or invoked via `/aios:agent {name}` |
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
