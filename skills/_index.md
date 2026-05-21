---
tags: [skills, index, ai-os]
created: '2026-03-20'
updated: '2026-05-21'
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
| [`skills/aios/`](./aios/) | AIOS-bundled skills (49) — domain-specific, design, engineering, security, finance, etc. | This framework | GPL-2.0-or-later |
| [`skills/superpowers/`](./superpowers/) | Core software-engineering workflows (14) — TDD, debugging, code review, plans, brainstorming, worktrees, subagent dispatching | [obra/superpowers](https://github.com/obra/superpowers) | MIT |
| [`skills/df-claude-skills/`](./df-claude-skills/) | Code-quality skills (2) — codebase audit, documentation expert | [fernandezdiegoh/df-claude-skills](https://github.com/fernandezdiegoh/df-claude-skills) | MIT |
| [`skills/custom/`](./custom/) | Your own skill extensions — survive `/aios:update` | Operator | Operator's choice |

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

## df-claude-skills (fernandezdiegoh/df-claude-skills)

| Skill | When to use |
|-------|-------------|
| `codebase-audit` | Full architecture / security / tech-debt audit |
| `documentation-expert` | Audit, create, and improve project documentation |

---

## AIOS-bundled (this framework)

49 skills across coding, design, engineering, security, finance, healthcare, and Obsidian-specific patterns. Browse `skills/aios/` for the full list.

Headline grouping:

**Engineering**
- `karpathy-coding` · `code-review-excellence` · `architecture-decision-records` · `architecture-patterns` · `api-design-principles` · `error-handling-patterns` · `git-advanced-workflows`
- `database-migration` · `python-{design-patterns,error-handling,project-structure,testing-patterns}` · `modern-javascript-patterns` · `next-best-practices` · `nextjs-app-router-patterns` · `react-state-management`

**Design**
- `frontend-design` · `design-system-patterns` · `visual-design-foundations` · `interaction-design` · `tailwind-design-system` · `responsive-design` · `accessibility-compliance` · `web-component-design` · `web-design-guidelines` · `data-storytelling` · `kpi-dashboard-design`

**Security**
- `sast-configuration` · `secrets-management` · `stride-analysis-patterns` · `security-requirement-extraction` · `threat-mitigation-mapping` · `pci-compliance`

**Finance / Strategy**
- `billing-automation` · `cost-optimization` · `competitive-landscape` · `market-sizing-analysis` · `startup-financial-modeling` · `startup-metrics-framework` · `risk-metrics-calculation` · `team-composition-analysis` · `employment-contract-templates`

**Obsidian / Content / Misc**
- `obsidian-markdown` · `obsidian-bases` · `obsidian-cli` · `json-canvas` · `defuddle` · `explain-code` · `prompt-engineering-patterns`

---

## Adding skills

**New AIOS-bundled skill** — drop into `skills/aios/<skill-name>/SKILL.md`, add to this index.

**Vendor a skill from a new upstream** — create `skills/<source-name>/`, copy the SKILL.md under it preserving attribution, add a new row to "Source folders" above with the upstream URL + license.

**Your own personal skill** — `skills/custom/<skill-name>/SKILL.md`. Survives `/aios:update`. Never gets overwritten.

---

## Upstream freshness

`/aios:housekeeping` includes a bucket that checks each upstream-sourced skill folder for new commits at the upstream repo. If updates exist, you get a summary of what changed and the choice to pull/cherry-pick.
