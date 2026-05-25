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
