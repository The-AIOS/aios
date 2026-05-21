# Migration map — Phase 0+1 source-to-destination

> **This document is the public face of the migration plan.** For internal context + deferred decisions + execution order, see the [authoritative reflection in chuy's personal vault](https://github.com/chuycepeda/obsidian/blob/main/vault/00%20-%20notes/reflections/2026-05-21-aios-migration-map.md).
>
> **Status:** scaffold landed 2026-05-21 (pre-Phase-0+1 execution). Actual migration commits land during Thu 2026-05-21 execution day per [deployment plan](deployment-plan.md).

## What moves here from chuy's vault

| Source path in `~/obsidian` | Destination in `The-AIOS/aios` |
|------------------------------|-------------------------------|
| `commands/` | `commands/` |
| `hooks/` | `hooks/` |
| `mcps/` | `mcps/` |
| `plugins/` | `plugins/` (core engine only — Sovra-flavored skin stays in company-scope) |
| `skills/` | `skills/` (excluding `sovra-web-design/` which is Sovra-specific) |
| `vault/02 - templates/` | `templates/` (top-level, promoted from vault/) |
| `vault/06 - agents/` (shared agents only — NOT `my-agents/`) | `agents/` (top-level, promoted from vault/) |
| `CLAUDE.md` | `CLAUDE.md` (after stripping chuy-specific examples) |
| `CHANGELOG.md` | `CHANGELOG.md` (with header note about pre-extraction history) |

## What does NOT move (stays in chuy's vault)

Everything personal: vault content (notes, projects, ideas, reflections, daily notes), USER.md, INTENT.md, SARAH.md, FORTRESS.md, observed memory, ventures context. See the full retention list in the [authoritative migration map](https://github.com/chuycepeda/obsidian/blob/main/vault/00%20-%20notes/reflections/2026-05-21-aios-migration-map.md).

## Phase 0 cleanup that lands BEFORE this repo is filled

To avoid migrating broken or Sovra-specific content:
1. Hardcoded `~/obsidian` paths → path-config-driven (17 surfaces; 13 commands + 4 hooks)
2. `com.sovra.claude-quota-watch.plist` → generic-named plist
3. `mcps/playwright-mcp/auth/*.json` → gitignored, removed from tracking
4. Sovra-flavored content (`ventures/sovra/`, `skills/sovra-web-design/`, sovra-branded `pdf-generator/` templates, `about_business.md` template, `vault/06 - agents/company-analyst.md`, `vault/.obsidian/snippets/sovra-colors.css`) → moves to company-scope, not product
5. Sovra mentions in shared docs/registries → genericized

## After this repo is filled

- `chuycepeda/obsidian` retains chuy's personal vault (vault/ + USER.md + addons/)
- `sovrahq/internal-vault` gets archived (its product-infra moved here; its company context folds into per-user `addons/` until/unless Zurda needs a separate company-scope repo)
- `/vault-update` tracker rewires to point at `The-AIOS/aios`
- First external clone validation: Zineb pulls latest, runs `/today`, reports
