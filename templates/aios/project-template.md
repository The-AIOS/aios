---
tags:
  - project
  - template
created: '{{date}}'
updated: '{{date}}'
status: active
venture: []                    # array — e.g. [venture-a], [venture-b], [venture-a, venture-b]
stakeholders: []               # array — groups from venture's Stakeholders table
exempt-line-check: false       # true for catalogs, reference docs, and APPEND-ONLY LOGS
                               # (council logs, journals, baselines, diagnostic records) —
                               # growing IS them working; set it at creation, not after the
                               # line-check has cried wolf for a week
path: ''
stack: []
aliases: []
---
# {{title}}

## Current State

<!-- FIRST SECTION — always at the top so Claude and humans can instantly orient.
     This table is the PROJECT ROUTER — Claude reads it to know where everything lives.
     Every project uses this same table structure, whether coding or non-coding. -->

| Key | Value |
|---|---|
| Type | Coding / Non-coding / Hybrid |
| Code | `~/code/...` or N/A |
| Drive | `~/cowork/...` or N/A |
| GitHub | `https://github.com/...` or N/A |
| Team | `https://github.com/{your-org}/...` or N/A |
| CLAUDE.md | `~/code/.../CLAUDE.md` ✓/❌ or N/A |
| README | `~/code/.../README.md` ✓/❌ or N/A |
| Settings | `~/code/.../.claude/settings.json` ✓/❌ or N/A |
| Stack | ... or N/A |
| Status | Active / Archived / Idea |
| Venture | [[venture-a]], venture-b (links to venture folders) |
| Stakeholders | founders, sales-team (groups from venture Stakeholders table) |
| Orient | One sentence — what this is and what Claude should know first |

## Overview
<!-- Brief description of the project, its purpose, and who it serves -->

## Tech Stack
<!-- Key technologies, frameworks, and tools -->

## Architecture
<!-- Key folders, structure, and how things connect -->

## To-Dos

### High Priority
- [ ] 

### Normal
- [ ] 

### Ideas / Someday
- [ ] 

## Decisions Log
<!-- Important decisions, trade-offs, and rationale — newest first -->

| Date | Decision | Rationale |
|------|----------|-----------|

## Session Notes
<!-- Running log of work sessions — newest first -->

## Links
<!-- Related notes, external URLs, and references -->
