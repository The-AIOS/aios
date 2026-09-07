---
tags:
  - aios
  - template
  - grammar
description: 'The vault structure grammar — one consistent answer to "where does retired content go, what do folders get named, and what does a rename owe the graph." Read by /aios:housekeeping (Bucket 21) as its structure checklist.'
---

# Vault Grammar — structure rules that keep retrieval working

> **What this is.** A vault stays useful only while *finding things stays cheap*. These rules give every session — and every operator — one consistent answer to the three questions that otherwise get answered differently each time: where does retired content go, what do folders get named, and what does a rename owe the rest of the graph. `/aios:housekeeping` (Bucket 21) audits against this file; the File Placement Router (CLAUDE.md § IV) routes *new* files, this grammar governs how existing structure *evolves*.
>
> **What this is not.** Not a mandate to restructure a working vault. The grammar is applied **forward** (new archives, new renames, new folders) and surfaced as *proposals* when housekeeping finds drift — never auto-applied. A vault that deliberately diverges can; the point is that divergence be a decision, not an accident.

---

## 1 · The two species — record vs lifecycle

Every folder under `00 - notes/` holds one of two species, and the retirement rule differs by species. Misclassifying is the root cause of most structure drift.

| Species | What it holds | Retirement rule |
|---|---|---|
| **Record** | Files that ARE the record — each one a finished capture (an audit, an ingest, a book's notes, a research capture, a symposium log) | **No archive subfolder, ever.** A record never retires — it just gets older. Date-stamped filenames carry the timeline; the folder stays flat (topic subfolders allowed, § 3). |
| **Lifecycle** | Files with an open/closed state — dashboards and working surfaces (projects, roadmaps, briefs, plans) | Retired items move to **`_archived/`** inside the same folder, with the frontmatter in § 4. |

**The test:** *does this file's usefulness end?* A project note ends (shipped, killed, superseded) → lifecycle. An audit's findings stay evidence forever → record. When a folder seems to need `done/` or `archive/`, first ask whether its files are records — if they are, the folder needs nothing.

## 2 · Reserved names — the underscore family

`_`-prefixed names are **system surfaces**, one meaning each, never repurposed:

- **`_index.md`** — the folder's self-documentation (what lives here, what each file is). Every indexed folder has exactly one; update it when files are added/renamed/removed.
- **`_archived/`** — THE name for retired lifecycle content. Not `archive/`, not `done/`, not `old/`, not `{folder}-archive/`. One name means one grep (`ls */_archived/`) finds every retirement shelf in the vault.
- **`_inbox/`** — a *provisional* landing zone (unrouted spawned-worker output, pending filing). Normally empty; housekeeping empties it. **An empty `_inbox/` is healthy, not noise** — it is the safety net that keeps unrouted output from inventing its own home.
- **`_system/`, `_components/`** — machine-read assets serving the folder (templates, shared parts).

Anything else `_`-prefixed should justify itself the same way: a surface the *system* reads, not a topic.

## 3 · Folder naming

- **Plain-noun, species-named folders** — `audits/`, `briefs/`, `decks/` — never dates in folder names (`audits-2026-07/` ✗). Date-stamped *filenames* carry time; a dated folder freezes a moving species and breeds a sibling next quarter.
- **Topic subfolders inside record species are fine** (rule of 3, per the Router) — but only when the topic answers a retrieval question the filenames don't already answer. Eight files that all share a date prefix don't need a subfolder restating the date.
- **One home per species.** When the same species accumulates in two places (e.g. specs both at a folder root and inside a sibling), merge to one — two homes mean every search must know which one to check.

## 4 · Retiring a note (lifecycle species)

Retirement is a checklist, not a move:

1. **Move** the file to the sibling `_archived/` folder.
2. **Frontmatter:** set `status: archived`; add `superseded-by: "[[successor]]"` when a successor exists (the pointer is what makes the archive navigable instead of a graveyard).
3. **Open items survive the note, never die with it.** Before archiving a dashboard, re-home every still-open task/key to its successor surface (the replacing note, the roadmap row, the project to-do). An archived note with live obligations inside is the silent-loss failure mode.
4. **Indexes:** update the folder's `_index.md` (and any board/registry that listed the note).

## 5 · Renames and moves owe the graph

Wiki-links resolve by **basename**, so the graph survives folder moves for free — but renames and deletions are breaking changes:

- **Every rename leaves `aliases:`** — add the old name to the note's `aliases:` frontmatter so historical `[[old-name]]` links keep resolving. Zero-cost insurance; skipping it orphans every inbound link silently.
- **High-traffic basenames get a redirect stub.** When a heavily-linked note is dissolved or split (dozens+ of inbound links), leave a stub at the old basename pointing to the successor(s), rather than editing every referrer.
- **Check basename collisions before moving.** Two files sharing a basename make `[[name]]` ambiguous — resolve the collision (rename one, with aliases) before the move, not after readers hit the wrong note.
- **Bulk moves are migrations.** Anything beyond a handful of files follows the `vault-migrations` skill: dry-run, inventory verification, then write.

## 6 · Consistency beats local optimality

A locally-clever structure (`done/` here, `archive/` there, `_archived/` elsewhere) taxes every future search with "which convention does *this* folder use?" When in doubt, match the vault's existing pattern — and when the pattern itself is wrong, change it *everywhere* in one migration, not one folder at a time.

---

## The housekeeping checklist (what Bucket 21 verifies)

- [ ] No `archive/`, `done/`, `old/` variants where `_archived/` is the grammar (§ 2)
- [ ] No archive subfolders inside record species (§ 1)
- [ ] No date-suffixed folder names (§ 3)
- [ ] Archived notes carry `status: archived` (+ `superseded-by:` where a successor exists) and no still-open obligations (§ 4)
- [ ] Renamed notes carry `aliases:` for their former names (§ 5)
- [ ] No basename collisions among linked notes (§ 5)
- [ ] Each species has one home; `_index.md` files reflect current contents (§ 3, § 4)
