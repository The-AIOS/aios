---
name: team-archetypes
description: Compose a team (of people OR agents) by lifecycle posture, not job title, using the five product archetypes — Prototyper, Builder, Sweeper, Grower, Maintainer — and the rule that a healthy mix depends on product stage. Use when deciding which agents/people to deploy on a project, diagnosing why a team or agent bundle feels lopsided (all builders, no maintainers), choosing what posture to take on a given piece of work, staffing a pre-PMF vs growing vs mature product, or selecting an agent mix in /today, /7plan, /emerge. The team-composition complement to leverage-points: leverage-points says WHERE to intervene; this says WITH WHAT POSTURE.
---

# Team Archetypes — compose by posture, not by title

As engineering, product, design, and DS melt into a new kind of role, the durable unit of a team isn't the job function — it's the **posture** someone takes toward the work at a given stage. Boris Cherny (Claude Code) named five archetypes that recur across every function: the same person can be a Prototyper on one project and a Maintainer on another; a designer, an engineer, and a PM can each be any of the five. This skill is a lens for **composing a team — of humans OR of AIOS agents — by archetype, matched to product stage.**

## The five archetypes

| # | Archetype | What they do | Posture |
|---|---|---|---|
| 1 | **Prototyper** | Churns out brand-new ideas; most don't ship | Generative, throwaway-tolerant, speed over polish |
| 2 | **Builder** | Turns a prototype/idea into production-grade product/infra | Hardening, end-to-end ownership |
| 3 | **Sweeper** | Simplifies code/systems, unships, optimizes, cleans UI | Subtractive, entropy-fighting |
| 4 | **Grower** | Iterates a *built* product to improve Product-Market Fit | Experiment-driven, metric-chasing |
| 5 | **Maintainer** | Owns a mature system: secure, reliable, fast, efficient at scale | Stewardship, operational rigor |

Most people (and most good agents) span **2–3** of these. Archetype is **not** tied to job function — it's a disposition toward the work.

## The core move — match the mix to the stage

A healthy team needs a *mix*, and the right mix depends on where the product is:

| Product stage | Archetype mix it needs |
|---|---|
| **New / pre-PMF** | strong **1 + 2 + 3** (prototype, build, keep it simple) |
| **Growing / found PMF** | **2 + 3 + 4** + some **5** |
| **Strong PMF / scaling** | **3 + 4 + 5** + some **2** |

When you staff or compose for a project, **name the stage first, then assemble the matching mix.** A pre-PMF product staffed entirely with Maintainers will stall; a scaling product full of Prototypers will thrash.

## The reframe that prevents the category error

**Archetype is orthogonal to capability.** Capability = *what* someone/an agent can do (review code, threat-model, research a market). Archetype = *how/when* they deploy it, matched to stage. The two **multiply** — they don't collapse.

- Don't rename your roles/agents to the five archetypes. That fuses two independent axes and destroys the capability information (a "Prototyper" *of what*?).
- Instead, **tag** each role/agent with the archetype(s) its posture can serve (1-to-many), and let the *same* unit shift posture by stage.

## Applying it to AIOS agents

AIOS bundles agents by **domain** (sales / strategy / engineering / …). Archetype is the **orthogonal posture layer** on top. The engineering bundle maps roughly:

| Archetype | AIOS agent(s) | Posture-mode notes |
|---|---|---|
| Prototyper | `technical-cofounder` *(prototype mode)* | Throwaway-churn posture pre-PMF — explicitly *not* production-grade |
| Builder | `technical-cofounder`, `aios-builder` | Production-grade, end-to-end |
| Sweeper | `refactor-engineer` (+ `code-reviewer`, `/simplify` skill) | Simplify, unship, optimize — proactive entropy reduction on a mature codebase |
| Grower | `growth-engineer` | PMF-iteration on a *shipped* product — funnel, activation, retention, experiments |
| Maintainer | `security-engineer`, `bug-triager`, `code-documenter` | Reliability, security, docs-in-sync |

**Coverage read:** the engineering bundle now spans the full **build → grow → maintain** lifecycle. **Prototyper** is the one archetype with no dedicated agent — by design: it's a *posture-mode* of `technical-cofounder` (pre-PMF churn), not a missing capability. The rule it illustrates: fill a thin archetype with a posture-mode when the capability already exists, and a new agent only when a genuine capability is absent (as `growth-engineer` was) — never with a bundle restructure.

## Three use-sites

1. **Agent/team selection** (`/today`, `/7plan`, `/emerge`): for each active project, name its stage, then check the deployed mix matches — and flag the gap if it doesn't.
2. **Posture self-location** (an agent reading this skill): a builder agent on a *pre-PMF* project takes the **Prototyper** posture (churn, throwaway, speed); on a *scaling* project, the **Builder/Maintainer** posture (hardening, rigor). Same agent, stage-appropriate posture.
3. **Project staging:** tag each project (Active / Idea) with a lifecycle stage so the mix-check has an input.

## Guardrails

- **Don't restructure bundles around archetypes.** Domain bundling works; archetype is a lens layered on top, not a replacement. Restructuring is churn against a taxonomy that already works.
- **Don't manufacture five agents per domain.** 5 archetypes × N domains is an explosion that re-buries the capability axis. Tag, don't multiply.
- **A thin archetype = a capability question, not a naming question.** "We have no Grower" means "we lack PMF-iteration capability," addressed via `/emerge` → a new *capability* agent — not by relabeling an existing one.

## Relationship to the rest of the system

Companion to `leverage-points` (where to intervene) and `sustainable-cadence` (at what pace). Worldview-neutral team science, like Meadows/Ostrom — it belongs to the invariant core, not a working-style template. Source: [Boris Cherny on product-role archetypes](references/cherny-archetypes-source.md).
