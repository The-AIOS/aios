---
name: shipping-a-saas
description: The build ORDER and the defaults that decide whether a product is debuggable six months in — what to build first (admin and seed data before the product, which is the part everyone gets wrong), deterministic seed data, non-sequential ids, one-command environments, and PR discipline. Use when starting a new product or service, when planning an MVP's sequence, when a build is about to skip straight to features, when reviewing whether a project has the scaffolding to be supported, or when setting up a repo's CI and deploy path. Opinionated defaults, all overridable in USER.md.
---

# Shipping a SaaS — order first, features second

Most build advice is about *what* to build. This is about **what order**, which is the decision that quietly determines whether the thing can be operated later. The order below is not a preference; each rung exists because skipping it costs more than it saves, and the cost arrives months after the decision.

> ### Read the operator's own stack declaration before anything below
>
> If `vault/00 - notes/context/declared/coding_style.md` or `coding-practices.md` exists, **it wins.** This file is the framework's recommendation for someone who has not decided yet; an operator who has decided has already written it down, and re-litigating their stack every session is the opposite of useful. Read theirs, apply §§ 1, 4 and 5 (which are stack-independent), and treat § 2's recommended stack as already answered.
>
> When their declaration and this file disagree, that is not drift — **a deviation is a decision.** Record it in their file with the reason, and move on.

---

## 1 · The build order

```
1  Foundation      environment · repo shape · database · migrations
2  Admin + seeds   admin view · impersonation · deterministic seed data   ← day one
3  Auth            signup · login · sessions · password reset
4  The product     the thing you actually set out to build
5  Polish          errors · loading states · accessibility · performance
```

**Rung 2 is the one everyone gets wrong, and it is second on purpose.**

The instinct is to build admin tooling last, because it is not the product and no customer asks for it. The consequence is that for the entire period *before* it exists — which is the period when everything is broken — nobody can see inside the system. Every support question becomes a hand-written database query. Every bug report becomes an archaeology session. Every demo is either fake or terrifying.

Concretely, rung 2 means: **a way to look at any record**, **a way to become a user** (impersonation, with an audit trail), and **seed data that produces a realistic populated system in one command.** Once those exist, everything after them is faster to build, faster to debug, and demonstrable at any moment. Build them before you have anything to look at, because you will not stop to build them once you do.

**Auth is rung 3, not rung 1.** It feels foundational and it is not: an admin view behind a single environment-variable check is enough to make rungs 1 and 2 real, and a product with no users does not need a password-reset flow. Building auth first is a common way to spend three weeks producing nothing anyone can see.

---

## 2 · The recommended stack

For an operator with no existing opinion, this is the framework's recommendation. It is **one coherent stack rather than a menu**, which is the point — the value is that every piece was chosen to work with the others, and mixing halves of two stacks gets you the integration problems of both.

```
Backend    Elixir + Phoenix, API-only (REST/JSON — no server-rendered HTML)
Frontend   React + TypeScript + Vite
Data       PostgreSQL · Redis (cache) · Meilisearch (search) · a DB-backed job queue
Dev env    Nix flakes — one command to a working environment, no Docker
Deploy     a push-to-deploy platform for most things;
           bare metal + declarative OS config when the economics or control win
```

**Why this shape, briefly.** API-only separates cleanly: backend is data and logic, frontend is presentation, and the boundary stays honest because there is no template layer to blur it. A DB-backed job queue means jobs are transactional with your data and visible in the same place — no second system to reason about at 2am. Nix gives the *same* definition across dev, CI and production, which is the actual property you want; the sentence that matters is **"`nix develop` gets you a working environment,"** not the tool's name.

**The deploy line is deliberately two options.** A push-to-deploy platform is right for most products, most of the time — the build-and-ship loop is the thing you touch daily. Bare metal with a declarative OS config wins when you are running stateful always-on services and the per-month economics or the sovereignty actually matter. Choose per product and say which, on the record.

**Where this recommendation comes from, and its honest caveats.** It is adapted from an open-sourced SaaS checklist by a working engineer, generalised here. Two caveats worth carrying:

- **Nix has a genuine learning curve.** *Timebox the spike.* Keep a fallback (a conventional Linux box with native service management and a reverse proxy) so the stack never blocks the ship. Lean toward the reproducible end-state; do not yak-shave into it.
- **A recommended stack and a shipping estate are different things.** Most operators already have running products on something else. That is not a migration order. **Every new product names its choice explicitly against this standard** — and inheriting an existing product's stack is a perfectly good reason, stated once, rather than a thing to feel bad about.

**Not this stack?** Sections 1, 4 and 5 hold regardless — build order, PR discipline and the deploy properties are stack-independent, and they are where most of the durable value is.

---

## 3 · Defaults that are hard to retrofit

Each of these is cheap on day one and expensive-to-impossible later. That asymmetry is the whole reason they are defaults.

**Deterministic seed data — no `Faker`, no random generators.** Seeds must produce byte-identical data on every run. Random test data makes every failure a one-off: the bug reproduces on your machine and not on anyone else's, and the test that catches it today passes tomorrow for no reason. Explicit, predictable values cost slightly more to write and remove an entire class of unreproducible failure. *A test whose input you cannot reconstruct is not a test, it is an anecdote.*

**Non-sequential ids (UUID/ULID) on anything a client can see.** Sequential ids leak volume and invite enumeration — `/invoice/1041` tells a stranger you have roughly a thousand invoices and lets them walk the range. They also make merging data across environments a manual reconciliation. Retrofitting means rewriting every foreign key.

**One command to a working environment.** The test is exact: *a new machine, a fresh clone, one command, a running app with data in it.* The tool does not matter — a devcontainer, `docker compose`, Nix, or an honest Makefile all pass. What fails is a README with eleven steps and a paragraph beginning "you may also need to." An environment only you can build is a project only you can work on.

**One place for the data model.** Schemas and migrations in a single location, one connection module used everywhere. When the model lives in three places, the third one is always the one that is wrong.

**Decide the money and time representation on day one.** Integer minor units for currency (never floats), UTC everywhere with the timezone applied at the edge. Both are trivial now and are data migrations later.

---

## 4 · PR discipline

**Rebase onto the mainline before you build, not before you merge.** Building on a stale base means your tests pass against a repository that no longer exists. Rebase first, force-push with `--force-with-lease` so you cannot silently discard someone else's push. (A single-branch clone cannot evaluate the lease — verify the remote by hand there.)

**One logical change per PR.** The reviewable unit is a change someone can hold in their head, not a day's work.

**Say what would break if the change is wrong.** A PR body that describes what changed is a diff with adjectives. The useful sentence is the failure the change prevents, or the one it would cause. It is also the fastest way to discover you cannot name one.

**Require that CI could actually fail.** The most common defect in a test suite is a check that measures nothing: a range selecting zero lines, an assertion vacuously true because a fetch returned nothing, an alternation satisfied by a helper the code never calls. **The discipline is mechanical — mutate the code so the defect is genuinely present, and require the red line before you trust the green one.** Where a check protects something important, ship the control alongside it: an assertion that fails loudly if the setup that makes the check meaningful did not happen.

**Merge one at a time when PRs touch a shared file.** Anything that edits the CI workflow, a lockfile, or a shared index will conflict with its siblings. Rebase each onto fresh mainline and merge serially; parallel merges of shared-file PRs produce conflicts that look like content disagreements and are not.

**Scope your commits when other agents or people write to the same tree.** `git add -A` sweeps whatever anyone else has in flight into your commit, which scrambles attribution and can commit half of someone's unfinished work. Name the paths.

---

## 5 · Deploy and platform — the property that matters

**The property that matters is a preview deployment per pull request.** Everything else is preference; this one changes how the team reviews, because a reviewer who can click the change reviews differently from one reading a diff. Choose whatever provides it.

The framework's default pairing is a **managed frontend host** for the web app and a **container platform** for services that need to run continuously (workers, queues, cron, anything with a long-lived process). Two named ones, with the traps that cost real time on each:

**Vercel-shaped hosts (frontend):**
- `--prebuilt` uploads a build made on *your* machine — including platform-specific binaries. A macOS build can fail on their Linux runtime in ways the local build never shows.
- Anchor `.vercelignore` patterns with a leading `/` or they match at every depth.
- Some plan tiers reject builds from commits carrying unexpected trailers; if builds fail with no useful log, check the commit trailers before the code.

**Railway-shaped hosts (services):**
- Free tiers commonly refuse deploys at peak hours. A deploy that "hangs" may be queued, not broken.
- Collaborator access and account access are different credentials; a collaborator generally needs a project-scoped token and the CLI rather than the dashboard integration.
- Creating a service from a Git source silently no-ops if the platform's app is not installed on the repo. Verify the service actually points at a source before assuming the deploy is configured.

**Environment variables are not a secret store.** Anything marked sensitive is typically write-only — pulling it back returns a placeholder, not the value. Code that expects to read its own secrets locally will work in development and fail in production. Reach the value from inside the deployed runtime, not from a local script.

---

## 6 · Before you call it shipped

- **A new machine can run it** from the README alone, with no conversation.
- **Someone else can support it** — the admin view answers "what happened to this user?" without a database client.
- **The tests can fail.** At least one was verified red before it was green.
- **Secrets are not in the repo**, and a pre-commit hook enforces that rather than a habit.
- **The operator can explain it.** An end-to-end build is the largest generator of comprehension debt there is — recap what shipped and offer the walkthrough. See the `comprehension-debt` skill.

---

*The build-order argument and the deterministic-seed and non-sequential-id defaults are adapted from an open-source SaaS checklist by an outside engineer, generalised here off its original stack. The PR and platform notes are this framework's own, each one written after it cost somebody a day.*
