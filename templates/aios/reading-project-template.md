---
title: Reading — Study Protocol & Queue
tags:
  - project
  - personal
  - reading
  - study
  - knowledge
created: '{{YYYY-MM-DD}}'
updated: '{{YYYY-MM-DD}}'
status: active
aliases:
  - reading
  - reading-protocol
  - study-protocol
---
# 📚 Reading — Study Protocol & Queue

> *The AI reads the book so you don't have to. Every session produces actionable takeaways, not summaries — grown into one interactive Study Atlas per book.*

The knowledge-absorption engine: a weekly book-study loop run by the [[study-buddy]] agent. Per book, one **Study Atlas** — not a pile of files. This note is the **dashboard/router**; the folder index `reflections/books/_index` is the **file index** it points to.

> **Setup placeholders** — replace on scaffold: `{STUDY_DIR}` = your book folder (default `~/study/`); wire the 📚 reading routine into `USER.md → ### Growth routines → Reading` (Project = this note, Section = Reading Queue).

---

## Current State

| Field | Value |
|---|---|
| **Type** | Non-coding |
| **Drive** | `{STUDY_DIR}` (book PDFs — source of truth) |
| **Stack** | [[study-buddy]] agent · Obsidian (atlas + source) |
| **Status** | Active |
| **Orient** | Weekly book-study loop: study-buddy reads the source live, discussion shapes the atlas, the atlas grows per sitting, the queue advances; on completion the atlas *is* the synthesis. |

---

## The Library Pipeline (WIP = 5)

The focus constraint, named: **5 books "active" at once — read all 5, then bring 5 more.** A Kanban work-in-progress cap on reading — the antidote to a large backlog scattering attention.

**Three nested stages — all under `{STUDY_DIR}`:**

| Stage | Folder | Holds | Rule |
|---|---|---|---|
| **Active (top level)** | `{STUDY_DIR}` | **5 books** (the batch) | The WIP cap. Renamed to convention on promotion. |
| **Backlog** | `{STUDY_DIR}library/` | the unread shelf | "Pour" new books here, raw-named — no cataloguing burden, they wait. |
| **Read** | `{STUDY_DIR}read/` | completed | On completion, archive the finished PDF here (renamed). The vault folder keeps the atlas. |

**Replenishment — batch of 5 (not rolling):**
1. Study the active 5 to completion. As each book finishes → **archive its PDF** from the top level → `read/`.
2. When all 5 are read, **bring the next 5 up** from `library/` into the top level.
3. **Naming normalization happens on every library → top-level promotion**: rename each PDF to the convention + create its vault book folder + slug. *Then* study the new batch.

### Picking the next 5 — deepen + mutate

When the batch is read, study-buddy dives the library and proposes the next 5 — never at random, never all-coherent (the explore/exploit balance: a search with zero mutation rate gets stuck in a local optimum):

- **~3 deepen** — same vein as the batch just finished, *varied lenses* (different author / discipline / angle). Compounds context.
- **~1 bridge** — one step out: an adjacent domain.
- **≥1 mutation (hard floor — never zero)** — a deliberately *unrelated* book. The rule that guarantees expansion.

Refinements: **directed mutation > random** (aim the wildcard at a latent interest — a venture theme, an active growth edge — not pure noise); **mutations seed the next vein** (today's unrelated book is often tomorrow's cluster — track which ones *catch*); **the agent proposes with a one-line rationale per book, you curate** (approve/swap).

**Naming convention** (applied *on promotion*, not on intake):
- **PDF filename:** `{Title} — {Author} ({Year}).pdf` — title-first, em-dash separator, author surname(s), year in parens. Subtitle lives in the vault note, never the filename.
- **Vault book-slug** (folder + note names): kebab-case of the title, dropping a leading article unless ambiguous (`The Body Electric → body-electric`).
- **Why rename on promotion, not intake:** the backlog keeps whatever names books arrive with — zero up-front cataloguing. The clean name is created only for the ~5 you actually activate.

---

## Study Protocol

### The method — read it to me, unfiltered but engaging

study-buddy's job is to **read the chapter *to* you from the source — as if reading it aloud — faithfully, but more engaging than the page.** Not a summary, not a sanitized highlight reel. Transmit what the author actually says, in order, claims and evidence intact — then make it a conversation.

Non-negotiables of the method:
- **Source fidelity first.** Never improve, soften, or skip the parts that are weak, uncomfortable, or off-thesis. If a chapter is thin or wrong, you hear it *as the author wrote it*. Reading the source, not a digest, is what surfaces the real mind-opening.
- **Register-honest.** Keep the cool empirical floor and the hot rhetoric *distinct* as you go, so you feel where the author shows evidence vs. asks you to believe. Name the moment the floor changes.
- **Engaging, not flat.** Teach it — analogies, connections to your work/life, the occasional sharp aside. The source is the text; the *walk* + the growing atlas are the value.
- **Discussion-first, atlas-after.** Walk → react → discuss → THEN grow the atlas.

The one-line test: *"Did it feel like you heard the chapter, not a book report about it?"*

### How it works — the Study Atlas

Per book: one interactive `{slug}-atlas.html` (the experience) + a growing `{slug}-source.md` (the md spine) + `_index.md` (tracker). Per-chapter notes, the master note, the non-negotiables, and separate infographics all become *views* inside the atlas.

- **The 3 mains:** **Overview** (thesis + axioms + source/Drive links + how-we-read-it) · **Infographic** (the visual one-pager — hosts the generated hero diagram + full-richness visuals) · **Actionables** (concrete practices / lenses, each with cadence + why + where it routes).
- **Supporting:** a per-chapter **Reflections** group · **detail sections** (non-negotiables / plates) · a **Close (Verdict)** · a lifecycle **badge** (`✦ Complete` / `◔ In progress`).
- **Two modes:** *plate* (diagram-rich books — rebuild the plates; raw assets in `plates/`) · *argument* (prose books — generate the hero diagram the book never had, inside the Infographic).
- **Grows per sitting** — never a big-bang build: append the source, add/refine one plate-or-panel + the chapter's Reflection, route behavior-changing takeaways out.
- **Route insights out** — every atlas has a "what flows out to your OS" surface; behavior-changing takeaways route into your growth project / `growth.md` / observed context / the relevant skill. The atlas is never where they go to die.

### Study session flow

1. `/today` surfaces the next un-studied chapter (source PDF at `{STUDY_DIR}`).
2. study-buddy reads the chapter **from the source, with you** — faithful, engaging, register-honest; discuss + challenge as you go.
3. **Grow the atlas** (`reflections/books/{slug}/{slug}-atlas.html`): append the chapter to `{slug}-source.md`; add/refine the chapter's plate (plate mode) or panel (argument mode) in the **Infographic**; add its **Reflection** card; then route any behavior-changing takeaway out.
4. **Advance the Reading Queue** — mark studied, move "Next:" forward.
5. **Update the book `_index` Study Log** so `/today` + `/close-day` see the current position.
6. Mark the streak in the daily note.

### On book completion — the atlas *is* the synthesis

When the LAST chapter/part is studied, there are no separate deliverables to generate:

1. **The atlas already carries it all** — the non-negotiables, the generated hero diagram, the Actionables, and the route-insights-out surface all live inside. Flip the badge to `✦ Complete`; confirm every behavior-changing takeaway routed out.
2. **Folder to shape** — `_index` + `{slug}-atlas.html` + the md spine at top level; scaffolding (retrofits) in `archive/`, raw plates in `plates/`. Mark complete in `reflections/books/_index` + advance the queue.
3. **Archive the PDF** — move it from the top level → `read/`. Frees a slot; when all 5 are read, the next batch promotes up.

*(Retrofit rule: for a book studied before the atlas existed, **add** the atlas + **archive** its scaffolding — never delete history, wikilinks resolve by basename.)*

---

## Read (complete)

| Book | Author | Folder | Atlas | Non-negotiables |
|---|---|---|---|---|
| _(first completed book lands here)_ | | | | |

---

## Reading Queue

| # | Book | Author | Progress |
|---|------|--------|----------|
| 1 | _(your first book)_ | | ⏳ Next |

---

## See also

- [[study-buddy]] — the agent that runs this protocol
- `reflections/books/_index` — the per-book folder index
