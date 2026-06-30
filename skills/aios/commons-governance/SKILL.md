---
name: commons-governance
description: "Govern shared resources well using Elinor Ostrom's design principles for the commons — applied to AIOS shared substrate: multi-operator vaults, collaboration spaces, company-synced infrastructure, and multiple agents writing one git repo. Use when designing rules for a shared space, deciding who-decides-what across collaborators or agents, preventing tragedy-of-the-commons or write-collision dynamics, setting boundaries on a shared repo/folder, or standing up collab/company governance. Distributed authority done right, grounded in governance science rather than top-down control."
---

# Commons Governance — sharing a resource without a boss

A shared vault, a collaboration space, a company-synced infra repo, a single git repo written by a fleet of agents — these are all **commons**: resources many actors draw on and modify. The naive failure is "tragedy of the commons" (everyone optimizes locally, the shared thing degrades — merge collisions, clobbered files, drift). The naive fix is top-down control (one owner gates everything → bottleneck, "move information to authority"). Elinor Ostrom's Nobel-winning work showed a third way: **self-governed commons that work, via specific design principles.** This skill applies them to AIOS shared substrate.

The eight principles, applied, with sources: [`references/ostrom-design-principles.md`](references/ostrom-design-principles.md).

## The eight principles, applied to AIOS shared substrate

1. **Clear boundaries** — define exactly what's shared and who the participants are. (Which folders/repos are the commons? Who has access? `custom/` and personal vault are explicitly *not* the commons.)
2. **Rules fit local conditions** — match the rules to *this* group's actual usage, don't import generic policy. (A two-person space and a ten-person company need different rules.)
3. **Collective-choice arrangements** — those affected by the rules can change the rules. (Authority moves to the information — the people doing the work shape how the space works.)
4. **Monitoring** — the state of the commons is visible to participants. (Sync trackers, status commands, a shared changelog — everyone can see drift.)
5. **Graduated sanctions** — responses to problems are proportional, starting gentle. (A first collision → a nudge and a convention; not a lockdown.)
6. **Conflict-resolution mechanisms** — cheap, fast ways to resolve disputes. (A defined merge/conflict protocol, a clear escalation path.)
7. **Recognized right to organize** — the group's authority to govern itself is respected, not overridden from outside. (A company/space owns its namespace; canonical doesn't reach in.)
8. **Nested enterprises** — for larger systems, govern in layers. (Personal `custom/` → `<company>/` namespace → canonical: three nested scopes, each self-governing.)

## How to apply (the workflow)

1. **Draw the boundary first (Principle 1).** Name precisely what's shared and who participates. Most shared-space pain is an undrawn boundary — personal content leaking into the commons, or unclear membership.
2. **Set the smallest rule set that fits (2 + 3).** Don't import a heavy policy. Write the few rules this specific group needs, and make them changeable by the group.
3. **Make state visible (4).** A commons no one can monitor degrades silently. Ensure there's a tracker/status surface everyone can read.
4. **Define the conflict path before the conflict (5 + 6).** Decide the merge/collision/dispute protocol up front, graduated and cheap. (For agents on one repo: scope every `git add`, never `-A`; commit fast to release the lock; a known re-sync path.)
5. **Respect the layer (7 + 8).** Govern at the right scope. Personal stays personal; a company governs its namespace; only the genuinely-universal rises to canonical. Don't govern down into a layer that owns itself.

## The AIOS-native instances this lens governs

- **One git repo, many agents.** Classic commons. The collision risk (whoever commits first sweeps others' in-flight files) is a tragedy-of-the-commons dynamic; the fix is path-scoped staging + fast commits + a known protocol (Principles 5–6), not a single committer.
- **Collaboration spaces (`/aios:collaborate`).** A shared work substrate with external collaborators — needs explicit boundaries, fitted rules, and a conflict path.
- **Company-synced infra (`/aios:company`).** A company namespace is a nested, self-governing enterprise (Principle 8): it owns its layer, governs its own rules, and only universal pieces graduate upstream.

## Worked example

*Standing up a two-person collaboration space.* Naive: share a folder and hope. Commons lens: (1) name exactly which folder is shared and that personal vaults are out of scope; (2) write the two rules that actually matter for two people; (3) agree either can change them; (4) point both at the sync status; (6) agree the conflict protocol (who resolves a merge, how). Five minutes of Ostrom up front prevents the slow degradation that kills shared spaces.

## Relationship to the rest of the system

This is the governance-science backing for "Trust Is Architecture" and "move authority to information," and it's the lens for `/aios:collaborate` and `/aios:company`. Where `sustainable-cadence` governs the operator's capacity and `leverage-points` chooses where to intervene, this one governs *shared* resources across multiple actors.
