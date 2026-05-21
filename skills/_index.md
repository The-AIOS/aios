---
tags: [skills, index, ai-os]
created: '2026-03-20'
updated: '2026-03-28'
---
# Skills — 60 Curated Skills

> Skills are specialized prompt files that extend Claude's capabilities. Each skill is a `SKILL.md` file in its own folder. Claude loads them when the task matches.
>
> **Path pattern:** `skills/{skill-name}/SKILL.md`

---

## Superpowers (Core Workflows)

| Skill | Description | When to use |
|-------|-------------|-------------|
| `brainstorming` | Explore intent, requirements, design before implementation | Before any creative work — features, components, functionality |
| `writing-plans` | Comprehensive implementation plans for multi-step tasks | Before touching code on non-trivial tasks |
| `executing-plans` | Execute plans with review checkpoints | Implementation sessions with batched review |
| `dispatching-parallel-agents` | One agent per independent problem domain | 2+ independent concurrent tasks |
| `subagent-driven-development` | Dispatch fresh subagent per task with two-stage review | Plans with independent tasks in current session |
| `test-driven-development` | Write test first, watch it fail, write minimal code | Before writing implementation code |
| `systematic-debugging` | Find root cause before fixes — no random patches | Before proposing fixes for any bug |
| `explain-code` | Explain code with visual diagrams and analogies | Teaching, onboarding, "how does this work?" |
| `requesting-code-review` | Dispatch code-reviewer subagent to catch issues | Before merging, after completing features |
| `receiving-code-review` | Process feedback with technical rigor, not blind agreement | When receiving review comments |
| `finishing-a-development-branch` | Guide merge/PR/cleanup decisions | When implementation is complete and tests pass |
| `verification-before-completion` | Run verification before claiming work is done | Before committing or creating PRs |
| `using-git-worktrees` | Isolated git worktrees with smart directory selection | Feature isolation, parallel work |
| `using-superpowers` | Discover and invoke available skills | Start of any conversation (meta-skill) |
| `writing-skills` | Create, edit, verify skills with TDD for process docs | Creating or editing skills |

## Strategy & Business

| Skill | Description | When to use |
|-------|-------------|-------------|
| `competitive-landscape` | Porter's Five Forces, Blue Ocean, positioning maps | Competitor analysis, market positioning |
| `market-sizing-analysis` | TAM/SAM/SOM using top-down, bottom-up, value theory | Market opportunity sizing, investor decks |
| `startup-financial-modeling` | 3-5 year financial projections, revenue models, scenario planning | Financial forecasts, burn rate, runway |
| `startup-metrics-framework` | SaaS metrics — MRR, ARR, CAC, LTV, burn multiple, Rule of 40 | Unit economics, investor reporting |
| `data-storytelling` | Transform data into narratives with setup→conflict→resolution | Executive presentations, data reports |
| `kpi-dashboard-design` | KPI selection, visualization patterns, strategic/tactical metrics | Business dashboards, metric design |
| `cost-optimization` | Cloud cost rightsizing, tagging, reserved instances | Reducing infrastructure costs |
| `team-composition-analysis` | Team structures, hiring plans, compensation, equity | Org design, hiring plans |
| `employment-contract-templates` | Employment contracts, offer letters, HR policies | Drafting agreements, HR |
| `billing-automation` | Recurring billing, invoicing, dunning, proration, tax | Subscription billing |
| `risk-metrics-calculation` | VaR, CVaR, Sharpe, Sortino, drawdown analysis | Portfolio risk, risk monitoring |

## Design & Frontend

| Skill | Description | When to use |
|-------|-------------|-------------|
| `frontend-design` | Production-grade frontend interfaces, avoids generic AI aesthetics | Web components, pages, applications |
| `tailwind-design-system` | Design systems with Tailwind CSS v4, tokens, component libraries | Component libraries, design standardization |
| `responsive-design` | Container queries, fluid typography, adaptive layouts | Building responsive interfaces |
| `interaction-design` | Microinteractions, motion, transitions, user feedback | UI polish, loading states, delightful UX |
| `visual-design-foundations` | Typography, color theory, spacing systems, iconography | Design tokens, style guides |
| `design-system-patterns` | Scalable design systems with tokens, theming, component arch | Theme switching, component libraries |
| `web-component-design` | React/Vue/Svelte component patterns, composition | UI component libraries |
| `web-design-guidelines` | Review UI code for Web Interface Guidelines compliance | UI review, UX review |
| `accessibility-compliance` | WCAG 2.2 compliance, ARIA patterns, assistive tech | Accessibility audits, inclusive UX |

## Engineering (General)

| Skill | Description | When to use |
|-------|-------------|-------------|
| `api-design-principles` | RESTful design, versioning, pagination, error handling | API design, endpoint planning |
| `architecture-decision-records` | Structured ADRs for architectural choices | Documenting technical decisions |
| `architecture-patterns` | Microservices, event-driven, CQRS, hexagonal | System design, architecture reviews |
| `code-review-excellence` | Structured code review with security, performance, patterns | Reviewing PRs, code quality |
| `codebase-audit` | Full codebase health assessment | Technical debt, architecture audit |
| `documentation-expert` | Technical writing, API docs, READMEs, runbooks | Writing or improving docs |
| `error-handling-patterns` | Error hierarchies, recovery, retry, circuit breakers | Robust error handling |
| `git-advanced-workflows` | Rebasing, cherry-picking, bisect, reflog recovery | Advanced git operations |
| `modern-javascript-patterns` | ES2024+, async patterns, modules, performance | Modern JS development |
| `prompt-engineering-patterns` | Structured prompting, chain-of-thought, few-shot | Better AI interactions |
| `database-migration` | Schema evolution, zero-downtime migrations, rollback | Database changes |
| `secrets-management` | Vault, env vars, rotation, CI/CD secrets | Secure credential handling |

## Python

| Skill | Description | When to use |
|-------|-------------|-------------|
| `python-design-patterns` | Factory, strategy, observer, decorator in Python | Python architecture |
| `python-testing-patterns` | Pytest, fixtures, mocking, property-based testing | Python test suites |
| `python-error-handling` | Exception hierarchies, context managers, retry patterns | Robust Python error handling |
| `python-project-structure` | Package layout, pyproject.toml, src layout | New Python projects |

## Next.js / React

| Skill | Description | When to use |
|-------|-------------|-------------|
| `next-best-practices` | App Router, server components, data fetching, caching | Next.js development |
| `nextjs-app-router-patterns` | Route groups, parallel routes, intercepting routes | Advanced Next.js routing |
| `react-state-management` | Context, Zustand, Jotai, server state patterns | React state architecture |

## Security

| Skill | Description | When to use |
|-------|-------------|-------------|
| `security-requirement-extraction` | STRIDE-based security requirements from specs | Security planning |
| `stride-analysis-patterns` | Threat modeling with STRIDE methodology | Threat analysis |
| `threat-mitigation-mapping` | Map threats to mitigations with coverage tracking | Security architecture |
| `sast-configuration` | Static analysis tool setup and tuning | Code security scanning |
| `pci-compliance` | PCI DSS requirements, SAQ selection, evidence | Payment compliance |

## Venture-flavored skills

| Skill | Description | When to use |
|-------|-------------|-------------|
| `sovra-web-design`¹ | Sovra brand tokens — colors, typography, sections, animations | Building or reviewing any sovra.io page |

¹ **`sovra-web-design` is venture-flavored — Sovra-specific brand tokens at the shared infrastructure layer.** Same pattern as `plugins/pdf-generator/` (see `plugins/_index.md`). Future cleanup: relocate to `vault/00 - notes/context/ventures/sovra/skills/sovra-web-design/` so the shared `skills/` folder stays venture-agnostic. Marked as TODO, not action this round — the relocation requires coordinated path updates wherever the skill is referenced.
