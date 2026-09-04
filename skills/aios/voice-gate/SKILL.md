---
name: voice-gate
description: Measure AI-writing tells in a draft against the operator's own voice — density, bursts, and position — and report rather than rewrite. Use before publishing anything in the operator's name (essay, post, chapter, email, proposal, deck copy, back cover), when a draft "feels AI-ish" and you need to know where, when a ghostwritten piece needs a voice check before it ships, or when calibrating an operator's voice budget from their published corpus. Governs by budget, never by banned list — a banned list flattens the voice it exists to protect.
---

# Voice Gate — measure the tells, don't ban them

A draft written or edited with AI carries statistical habits: reversals that manufacture insight, tricolons that pad, dashes that stand in for sentence structure. The reflex fix is a banned list. That reflex is wrong, and it is wrong in a specific, costly way: **many of these constructions are also load-bearing in real voices.** A writer whose whole method is the reframe will be flattened by a rule that removes reframes.

This skill grades. It does not rewrite. It answers three questions the operator can act on:

- **How often?** — density against *their own* baseline, not a universal number.
- **How clustered?** — bursts, which are the actual tell.
- **Where?** — position, which matters more than either.

## The core principle: position beats volume

Readers do not sample a piece uniformly. They sample **titles, subtitles, opening lines, section openers, pull-quotes, closing lines, back covers, and the one sentence that gets screenshotted.** A tell buried mid-paragraph does honest work and nobody clocks it. The same construction in a title is the reader's entire impression of the voice.

So the budget is positional:

| Zone | Bar |
|---|---|
| Title · subtitle · hook · kicker · pull-quote · back cover · standalone post | It must be the **best available sentence**, not the default shape. One per piece, earned. |
| Section openers and closers | Sparing. Two in a row reads as a template. |
| Body prose | Effectively free. This is where the move does its job. |

**The burst rule is absolute regardless of zone: never twice in one paragraph.** A single instance reads as a writer making a point; two in a row reads as a generator with a favorite move.

## Step 1 — build the operator's baseline before judging anything

Do not carry a number in from outside. Establish what *this* writer's prose actually does:

1. Read `vault/00 - notes/context/declared/personal_voice.md` — the operator's declared register, signature constructions, and any explicitly protected moves.
2. Read `vault/00 - notes/context/observed/preferences.md` for recorded writing corrections.
3. Sample their **published** work — the pieces they stand behind. Five to ten thousand words gives a stable number.
4. Compute tells per 1,000 words, and record the count of paragraph bursts separately.

That figure is the operator's **budget**, not a target to minimize. A writer who argues by reframe will legitimately run several times higher than one who argues by evidence, and cutting them to match would destroy the thesis. What you are looking for later is **drift from their own baseline**, plus any breach of the positional bar above.

If the operator has supplied a writing sample, it overrides every default in this skill — including the dash guidance below. Match the sample's rate; do not impose a rule the sample contradicts.

## Step 2 — score the draft

Walk the draft and mark each instance with its **pattern**, **position zone**, and **paragraph**. Then report:

- Density per 1,000 words, next to the operator's baseline.
- Every paragraph containing two or more (the burst list).
- Every instance in an exposed zone, quoted in full — this is the section the operator actually reads.
- Drift: is this draft above or below their own norm, and by how much.

## Step 3 — report, never rewrite

Output a short table plus three lists: **exposed-zone instances**, **bursts**, and **everything else** (usually the majority, usually fine). For each exposed-zone instance, ask the question that decides it:

> *Is this the best available sentence here, or the default shape?*

Offer alternatives only when asked. An operator who can see the instance in its position can usually fix it in one pass, and the fix will sound like them. A rewrite offered unprompted tends to sand the voice toward the mean — the exact failure this skill exists to prevent.

**Never edit the file unless the operator asks for edits.** Grading and rewriting are different jobs, and conflating them is how a voice gate becomes a homogenizer.

## The pattern catalogue

Detectors, not a kill list. The taxonomy is adapted from Wikipedia's community-maintained *Signs of AI writing* (see Sources); the positional and budget treatment is this skill's own.

**Structural**
- The negation pivot — *"It's not X, it's Y"*, *"was never X. It's Y."* Manufactures the feeling of a reversal whether or not one was earned. The highest-signal tell, and frequently a real voice's spine — which is exactly why it is governed by budget here.
- Forced tricolons — three items where the meaning needed two or four.
- False ranges — *"from X to Y"* where X and Y do not bound anything.
- Fake alternatives raised and dismissed in a clause, then never mentioned again.
- Objections answered that nobody raised — *"I'm not saying…"*, *"To be clear…"* with no interlocutor in the text.
- Dramatic fragment stacks — a row of short sentences each trying to be the closing line.

**Rhetorical**
- Announced transitions — *"Let's dive in"*, *"Here's what you need to know"*, and their casual register cousins.
- Fake-candid openers — *"Honestly?"*, *"Look,"*, *"Here's the thing"* used as a staged pause before an ordinary point.
- Manufactured depth — *"At its core"*, *"The real question is"*, *"what really matters"*.
- Formulaic aphorism — *"X is the language of Y"*, *"the currency of"*, *"the architecture of"*.
- Inflated significance — ordinary facts described as pivotal, a testament, a turning point.
- Vague attribution — *"experts believe"*, *"industry reports suggest"* with no named source.

**Lexical and typographic**
- Register words that cluster in generated prose: *delve, landscape, tapestry, testament, pivotal, underscore, crucial, seamless, robust, vibrant, intricate, foster, navigate, unlock, leverage*. One is nothing; four in a page is a signal.
- Verb avoidance — *serves as*, *stands as*, *boasts*, *features* where *is* and *has* would do.
- Bold-led list items with mini-headings, where prose would carry the idea better.
- Title Case In Headings; decorative emoji in headings or bullets.
- Dash density. **Not a ban** — many strong writers and most edited English use them heavily, and they are near-useless as a standalone signal. Flag only when the rate is far above the operator's own baseline.

**Residue**
- Assistant artifacts left in the text — offers to continue, *"I hope this helps"*, agreement openers.
- Knowledge-limit hedging, or a plausible guess presented as fact where a source is missing.
- Prose describing a previous version of the thing instead of the thing.

## What is NOT evidence

Flagging these is how a voice gate loses the operator's trust. None of the following counts on its own:

- **Polish.** Professional or edited writing is clean. Clean is not synthetic.
- **A single em dash, or curly quotes.** Editors, word processors and most CMSes produce both by default.
- **One formal transition.** *However*, *moreover*, *additionally* are AI-coded only when stacked.
- **One short sentence for emphasis.** Flag fragments only in runs.
- **Deliberate repetition.** Anaphora is a device. *"She came. She saw. She conquered."* is not a defect.
- **Non-native-English patterns.** Simpler constructions and lower lexical variety read as "generated" to naive detectors and are heavily over-flagged. Treat an operator's second-language patterns as voice, and record them in their voice file so future passes stop re-flagging them.
- **Structured, literal, or repetitive style.** This is a documented bias against neurodivergent writers. It is not evidence.
- **Formulaic genres.** Recipes, abstracts, changelogs and reference docs are formulaic because the form demands it.
- **Quoted material, titles, and examples.** Never flag a construction inside a quotation or one the text is discussing rather than using.

When uncertain, weight **co-occurrence**: several patterns in one passage is a signal, one pattern anywhere is noise.

## Traceability mode — for pieces with a source recording

When a draft derives from the operator's own speech (a recorded talk, a dictated chapter, an interview transcript), a stronger measure is available: **how much of their literal wording survived.**

Classify each sentence against the transcript:

- **Verbatim** — most of its content words appear in one region of the source.
- **Edited** — recognizably their sentence, cut or joined.
- **Composed** — written by the model.

Report the percentage that is theirs and list every composed sentence. The published measurement behind this approach found the relationship is a **threshold rather than a gradient**: drafts holding roughly 85% or more of the author's own wording read as human, and below that the verdict flips sharply. In practice that leaves about one sentence in eight for joins and transitions — enough for connective tissue, not enough for a section.

Two rules make this work:

- **Never clean the transcript first.** The disfluencies, false starts and odd constructions are the voice. A tidy-up pass converts the author's prose into model prose before drafting begins.
- **Hand composed sentences back to be re-said, not improved.** Asking the model for a better version reproduces the problem. The author saying it out loud and typing what they said is the fix.

## Honest limits

**This skill does not defeat AI detectors, and must never be sold as though it does.** Modern classifiers are trained adversarially against exactly this category of tool and catch the large majority of "humanized" text; the documented paradox is that the more fluent such output becomes, the more detectable it gets. Anything that reliably evades does so by making the writing worse.

What actually protects a writer who is genuinely writing is **provenance**: drafts, version history, recordings, notes. Keep them. If authorship is ever questioned, process evidence outranks any score.

Detector scores also carry real false-positive costs that fall hardest on second-language and neurodivergent writers. Treat any score as a lead, never a verdict, and never sand good prose to placate a classifier.

The honest framing for this skill: **it improves writing, and it protects a voice from being averaged away.** Those are the claims it can support.

## Sources and prior art

- The pattern taxonomy adapts **[Wikipedia: Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing)**, maintained by WikiProject AI Cleanup — the most thorough public catalogue of these markers, and explicit that they are descriptive observations rather than proof.
- **[blader/humanizer](https://github.com/blader/humanizer)** (MIT) is the reference implementation of the rewrite-oriented approach, and the source of the false-positive-guard framing. This skill deliberately diverges: it measures and reports where that one rewrites, because a banned list flattens a voice.
- **[charlie947/voiceprint](https://github.com/charlie947/voiceprint)** is the source of the traceability threshold and the edit-by-deletion discipline in that mode.

No code or prose from either project is vendored here; both are credited as prior art for approaches this skill builds on and, in one case, deliberately departs from.
