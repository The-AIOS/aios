---
tags:
  - logs
  - index
  - MOC
created: '2026-03-05'
updated: '2026-03-05'
type: index
---
# Logs — Index

> Activity logs and context snapshots, organized in monthly subfolders. These preserve the evolution of work and observations over time.

---

## What Lives Here

Two types of logs, both organized by month (`{YYYY-MM}/`):

### `observed-snapshots/`

Archived versions of observed context files. Before Claude edits any file in `context/observed/`, the previous version is copied here first. This creates a timeline of how observations evolve.

- **Naming convention:** `{YYYY-MM-DD}-{filename}.md` (e.g., `2026-03-05-patterns.md`)
- **Purpose:** Preserves the full history of observed context. Feeds the `/aios:trace` and `/aios:drift` commands, which analyze how thinking and patterns have shifted over time.
- **Created by:** Claude, automatically during the session end ritual before updating observed files.

### `role-logs/`

Daily work activity organized by role pillars. These capture what was accomplished in a day, broken down by area of responsibility.

- **Naming convention:** `{YYYY-MM-DD}-{filename}.md` (e.g., `2026-03-05-role-log.md`)
- **Purpose:** Structured record of daily work output. Feeds the `/aios:role-report` command for quarterly performance summaries.
- **Created by:** `/aios:close-day` when the day's work maps to role pillars defined in `declared/role-expectations.md`.

---

## Folder Structure

```
logs/
├── observed-snapshots/
│   ├── 2026-03/
│   │   ├── 2026-03-01-patterns.md
│   │   ├── 2026-03-01-session-insights.md
│   │   └── ...
│   └── {YYYY-MM}/
└── role-logs/
    ├── 2026-03/
    │   ├── 2026-03-01-role-log.md
    │   └── ...
    └── {YYYY-MM}/
```

Monthly subfolders are created as needed. Do not pre-create empty months.

---

## Related

See `vault/00 - notes/context/observed/` for the live observed context files these snapshots archive.
See `vault/00 - notes/context/declared/role-expectations.md` for the role pillars that structure role logs.
