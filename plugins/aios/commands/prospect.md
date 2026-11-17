---
tags:
  - aios
  - command
  - on-demand
description: Mine the vault for opportunities nobody has named yet (business, products, offerings) with a blind multi-lens sweep, then rank and argue them
allowed-tools: mcp__obsidian__*, Read, Grep, Glob, Agent, Write, Bash(ls *), Bash(cd ~/aios && ~/aios/hooks/vault/aios-commit:*)
---

# /prospect: Opportunity Prospector

You are mining the operator's own vault for **latent value**: the businesses, products, offerings and plays the accumulated context already implies but nobody has named. You return a short, ranked, argued menu. **You surface and argue; you never commit.** Which candidate becomes a project or an offering is the operator's strategic call.

## When to use

As needed, roughly monthly or quarterly, and best right after a burst: a launch, a conference, a run of client calls, the end of a quarter, or when the operator senses value they cannot name. It mines *accumulated* context, so run daily it finds nothing new.

**Neighbors (complementary, non-overlapping):**

| Command | Surfaces |
|---|---|
| `/emerge` | behavioral *patterns* (how you work) |
| `/connect` | note-to-note *links* |
| `/drift` | *avoidance* |
| **`/prospect`** | latent *opportunities* (business / product / offering value) |

**Partner agent:** `lead-generator` works outward (it finds buyers for an offering that already has a name); `/prospect` works inward (it finds offerings that do not have one yet). The run ends by offering the hand-off.

## Why it is shaped this way

Four lenses run as **independent subagents that cannot see each other**. Diversity is the mechanism: a lens that has read another lens's findings converges on them, and the sweep collapses into one angle repeated four times. Per the `orchestration-ladder` skill this is **rung 2 (parallel agents) as background subagents**: the four lenses are independent, share no state, and their results must come back to this session for synthesis. The critic and the synthesis depend on the lenses, so they run after them, in order. It stays a coordinating session, not a dynamic workflow: the pipeline is three short stages and the synthesis is judgment this session has to hold. An operator who runs it often enough to want it deterministic can encode the same stages as a workflow; the contract below does not change.

## Steps

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /prospect` for any user overrides (extra lenses, surfaces to add or skip, a different output folder). Also read `INTENT.md` (if it exists): anything in "Explicitly NOT doing" was decided against, and is never surfaced as an opportunity.

All paths are relative to the vault root (`vault/`).

### 0. Readiness gate

List `00 - notes/projects/`, `00 - notes/ideas/`, `00 - notes/context/ventures/` and the daily notes under `01 - calendar/`. If together they hold too little to mine (a freshly cloned vault: a handful of daily notes, no ventures, setup-era projects only), say so in one line and stop. A sweep over an empty vault invents opportunities, and an invented opportunity is worse than none.

A vault past the gate but small enough that every lens will end up reading all of it still runs, but the lenses cannot stay apart by surface there, so their convergence means less. Mark the report header `small vault: lenses overlapped` and weigh convergence lightly in step 4.

### 1. Build the known set (this session, before any lens runs)

The known set is what the sweep must **not** re-surface. Build it once; every lens receives the same copy.

- **Named work:** `00 - notes/projects/_index.md` plus the title and one-line orient of every project note (active, maintenance *and* archived: an archived project is a known decision, not a seed, unless a lens can say what changed since).
- **Decided against:** INTENT.md "Explicitly NOT doing".
- **Already surfaced:** every earlier run in `00 - notes/reflections/prospects/`. A candidate an earlier run surfaced comes back only with *new* evidence, and says what is new.
- **Graduated ideas:** `00 - notes/ideas/_index.md` entries marked as promoted to a project.

**Seeds are not the known set.** An unpromoted note in `00 - notes/ideas/` is written down but not *named work*: it is the raw material of lens 4, and any lens may return it, provided the candidate cites the seed and says what changed since it was shelved. Do not list seeds in the known set, or lens 4 is told to ignore the only surface it has.

Write the known set as a plain list of names with one line each. Keep it short: it is an exclusion list, not context.

**Hold back the thesis.** Read `00 - notes/context/declared/about_business.md`, `00 - notes/context/observed/business.md` and, if present, the `## Compass` section of `00 - notes/context/observed/growth.md`. These score thesis-fit in step 4 and are **not** given to the lenses: a lens that knows the thesis mines for what fits it, which is exactly the blind spot this command exists to get past.

### 2. Run the four lenses in parallel, blind

Dispatch four subagents with the Agent tool **in a single message**, so they run concurrently. Each brief contains only: its lens question, its surfaces, the known set, and the return contract below. **Never** another lens's question, surfaces or findings. Leave the model at the session default and do not drop a lens to a cheaper tier: mining latent value is judgment, not a file sweep.

| # | Lens | The question | Surfaces it mines |
|---|---|---|---|
| 1 | **Underexploited assets** | *What does the operator own that they are not selling?* IP, methods, frameworks, built systems, corpora, reusable deliverables, capabilities. | `00 - notes/context/ventures/*/` (every file) · project notes' Current State table, or the note body where there is none (what was actually built, the stack) · `00 - notes/reflections/` (methods and frameworks written down) · `03 - export/` (deliverables made once that could be made again) · `00 - notes/context/declared/` (skills and history the operator states about themselves) |
| 2 | **Cross-surface product-shapes** | *What new thing do two or more existing things combine into that nobody has named?* | every note in `00 - notes/projects/` · `00 - notes/context/ventures/*/about_venture.md` · `00 - notes/ideas/` · `00 - notes/context/observed/ecosystem.md` |
| 3 | **Demand-signal gaps** | *What do people keep asking for that is not packaged?* Requests, recurring questions, workarounds, "do you also do…", things clients pay for informally. | meeting notes, wherever this vault keeps them (grep titles, tags and headings for `meeting`, `call`, `sync`, `1:1`; check project notes' meeting logs and `00 - notes/reflections/`) · daily notes from the last ~90 days under `01 - calendar/` · `00 - notes/context/observed/ecosystem.md` · `00 - notes/context/observed/business.md` · `00 - notes/reflections/ingests/` |
| 4 | **Dormant seeds** | *What did the operator shelve that is ripe today?* | `00 - notes/ideas/` (all, oldest included) · project notes with an idea, parked or archived status · parking-lot and carried items in daily notes · `00 - notes/reflections/_inbox/` · reflections no newer note links to |

**The brief each lens receives** (fill the bracketed parts; send nothing else):

```
You are one lens of a blind opportunity sweep over an Obsidian vault at {absolute vault path}.
Other lenses exist; you do not know what they look at, and that is deliberate.

Your question: {lens question}
Mine these surfaces: {lens surfaces}. Every candidate must ORIGINATE in them: at least one of its citations comes from
your own surfaces. You may follow links elsewhere for corroboration, never to go looking for new candidates.
Read only. Do not write, move or create anything.

Do NOT return anything on this known list (already named, decided against, or surfaced before), unless you can
cite NEW evidence and say what is new: {known set}

Bar: a real, actionable opportunity the operator has not named. Zero candidates is a valid answer. Return at most 5.
{lens rule}

Return, for each candidate:
- opportunity: one line, a noun phrase (what it is, for whom), never "we should..."
- evidence: 2+ vault-relative paths, each with a short exact quote from that file
- why now: what in the vault makes this timely (a date, a change, a recent ask)
- first cheap step: one action under a day of effort that would test it
- requires / cannibalizes: what it costs, and what existing work it would take time or revenue from
- strongest objection: the best case against it
Then a coverage manifest: every file you read, and every surface in your list you found empty or missing.
```

**Lens rules** (the `{lens rule}` line):
- Lens 1: name the asset and the buyer it is not yet sold to. An asset with no plausible buyer is not a candidate.
- Lens 2: every candidate cites at least two *different* projects, ventures or ideas; one source is a feature request, not a product-shape.
- Lens 3: every candidate cites asks from at least two different people or occasions; a single ask is reported as `single-signal`.
- Lens 4: every candidate states what changed since it was shelved; without that, it is still shelved.

**No Agent tool available?** Run the lenses yourself, strictly one at a time: finish lens N, write its candidates and manifest into a scratch section of the output, and do not re-read them while running lens N+1. Mark the report `sweep: sequential (not blind)` so the operator knows the diversity guarantee was weaker.

### 3. Completeness critic

When all four return, dispatch one more subagent, in its own context, with: the four lens questions, the four coverage manifests, a listing of the vault's top-level folders under `00 - notes/` with file counts, and the candidate *one-liners only* (no evidence, no arguments). Its question: ***"What lens or surface did this sweep not mine?"*** Tell it the known set was built from `projects/`, INTENT.md and earlier prospect runs and is already applied, so it does not re-propose a filter as a gap: a gap is a surface that could *yield* candidates. It returns at most two gaps, each as a surface (paths) plus the question to ask of it, or `none`.

If a gap names a surface with real content, run it as **one** more blind lens (same brief, same contract, the gap as its question). One extra round per run, no more; any further gap goes in the report's *Next round* section. This is how the lens set grows: a gap the critic names in two runs running belongs in the operator's `### /prospect` personalization as a standing fifth lens.

### 4. Synthesis (this session)

1. **Verify every citation.** Open each cited path and confirm the quote is there. A candidate whose evidence does not resolve is dropped, not repaired: a subagent can cite a file it never read.
2. **Re-check the known set.** Drop anything that is, under another name, already a project, a decided-against item or an earlier surfaced candidate with no new evidence.
3. **Dedup.** Merge candidates that are the same opportunity seen from different lenses, and keep every lens's evidence. The same asset sold to a different buyer at a different price stays a separate candidate; the same asset reached through a different *channel* (a newsletter, a community, an existing client) is not a candidate at all: fold it into the first cheap step of the offering it would sell. **Independent convergence is signal:** record which lenses found it (`lenses: 1, 3`).
4. **Score** each survivor 1-3 on **value** (size of the upside), **feasibility** (can the operator test it with what they have now) and **thesis-fit** (against the thesis held back in step 1), each with a one-clause reason. Rank by the product. Convergence across lenses breaks ties.
5. **Cut.** Keep the top three to seven. A short sharp list beats a long soft one; if only two clear the bar, the menu has two. Everything cut gets one line and the reason.

### 5. Write the report

## Output

```
## Prospect: {date}

> sweep: blind ({N} lenses{ + 1 critic round}) · known set: {N} items excluded · candidates: {raw} raw → {kept} kept

### The menu

#### 1. {opportunity, one line} · {value}×{feasibility}×{fit} = {score} · lenses: {list}
- **Evidence:** [[{note}]]: "{quote}" · [[{note}]]: "{quote}"
- **Why now:** {what makes it timely}
- **First cheap step:** {one action, under a day}
- **Requires / cannibalizes:** {cost} / {what it takes from}
- **The case against:** {the strongest objection}
- **Scores:** value {n}: {reason} · feasibility {n}: {reason} · fit {n}: {reason}

{repeat for each kept candidate}

### Considered and cut
- {one line}: {why it did not clear the bar}

### Next round
{Gaps the critic named that this run did not mine, each as surface + question. `none` if none.}

### Your call
{One line per candidate the operator could act on, phrased as a choice, never as a recommendation:
"Name it an offering · park it · drop it". Nothing here is decided until the operator says so.}

If you name **{top candidate}** an offering, I can run the `lead-generator` agent (`/aios:agent lead-generator`) to find who would buy it.
```

## Save to vault

Write the report to `00 - notes/reflections/prospects/{YYYY-MM-DD}-prospect.md` (a second run the same day: `{YYYY-MM-DD}-prospect-2.md`) with frontmatter `{"tags": ["prospect", "aios-command", "opportunities"], "created": "{today}", "type": "prospect"}`. It lives in `reflections/` because it compounds: the next run reads every earlier one to build its known set, and the question it answers later is *"what opportunities has the vault surfaced, and which did I act on?"* (the retrieval test in CLAUDE.md § File Placement Router). It is not a log (a person reads it for meaning) and not an export (it is not made for an audience). If the `prospects/` folder is new and `00 - notes/reflections/_index.md` exists, add a line for it there.

Commit only what this run wrote:

`cd ~/aios && ~/aios/hooks/vault/aios-commit -m "Prospect {date}" -- "vault/00 - notes/reflections/prospects/{YYYY-MM-DD}-prospect.md"` (add `"vault/00 - notes/reflections/_index.md"` if you touched it).

## Rules

- **Never decide.** Flag, argue, rank. No "we should", no "I recommend": the menu is the operator's to order from.
- **Never act on a candidate.** Do not create a project note, an idea note, a to-do, a draft, a message or a post, and do not send or publish anything. Graduating a candidate is the operator's move (and then `/aios:ingest`, a project note or `lead-generator` takes over).
- **Never re-surface the known.** The known set is the first filter and the last.
- **Lenses stay blind.** Nothing one lens found reaches another lens's brief, ever, including through the critic: the critic sees one-liners, and lenses never see the critic.
- **Evidence or it did not happen.** Every candidate cites the vault; every citation is checked before it reaches the operator.
- **Generic is a failure.** "Offer consulting" or "write a course" with no vault-specific buyer, asset and timing is noise. Cut it.
- Use [[wiki-links]] for every project, venture, context file and note cited.
