---
tags:
  - agents
  - index
  - moc
created: '2026-05-21'
updated: '2026-05-21'
---
# Agents — Top-Level Registry

> Specialized task agents that spawn as sessions, execute with loaded instructions, and call close-session when done. Not persistent identities — they receive tasks, ship, report back.

Organized into **6 bundles by purpose**. Install only the bundles you need.

---

## Bundles

| Bundle | Purpose | Count |
|---|---|---|
| **`aios/sales/`** | Lead generation, proposals, CRM, brand monitoring | 4 |
| **`aios/strategy/`** | Market research, advisory, company analysis | 3 |
| **`aios/finance-legal/`** | Accounting, legal review, invoicing, compliance | 4 |
| **`aios/engineering/`** | Code review, documentation, bug triage, security, building | 6 |
| **`aios/communication/`** | Content, decks, emails, meeting prep, reports, design systems | 7 |
| **`aios/personal/`** | Study, journaling, growth, decision-making, onboarding, crisis | 6 |
| **`custom/`** | Your own agents (operator-specific extensions, never synced) | — |

**Total bundled agents: 30.** Each bundle has a `README.md` describing its scope; this file is the master registry.

> **Standard:** all agents follow the [Agent Skills open standard](https://github.com/anthropics/skills) (138K⭐ — Anthropic's public canonical repo). Cross-platform compatible with Claude Code, Codex, Gemini CLI, Cursor, Antigravity.

---

## How agents work

1. **Define:** Create an agent file from [[agent-template]] in the relevant bundle subfolder (or `custom/` for your own).
2. **Match:** `/today` reads this index, matches tasks to agents by keywords/domain.
3. **Spawn:** `spawn {name}` opens a new terminal and launches a session with the agent's instructions loaded.
4. **Execute:** Agent does the work with its specified tools.
5. **Close:** Agent calls `/close-session` — writes what it did, what's unresolved.
6. **Report:** `/close-day` picks up the session report and routes it.

---

## Agent matching

When a session starts with a name that doesn't have an exact match, the spawn wrapper + CLAUDE.md perform **glob + fuzzy matching:**

1. **Exact match** → `agents/**/{name}.md` glob — first match wins. Both bundle agents and `custom/` agents resolve.
   - Conflict rule: if two bundles ship an agent with the same name, the wrapper warns and lists matches. `custom/` always takes precedence over bundled (operator overrides).
2. **Semantic match** → scan this registry table (and `custom/_index.md` if it exists). Compare session name against agent names, purposes, domains, and match keywords. Pick the closest match if confidence is high.
   - `bookkeeper` → matches [[accountant]] (finance domain, bookkeeping keywords)
   - `contract-reviewer` → matches [[lawyer]] (legal domain, contract/NDA keywords)
   - `strategist` → matches [[consultant]] (strategy domain, advisory keywords)
3. **No match** → general-purpose worker with session name as role context.

When a fuzzy match is used, the session tells the user which agent was matched and why, so they can correct if wrong.

---

## Agent vs Session

| | Agent | Persistent session |
|---|---|---|
| Identity | Task-specialized, temporary | Named identity, personal |
| Lifecycle | Spawn → execute → close-session | Runs continuously |
| Free will | Executes assigned tasks only | Autonomous decisions |
| Scheduling | Can be scheduled (cron/recurring) | Always-on or manual |
| Example | lead-gen, code-reviewer, content-writer | Primary sessions (e.g. `buddai`, `sarah`) |

---

## Registry (all bundles, all agents)

<!-- /today reads this table to match tasks to agents. -->

### aios/sales/ — Lead generation, proposals, CRM, brand

| Agent | Purpose | Match keywords | Schedule |
|---|---|---|---|
| [[sales-lead-hunter]] | Explore leads, qualify, score, draft outreach emails | lead, prospect, outreach, qualify, pipeline, hunt | on-demand |
| [[sales-proposal-writer]] | Draft proposals from project notes + the user's consulting catalog | proposal, quote, offer, pitch, engagement letter | on-demand |
| [[sales-crm-updater]] | Sync deal updates to Monday/CRM from meeting notes | CRM, Monday, deal update, pipeline sync | on-demand |
| [[brand-monitor]] | Track mentions, competitors, industry news | brand mentions, competitor check, industry news, market scan | weekly (Monday) |

### aios/strategy/ — Research, advisory, deep dives

| Agent | Purpose | Match keywords | Schedule |
|---|---|---|---|
| [[market-researcher]] | Deep 11-section McKinsey-style market intelligence | market research, TAM, competitive landscape, market sizing | on-demand |
| [[consultant]] | Strategic advisory, frameworks, business analysis | consulting, strategy, advisory, framework, recommendation | on-demand |
| [[company-analyst]] | Acquired-style deep dives — history, strategy, moat, playbook | company analysis, acquired, deep dive, moat, 7 powers | on-demand |
| [[protocol-steward]] | Governance + open-source + licensing + trademark for an open protocol/standard — lead technically without being perceived as owner (avoid vendor-capture) | governance, open-source, license, Apache, MIT, consortium, foundation, steering committee, trademark, vendor-capture, protocol, standard, CLA | on-demand |

### aios/finance-legal/ — Accounting, legal, invoicing, compliance

| Agent | Purpose | Match keywords | Schedule |
|---|---|---|---|
| [[accountant]] | Financial analysis, bookkeeping, tax prep, cash flow | accounting, taxes, bookkeeping, cash flow, P&L, fiscal | on-demand |
| [[lawyer]] | Legal review, contract analysis, risk assessment | legal, contract, NDA, terms, liability, IP, trademark | on-demand |
| [[invoice-tracker]] | Track pending invoices, flag overdue, draft follow-ups | invoice, payment, overdue, billing, factura, cobro | on-demand |
| [[compliance-checker]] | Review documents against legal/regulatory requirements | compliance, contract review, NDA, regulatory | on-demand |

### aios/engineering/ — Code, build, ship

| Agent | Purpose | Match keywords | Schedule |
|---|---|---|---|
| [[code-reviewer]] | Review PRs for security, quality, pattern consistency | review PR, code review, diff review | on-demand |
| [[code-documenter]] | Generate/update README, CLAUDE.md, inline docs | update docs, document code, sync docs | on-demand |
| [[bug-triager]] | Classify GitHub issues, suggest priority + assignee | triage issues, classify bugs, bug triage, issue backlog | on-demand / weekly |
| [[security-engineer]] | STRIDE threat modeling, SAST setup, secrets management, vulnerability triage with prioritized remediation | threat model, STRIDE, SAST, semgrep, sonarqube, codeql, security review, secrets management, vault, vulnerability scan, CVSS, security audit | on-demand / quarterly |
| [[technical-cofounder]] | Build real products end-to-end — discovery → ship → handoff | build app, build product, MVP, prototype, ship, launch | on-demand |
| [[aios-builder]] | Scaffold a new custom AIOS element (agent/skill/plugin/command/template/hook/MCP) — compliant structure + registration | new agent, new skill, new plugin, new command, new template, new hook, new MCP, scaffold custom, add custom element | on-demand |

### aios/communication/ — Content, decks, emails, meetings, design

| Agent | Purpose | Match keywords | Schedule |
|---|---|---|---|
| [[content-writer]] | Draft posts for LinkedIn, Twitter/X, Substack in the user's voice | draft post, write article, LinkedIn, tweet, Substack | on-demand |
| [[content-scheduler]] | Plan and queue content calendar from vault insights | content calendar, schedule posts, publishing plan | weekly (Monday) |
| [[email-drafter]] | Draft professional emails matching voice + context | email, draft email, follow up, outreach, reply to | on-demand |
| [[deck-builder]] | Build presentations end-to-end via 6-phase AIOS process | deck, presentation, slides, keynote, pitch, investor | on-demand |
| [[meeting-prepper]] | Prepare context-rich briefings for upcoming meetings | meeting, prep, briefing, talking points, agenda | on-demand |
| [[report-drafter]] | Draft status reports and board updates from vault activity | status report, board update, weekly report, progress | on-demand |
| [[design-md-author]] | Author design.md per Google's spec; interview + validate + optional Stitch upload | design system, design.md, brand identity, design tokens | on-demand |

### aios/personal/ — Growth, study, journaling, decisions, onboarding

| Agent | Purpose | Match keywords | Schedule |
|---|---|---|---|
| [[study-buddy]] | Pre-read chapters, prepare briefs, facilitate study sessions | study, chapter, book, learning session | on-demand |
| [[journal-prompter]] | Generate reflection prompts from sessions + patterns | reflect, journal, prompts, introspection | on-demand |
| [[growth-companion]] | Listen + witness + surface growth from observed context. Anti-sycophancy. | vent, frustrated, stuck, heavy day, growth check | on-demand |
| [[onboarding-aios]] | Standing AIOS orientation companion — knows the org/repo/CHEATSHEET/FORTRESS/USER.md map, self-update loop, semantic invocation for "lost" moments | I'm lost, where do I start, what is this, how does this work, what should I try next, what am I missing, onboarding, getting started, day N, compound effect, AIOS guide | on-demand (anytime) |
| [[decision-journaler]] | Proactive Decision Journal — inversion + pre-mortem + tradeoff scoring | decision, deciding, dilemma, weighing, pre-mortem | on-demand |
| [[crisis-mode]] | Heavy-day emergency handler — stabilize, triage, sequence response, route to specialist, bridge to growth-companion when stable | emergency, crisis, urgent, panic, fire, breach, lawsuit, threat | on-demand |

---

## Custom agents

Operator-specific extensions live in [[custom/_index|`custom/`]]. They survive `/aios:update` — bundled agents at the bundle subfolders get replaced, but `custom/` is yours.

Create custom agents from [[agent-template]]. They work exactly like bundled agents — `/agent`, `spawn`, scheduling, fuzzy matching — all supported.

Run `/emerge` to get agent suggestions based on your observed patterns.

---

## Adding a new bundled agent

1. Decide which bundle it belongs in (see bundle README.md files for scope)
2. Create the agent file from [[agent-template]] in that bundle subfolder
3. **Declare relevant skills** — if a registered skill (`skills/` → `~/.claude/skills` via `bash skills/setup.sh`) supplies methodology the prompt doesn't already encode, name it in the agent's `## Skills` section. Only where it genuinely adds — don't bolt generic skills onto a self-contained agent (it dilutes). Skills auto-load by description; naming them is a reliability nudge.
4. Add a row to the matching bundle table above
5. Test: `spawn {name} "test task"` → should resolve via glob match

If creating a new bundle (rare):
1. Create the bundle folder `agents/aios-{name}/`
2. Write `agents/aios-{name}/README.md` (one-paragraph scope + agent list)
3. Add a row to the **Bundles** table above
4. Update CLAUDE.md if the bundle changes spawn/matching logic
