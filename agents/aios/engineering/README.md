# aios/engineering

> Code review, documentation, bug triage, building. The "ship better software faster" bundle.

Install this bundle if you write code, ship products, or manage an engineering pipeline.

## Agents

| Agent | What it does |
|---|---|
| [[code-reviewer]] | Review PRs for security, quality, pattern consistency. Reads diffs, surfaces issues, suggests fixes |
| [[code-documenter]] | Generate/update README, CLAUDE.md, inline docs from code changes. Keeps docs in sync with shipped reality |
| [[bug-triager]] | Classify GitHub issues by severity, suggest priority + assignee. Run weekly to clear backlog drift |
| [[security-engineer]] | Application security — STRIDE threat modeling, SAST setup (Semgrep/SonarQube/CodeQL), secrets management, vulnerability triage with prioritized remediation backlog |
| [[technical-cofounder]] | Build real products end-to-end — discovery → planning → building → polish → handoff. Flagship engineering agent for solo/founder operators |
| [[growth-engineer]] | Iterate a *shipped* product toward Product-Market Fit — instrument the funnel, find the leak, run prioritized growth experiments, decide ship/kill/iterate from evidence |

## Archetype lens (compose by posture, not title)

These agents are tagged with **product archetypes** (see the [[../../../skills/aios/team-archetypes/SKILL|team-archetypes skill]]) so you can ask *"who's my Builder / Maintainer?"* and so `/today`·`/7plan`·`/emerge` can check the mix matches a project's lifecycle stage. The bundle now spans the full build→grow→maintain lifecycle: **Prototyper** is a *mode* of [[technical-cofounder]] (pre-PMF); **Builder** = [[technical-cofounder]]/[[aios-builder]]; **Sweeper** = [[code-reviewer]] + `/simplify`; **Grower** = [[growth-engineer]] (PMF-iteration); **Maintainer** = [[security-engineer]]/[[bug-triager]]/[[code-documenter]]. Archetype is a lens *on top of* these agents, never a reason to rename or restructure them.

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
