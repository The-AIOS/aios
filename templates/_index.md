---
tags:
  - templates
  - index
  - MOC
created: '2026-03-05'
updated: '2026-06-02'
type: index
---
# Templates — Index

> Starter templates for vault files. Copy to the target folder, rename, and fill in the placeholders.
>
> **Bundled templates live in `templates/aios/`** (e.g. `templates/aios/about_me-template.md`) — matching the `{layer}/aios/` + `custom/` + `<company>/` convention used by agents, skills, and plugins. Operator-authored templates go in `templates/custom/`; company-distributed ones land in `templates/<company>/` via `/aios:company --sync`. The `[[wiki-links]]` below resolve by filename regardless of folder.

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
| [[psychometric-profile-template]] | `vault/00 - notes/context/declared/psychometric-profile.md` | **Optional but high-leverage** — assessment-based self-knowledge (MBTI / Strengths / Saboteurs / Neurochemistry / etc.). Even 1-2 lenses + a synthesis paragraph dramatically calibrate the AI's voice, framing, and nudges. |
| [[about_venture-template]] | `vault/00 - notes/context/ventures/{venture}/about_venture.md` | Venture overview — one-liner, category, thesis, products, traction |

### Operational

| Template | Target location | What it creates |
|----------|----------------|----------------|
| [[project-template]] | `vault/00 - notes/projects/{project}.md` | Active project tracking note |
| [[reading-project-template]] | `vault/00 - notes/projects/{name}-reading.md` | Book-study system — the method, WIP-5 library pipeline, naming convention, per-book output stack (briefs → master note → non-negotiables → infographics). Scaffolded by the [[study-buddy]] agent when no reading protocol exists. |
| [[role-log-template]] | `vault/00 - notes/logs/role-logs/{date}.md` | Daily role activity log |
| [[meeting-prep-template]] | `vault/03 - export/meetings/{YYYY-MM-DD}-{slug}-prep.md` | High-stakes meeting prep — disambiguation, two-path flow (demo vs discovery), materials checklist, post-call routing |
| [[agent-template]] | `agents/custom/{name}.md` | Specialized task agent — purpose, tools, instructions, constraints |
| [[roadmap-template]] | anywhere in `vault/` (e.g. `00 - notes/reflections/{push}/roadmap.md`) | **Opt-in** keyed roadmap for a big multi-project push — one prioritized truth surface with stable keys; wired to the ship-time truth-flip contract (CLAUDE.md § Discipline) via `type: roadmap` frontmatter |

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
