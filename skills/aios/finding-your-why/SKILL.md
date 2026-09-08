---
name: finding-your-why
description: Derive the operator's durable purpose from their observed context — the compass under the goals — and connect the work they ship to the values it expresses. Use when the operator asks what they are actually building toward ("what's my why", "what am I doing all this for", "state my purpose"), when a big ship lands and their own words go flat ("done, what's next", "ok, next"), when they describe feeling scattered or on a treadmill despite shipping well, when /close-day's verdict line has answered only what-they-did for a stretch, and when the variation gate crosses and it is time to offer a compass for the first time. NOT for pace or workload (that is sustainable-cadence) and NOT for deciding what to do next (that is the roadmap and /7plan). The "what does all of this add up to?" lens.
---

# Finding your why — the compass under the goals

Every tracked thing in this framework completes. A key flips, a ship lands, a streak extends, a carry clears — and then asks what is next. That machinery is good and this skill does not touch it. It exists because **a system built entirely of things that complete can only ever answer one of the two questions an operator has**, and the second one is the one that decides whether they are still doing this in three years.

- **What did I do?** — the boards, the keys, the ships, the streaks. Already answered, well, at a daily cadence.
- **What did it mean?** — answered nowhere, unless something makes it answerable.

> **A goal is a destination on the map. Purpose is the compass.** *(Compressed from the arrival-fallacy framing — carry this attribution wherever the line is quoted.)*
>
> And the sharpening that belongs to this era: **when agents can chase any destination, goals stop being identity — only the compass is inalienable.** The more a system can execute on an operator's behalf, the more the *why* becomes the only part that is actually theirs.

---

## The rule that outranks everything else here: do not manufacture a compass

**Never ask the operator to state their purpose, and never derive one from thin evidence.** Both produce the same artifact — something plausible, aspirational, and not true — and a false compass is materially worse than no compass, because every subsequent goal→value link decorates real work with a value the operator never held.

Asking fails for a specific reason: *a stated purpose is exactly where the substitution heuristic hides.* Asked directly, a person substitutes the hard question (*what is my purpose?*) for an easy one (*what would a purposeful person say?*) and hands over the answer to the second. Deriving too early fails because the method below needs variation, and with one project's worth of evidence the invariant **is** that project — which is a goal, not a compass.

So this skill has three states and it is silent in the first one.

---

## The three states

### State 0 — not enough evidence. Say nothing about purpose.

No prompt. No placeholder. No "set your purpose" nudge in any surface. The operator gets the full working system — boards, ships, streaks, rituals — and no claim about meaning, because none has been earned.

The system is not idle in this state: observed context accrues, `/close-day` asks *"what was most useful?"*, and the verdict line already names what a day **meant** rather than counting what it held. Both questions are being served from day one. Only one of them is visible as a feature, and that is correct.

*(The precedent for this posture is already in the framework: when `USER.md` declares no growth routine, `/today` prints one gentle line and moves on. It does not manufacture a routine to have something to show.)*

### State 1 — the variation gate crosses. One warm offer, once.

**The gate is variation, not tenure.** Elapsed days are the wrong measure — an operator can run the system for six months inside a single project and still have nothing an invariant could be drawn from. What the method needs is *maximal variation*: enough distinct domains that "the thing that did not change" is informative rather than tautological.

Computable from what is on disk:

- distinct projects with real activity (not scaffolded, not archived-on-arrival)
- distinct ventures or domains represented in `context/ventures/` and `context/observed/business.md`
- how much of `context/observed/` describes the operator across contexts rather than inside one

Below the gate → stay in State 0. **Do not offer, do not hint, do not ask.**

Above it → make the offer **once**, at `/close-day`, in a reflective moment rather than a morning full of intentions. See § How to offer it.

### State 2 — a compass exists. Connect the work to it.

The compass lives in `context/observed/growth.md`, and it carries its own gloss so it explains itself to anyone who opens that file cold — including the operator six months from now:

```markdown
## Compass
*What hasn't changed across everything you've done — derived from your observed
context, not stated by you. It has no checkbox and nothing to advance; the goals
elsewhere in this vault are expressions of it. Refine or replace it any time.*

{one or two sentences, in the operator's own register}
```

**The heading is `## Compass`, and the word was chosen against a real alternative.** *Horizon* was the first pick and it is wrong twice over: this framework already has a `Horizon` — a carry-bearing section in the daily note, holding things that **complete** — and the ordinary idiom *"on the horizon"* means *approaching*. A word chosen to mean *you never arrive here* colloquially means *arriving soon*, which is precisely the destination reading the whole design exists to separate from. A compass, by contrast, cannot be arrived at; the property is in the word. Don't rename it back.

Once the section is there:

- `/today` adds **one clause** to the day's most significant item, naming the value it expresses. Not a section. A clause.
- `/close-day`'s verdict line answers the second question alongside the first.
- The health test below runs against the system's own output.

---

## How to derive it — hunt the invariant under maximal variation

The domains an operator works in change, sometimes completely. Whatever survives every one of those changes unchanged is the compass; everything that completed along the way was a goal. So read across the widest span of observed context available and look for what did not move.

Three tells sharpen it, and all three are read from evidence rather than asked:

1. **What they build when nobody is measuring.** Unpaid, unpromoted, unscheduled work is the least contaminated signal in the vault — nothing about it is performance.
2. **What makes them emotional.** Note *where* the emotion sits. Emotion attached to a milestone is the wanting system; emotion attached to someone else's outcome is usually the compass reading itself back.
3. **What they refuse to trade even at cost.** A principle held when holding it is expensive is a principle; held only when it is free, it is a preference.

**The definitional filter, applied without exception: if a candidate could ever be checked off, reject it.** A purpose that completes was a goal wearing purpose's clothes. This single test removes most of what a session will be tempted to write.

**Say it in the operator's own register.** The compass is not a mission statement and must not read like one. If the sentence would look at home on a careers page, it is wrong.

---

## How to offer it — the tone is a contract, not a preference

The offer is an **observation shared warmly**, never a verdict delivered. Concretely:

- Open by naming that it is an observation and what it is *for* — the shape is *"here is something I've noticed across your work that I think would help you with direction."*
- Offer **candidates**, not a conclusion. Two or three readings of the invariant, in their language, with the evidence each one rests on.
- **Invite refinement explicitly.** *"Refine it, replace it, or tell me I've got it wrong"* is part of the offer, not a politeness. The operator holds the pen; the system is doing the reading, not the deciding.
- **A rejection is a real answer.** Record it and do not re-ask for a long while. An operator who says *"that's not it"* has given genuine information — usually that the evidence is thinner than the gate suggested.
- **Never bundle it with a request.** The offer asks for nothing else in the same breath — no task, no confirmation of anything, no next step.

If the operator edits it, **their words win, completely.** The derivation was a draft for them to correct.

---

## The health test — run it against the system, not the operator

One question, and it is asked of the *output* rather than of the person:

> **When a ship lands, does the system say "next!" — or "look who you became"?**

A report that only ever answers the first is a system with one layer running. This is checkable: if `/close-day`'s verdict line has named only *what was done* for two weeks running while ships were landing, that is a flag — the second layer is not firing. It is a system alert, not a missed task; one flat day is a day.

**Never turn this into a quiz for the operator.** Asking someone whether they feel they became something is the substitution heuristic again, wearing a caring face.

---

## The identity layer needs a forcing function — the one thing that does not grow by itself

Every other layer of a vault grows as a **byproduct of work**: ships generate project state, sessions generate observed context, living generates daily notes. The identity layer only grows by deliberate reflection, and deliberate reflection has no forcing function.

So it does not merely stall — **it falls every time anything else succeeds.** Nothing is removed; the denominator grows. An operator can have a spectacular quarter and end it knowing measurably less about who they are than when it started.

Two mechanics fix the rate, and they are the whole of what a routine needs:

- **Deficit-driven, not round-robin.** The next question comes from whichever dimension of the operator's own context is thinnest, computed from what is on disk — never the next card in a fixed deck. That is what makes it a ratchet: it always pushes where the gap is.
- **Measured by share, not streak.** An activity metric can be *fully satisfied while the thing you care about falls* — seven answers a week means nothing if the share of the vault that knows who the operator is keeps shrinking. Track the share and the direction of travel.

This plugs into `USER.md` → `### Growth routines` as a **third routine shape** beside reading and writing, using machinery that already exists. Reading feeds what an operator knows. Writing feeds what they ship. This feeds **who they are** — the layer the other two draw on and neither replenishes.

**The anti-journaling constraint is load-bearing.** This framework is explicit that a vault is not a journal. Every question asks for an **episode and its specifics** — what happened, who was there, what it cost — never for feelings in the abstract. Autobiographical *fact* is what a corpus can retrieve and reason from later; a mood is not. A question bank drawn from the operator's own thinnest dimension by a session that has read their context asks what is genuinely missing, and gets sharper as the context deepens.

---

## What not to do

- **Do not name the mechanism after its neurochemistry.** The two layers have well-known biological names and using them in operator-facing text turns a design into a lecture, invites bad pop-science, and makes a claim about a person's body that a vault has no standing to make. Describe the behaviour: *what did you do* and *what did it mean*.
- **Do not add a surface.** Everything here lands on `/today`, `/close-day`, and `growth.md`. A dashboard for purpose is the wanting system eating the other layer.
- **Do not let the compass become a to-do.** It has no checkbox, no progress bar, no percentage. The moment it can be advanced it has become a goal.
- **Do not re-derive it casually.** A compass that changes every month was never read correctly. Revisit on genuine evidence — a real pivot, a rejection, an operator's own revision — not on a cadence.
- **Do not use it to justify a decision the operator did not make.** The compass explains work; it does not authorise it.

## Related

`sustainable-cadence` owns **pace** — whether the rhythm can hold. This owns **direction** — whether the rhythm is pointed anywhere. `comprehension-debt` owns whether the operator still understands what their system shipped. The three are siblings: capacity, understanding, and meaning, all of them operator-condition rather than work-output.
