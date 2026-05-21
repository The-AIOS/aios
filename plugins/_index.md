---
tags:
  - moc
  - plugins
  - index
created: '2026-03-30'
updated: '2026-03-30'
type: index
---
# Vault Plugins — Index

> Vault plugins extend Claude's capabilities with context, templates, scripts, skills, and commands.
> Each plugin lives in its own folder with a `manifest.md` at the root.
>
> **Path pattern:** `plugins/{plugin-name}/manifest.md`
>
> **Adding a plugin:** Create folder → add `manifest.md` with frontmatter → add content → update this index.

---

## Installed Plugins

| Plugin | Type | Description | Triggers |
|--------|------|-------------|----------|
| [[pdf-generator]]¹ | context | HTML→PDF generation pipeline (pandoc + Chrome headless) — venture-flavored example | pdf, branded document, sales template, html template |

¹ **`pdf-generator` is venture-flavored — currently bundled with Sovra branding (logos, product sheets for SovraGov / SovraID / SovraWallet / SovraChain).** It exists at the shared infrastructure layer for historical reasons, but the *content* (HTML templates, brand assets) is Sovra-specific. Teams using a different venture should fork it: copy `plugins/pdf-generator/` to `vault/00 - notes/context/ventures/{your-venture}/plugins/pdf-generator/` and rebrand. The pandoc + Chrome pipeline itself is generic; only the templates carry Sovra colors and product names. Future cleanup: relocate the Sovra-specific assets to `vault/00 - notes/context/ventures/sovra/plugins/pdf-generator/` and leave `plugins/pdf-generator/` as a generic template scaffold.

---

## Plugin Types

| Type | What it means |
|------|---------------|
| `context` | Claude reads docs/templates to know how to use the plugin (no code invocation) |
| `skill` | Contains `skills/{name}/SKILL.md` files that extend Claude's capabilities |
| `command` | Contains slash commands (may register in Claude Code marketplace) |
| `tool` | Provides executable scripts or binaries |
| `hybrid` | Mix of the above |

## Standard Structure

```
plugins/{plugin-name}/
├── manifest.md              ← REQUIRED: metadata (frontmatter) + usage
├── README.md                ← Optional: detailed documentation
├── skills/                  ← Optional: SKILL.md files
├── commands/                ← Optional: slash command .md files
├── scripts/                 ← Optional: executables
├── templates/               ← Optional: HTML/MD templates
├── assets/                  ← Optional: fonts, images, logos
└── ...                      ← Any plugin-specific content
```
