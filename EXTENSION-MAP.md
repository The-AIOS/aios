# EXTENSION-MAP — where every infra layer lives, resolves, and survives

> **Stopgap reference.** A single map of the three-layer model — **bundled** (`aios`/source), **custom** (operator), **company** (synced) — across all six infra types. It consolidates what `CLAUDE.md` (§ *Structure*, § *Hooks · Skills · Plugins*, § *Custom/ + company namespacing*) and `CONTRIBUTING.md` state in pieces. Interim until the model is formalized in `TOOLS.md`; when this and `CLAUDE.md` disagree, `CLAUDE.md` wins.

---

## The three layers

Every infra type has up to three provenance layers. They **compose**, never collide:

- **Bundled** — ships with the framework, authored in canonical (`The-AIOS/aios`), **overwritten by `/aios:update`**. Never hand-edit bundled infra in your vault; edits are authored in canonical and pulled.
- **Custom** — the operator's own extensions, in a `custom/` subfolder. **Survives `/aios:update`** and **overrides bundled** on name collision (most-specific-wins). This is where operator-built infra goes — *never* inside `aios/`.
- **Company** — infra a company distributes via `/aios:company --sync`, landing at a **`{company}`-namespaced** path. Private to mounters, licensed at the company's discretion (see `LICENSE-AUDIT.md` §4), never collides with `custom/` or bundled.

**Precedence on name collision:** `custom/` > bundled. Company infra is namespaced, so it never competes for a name. (The `spawn` wrapper warns on cross-bundle agent-name collisions.)

---

## The map (per infra type)

| Infra type | Bundled | Custom (operator) | Company (synced target) | Add via |
|---|---|---|---|---|
| **Agents** | `agents/aios/{sales,strategy,finance-legal,engineering,communication,personal}/` | `agents/custom/` | `agents/{company}/` | Copy `templates/aios/agent-template.md` → `{name}.md` into the bundle or `custom/`; update `agents/_index.md` |
| **Skills** | `skills/aios/` (+ vendored `skills/anthropic/`, `skills/superpowers/`) | `skills/custom/` | `skills/{company}/` | Folder with `SKILL.md`; register into `~/.claude/skills` via `skills/setup.sh`/`.ps1`; update `skills/_index.md` |
| **Hooks** | `hooks/` (flat: `claude-identity/`, pipeline `.py`, `markitdown-convert.py`, …) | `hooks/custom/` | `hooks/{company}/` | Add `.py`, document in `hooks/_index.md`, reference the path in `settings.json` |
| **MCPs** | `mcps/*-mcp/` (flat, `-mcp` suffix namespaces) | `mcps/custom/` | `mcps/{company}/` | Vendor in `mcps/{name}-mcp/` (README + auth), add block to `mcps/setup.sh`, register with `claude mcp add`, update `mcps/_index.md` |
| **Plugins** | `plugins/aios/` | `plugins/custom/<name>/` | `plugins/{company}/<plugin>/` | `plugins/custom/<name>/` with `.claude-plugin/plugin.json` + `commands/`; register in `.claude-plugin/marketplace.json` |
| **Templates** | `templates/aios/` | `templates/custom/` | `templates/{company}/` | Add `{name}-template.md`; update `templates/_index.md` |

**Layer folders confirmed present:** `agents/{aios,custom}`, `skills/{aios,anthropic,custom,superpowers}`, `hooks/{claude-identity,custom, …}`, `mcps/{*-mcp,custom}`, `plugins/{aios,custom}`, `templates/{aios,custom}`.

### Notes per type

- **Skills** carry a **source** dimension on top of the layer model: bundled skills are grouped by upstream origin (`aios/` = this framework, `anthropic/` = Apache-2.0 examples, `superpowers/` = MIT) so `/aios:housekeeping` Bucket 18 can check each source for updates. `custom/` and `{company}/` are still the operator/company layers.
- **Hooks** and **MCPs** are **flat** (no `aios/` subfolder) — the framework hooks/MCPs sit at the top level, and `custom/` (+ synced `{company}/`) are the only nested layers. `settings.json` / `~/.claude.json` reference hook and MCP paths directly.
- **Plugins** are the one type where the operator's own slash commands belong. To add `/my-stuff:my-command`, build `plugins/custom/my-stuff/` — **never** add a command inside `plugins/aios/`. Company plugins land at `plugins/{company}/<plugin>/`, each a self-contained bundle invoked as `/<plugin>:<name>`.
- **Commands** are not a separate top-level type — they live *inside* plugins. Editing a bundled `aios` command has a 3-location sync (source → marketplace → cache); see `CLAUDE.md` § Personalization. Operator command **behavior** is personalized in `USER.md` (never by editing command files).

---

## Company sync routing (how `{company}/` paths get populated)

`/aios:company --sync` walks each top-level infra folder in a company's `*-context` repo. For **non-empty** folders, content lands at `{infra-type}/{company}/` in the operator's vault (namespaced). The `context/` folder is the exception — it lands at the canonical venture path `vault/00 - notes/context/ventures/{company}/` (no `context/` prefix). An **empty** company folder (README placeholder only) ships nothing — companies opt into each infra type as needs evolve. Full behavior: `plugins/aios/commands/company.md` → *Optional company-distributed infra*.

---

## Survival across `/aios:update`

| Layer | `/aios:update` behavior |
|---|---|
| Bundled (`aios/`, vendored subtrees) | **Overwritten** to match canonical HEAD. Author changes in canonical, then pull. |
| Custom (`custom/`) | **Never touched.** Operator content is preserved. |
| Company (`{company}/`) | **Not touched by `/aios:update`** — refreshed only by `/aios:company --sync`. |

The rule of thumb: **if it's yours and you want it to survive, it lives in `custom/`.** If it's the framework's, it lives in the bundle and you don't hand-edit it locally.
