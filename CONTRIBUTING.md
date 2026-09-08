# Contributing to The AIOS

The AIOS compounds when operators feed real-world use back into the framework. Every operator running it surfaces a *class* of problem that can be fixed once at the spec layer and inherited by everyone via `/aios:update`. That is the whole flywheel — **adoption is a diagnostic surface, not just distribution.** This document is how you contribute to it without breaking that flywheel.

You don't have to write code — or open a pull request — to contribute. There are two flavors, and both are first-class.

---

## The one rule that protects everyone: `custom/` first

Before any contribution question, learn this: the framework ships **canonical infrastructure** — commands, agents, skills, hooks, MCPs, templates — that is byte-identical for every operator and overwritten on every `/aios:update`. The thing that makes the framework *yours* is the **extension layer**, and it lives in `custom/`.

Every infra layer has a `custom/` subfolder reserved for your additions:

```
agents/custom/        skills/custom/        plugins/custom/<your-plugin>/
hooks/custom/         mcps/custom/          templates/custom/
```

**`/aios:update` never touches anything inside `custom/`.** Your extensions survive every framework update. Build whatever you need there first.

**Why this matters:** if you hand-edit a bundled file (e.g. `plugins/aios/commands/today.md`) in your own vault, your edit vanishes on the next update. Worse — if you *only* ever edit bundled files, your work can't be shared without collisions. So:

1. **Personal need** → build it in `custom/`. Done. It's yours, it's safe.
2. **Per-command tweak** → `USER.md` → `## Command personalizations` → `### /<command>`. Read before every run, never overwritten.
3. **Want others to have it** → that's a contribution (read on).

Most things should stay in `custom/`. The bar for shipping something beyond your own vault is **"others need this,"** not **"this is good."** Plenty of excellent infra should live forever in `custom/`.

---

## Which repo? — three repos, and the question that actually routes you

The AIOS ships from **three public repos**, and every one of them takes contributions the same way: **fork → branch → pull request** (the commands, and the one accident to avoid, are in § The contribution dance below).

| Repo | Owns | You're here if… |
|---|---|---|
| **[The-AIOS/aios](https://github.com/The-AIOS/aios)** (canonical) | The framework: commands, agents, skills, hooks, MCPs, templates, and the docs you're reading | Your change is to a `/aios:` command, an agent, a skill, a hook, a template, or a rule in `CLAUDE.md` |
| **[The-AIOS/aios-glass](https://github.com/The-AIOS/aios-glass)** | The IDE surface — the panel, its controls, the in-editor session experience | Your change is to what the panel shows or does |
| **[The-AIOS/aios-app](https://github.com/The-AIOS/aios-app)** | The desktop app — installer, first-run, the explorer, viewers, session panes | Your change is to the app's windows, setup flow, or packaging |

Both surface repos carry their own `CONTRIBUTING.md` with their setup, gates and house style — **read theirs once you know you're in the right place.** This section's only job is getting you to the right door, not through it.

> **⚠️ "Extension" means two unrelated things in this document, and the collision is worth one sentence.** Above, *"the extension layer"* means **`custom/`** — your own agents and skills inside a vault. **AIOS Glass is also an extension** — an IDE extension, a separate repo, nothing to do with `custom/`. When this file says *extension layer*, it always means `custom/`.

### The question that routes you is what you OBSERVED, not which layer you think you're in

*"Agent/skill/command/template → canonical"* is a **layer** rule, and it only helps if you already know your layer. It fails in exactly the case where misrouting actually happens: **when a documented thing does not work.** The doc is canonical; the behaviour may not be.

| What you observed | Suspect | Why |
|---|---|---|
| **A documented flag or field has no effect** | The surface that **executes** it — not the doc that **describes** it | Check the launch args (`ps -p <pid> -o command=`) **and** the running behaviour before filing. A flag can be accepted and silently dropped. |
| A command's *instructions* are wrong, unclear, or missing a case | canonical | The spec is the artifact |
| A rule in `CLAUDE.md` produced the wrong behaviour | canonical | …unless the surface never applied it — see row 1 |
| The panel shows the wrong thing, or a button does nothing | Glass | |
| Install, first-run, updates, windows, packaging | the App | |
| An agent/skill/template is missing or wrong | canonical | |
| It works in one surface and not the other | the surface that's wrong | Glass and the App are **two independent implementations of one protocol**. A fix ported into one and not the other is the expected shape of the bug, not a surprise |

**The worked example, because it is the case the layer rule gets wrong.** A spawn request carrying `"tier":"fast"` was silently ignored: the field was accepted, no error, and the worker ran on the frontier model. `"tier"` is documented in **three canonical files** — so filing against canonical was the reasonable conclusion and the wrong one. The defect was in the App's fulfiller, which launched `claude` without the flag. Locating it took the launch `argv` **plus** the worker's own transcript, because argv alone is a cousin of the running behaviour.

**If you're unsure after all that, file against canonical.** We route it. A misfiled issue costs a comment; an unfiled one costs the fix.

---

## The contribution dance — from "I found something" to an open PR

The router above gets you to the right door. This gets you through it.

### The rule that prevents the one accident that matters: never contribute from your vault

**Your `~/aios` is not a clone of canonical, even though it started as one.** The setup flow clones the framework and then points `origin` at **your own private repo** — so on a live install `origin` is your vault, and canonical is usually **not a remote at all**. It exists as `repo=` in `.aios-update`, and `/aios:update` reaches it by cloning to a temp directory.

That matters because canonical also ships a **template `vault/`** at the same paths your private content occupies. So the obvious sequence — branch from your vault's `main`, push it to a fork, open a PR — puts `vault/00 - notes/context/observed/` in the diff. It is the § Personal hygiene violation this file calls non-negotiable, reached by following the steps that look correct.

So the mechanic is one sentence: **contributions come from a second, separate clone that has never held a vault.**

> **The tell, for humans and sessions alike:** if the tree you are about to push from contains a **`.aios-update`** file, it is somebody's *vault*, not a contribution clone — stop. Canonical does not ship that file; it appears only once a vault has synced. This holds on both install paths, including a vault that was forked rather than cloned.

### First time — set up a contribution clone

```bash
# Fork canonical, then clone YOUR FORK somewhere that is NOT ~/aios
gh repo fork The-AIOS/aios --clone=false          # creates {your-username}/aios
git clone git@github.com:{your-username}/aios.git ~/code/aios-contrib
cd ~/code/aios-contrib
git remote add upstream git@github.com:The-AIOS/aios.git    # canonical
```

You now have `origin` = your fork (you can push) and `upstream` = canonical (you cannot). That asymmetry is the point.

### Every contribution after that

```bash
cd ~/code/aios-contrib
git fetch upstream
git checkout -b fix/short-slug upstream/main     # branch from CANONICAL main, never your fork's
# ...make the change · add or extend a test · add the CHANGELOG entry...
git push -u origin fix/short-slug
gh pr create --repo The-AIOS/aios --fill
```

Then work the § Before-you-open-a-PR checklist, and watch CI on the PR.

**Branch from `upstream/main` every time.** Your fork's `main` goes stale the moment canonical moves, and a branch cut from a stale base produces a diff full of changes you did not make — the review then cannot see your actual contribution.

**`git push` to canonical will be refused, and that is correct.** Nobody outside the maintainers has push access, so a permission error there means your setup is right, not broken. You push to *your fork*; the PR crosses the gap.

### If you are a Claude session doing this on an operator's behalf

The sequence is the same, plus one hard precondition and one habit:

- **Before the first push, run `git remote -v` and check for `.aios-update`.** A tree carrying that file is the operator's live vault — do not create a branch there, and do not push from it. Set up a contribution clone instead, per above. A session cannot un-publish an operator's observed context once it is in an open PR.
- **`gh pr create` is an outward-facing action** — confirm with the operator before opening it, the same as any send. Everything up to the push is reversible; the PR is public.

---

## The two flavors of contribution

You've found something the framework should absorb. There are two ways to give it back, depending on whether you're shipping *code* or *signal*.

### Flavor A — Non-technical (no PR): report the problem, propose the direction

You don't need to build anything to make the framework better. The single most valuable contribution is often **a clearly-named problem-class** — surfaced by email, message, a GitHub Issue, a Discussion thread, or any channel that reaches a maintainer.

This flavor covers:
- **A bug or friction class** you hit in real use ("every multi-agent session re-introduces X because the docs instruct the racy pattern").
- **A design proposal / discussion draft** for something with a fork in it, where nothing is built yet and the call belongs to the maintainer ("should this become a canonical contract, or stay optional?").
- **A conduct or philosophy observation** about how the framework or its community operates.

What makes a non-technical contribution land:

1. **Name it as a *class*, not an incident.** "This happens to every operator who runs N parallel agents," not "this happened to me once." Class-level framing is what makes something a *framework* candidate rather than a personal `custom/` tweak.
2. **Bring the smallest reproduction you can.** What you did, what you expected, what happened. One concrete trace beats a paragraph of description.
3. **Propose a direction, hold the decision loosely.** "Here's how I'd fix it — but the canonical-vs-optional call is yours." Proposing without assuming it belongs in core is the right posture.
4. **For design forks, open a discussion draft before code.** If the change has architectural consequences (a new canonical contract, a runtime assumption, a cross-cutting convention), open a **GitHub Discussion or Issue describing the problem-class and proposed direction first** — a lightweight RFC. Get alignment on the *shape* before anyone builds it. This is the right home for "nothing's built yet, but here's the idea."

A non-technical contribution can graduate into a technical one — either you build it once there's alignment, or a maintainer does. Either way the signal was the contribution.

### Flavor B — Technical (PR): you built the fix

You built something and want it shipped as code. Two sub-routes, by **scope** — they are not a hierarchy.

#### B1 — Canonical PR (for genuinely universal fixes)

You hit a problem that **any operator running the framework will hit**, built a structural fix, tested it live, and want it in core so everyone inherits it via `/aios:update`. Canonical PRs go to the framework repo: **[`github.com/The-AIOS/aios`](https://github.com/The-AIOS/aios)**.

A good canonical PR:

1. **Fixes a problem-class, not an incident.** The bar for canonical is *"every operator needs this,"* not *"this is useful to me."*
2. **Prefers structural fixes over per-actor discipline.** A fix that makes the wrong thing *impossible* beats one that asks every operator to remember to do something. (Fix the system, not the symptom.)
3. **Is tested live in a real vault before you propose it.** A design that's never executed is a discussion draft (Flavor A), not a PR.
4. **Carries zero operator data.** See § Personal hygiene — this is non-negotiable.
5. **States the upstream question when the design has a fork.** Build it for yourself first so it's real, but don't assume it belongs in core — name the canonical-vs-optional decision and leave it to the maintainer.

#### B2 — Company-distributed (team-scoped, no canonical PR)

You built infra your *company or stable team* needs, but it isn't universal — a jurisdiction-scoped bundle, a venture's deck-builder, a domain agent tuned to one market. **Don't PR it to canonical.** Distribute it through a company-context repo:

- Scaffold one from [`The-AIOS/company-template`](https://github.com/The-AIOS/company-template) (context files + optional infra folders: `agents/` · `plugins/` · `hooks/` · `mcps/` · `skills/` · `templates/`).
- Drop your infra into the matching folder.
- Teammates run `/aios:company --mount <your-repo-url>` and inherit the whole layer **in one prompt**. It lands namespaced under `agents/<company>/`, `plugins/<company>/<plugin>/`, etc. — never colliding with `custom/` or canonical.

`custom/` (personal), `<company>/` (team), and canonical (everyone) are the same extension principle at three scopes. The question that picks the route is simply: **who needs this?**

---

## The promotion path (how a personal tweak becomes universal)

The cleanest canonical contributions *start* as personal extensions and earn their way up:

```
custom/ extension  →  proves useful in real use  →  confidence it's universal
   →  PR moving it from custom/ into the canonical bundle
```

For commands, the promotion candidate is flagged by `/aios:housekeeping` after an override has earned its keep. For other infra (agents/skills/hooks/MCPs/templates): build in `custom/`, run it for real, and open a PR moving it into the canonical bundle only once you're confident it's *universal* — not just useful to you.

---

## How to add each kind of infra

The mechanical "how" for a technical contribution. Each layer has a personal home (`custom/`), a company home (`<company>/`), and a canonical home (the PR target). → For the at-a-glance map of **every infra type × the three layers** (bundled · `custom/` · `<company>/`) with the exact add-steps for each, see **[`EXTENSION-MAP.md`](./EXTENSION-MAP.md)**.

### A command (`/aios:<name>`)
1. **Personal:** `plugins/custom/<your-plugin>/commands/<name>.md` + a `.claude-plugin/plugin.json`, registered in `.claude-plugin/marketplace.json`. Never add operator commands inside `aios/`.
2. **Canonical (PR):** `plugins/aios/commands/<name>.md`. A bundled command must be synced across its **3 runtime locations** (source → marketplace cache → plugin cache); document the change in `CHANGELOG.md` and bump the count everywhere it's stated (CLAUDE.md, README, SETUP, `commands/_index.md`).

### An agent
1. Copy `templates/agent-template.md`.
2. **Personal** → `agents/custom/<name>.md` (overrides a bundled agent of the same name; the spawn wrapper warns on collisions).
3. **Company** → `agents/<company>/<bundle>/<name>.md`, shipped via `/aios:company`.
4. **Canonical (PR)** → the right bundle under `agents/aios/{sales,strategy,finance-legal,engineering,communication,personal}/`. Update `agents/_index.md`.
5. Frontmatter must include `name`, `description` (with semantic trigger phrases), `keywords`, `tools`, `tags`, `created`/`updated`, `status`.

### A skill
A folder with a `SKILL.md`. Personal → `skills/custom/<name>/`. Canonical → `skills/aios/<name>/`. Vendored third-party skills go in their source-named folder (e.g. `skills/anthropic/`) with the upstream license preserved.

### A hook
A `.py`/`.sh`/`.ps1` script referenced by `settings.json`. Personal → `hooks/custom/`. Canonical → `hooks/` flat, documented in `hooks/_index.md`. A good hook PR arrives with its install rationale + knobs documented, not just the code — local-first, no surprise dependencies, and a clear contract if it has swappable backends.

### An MCP
Vendor the server in `mcps/<name>-mcp/` (the `-mcp` suffix namespaces it) with a `README` + auth notes, add an install block to `mcps/setup.sh`, register via `claude mcp add`, and update `mcps/_index.md`. Personal MCPs → `mcps/custom/`. **MCP policy: bundled (local) over claude.ai-hosted** — hosted MCPs break on an Anthropic account switch; bundled ones authenticate independently and survive. If you add a hosted MCP because no local server exists yet, flag it as a "bundling candidate" in `mcps/_index.md`.

### A template
`.md` in `templates/`. Personal → `templates/custom/`. Canonical → `templates/aios/`. Update `templates/_index.md`.

### Marketplace registration
New bundled plugins register in `.claude-plugin/marketplace.json` (`name`, `displayName`, `version`, `description`, `source`, `license`, `repository`, `keywords`). The aios plugin's own manifest lives at `plugins/aios/.claude-plugin/plugin.json` — keep version + description in sync between the two.

---

## Testing & evidence (the bar before you assert "done")

- **Run it live in a real vault before proposing it for core.** A design that's never executed is a discussion draft, not a PR.
- **Run a premortem / inversion pass.** Ask *"how does this fail?"* — timeouts, offline, concurrency, cost ceilings, platform differences (macOS vs Linux vs Windows). Report what testing caught.
- **Concurrency matters.** The AIOS often runs several agents at once, and they all read and write the same vault — a single shared git repo. If your contribution touches git, files, or shared state, test it with **2+ agents running in parallel** before you ship it.
- **Don't claim it passes without showing the command + output.** Evidence before assertions, always.
- **When the claim is behavioural rather than mechanical, pre-register the criteria.** A test proves a function; it cannot prove *"the rewrite still makes a session behave the same way."* For that, write the acceptance scenarios **before** the new text exists, state the bar so it can fail (*accepted only if the new version passes every scenario the old one passes*), run both, and read the results against the written criterion rather than by keyword. Publish the criteria before the numbers — the order is the evidence. [#98](https://github.com/The-AIOS/aios/pull/98) is the worked example.

### The contribution we cannot make ourselves: a platform or locale nobody here runs

This is a standing request, not a nice-to-have. **Three of the five most valuable findings in a recent week came from platforms and locales no maintainer runs**, and none of them was subtle once seen:

- Two Python hooks read text with no explicit encoding, so on Windows they fell back to the locale codepage and died on the **first accented character**. `/today` and `/close-day` then reported no data — **indistinguishable from a vault with nothing configured.** Found by an operator on a Spanish-locale Windows install.
- `SETUP.md` told Windows and Linux operators the desktop app was macOS-only for **three days after both platforms shipped**, routing them to install an IDE and an extension when one installer would do. Found by watching a new operator onboard.
- A brand-new operator's very first daily note reported a cheerful green *"no unread Slack"* — for a Slack they had declined to connect.

None of those is findable by more care on the maintainer side. **The knowledge that lets you maintain a system is the same knowledge that blinds you to its first surface** — you cannot un-know that your own Slack is configured, or that your locale is UTF-8. So if you are running AIOS on **Windows, on Linux, in a non-English locale, or as a genuine first-timer**, the most useful thing you can send is not a fix. It is:

- **what the first run actually looked like** — the wrong turn, the step that assumed something you didn't have, the message that asserted a state nobody measured;
- **the exact error text**, before you work around it;
- **what you expected to happen**, which is often the more valuable half.

A Flavor-A report (§ *The two flavors of contribution*) is a complete contribution here. You do not need to build the fix, and you do not need to be sure it is a bug — *"this confused me and here is what I saw"* is a finding, because confusion at the first surface is a defect in the surface.

### Shell portability — write for bash 3.2, not just the bash you have

Anything with a `#!/usr/bin/env bash` shebang (every hook in `hooks/`) may be serviced by **bash 3.2** — the bash Apple still ships at `/bin/bash`, and what a stock Mac resolves to. If your PATH has Homebrew bash first, *your machine cannot reproduce this class of bug*, and neither could most maintainers.

The one that bites, because our hooks run `set -u`:

```bash
arr=()
"${arr[@]}"                 # ✗ bash 3.2: "arr[@]: unbound variable" → the script ABORTS
${arr[@]+"${arr[@]}"}       # ✓ portable empty-safe form; no-op on bash 4+, quoting preserved
```

Use the `+alternate` form for **any array that can legitimately be empty** — optional flags, optional parents, collected varargs. An array with a proven length guard above it (`[ ${#arr[@]} -eq 0 ] && …`) doesn't need it; don't widen a diff speculatively.

Why this earns a section: it fails **mid-operation**, not at startup. `#6` aborted `aios-note-append` *after* the block was written into the note and *before* it was committed — so `/close-session` silently lost its capture on stock-bash Macs, and the natural retry duplicated the block. `tests/aios-commit.test.sh` now covers both empty-array paths, and CI runs that suite under real 3.2 on macOS (`primitives_bash32`).

### Before-you-open-a-PR checklist
CI (`.github/workflows/validate.yml`) covers repo structure, manifests, frontmatter, personalization + credential guards, migration drift, capability counts, skill resolution, and the commit-primitives regression suite — on ubuntu **and** under bash 3.2 on macOS. It's a floor, not a substitute: most of what matters here is a spec executed by Claude at runtime, so review stays human and the discipline stays author-run. Before opening a PR, confirm:

- [ ] It lives in the right home (`custom/` / `<company>/` / canonical) for who needs it.
- [ ] Zero operator data anywhere in the diff (see § Personal hygiene). Grep your own diff.
- [ ] Indexes updated (`*_index.md` for the layer you touched) and any stated counts bumped.
- [ ] For commands: synced across the 3 runtime locations.
- [ ] For git/file/shared-state changes: a 2-parallel-actor test, with output.
- [ ] `CHANGELOG.md` entry added (see below).

---

## Personal hygiene — the inviolable rule for shared contributions

**Any contribution that leaves your own vault — a canonical PR, or company-distributed infra given to others — must contain ZERO operator data.** This is non-negotiable.

- No names of people in narrative (commit messages, CHANGELOG, code comments). Reference by PR number (`#4`), describe *what* changed, never *who* found it.
- No paths, emails, IDs, or anything from `vault/` (especially `context/declared/` and `context/observed/` — those are private and never leave the personal repo).
- Infra files never reference personal-vault content. Personal → infra references are fine; infra → personal references are broken links for everyone else.
- De-personalize before you send: swap your identifiers to placeholders, and grep the diff for your own name/email/paths.
- Secrets: never commit real tokens. Ship `.template` files + `.gitignore` the reals. GitHub push-protection will block secrets — if it fires, reset and re-commit clean, never click "unblock."

---

## Commit & CHANGELOG conventions

- **[Conventional Commits](https://www.conventionalcommits.org):** `<type>(<scope>): <description>` — subject < 72 chars, imperative, no period. Types: `feat`·`fix`·`docs`·`refactor`·`perf`·`test`·`chore`·`build`·`ci`·`style`. Body = WHY + refs. Footer = `BREAKING CHANGE:` when applicable.
- **CHANGELOG** (Keep a Changelog): one consolidated entry per day across ships. Entries use a **State → Ask → Act** structure because they're executed by the *teammate's Claude* during their `/aios:update` flow (detect drift, ask inline, execute — hard preconditions skip the rest; restart steps go LAST). Reference `hash: {short-sha}` + PR numbers. `CHANGELOG.md` is byte-identical across all repos — and every `hash:` must be **reachable from `main`** in canonical, not merely resolvable. Those differ: a PR branch head resolves fine in a full clone and disappears on squash-merge, while `/aios:update` clones `--single-branch main`, so an unreachable hash makes the ancestor test return 128 — read as *inconclusive, not synced*, which leaves that entry reading NEW forever for every operator. The value you want is the **squash-merge commit**, which only exists after merge: cite the PR number in your PR and add the hash in a follow-up commit once it lands.
- De-personalization applies to CHANGELOG narrative exactly as to commits.

---

## Licensing

The framework is **GPL-2.0-or-later** — uniformly. `LICENSE` (GPL v2), `NOTICE`, the marketplace manifest, and the plugin manifest all agree. Your contributions to canonical are accepted under the same license.

**Vendored third-party components keep their upstream license.** Some directories vendor external open-source work that ships under a different license (e.g. `skills/anthropic/` and some `mcps/*-mcp/` upstreams are Apache-2.0). When you vendor or compose third-party open-source into a contribution: **preserve the upstream license, attribute it in the folder, and keep provenance clean.** Don't relicense someone else's work by absorbing it, and don't add an upstream whose license is incompatible with GPL-2.0-or-later distribution. → The full per-repo, per-subtree license map — what's GPL vs Apache/MIT-vendored vs private-vault vs company-licensed, plus the redistribution checklist (e.g. the **proprietary** Anthropic skills that must *never* be vendored) — is **[`LICENSE-AUDIT.md`](./LICENSE-AUDIT.md)**.

---

## How we engage

How we hold each other while contributing is load-bearing, not decoration. The same principles that govern the framework govern its community (see `CLAUDE.md`):

- **Radical Candor over Ruinous Empathy.** Critique the work directly; hold the contributor warmly. Sycophancy and performative agreement both erode the system's integrity.
- **Protect the ugly babies.** A rough first contribution — a half-built hook, a discussion draft with open questions — is more welcome than polished silence. The first version is allowed to be ugly.
- **Authority moves to the information.** The operator who hit the problem live often knows more than the maintainer. Listen to where the knowledge actually is.
- **Contributions in any language, from any background, are first-class.** The onboarding and cold-start flows already run in operators' native languages; the same inclusivity applies to who shapes the framework.

No harassment, no discrimination, and no extraction of unpaid labor framed as "community" — provenance and credit stay clean and honest.

---

## Where to learn the system before you contribute

- **Read [CLAUDE.md](./CLAUDE.md) first** — the behavioral contract, the principles of intelligence collaboration, the self-update / antifragile rules. Contributions that don't fit the operating philosophy get bounced regardless of code quality.
- **The full Operating Manual** lives at **<https://www.the-aios.com/#manual>** — the design language, architecture, fleet, rituals, and trust contract in one document (online or PDF). The deepest single artifact for understanding *why* the framework is shaped the way it is.
- **[CHEATSHEET.md](./CHEATSHEET.md)** — the operating index. **[TOOLS.md](./TOOLS.md)** — the full menu. **[SETUP.md](./SETUP.md)** — install + the canonical flow.
- When in doubt about *where* a contribution belongs, the [`onboarding-aios`](./agents/aios/personal/onboarding-aios.md) agent knows the whole doc + repo map.

---

*The framework gets better every time an operator's real-world use becomes everyone's inherited fix. That's the contribution. Welcome.*
