---
tags:
  - context
  - meta
  - system
created: '2026-03-02'
updated: '2026-03-27'
---
# Context — How This Folder Works

This folder is your persistent context system, designed to ground every Claude session in who you are, what you're building, and what we're learning together.

---

## Structure

### Declared Context (`declared/`)
Written by you. These define identity, voice, working style, and business positioning.

| File                  | Purpose                                                              |
| --------------------- | -------------------------------------------------------------------- |
| [[about_me]]          | Who you are — identity, thesis, principles, bio                      |
| [[personal_voice]]       | How you sound — tone, audience calibration, templates                |
| [[working_style]]     | How you want Claude to behave — modes, protocols, output formats     |
| [[about_business]]    | Distilled overview of all ventures — points to `about_venture.md` per venture |
| [[role-expectations]] | Current role, pillars of responsibility, and what success looks like |

### Observed Context (`observed/`)
Written by Claude. These capture what Claude learns through working together — patterns, preferences, insights, growth edges. Updated continuously.

| File | Purpose |
|------|---------|
| [[profile]] | Claude's evolving description of you as a person |
| [[patterns]] | How you think, decide, communicate |
| [[preferences]] | Implicit choices observed through behavior |
| [[business]] | Learnings about your ventures and strategic dynamics |
| [[ecosystem]] | How ventures and life domains connect |
| [[growth]] | Honest observations in service of growth |
| [[session-insights]] | Running log of raw observations from sessions |

### Venture Deep Dives (`ventures/`)
Each venture has its own subfolder with an `about_venture.md` (required overview) plus deep-dive documents — market analysis, GTM, personas, positioning, pricing, primitives. The declared `about_business.md` distills all ventures into one file; the details live here. Add subfolders for additional ventures as needed.

---

## How It's Used

### Every session
1. **Load declared context** — read the root files to understand who you are and how to work with you
2. **Load observed context** — read `observed/` files to ground in accumulated learnings
3. **Load venture context** — if the session involves strategy, product, or market work, read relevant files from `ventures/`
4. **Work** — execute tasks with full context
5. **Update observed context** — capture new observations, patterns, or insights before session ends

### Project-specific context
Individual projects maintain their own context folders for project-specific knowledge and self-updates. This top-level context is about you as a person and across all ventures — not about any single project.

### The difference matters
- **Declared** = what you tell Claude about yourself (stable, foundational)
- **Observed** = what Claude learns through working together (evolving, reflective)
- **Venture deep dives** = deep reference material for specific ventures
- **Project-level** = scoped knowledge living inside each project's own context

---

## Principles
- Observed context is written with dignity and honesty
- You can read, correct, or challenge anything Claude writes
- Files are updated incrementally — never overwritten wholesale
- The system is designed for compounding understanding over time
