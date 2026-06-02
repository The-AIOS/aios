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

> *The AI reads the book so you don't have to. Every session produces actionable takeaways, not summaries.*

The knowledge-absorption engine: a weekly book-study loop run by the [[study-buddy]] agent, with a per-book output stack (briefs → master note → non-negotiables → infographics). This note is the **dashboard/router**; the folder index `reflections/books/_index` is the **file index** it points to.

> **Setup placeholders** — replace on scaffold: `{STUDY_DIR}` = your book folder (default `~/study/`); wire the 📚 reading routine into `USER.md → ### Growth routines → Reading` (Project = this note, Section = Reading Queue).

---

## Current State

| Field | Value |
|---|---|
| **Type** | Non-coding |
| **Drive** | `{STUDY_DIR}` (book PDFs — source of truth) |
| **Stack** | [[study-buddy]] agent · `infographic-builder` skill · Obsidian (briefs/notes) |
| **Status** | Active |
| **Orient** | Weekly book-study loop: study-buddy walks a brief, discussion shapes the master note, queue advances; on completion → non-negotiables + infographics. |

---

## The Library Pipeline (WIP = 5)

The focus constraint, named: **5 books "active" at once — read all 5, then bring 5 more.** A Kanban work-in-progress cap on reading — the antidote to a large backlog scattering attention.

**Three nested stages — all under `{STUDY_DIR}`:**

| Stage | Folder | Holds | Rule |
|---|---|---|---|
| **Active (top level)** | `{STUDY_DIR}` | **5 books** (the batch) | The WIP cap. Renamed to convention on promotion. Briefs kept pre-built for these. |
| **Backlog** | `{STUDY_DIR}library/` | the unread shelf | "Pour" new books here, raw-named — no cataloguing burden, they wait. |
| **Read** | `{STUDY_DIR}read/` | completed | On completion, archive the finished PDF here (renamed). The vault folder keeps the notes. |

**Replenishment — batch of 5 (not rolling):**
1. Study the active 5 to completion. As each book finishes → **archive its PDF** from the top level → `read/`.
2. When all 5 are read, **bring the next 5 up** from `library/` into the top level.
3. **Naming normalization happens on every library → top-level promotion**: rename each PDF to the convention + create its vault book folder + slug + queue brief-prep. *Then* study the new batch.

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

study-buddy's job is to **read the chapter *to* you — as if reading it aloud — faithfully, but more engaging than the page.** Not a summary, not a sanitized highlight reel. Transmit what the author actually says, in order, claims and evidence intact — then make it a conversation.

Non-negotiables of the method:
- **Source fidelity first.** Never improve, soften, or skip the parts that are weak, uncomfortable, or off-thesis. If a chapter is thin or wrong, you hear it *as the author wrote it*.
- **Register-honest.** Keep the cool empirical floor and the hot rhetoric *distinct* as you go, so you feel where the author shows evidence vs. asks you to believe. Name the moment the floor changes.
- **Engaging, not flat.** Teach it — analogies, connections to your work/life, the occasional sharp aside. The brief is the scaffold; the *walk* is the value.
- **Discussion-first, notes-after.** Walk → react → discuss → THEN write the master note.

The one-line test: *"Did it feel like you heard the chapter, not a book report about it?"*

### Study session flow

1. The brief is detected → linked in the study task.
2. Read the brief (~10–15 min).
3. Discussion — go deeper, challenge assumptions.
4. Update the **master study note** (`reflections/books/{slug}/{slug}-{author}.md`): "Do This" table + a `## Ch.N` section with key concepts, your assessment, connections, actions.
5. **Advance the Reading Queue** — mark studied, move "Next:" forward.
6. **Update the `_index.md` snapshot** so `/today` + `/close-day` see the current position.
7. Mark the streak in the daily note.

### On book completion (the closing stack)

When the LAST chapter/part is studied, study-buddy produces the book-level deliverables:

1. **Non-negotiables synthesis** — `reflections/books/{slug}/{slug}-non-negotiables.md`: the 5–7 rules that hold the whole book up + its "Secret Architecture." The compressed return-to.
2. **Folder hygiene** — folder `_index.md` collecting all artifacts; mark complete in `reflections/books/_index`; advance the queue.
3. **The visual layer — infographic(s)** via the `infographic-builder` skill: **(a)** an *argument* one-pager of the master note; **(b)** *if the book has personal-specific value*, a *personal* one applying the book's lens to your own context. Save HTML inside the book folder (`{YYYY-MM-DD}-{slug}.html`); link from the Read table.
4. **Archive the PDF** — move it from the top level → `read/`. Frees a slot; when all 5 are read, the next batch promotes up.

---

## Read (complete)

| Book | Author | Folder | Non-negotiables | Infographic(s) |
|---|---|---|---|---|
| _(first completed book lands here)_ | | | | |

---

## Reading Queue

| # | Book | Author | Progress |
|---|------|--------|----------|
| 1 | _(your first book)_ | | ⏳ Next — brief pending |

---

## See also

- [[study-buddy]] — the agent that runs this protocol
- `reflections/books/_index` — the per-book folder index
