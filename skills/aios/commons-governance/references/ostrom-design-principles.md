# Ostrom's 8 Design Principles for the Commons — full reference

> Source: Elinor Ostrom, *Governing the Commons: The Evolution of Institutions for Collective Action* (Cambridge University Press, 1990). Ostrom received the 2009 Nobel Memorial Prize in Economic Sciences for this work. The eight principles are her empirical findings from long-enduring, self-governed common-pool resources (irrigation systems, fisheries, forests) that avoided both tragedy-of-the-commons collapse and top-down capture.

The big result: **commons can be governed sustainably by their users themselves** — neither privatization nor central control is required — *when* these institutional design principles are present. Long-lasting commons reliably have them; failed ones reliably lack some.

## The 8 principles (original, + AIOS translation)

**1. Clearly defined boundaries.**
*Original:* the resource and the set of legitimate users are clearly defined. You can't govern a commons whose edges and membership are fuzzy.
*AIOS:* name exactly which repos/folders are shared and who participates. Personal vault and `custom/` are explicitly outside the commons.

**2. Congruence between rules and local conditions.**
*Original:* appropriation and provision rules fit the local environment and the users' actual needs — no generic, imported policy.
*AIOS:* a 2-person space and a 10-person company need different rules. Write the rules *this* group needs, not a template.

**3. Collective-choice arrangements.**
*Original:* most people affected by the rules can participate in modifying them. Governance isn't done *to* users; it's done *by* them.
*AIOS:* "move authority to information" — the people doing the work shape how the shared space works. Rules are changeable by participants.

**4. Monitoring.**
*Original:* monitors who actively audit the resource's condition and users' behavior are accountable to the users (often are the users).
*AIOS:* sync trackers, `--status` commands, a shared changelog — the state of the commons is visible to everyone in it. A commons no one can see degrades silently.

**5. Graduated sanctions.**
*Original:* violations are met with proportional, escalating responses — a small first response, not immediate maximum penalty.
*AIOS:* a first merge collision → a nudge + a convention, not a lockdown. Proportional, starts gentle, escalates only if needed.

**6. Conflict-resolution mechanisms.**
*Original:* rapid, low-cost, locally-accessible arenas to resolve disputes among users or between users and officials.
*AIOS:* define the merge/collision/dispute protocol *before* the conflict — cheap and fast. For agents on one repo: a known re-sync path and scoping discipline.

**7. Minimal recognition of rights to organize.**
*Original:* the right of users to devise their own institutions is not challenged by external authorities.
*AIOS:* a company/space owns and governs its own namespace; canonical doesn't reach in. Self-governance at a layer is respected.

**8. Nested enterprises.**
*Original:* for commons that are parts of larger systems, governance activities are organized in multiple nested layers.
*AIOS:* personal `custom/` → `<company>/` namespace → canonical. Three nested, each self-governing at its scope, composing into the whole.

## Why this beats both naive options

- **vs. tragedy of the commons** (everyone optimizes locally, the shared thing degrades): the principles create monitoring + graduated sanctions + fitted rules, so local incentives align with the shared resource's health.
- **vs. top-down control** (one owner gates everything): collective-choice + right-to-organize + nested layers distribute authority to where the knowledge is, avoiding the bottleneck and the "move information to authority" anti-pattern.

## Practical distillation

Most shared-substrate failures trace to a *missing* principle:
- Silent drift → no **monitoring** (4).
- Personal content leaking in → no **boundary** (1).
- Bottleneck on one owner → no **collective-choice** (3) or **nested layers** (8).
- Recurring collisions → no **conflict-resolution mechanism** (6) or **graduated sanctions** (5).

Diagnose a struggling shared space by asking which principle is absent, then add it.
