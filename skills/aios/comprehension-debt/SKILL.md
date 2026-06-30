---
name: comprehension-debt
description: Keep the operator's understanding from falling behind what their agents ship — the gap between what the vault and repos contain and what the operator actually grasps. Use when agents (spawned workers, overnight sessions, autonomous loops, /aios:update self-modification) have shipped work the operator didn't author, when deciding whether to trust an autonomous loop, when a repo or venture starts feeling opaque, or during /close-session and /aios:housekeeping. The defensive complement to Arc sessions — arcs build understanding as work happens; this guards it from eroding when agents outrun the operator.
---

# Comprehension Debt — guard the operator's understanding, don't outrun it

The leverage of an AI-OS is that agents ship work the operator never typed. The hidden cost is **comprehension debt**: the widening gap between what the operator's vault and repos *contain* and what the operator actually *understands*. It's invisible — nothing breaks at ship time — until the day they have to debug, defend, or decide on a system no one on their side has grasped. The token bill was never the expensive one; the un-comprehended system is.

## Whose debt this is (read this first)

The debt is the **operator's**, not yours. *You* (the model) can read and understand every diff in-context — that's exactly why it's easy to wave agent output through and assume it's understood. But the operator is the one who has to own the system in a room, stay irreplaceable, and make the judgment call when the gate is silent. Your job is to **keep their debt low** — surface what they haven't grasped and offer to close it — never to be the subject of the rule yourself.

> This is distinct from *leadership culture*, which is shared ("ours" — model and operator co-orchestrate). Comprehension debt is the operator's alone, because defending a system in a room is theirs alone.

## The core test

One question, posed as an **offer, not a quiz**:

> *"A fair amount shipped this session — want me to walk you through any of it? The bar isn't reading every line; it's that you understand what shipped well enough to defend, debug, or decide on it later. Anything you'd like me to explain?"*

**Reading is necessary, not sufficient.** A read-but-not-grasped change is still debt. The unit of debt is the *un-comprehended* change, not the *un-read* one — so the bar is comprehension (could they defend / debug / decide?), never line-by-line reading.

## The counterintuitive core

The risk **sharpens as the loops get better.** Slow, error-prone agents force the operator to stay close. Fast, trusted, well-gated agents earn the operator's trust to look away — and that's exactly when the gap widens fastest. The better the orchestration, the more deliberate the comprehension discipline has to be. Don't treat a smooth-running fleet as a reason to relax the check; treat it as the reason to keep it.

## How to apply (the workflow)

1. **Detect agent-authored change.** What shipped this session that the operator did *not* write themselves — commits by spawned workers / other agent sessions, files written by background subagents, anything `/aios:update` or an autonomous loop changed. If the operator authored everything, there's no debt to surface — skip silently.
2. **Surface as an offer.** Pose the core-test question. List the changes plainly. Don't interrogate; invite.
3. **Walk through what they ask about.** Explain at the altitude they need — the *why* and the *failure modes*, not a line reading. The goal is ownership, not coverage.
4. **Roll the rest forward as debt.** What they decline to grasp carries forward (in the `/close-session` ledger → an open-threads carry), marked *un-grasped*, never *done*. `/close-day` and `/aios:housekeeping` resurface it.
5. **Protect against the structural causes** — the prevention axis, not just detection:
   - **Spot-check the gate.** Help them verify the test/review/build that approved agent work actually catches the failure mode they care about. Gates rot. (`/aios:housekeeping` runs this on a cadence.)
   - **Block loops from judgment work.** Keep autonomous loops on machine-checkable changes; architecture, strategy, auth/payments, and anything where "done" is a judgment call stay operator-in-the-chair.
   - **Pair-design loops.** A second perspective when a routine/agent is designed catches the blind spot it would otherwise exploit on every run.

## Worked example

Two agents ran deep over a weekend — one rebuilt a dashboard, one landed a wallet feature; an overnight worker shipped a reflection; `/aios:update` self-modified the framework. *Naive read:* a productive weekend, all green, ship it. *Comprehension read:* four bodies of work exist that the operator hasn't grasped. At `/close-session`, surface them as an offer. The operator takes the dashboard walkthrough (they'll demo it), skips the framework diff (trusts the dogfood loop). The wallet feature and the framework change roll forward as comprehension debt — not blockers, but flagged, so when the operator next opens those, the gap is named instead of silent.

## Relationship to the rest of the system

- **Arc sessions** (CLAUDE.md § Proactive Execution) are the *offense* — one long session builds the operator's understanding as the work happens. Comprehension debt is the *defense* — it guards that understanding from eroding when work happens *without* the operator in the loop.
- **`sustainable-cadence`** asks whether the *pace* is sustainable; this asks whether the *understanding* is keeping up. A fleet can run at a sustainable pace and still outrun comprehension.
- **`leverage-points`** says *where* to intervene in a system; this is one reason the operator must retain enough understanding to choose the leverage point at all.
- Enforced by the `/close-session` comprehension ledger (detection) + `/aios:housekeeping` gate-health bucket (prevention). CLAUDE.md § VI holds the always-on principle; this skill is the full mechanism.
