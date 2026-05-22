---
tags:
  - context
  - declared
  - index
  - MOC
created: '2026-03-05'
updated: '2026-03-27'
type: index
---
# Declared Context — Index

> What the vault owner explicitly tells Claude about themselves. This is the foundation of personalization — the more you declare, the better Claude understands your work.

---

## What Is Declared Context?

Declared context is information you write yourself. It tells Claude who you are, how you work, how you communicate, and what you're building. Unlike observed context (which Claude generates), declared context is authored and maintained by you.

These files are read at the start of every session. They shape how Claude responds, prioritizes, and communicates.

---

## Standard Files

| File | What it covers | Scope |
|------|---------------|-------|
| `about_me.md` | Identity, background, roles, values, what you're building | Personal |
| `personal_voice.md` | Communication style, tone, audience, writing preferences | Personal |
| `working_style.md` | How you think, make decisions, and prefer to work | Personal |
| `about_business.md` | Distilled overview of all ventures — points to `about_venture.md` in each venture folder | Updated when ventures are added or their overview changes |
| `role-expectations.md` | Professional role, pillars of responsibility, success signals | Personal |
| `psychometric-profile.md` | MBTI, Strengths, Saboteurs, Creative Type, Braverman — formal assessments | Personal |

**Note:** `about_business.md` is a high-level overview that summarizes all ventures. The detailed context lives in each venture's `about_venture.md` (see `ventures/`). Sources config (calendar, tasks, Slack, dev projects, growth routines) has moved to `USER.md` → `## Sources` at the vault root.

---

## How to Fill These In

Templates are available in `vault/02 - templates/`. For each file:

1. Copy the matching template (e.g., `about_me-template.md`) to this folder
2. Rename it by removing the `-template` suffix
3. Fill in the placeholders with your actual information
4. Remove any template instructions once complete

You do not need to fill everything at once. Start with `about_me.md` and `working_style.md` — those have the highest impact on session quality.

---

## Related

See [[README|context/README]] for the full context model (declared vs. observed vs. venture-level).
See `vault/00 - notes/context/observed/` for what Claude learns about you over time.
