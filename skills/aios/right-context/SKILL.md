---
name: right-context
description: Decide how much operator context to load at session start, and when to climb higher mid-task. Use when the Session Start Ritual's one question does not settle it — an unfamiliar task shape, a vault whose proportions you do not know, a worker unsure whether its output will be read as the operator's own words, or a session that catches itself guessing at voice, people, or past decisions. Carries the four-rung ladder, the escalation tells, and the command that measures what each rung costs in THIS vault.
---

# Right-Context — load what the work needs, know what you skipped

`CLAUDE.md` § Identity & Greeting carries the **floor** and the **one question**, and they are unconditional: the map always, then *will what I produce be read as the operator's own words, or act on their behalf?* Ninety percent of sessions need nothing more, which is why the rule lives there and this file does not.

This skill is for the other ten percent — and for the moment mid-task when the answer you gave at minute one turns out to have been wrong.

> **This skill obeys the rule it describes.** Every word in `CLAUDE.md` is paid by every session forever; the ladder below is needed only by sessions that hit a hard case. So the floor is always-loaded and the judgment is load-on-demand. If that split feels familiar, it is the same trade you are here to make about the vault.

## First, stop asserting and measure

```bash
python3 ~/aios/hooks/context-rungs.py          # or --json
```

It prints the four rungs **for the vault in front of you**, in words and estimated tokens, and ends in a verdict. Run it before reasoning about cost. Two vaults give opposite correct answers:

- A **small context** — a handful of thousand tokens, less than this page. Usually a new vault, but just as often a long-standing one belonging to someone who writes little. The verdict says *read all of it*, and that is right: the ladder is not for this vault.
- A **large context** — six figures of tokens, `observed/` several times `declared/`. The verdict says floor at rung 1 and climb deliberately. **Judge the vault in front of you, never its age** — the tool reports size because size is the thing that decides.

**Never hardcode a number you read out of this tool into a file.** That is the bug the tool exists to end: *"read everything"* was correct when it was written, silently stopped being correct as the vault grew, and nothing reported the change. A constant about a growing quantity works, then doesn't, and no one is told.

## The rungs are a price list, not a staircase

**Intelligence is the right information at the right time — not the largest pile you can afford.** That definition does real work here, because it rules out the two obvious designs. A fixed small read is not intelligent (it is cheap). A fixed total read is not intelligent either (it is a stockpile, and it is what a worker does when it has no judgment to apply). What makes a session intelligent is **fit**: what it opened, when, because of what the task turned out to need.

So the numbers below are **costs you can look up**, not levels you unlock. Only the first is a rule.

**Rung 0 — both `_index.md`.** Filenames and a line each. Orientation, never a resting place.

**Rung 1 — THE FLOOR. `python3 ~/aios/hooks/context-floor.py`.** The only fixed thing in this skill. One call emits both `_index.md`, every heading in `declared/` and `observed/`, **the last 5 `###` entries of every observed file in full**, `INTENT.md`, and a listing of `ventures/`. Everything after this is judgment.

**Rung 2 — all of `declared/`.** A common depth, priced for convenience. Not a level: if one declared file answers your question, read that file.

**Rung 3 — everything, all three corpora.** The degenerate case, correct in two situations and no others — see below.

### Deepening is unconstrained, and that is the point

The floor is a **starting position, not an allowance.** Three rules, and they all say the same thing from different angles:

- **Read past the floor's slice whenever a title says so.** Five recent entries of `preferences.md` is where you *start*, not a quota. If the title of an older entry is what the task turns on, open it — or twenty of them, or the file.
- **Read a single file, not its folder.** "All of `declared/`" is a shorthand for a common case, not the only way to touch that folder. One file is often the right read and it is always available.
- **Open a venture the moment the task names one.** You do not need to be "at" any particular depth first.

If you find yourself thinking *"I am only at the floor, so I should not read that"* — that is the misreading this section exists to prevent. There is no permission gate above the floor.

### Later beats speculatively earlier

Reading `declared/` at minute thirty because you have just discovered the deliverable goes out in the operator's name is **better fit** than reading it at minute one in case it might. Fit is about the moment, and the moment is usually not the first one.

This is why **reaching mid-task is the normal mode rather than a fallback**, and why the floor is the only thing loaded in advance: what you cannot discover at the moment of need is what you never knew existed. The floor buys exactly that and nothing more.

### When reading everything is right — and when it is just brute force

Two situations, and they are narrow:

- **The whole context is cheaper than deciding what to skip.** Run `python3 ~/aios/hooks/context-rungs.py`; if the verdict says read it all, read it all. This is not thoroughness, it is arithmetic: when deliberating costs more than acting, do not deliberate.
- **The task IS the context.** Synthesising across the operator's history, auditing or compacting the observed files, deriving a pattern that only appears across many of them, answering *as* them. Here an index is a lossy summary of precisely the thing under analysis.

**Outside those two, reaching for everything is not caution — it is the absence of a judgment.** Measured: a worker told to read all of both folders for a two-sentence task spent 38 tool calls across 18 files and never wrote the two sentences. Volume is the failure mode that looks like diligence.

## Why rung 2 reads a whole folder when rung 1 only reads titles

Not because `declared/` is unindexable — **it is not**, and an earlier version of this rule claimed so without measuring. Measured, `declared/` carries *more* headings per word than `observed/` does. The claim was wrong and it is worth knowing why the conclusion survived anyway:

**The two failures are not equally detectable.**

- Under-read `observed/` → you do not know a preference or a past decision. This shows up. The work is visibly missing something, or you know to ask, or a title you *did* see nags at you. The error announces itself.
- Under-read `declared/` → you write in a voice that is fluent, competent, and **not theirs**. Nothing in the output looks wrong. There is no gap to notice, because plausible prose fills the hole exactly.

You cannot detect the absence of a voice from inside your own output. That is the asymmetry, and size is only what makes acting on it cheap: `declared/` is the small folder, so reading it whole costs little, and the failure it prevents is the one you would never catch.

## Tells that you are already too low — climb NOW, mid-task

Reaching mid-task is **expected, not exceptional**. Do not finish the task and then wish you had read more. The tells:

- You are about to write something in the operator's name and you are **inferring** their register, their formality, their opening move. → rung 2, now.
- You catch yourself writing *"probably"* or *"presumably"* about the operator's own preference. → the answer is in `preferences.md`; open it by title.
- A person, company or venture appears and you are reconstructing the relationship from the task text. → `ecosystem.md` or `business.md`.
- You are about to publish, send, commit, or post. → `INTENT.md` decides whether that is yours to do.
- A title you saw at rung 1 keeps coming to mind. → that is the index working. Open the entry.
- You are about to run a command that changes state and have not scanned `antifragile.md` titles. → back to the floor first.

**Guessing is not a rung.** If the honest answer is "I do not know how they would put this," you are not at the wrong rung — you are about to produce the failure that does not announce itself.

## When the one question genuinely does not settle it

Rank these, in order, and stop at the first that applies:

1. **Will a human read this as the operator's words?** A post, an email, a message, a bio, a reply, a doc in their name → **rung 2**. Ghostwriting is the case this exists for.
2. **Will it act on their behalf?** Sending, publishing, committing, spending, scheduling, deciding → **rung 2** *and* `INTENT.md`, which is the trust contract for exactly that.
3. **Is "correct" checkable without knowing the operator?** Code, tests, file operations, data transforms, mechanical sweeps → **rung 1** is enough. Correctness here is a property of the artifact, not of the person.
4. **Mixed?** A task is a rung-2 task if *any* of its output speaks as them. Do not average.
5. **Still unsure → rung 2.** Per the asymmetry above: one costs tokens once, the other costs the voice and fails silently.

## The failure at the top of the ladder is real

A worker told to read *all* of both folders before a two-sentence task spent **38 tool calls across 18 files and never wrote the two sentences**. Rung 3 on a grown vault is not caution — it is a way of not doing the work. The same task, at rung 2, delivered in 26 calls in the operator's voice.

And the failure at the bottom is equally real and much quieter: measured across spawned workers on a live vault, one did substantive work having loaded **nothing at all**, and nothing reported it. `/aios:housekeeping` now names those (Bucket 30, via `hooks/context-load-audit.py`).

## What you owe the operator at the end

If you climbed mid-task, say so in one clause in your session capture — *"reached for `preferences.md` on the em-dash budget"*. It is evidence the floor is set right. If you found yourself repeatedly opening the same entry that the floor did not surface, that is a finding about the floor, not about you: route it as a `method` entry per § Self-Update.
