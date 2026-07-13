---
tags:
  - roadmap
  - template
created: '{{date}}'
updated: '{{date}}'
type: roadmap                  # ← the truth-surface contract switch (CLAUDE.md § Ship-time truth-flip)
status: live                   # live | archived — archive ONLY with zero open keys (retirement checklist)
ledger: ''                     # optional — '[[CHANGELOG]]' wiki-link to a ship ledger; empty = the git commit IS the ledger
exempt-line-check: true
aliases: []
---
# {{title}} — the keyed roadmap

> **What this is:** the to-do SOURCE OF TRUTH for one big multi-project push — every open item on ONE prioritized surface, each with a **stable key**. Use this when a push spans several project notes and you need one view; for normal work, your project notes are already the truth surface and you don't need this file.
>
> **THE KEY SYSTEM.** Pick a short prefix per lane/family (2–4 caps — `grep` the vault first so prefixes don't collide with an existing roadmap). **Keys are identity; list order is priority** — reorder rows freely, never renumber a key; new items append at the lane's next `n`. This is how you, daily notes, and `/7plan` refer to the work — cite keys, never re-copy items.
>
> **THE ANTI-RE-DRIFT RULE (ship-time truth-flip — CLAUDE.md § Discipline).** The session that ships an item flips its key to ✅ here — and appends the `ledger:` row if one is declared — *in that same session*. `/close-day` reconciles as the backstop. Daily notes and weekly plans only reference keys; they never grow competing to-do lists.
>
> **Status taxonomy:** ✅ shipped · 🚧 in-progress · 🔵 pending · 🚩 blocked / needs-operator · ⏳ waiting-external · ⏸ parked · 🔵→ future/dated-later · ❌ killed.
>
> **Row format:** `KEY · status · what (one line) · owner · when/gate · → depth ref`
>
> **Dual-homed items:** a project-note to-do that also lives here cites its key inline (`- [ ] ship the thing (AB-3)`) so one grep connects both surfaces. This file owns DONE-vs-OPEN; the project note owns the how/why.
>
> **Retirement:** when the push completes, close every key (✅ / ❌ / re-homed to its project note), then flip `status: archived`. `/aios:housekeeping` (Bucket 23) flags violations.

## 🅰️ {Lane / family one} (AB)

- AB-1 · 🔵 · {what — one line} · {owner} · {when or gate} · → [[{project-note}]]
- AB-2 · 🔵 · {what} · {owner} · {when} · → [[{ref}]]

**Tail — ⏸ parked · 🔵→ future · ❌ killed:**
- ⏸ {parked item, with its re-open trigger}

## 🅱️ {Lane / family two} (CD)

- CD-1 · 🔵 · {what} · {owner} · {when} · → [[{ref}]]

## ⏳ Waiting-external — clocks you don't own

| Clock | Gates | Your ungated twin |
|---|---|---|
| {external event} | {which keys wait on it} | {what proceeds anyway} |

## 📆 Checkpoints — dated, falsifiable

- **{date}:** {what must be true} — *{pre-committed consequence if it isn't}*
