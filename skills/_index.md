---
tags: [skills, index, ai-os]
created: '2026-03-20'
updated: '2026-06-30'
---
# Skills — Source-grouped Registry

> Skills are specialized prompt files (`SKILL.md` in their own folder) that extend Claude's capabilities. Claude loads them when the task matches the skill's description.
>
> **Path pattern:** `skills/<source>/<skill-name>/SKILL.md`
>
> Skills are grouped by their upstream origin so `/aios:housekeeping` can check each source for updates, and operators can see at a glance which skills came from where.

---

## Source folders

| Folder | What | Upstream | License |
|---|---|---|---|
| [`skills/aios/`](./aios/) | AIOS-bundled skills (20) — high-signal coding/Obsidian/meta/systems after the 2026-05-21 audit. See "What got pruned" below for what was removed. | This framework | GPL-2.0-or-later |
| [`skills/anthropic/`](./anthropic/) | Anthropic's example skills (11) — skill-creator, claude-api, mcp-builder, frontend-design, theme-factory, doc-coauthoring, internal-comms, web-artifacts-builder, webapp-testing, algorithmic-art, slack-gif-creator | [anthropics/skills](https://github.com/anthropics/skills) | Apache-2.0 |
| [`skills/superpowers/`](./superpowers/) | Core software-engineering workflows (14) — TDD, debugging, code review, plans, brainstorming, worktrees, subagent dispatching | [obra/superpowers](https://github.com/obra/superpowers) | MIT |
| [`skills/custom/`](./custom/) | Your own skill extensions — survive `/aios:update` | Operator | Operator's choice |

> **Note on skills available via Anthropic's plugin route** — operators get these via Claude Code's plugin marketplace: `claude plugin install document-skills@anthropic-agent-skills` (already enabled in this framework's default `~/.claude/settings.json`):
>
> - **`docx`, `pdf`, `pptx`, `xlsx`** — *not* vendored here because Anthropic ships them under a proprietary license that prohibits redistribution.
> - **`canvas-design`** — Apache 2.0 but ships with 5.5 MB of curated fonts (81 font files for poster/design variety). Not bundled by us to keep the framework lean (would have added ~29% to repo size); operators who need it get full quality via the plugin.

---

## Anthropic (anthropics/skills)

Apache-2.0 licensed example skills from Anthropic's official repo. Covers creative work, document authoring, MCP development, and meta-skills (creating skills, building Claude API apps).

| Skill | When to use |
|-------|-------------|
| `skill-creator` | Building new skills from scratch, editing existing skills, running evals |
| `claude-api` | Building/debugging/optimizing apps that use the Claude API or Anthropic SDK |
| `mcp-builder` | Creating high-quality MCP servers in Python (FastMCP) or Node/TypeScript |
| `frontend-design` | Distinctive, production-grade frontend interfaces that avoid generic AI aesthetics |
| `theme-factory` | Apply themed colors/fonts to artifacts (slides, docs, landing pages) |
| `doc-coauthoring` | Structured workflow for co-authoring documentation with users |
| `internal-comms` | Status reports, leadership updates, FAQs, incident reports — company-standard formats |
| `web-artifacts-builder` | Elaborate multi-component claude.ai HTML artifacts (React, Tailwind, shadcn/ui) |
| `webapp-testing` | Local web app testing via Playwright — UI verification, debugging, screenshots |
| `algorithmic-art` | p5.js generative art with seeded randomness |
| `slack-gif-creator` | Animated GIFs optimized for Slack (under size limits) |

---

## Superpowers (obra/superpowers)

Core software-engineering disciplines. Many of these reference each other (e.g., `requesting-code-review` dispatches via `subagent-driven-development`).

| Skill | When to use |
|-------|-------------|
| `brainstorming` | Before any creative work — features, components, functionality |
| `writing-plans` | Before touching code on multi-step tasks |
| `executing-plans` | Implementation sessions with batched review |
| `dispatching-parallel-agents` | 2+ independent concurrent tasks |
| `subagent-driven-development` | Plans with independent tasks in current session |
| `test-driven-development` | Before writing implementation code |
| `systematic-debugging` | Before proposing fixes for any bug |
| `requesting-code-review` | Before merging, after completing features |
| `receiving-code-review` | When receiving review comments |
| `finishing-a-development-branch` | When implementation is complete and tests pass |
| `verification-before-completion` | Before committing or creating PRs |
| `using-git-worktrees` | Feature isolation, parallel work |
| `using-superpowers` | Established at session start — how to find/use skills |
| `writing-skills` | Creating new skills or modifying existing ones |

---

## AIOS-bundled (this framework)

20 high-signal skills, post-2026-05-21 pruning. The bundle targets *load-bearing operator workflows* — daily reference + Obsidian power-user + meta + systems/stewardship — not generic technical reference (that's Claude's training).

**Coding & API**
- `karpathy-coding` — behavioral rules for any coding session (think before, simplicity, surgical changes)
- `architecture-patterns` — Clean / Hexagonal / DDD when designing systems
- `api-design-principles` — REST + GraphQL design
- `error-handling-patterns` — error design across languages
- `database-migration` — zero-downtime migration patterns

**Stack-specific consolidated**
- `python-best-practices` — design patterns + error handling + project structure + pytest, with deep references
- `react-nextjs-patterns` — App Router + RSC + state management, with deep references
- `tailwind-design-system` — Tailwind v4 system patterns

**Obsidian (vault power-user)**
- `obsidian-markdown` — wikilinks, embeds, callouts, properties
- `obsidian-bases` — `.base` files with views, filters, formulas
- `obsidian-cli` — read/write/search via CLI
- `json-canvas` — `.canvas` files with nodes/edges/groups

**Meta**
- `prompt-engineering-patterns` — production LLM prompting
- `data-presentation` — storytelling + dashboard design (consolidated)
- `infographic-builder` — turn a structured doc (ingest, role report, weekly learnings) into a self-contained HTML one-pager; brand-first theming with [VoltAgent/awesome-design-md](https://github.com/VoltAgent/awesome-design-md) as the fallback library

**Systems & stewardship**
- `leverage-points` — Meadows' lens for *where* to intervene in a system (the systems-science backing for "fix the system, not the symptom")
- `sustainable-cadence` — operator capacity/pace as a design input; tells paced work apart from avoidance (generative complement to the anti-values)
- `commons-governance` — Ostrom's commons design principles applied to shared vaults, collab spaces, company sync, and multi-agent repos
- `team-archetypes` — Cherny's five product archetypes (Prototyper/Builder/Sweeper/Grower/Maintainer); compose a team or agent fleet by lifecycle posture matched to product stage

**Compliance**
- `accessibility-compliance` — WCAG 2.2 audits
- `pci-compliance` — payment-card data handling

## What got pruned (2026-05-21)

26 skills removed in one sweep — they were either zero-value (CLI wrappers like `defuddle`), generic web content Claude already knows (`modern-javascript-patterns`, `git-advanced-workflows`, ADR docs), duplicates of upstream sources (`interaction-design`, `visual-design-foundations`, `web-component-design`, `responsive-design`, `design-system-patterns` — anthropic/frontend-design + canvas-design + theme-factory cover these), or framework-shaped knowledge better invoked through agents (`competitive-landscape`, `market-sizing-analysis`, `startup-financial-modeling`, `risk-metrics-calculation`, etc. — Porter's Five Forces and SaaS metrics are training knowledge, not opinion). Removed:

`defuddle` · `explain-code` · `web-design-guidelines` · `code-review-excellence` (superpowers covers) · `git-advanced-workflows` · `modern-javascript-patterns` · `architecture-decision-records` · `interaction-design` · `visual-design-foundations` · `design-system-patterns` · `web-component-design` · `responsive-design` · `competitive-landscape` · `market-sizing-analysis` · `startup-financial-modeling` · `startup-metrics-framework` · `risk-metrics-calculation` · `billing-automation` · `cost-optimization` · `team-composition-analysis` · `employment-contract-templates` · `sast-configuration` · `secrets-management` · `security-requirement-extraction` · `stride-analysis-patterns` · `threat-mitigation-mapping`

Their content lives in git history if anything needs to come back. 9 others (python-*, next/react-*, data-*) folded into 3 consolidated meta-skills with `references/*.md` preserving deep content.

---

## Adding skills

**New AIOS-bundled skill** — drop into `skills/aios/<skill-name>/SKILL.md`, add to this index.

**Vendor a skill from a new upstream** — create `skills/<source-name>/`, copy the SKILL.md under it preserving attribution, add a new row to "Source folders" above with the upstream URL + license.

**Your own personal skill** — `skills/custom/<skill-name>/SKILL.md`. Survives `/aios:update`. Never gets overwritten.

---

## Upstream freshness

`/aios:housekeeping` includes a bucket that checks each upstream-sourced skill folder for new commits at the upstream repo. If updates exist, you get a summary of what changed and the choice to pull/cherry-pick.
