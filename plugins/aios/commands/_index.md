---
tags:
  - moc
  - aios
  - backup
  - index
created: 2026-03-02
updated: 2026-03-27
type: index
---
# Vault Commands — Index

> Source of truth for all 24 vault command files (this folder: `plugins/aios/commands/`). Synced to plugin marketplace + cache.
> Marketplace: `~/.claude/plugins/marketplaces/the-aios/plugins/aios/commands/`
> Cache: `~/.claude/plugins/cache/the-aios/aios/0.1.0/commands/`

---

## Daily

| Command | What it does |
|---------|-------------|
| [[today]] | Morning plan — reads vault, writes today's daily note |
| [[close-session]] | Lightweight session capture — wins, learnings, open threads |
| [[close-day]] | Evening capture — done, learned, unresolved, observed |

## Weekly

| Command              | What it does                                      |
| -------------------- | ------------------------------------------------- |
| [[7plan]]            | Weekly strategy across all ventures               |
| [[drift]]            | Avoidance detector — what's being quietly ignored |
| [[weekly-learnings]] | Consolidate week's daily notes into summary       |

## Bi-weekly

| Command | What it does |
|---------|-------------|
| [[graduate]] | Promote half-formed daily ideas to permanent notes |
| [[emerge]] | Surface patterns implied by the vault but never written |

## Monthly

| Command | What it does |
|---------|-------------|
| [[compact]] | Digest + zip previous month's snapshots and role logs |

## As needed

| Command          | What it does                                                                     |
| ---------------- | -------------------------------------------------------------------------------- |
| [[ideas]]        | Grounded idea report — tools, content, connections                               |
| [[ghost]]        | Answer a question in the owner's voice                                           |
| [[challenge]]    | Steel-man your current thinking                                                  |
| [[trace]]        | Track how an idea evolved over time                                              |
| [[connect]]      | Find cross-domain bridges in the vault                                           |
| [[learned]]      | Distill insights into publish-ready content                                      |
| [[housekeeping]] | Vault housekeeping — 12 buckets: link/index repair, merges + archival, carry cleanup, table trim, INTENT drift, antifragile compact, plugin-cache verify, permissions audit |
| [[role-report]]  | Quarterly role report per pillars in role-expectations.md                        |
| [[company]]      | Mount/sync company context (multi-substrate, multi-company; reads USER.md `## Companies (mounted)`). Subcommands: `--create`, `--mount`, `--sync`, `--sync-all`, `--status`, `--invite`, `--dry-run` |
| [[cold-start-interview]] | First-touch interview after you clone AIOS — walks identity, declared context, INTENT.md, bundle install choices, MCP setup, optional Anthropic plugins, first /today |
| [[update]] | Pull latest framework infrastructure from upstream and auto-apply (commands, templates, agents, skills, hooks) |
| [[mcps-setup]]   | Guided MCP setup — walks you through tokens + zshrc + register + verify |
| [[ingest]]       | Process a source (PDF, URL, doc) into the vault — extract, file, cross-reference, log |
| [[agent]]        | Load an agent's expertise into the current session (temporary hat) or list agents |
| [[collaborate]]  | Scaffold a shared Collaboration Space (collab folder + first project) on Drive/GitHub/local. Subcommands: `--add-project`, `--status`, `--dry-run`. Substrate-pluggable; pure-mirror local routers; option-2 preservation on re-mount |

---

**See also:** [[vault-routine]] · [[context/observed/_index|Observed Context]]
