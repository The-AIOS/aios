---
name: deep-research
description: "Deep, multi-source research for acting under uncertainty — answers WHAT to aim for, WHY it matters, and HOW to pursue it, when the answer requires surveying a live field rather than retrieving one fact. Output-agnostic by design: the starting intent ('what should I write about?') is treated as provisional, because research routinely reveals the real move is something else — a thing to build, a decision to make, a plan to change, a habit to adopt, a feature to ship. It maps the operator's existing corpus first (no repeats), sweeps multiple sources and angles, triangulates, and returns ranked proposals each carrying its what/why/how and its recommended output mode. Use for: 'what should we write / build / do / cover next', 'research X and tell me what it means for us', domain-landscape or competitive/positioning analysis, white-space discovery, trend-to-thesis matching, evaluating where a field is heading, or any decision that deserves more than one search. NOT for single fact lookups (plain web search) and NOT for producing the deliverable itself (drafting/building are separate skills). Pushy default: if a request smells like 'help me figure out what to aim at,' use this skill even if the user never says 'research.'"
---

# Deep Research

Research for **acting under uncertainty**. The caller arrives with a provisional intent — *"what should I write about?"*, *"is X worth building?"*, *"what's happening in this space?"* — and this skill returns **what to aim for, why, and how**, grounded in a real survey of the field and the operator's own corpus.

## The prime directive: intent is provisional

There is a chicken-and-egg at the heart of research: **you need the research to know what you're actually looking for.** A run that starts as "find my next post topic" may surface a product gap worth building, a decision that's become urgent, or a risk that reframes the week — and a run that starts as "should we build X?" may reveal the right move is to *write* about X instead.

So this skill treats the caller's intent as a **starting lens, not a cage**:

- **Honor the lens** — the caller's intent shapes where you look first and how you rank.
- **Report what escapes it** — when findings point at a different output mode than the caller asked for, say so explicitly. Never silently discard a discovery because it doesn't fit the original question.
- **Re-examine the frame mid-run** — after the sweep, ask: *did the findings change what we should be aiming for?* If yes, name the reframe before ranking.

## Output modes

Every proposal names its recommended **output mode** — the form the finding wants to become:

| Mode | The finding is… | Typical hand-off |
|---|---|---|
| **Write** | a thesis/angle worth publishing | a writing skill / drafting session |
| **Build** | a capability/product/feature gap | a plan, a repo, a builder agent |
| **Decide** | a fork that's become ripe or urgent | a decision memo, `/challenge`, the operator |
| **Plan** | a sequencing/strategy insight | `/7plan`, a project note, a roadmap change |
| **Act** | a concrete near-term move (incl. personal: health, learning, habit) | a task, a routine, a calendar block |
| **Watch** | real but not ripe — an early signal | a dated watch-item with a re-check trigger |

One research run can return proposals in different modes. That's a feature — it's what makes the research honest.

## The core discipline

Bad research dumps links. Good research **triangulates, filters against what already exists, and privileges what's timely**. Failure modes to design against:

- **Dump** — twenty sources, no synthesis, no ranking. The human still has to do the thinking.
- **Duplication** — proposing what the operator already wrote/built/decided. Map the corpus first.
- **Evergreen bias** — recommending timeless-but-cold moves while a perishable window is open. Timely > timeless when both are real.
- **Lens-blindness** — forcing every finding into the output mode the caller asked for. The mode is a *finding*, not a premise.

## The loop

### 1. Frame — one line, held loosely
Write the provisional intent and what a good answer looks like: *"{caller} wants {X}; a good answer is {shape}."* This is the ranking filter — and step 4 explicitly revisits it.

### 2. Map the existing surface (BEFORE searching outward)
Read the operator's own corpus relevant to the domain — published work, drafts/pipeline, project notes, positioning/theses, prior decisions (`Read`/`Grep` over the relevant vault + repo paths). Inventory: *what's been said/built/decided, what's half-done, and what the operator's distinctive angle or asset is.* This turns "what's hot" into "what's hot that **we** are positioned to own" — and prevents proposing repeats.

### 3. Multi-angle sweep (never one query)
Run **several** `WebSearch` queries from genuinely different angles; `WebFetch` the 2–4 most promising sources for depth. Cover at least:

- **The live conversation** — what the domain is talking about right now, the phrases being used.
- **Adjacent voices** — what competitors / thinkers / publications the operator's audience reads are saying.
- **Open questions** — the contested, confusing, or unanswered points. White space lives here.
- **Direction of travel** — early signals of where the field is heading, not just current consensus.

Note publication dates on everything — recency is load-bearing for timeliness claims.

### 4. Re-examine the frame (the chicken-and-egg checkpoint)
Before ranking, ask explicitly: **do the findings support the original intent, or point somewhere else?** Three honest outcomes:
- *Confirmed* — the lens holds; proceed.
- *Widened* — the lens holds, AND findings surfaced moves in other modes; carry both forward.
- *Reframed* — the findings say the real aim is different; name the reframe as the headline and rank accordingly.

### 5. Triangulate + filter
Score each candidate on: **timeliness** (open window now? decaying by when?), **fit** (maps to an existing thesis/asset/draft that makes it fast, or genuine white space worth fresh effort?), and **ownership** (is the operator distinctively positioned, vs. anyone-could-do-this?). Drop duplicates of the corpus, cold-and-evergreen options when timely ones exist, and off-positioning moves.

### 6. Synthesize → ranked what/why/how proposals
Deliver **3–5 ranked proposals** — a decision aid, not a link dump:

```markdown
### {N}. {The move, stated as a move}
- **Mode:** write / build / decide / plan / act / watch
- **What:** {the concrete aim}
- **Why now:** {the timely reason — the open window, with source + date}
- **Why us:** {the operator's distinctive angle or asset, from the step-2 inventory}
- **How:** {the first concrete step + what it maps to (existing draft/repo/decision) or "fresh — needs {X}"}
- **Window:** {this-week / by-{date} / evergreen / watch-until-{trigger}}
- **Sources:** {2–3 links that ground it}
```

Lead with one line: **"If you do one thing: {top pick} — because {reason}."** If step 4 reframed the intent, lead with the reframe instead — that IS the finding.

## Rules
- **Never a single search.** Multi-angle sweep or it isn't deep research.
- **Corpus first.** You can't find white space without knowing what already exists.
- **Intent is provisional.** Honor the caller's lens; report what escapes it; reframe out loud when findings demand it.
- **Every proposal carries what/why/how + mode.** A topic without a mode and a first step isn't a proposal.
- **Timely > timeless** when both are real — and name the decay date.
- **Cite dates.** A "trend" from eight months ago isn't a window.
- **Rank, don't dump.** 3–5 proposals + a lead recommendation. A list of links means you're not done.
- **Stop at the proposal.** This skill chooses the aim; producing the deliverable (draft, code, memo) is the caller's or another skill's job.
