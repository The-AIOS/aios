---
tags:
  - templates
  - index
  - MOC
created: '2026-03-05'
updated: '2026-05-09'
type: index
---
# Templates — Index

> Starter templates for vault files. Copy to the target folder, rename, and fill in the placeholders.

---

## What Lives Here

Templates for the standard files used across the vault. Each template includes structure, placeholder text, and guidance on what to write. They exist so new vault owners (or team members setting up their own vault) can get started quickly.

---

## Current Templates

### Identity & context (declared context)

| Template | Target location | What it creates |
|----------|----------------|----------------|
| [[about_me-template]] | `vault/00 - notes/context/declared/about_me.md` | Identity, background, roles, and values |
| [[about_business-template]] | `vault/00 - notes/context/declared/about_business.md` | Ventures, products, team, and strategy |
| [[personal_voice-template]] | `vault/00 - notes/context/declared/personal_voice.md` | Communication style, tone, and audience |
| [[working_style-template]] | `vault/00 - notes/context/declared/working_style.md` | Decision-making, preferences, and rhythms |
| [[role-expectations-template]] | `vault/00 - notes/context/declared/role-expectations.md` | Professional role, pillars, and success signals |
| [[about_venture-template]] | `vault/00 - notes/context/ventures/{venture}/about_venture.md` | Venture overview — one-liner, category, thesis, products, traction |

### Operational

| Template | Target location | What it creates |
|----------|----------------|----------------|
| [[project-template]] | `vault/00 - notes/projects/{project}.md` | Active project tracking note |
| [[role-log-template]] | `vault/00 - notes/logs/role-logs/{date}.md` | Daily role activity log |
| [[meeting-prep-template]] | `vault/03 - export/meetings/{YYYY-MM-DD}-{slug}-prep.md` | High-stakes meeting prep — disambiguation, two-path flow (demo vs discovery), materials checklist, post-call routing |
| [[agent-template]] | `agents/custom/{name}.md` | Specialized task agent — purpose, tools, instructions, constraints |

### Operator extensions

- `custom/` — your own templates (survive `/aios:update`). Documented in `custom/_index.md`.

### Retired / migrated

- `sources-template.md` — replaced by USER.md `## Sources` section
- `session-reporting-template.md` — replaced by `/close-session` (the command IS the report)
- `thinker-reflection-template.md` + `symposium-reflection-template.md` — Philosopher-Oracle templates; operator-specific, now live in operator-vault `templates/custom/` (not bundled)

---

## How to Use

1. Copy the template to the target location listed above
2. Rename the file by removing the `-template` suffix
3. Fill in the placeholders (marked with `{curly braces}` or instructional text)
4. Remove any template instructions once complete

Templates are reference starting points. Adapt the structure to fit your needs — the goal is useful context, not rigid formatting.

---

## Related

See `vault/00 - notes/context/declared/` for the files these templates create.
See `vault/00 - notes/projects/` for active project notes.
