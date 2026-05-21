---
tags:
  - skills
  - custom
  - index
created: '2026-05-21'
updated: '2026-05-21'
---
# Custom Skills — Your Personal Registry

> Your custom skills. These survive `/aios:update` — bundled skills at the parent `skills/` folder get replaced, but `custom/` is yours.
>
> Create skills here following the [Agent Skills standard](https://github.com/anthropics/skills): one folder per skill with a `SKILL.md` containing YAML frontmatter (`name`, `description`) + markdown body of instructions. Optional: `scripts/`, `resources/`, `examples/` subfolders.

## Why custom?

If you create a skill with the same name as a bundled one, the matcher resolves `custom/` first. This is how you customize without forking — leave the bundled skill alone, write your own version in `custom/`, and Claude uses yours.

## Registry

<!-- Add a row when you create a new skill. -->

| Skill | Purpose | Status |
|-------|---------|--------|

