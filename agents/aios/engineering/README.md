# aios/engineering

> Building, growth, refactoring, code review, security, docs, triage. The "ship better software faster" bundle — it spans a product's whole life, from first prototype to maintenance at scale.

Install this bundle if you write code, ship products, or manage an engineering pipeline.

## Agents

Listed in **lifecycle order** — read top-to-bottom as a product's life.

| Agent | Stage · Archetype | What it does |
|---|---|---|
| [[technical-cofounder]] | Prototype → Build · *Prototyper / Builder* | Build real products end-to-end — discovery → planning → building → polish → handoff. Flagship for solo/founder operators (prototype mode pre-PMF, production mode after) |
| [[code-reviewer]] | Review & ship · *Sweeper / Maintainer* | Review PRs for security, quality, pattern consistency. Reads diffs, surfaces issues, suggests fixes |
| [[growth-engineer]] | Grow (find PMF) · *Grower* | Iterate a *shipped* product toward Product-Market Fit — instrument the funnel, find the leak, run prioritized growth experiments, decide ship/kill/iterate from evidence |
| [[refactor-engineer]] | Sweep / simplify · *Sweeper* | Proactively shrink a *mature* codebase — simplify tangled code, unship unused features, optimize measured hot paths. Behavior-preserving by default; evidence-driven |
| [[security-engineer]] | Maintain at scale · *Maintainer* | Application security — STRIDE threat modeling, SAST setup (Semgrep/SonarQube/CodeQL), secrets management, vulnerability triage with prioritized remediation backlog |
| [[bug-triager]] | Maintain at scale · *Maintainer* | Classify GitHub issues by severity, suggest priority + assignee. Run weekly to clear backlog drift |
| [[code-documenter]] | Maintain at scale · *Maintainer* | Generate/update README, CLAUDE.md, inline docs from code changes. Keeps docs in sync with shipped reality |

## Lifecycle playbook — compose by posture, not title

The roster above shows *who + when*; this is the **operational view** — how you actually invoke each stage and which skills fire (Boris Cherny's archetype framing — see the [[../../../skills/aios/team-archetypes/SKILL|team-archetypes skill]]). A product's needs change as it matures, so *which* agent you reach for depends on the **stage**, not the job title.

| Stage | Agent(s) | How you typically invoke | Skills that fire |
|---|---|---|---|
| **Prototype** (pre-PMF) | [[technical-cofounder]] *(prototype mode)* | `spawn technical-cofounder "prototype X — throwaway, fast"` | `brainstorming`, `using-git-worktrees`, `team-archetypes` |
| **Build to production** | [[technical-cofounder]], [[aios-builder]] | `spawn technical-cofounder "build X end-to-end"` | `writing-plans`→`executing-plans`→`subagent-driven-development`, `test-driven-development`, `architecture/api/error-patterns`, `verification-before-completion`, `finishing-a-development-branch` |
| **Review & ship** | [[code-reviewer]] | `/code-review`, or `spawn code-reviewer "review this PR"` | `requesting/receiving-code-review`, `systematic-debugging`, `verification-before-completion` |
| **Grow** (find PMF) | [[growth-engineer]] | `spawn growth-engineer "signups don't return — why?"` | `data-presentation`, `writing-plans`, `team-archetypes` |
| **Sweep / simplify** | [[refactor-engineer]] (+ [[code-reviewer]], `/simplify`) | `spawn refactor-engineer "simplify/unship/optimize X"`, or `/simplify` | `test-driven-development` (characterization), `systematic-debugging`, `using-git-worktrees`, `verification-before-completion`, `finishing-a-development-branch` |
| **Maintain at scale** | [[security-engineer]], [[bug-triager]], [[code-documenter]] | `spawn security-engineer …`, `spawn bug-triager …` (weekly), `spawn code-documenter …` | `systematic-debugging`, `verification-before-completion`, `pci-compliance`, `explain-code`, `obsidian-markdown` |

**How to use it:**
- **Name the stage, then pick the archetype.** A pre-PMF product wants Prototyper+Builder; a scaling one wants Sweeper+Grower+Maintainer. Staffing the wrong posture for the stage is the most common waste (e.g. polishing/maintaining a product that hasn't found fit).
- **Find an agent by posture:** the agents are tagged in [[../_index|the registry]] (`archetype: builder`, etc.), so `spawn maintainer …` or *"who's my Sweeper?"* resolves to the right one. (Tags are for *discovery*; the skill is the *reasoning lens* — two different mechanisms.)
- **Let the system check the mix for you:** `/7plan` flags when a week's planned work doesn't match a project's stage; `/emerge` surfaces a missing archetype as a new-agent suggestion. (Not `/today` — daily routing is tactical, stage→mix is strategic.)
- **Prototyper has no dedicated agent by design** — it's a *posture-mode* of `technical-cofounder`, because the capability already exists and only the disposition (throwaway, speed) differs. A thin archetype gets a posture-mode when the capability exists, a new agent only when it's genuinely absent (as Grower/Sweeper were). Archetype is a lens *on top of* the bundle — never a reason to rename or restructure agents.

> **Spec-driven dev:** AIOS covers the SDD loop natively via the `superpowers/` skills (`brainstorming` → `writing-plans` → `executing-plans`/`test-driven-development` → `verification-before-completion`). If you want repo-resident spec artifacts beside the code, [OpenSpec](https://github.com/Fission-AI/OpenSpec) (MIT) is a compatible external layer you can install per project — AIOS doesn't bundle it (it would duplicate superpowers).

## When to install

- You review PRs and want a structured first-pass
- Your docs drift from your code (and you want them to stop)
- You have a GitHub issue backlog that needs ongoing triage
- You're a solo founder/operator building products

## Dependencies

- **GitHub MCP** — for PRs, issues, file reads, branch ops
- **Bash** — for build/test/lint commands
- **Obsidian MCP** — for project note + decision log routing

See [[../_index|top-level agents registry]] for the full agent vocabulary.
