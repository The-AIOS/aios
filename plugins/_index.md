---
tags:
  - moc
  - plugins
  - index
created: '2026-03-30'
updated: '2026-05-21'
type: index
---
# Plugins — Index

> Claude Code plugins distributed via the `the-aios` marketplace. Each plugin has its own folder under `plugins/<name>/`, with a `.claude-plugin/plugin.json` manifest.

---

## Bundled plugins (ship with the framework)

| Plugin | Source | Description |
|--------|--------|-------------|
| [[aios]] | `plugins/aios/` | The 24 `/aios:*` slash commands — daily ritual, strategic reviews, insight mining, accountability, multi-company mounting |

---

## Operator extensions

The `custom/` subfolder is for operator-built plugins that should survive `/aios:update`:

- `plugins/custom/<your-plugin>/` — your own plugin, never overwritten by framework updates

---

## Company-namespaced plugins

Plugins distributed by `/aios:company --sync` from a company venture-context repo land at:

- `plugins/<company>/<plugin-name>/` — e.g., `plugins/sovra/pdf-generator/` for a Sovra-branded plugin

Same namespacing convention as `agents/<company>/`, `templates/<company>/`, etc. Company-distributed plugins never collide with the bundled `aios` plugin or operator `custom/` extensions.

---

## Plugin structure

Standard Claude Code plugin layout (matches Anthropic's `claude-plugins-official` convention):

```
plugins/<plugin-name>/
├── .claude-plugin/
│   └── plugin.json          ← REQUIRED: name, version, description, author
├── commands/                ← Optional: slash command .md files
│   └── <cmd>.md
├── agents/                  ← Optional: plugin-scoped task agents
├── skills/                  ← Optional: plugin-scoped skills
├── hooks/                   ← Optional: plugin-scoped hooks
├── .mcp.json                ← Optional: plugin-scoped MCP servers
├── CLAUDE.md                ← Optional: plugin-specific instructions
└── README.md                ← Optional: human-readable docs
```

**Plugin-scoped vs framework-level:** Plugins ship their *own* agents/skills/hooks/MCPs that only activate when the plugin is loaded. The framework-level layers at repo root (`agents/`, `skills/`, `hooks/`, `mcps/`, `templates/`) are *shared resources* available across all sessions, regardless of which plugin is active.

---

## Adding a new plugin

1. Create `plugins/<name>/` folder with `.claude-plugin/plugin.json`
2. Add `commands/<cmd>.md` files (or `agents/`, `skills/`, etc.)
3. Register in `.claude-plugin/marketplace.json` at repo root: `{"name": "<name>", "displayName": "...", "source": "./plugins/<name>", ...}`
4. Update this `_index.md`
5. Sync to runtime cache: `claude plugin update <name>@the-aios`
