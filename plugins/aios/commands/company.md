---
tags:
  - aios
  - command
  - sync
  - on-demand
description: Mount one or more companies into your vault. Multi-substrate (GitHub repo, Google Drive folder, future adapters), multi-company. Subcommands for create, mount, sync, status, invite, dry-run.
allowed-tools: mcp__obsidian__*, mcp__google-workspace__*, Bash(git:*), Bash(gh:*), Bash(rm:*), Bash(cat:*), Bash(mkdir:*), Bash(cp:*), Bash(file:*), Read, Write, Edit, WebFetch
argument-hint: "optional: --create | --mount {url} | --sync {name} | --sync-all | --status | --invite {name} | --dry-run"
---

# /company — Mount Your Company in Your Vault

Mount your company's shared business context (positioning, market docs, brand, primitives, operating manual) into your personal vault. Substrate-pluggable: GitHub repo, Google Drive folder, or future adapters. Supports **multiple** mounted companies (e.g., consulting firm + product venture).

## When to use

When mounting an existing company's venture-context repo into your vault, or scaffolding a new one. Substrate-pluggable (GitHub recommended ✅, Drive supported). Run `--sync-all` weekly to keep all mounted companies current.


## Mental model

This command is structurally different from `/collaborate`:

- **`/collaborate`** scaffolds *shared co-creation surfaces* — projects you and one or more collaborators build together (e.g., a partner space on Drive, a co-founder GitHub repo). Bidirectional content, multiple writers.
- **`/company`** mounts *upstream company context* into your vault — material that lives at a canonical source (your venture's GitHub repo or Drive folder), maintained by whoever has write access, **read-only-pulled** into your vault by `/company`. Companies you work with become discoverable layers in your AIOS.

The two commands compose naturally — a collaboration space can EXIST within a mounted company's substrate, but they answer different needs (mount the company once; collaborate as needed inside it).

## The hierarchy

- **Personal vault** — your individual AIOS (declared / observed / intent / projects-you-own)
- **Mounted company** — read-only mirror of a company's `venture-context` repo or Drive folder, landing at `vault/00 - notes/context/ventures/{company}/`
- **Multi-company** — operators may mount 0, 1, or many companies (an independent consultant might mount their own personal venture AND a client's company; a single-company employee mounts just their employer's)

## Natural-language triggers

Claude routes to `/company` when the user says things like:

| Phrase | Subcommand |
|---|---|
| *"Mount my company"* / *"Set up Acme in my vault"* | `/company` (default → create-or-mount-existing) |
| *"Sync the company"* / *"Refresh company context"* | `/company --sync {default-or-only-company}` |
| *"Sync all my companies"* | `/company --sync-all` |
| *"What's the status of my mounted companies?"* | `/company --status` |
| *"Create a new company repo"* / *"Spin up a venture-context for {company}"* | `/company --create` |
| *"Mount an existing company"* / *"Add {company} to my vault"* | `/company --mount {url}` |
| *"Generate invite for my teammates to mount {company}"* | `/company --invite {company}` |

## Subcommands

| Invocation | What it does |
|---|---|
| `/company` | Default interactive flow — detect mounted companies → offer create / mount / sync / sync-all |
| `/company --create` | Scaffold a new company-template (interview-driven) into a new remote — defaults to GitHub (highly recommended ✅), Drive as fallback. Registers in USER.md |
| `/company --mount {url}` | Register an existing company repo/folder in USER.md (teammate onboarding to someone else's company) |
| `/company --sync {name}` | Pull latest from one mounted company |
| `/company --sync-all` | Pull latest from all mounted companies |
| `/company --status` | List mounted companies + last-sync state + drift indicators |
| `/company --invite {name}` | Generate a copy-paste blob for teammates to mount this company |
| `/company --dry-run` | Preview the operation, no writes |

## USER.md schema

`/company` reads and writes the `## Companies (mounted)` section in `USER.md`. Format:

```markdown
## Companies (mounted)

> Each mounted company has its own venture folder + substrate config. /company reads this table to know what to sync.

| Company | Substrate | Source | Venture folder | Last sync |
|---|---|---|---|---|
| acme | github | git@github.com:acme/acme-context.git | vault/00 - notes/context/ventures/acme/ | 2026-05-21 |
| beta-co | github | git@github.com:beta-co/beta-co-context.git | vault/00 - notes/context/ventures/beta-co/ | 2026-05-21 |
| beta-co | drive | https://drive.google.com/drive/folders/... | vault/00 - notes/context/ventures/beta-co/ | 2026-05-19 |
```

**Empty section signals zero mounted companies** — the default interactive flow detects this and offers to scaffold the first one.

## The company-template (context + optional infra)

When `/company --create` runs, it scaffolds from [The-AIOS/company-template](https://github.com/The-AIOS/company-template). The structure has **two layers**: **context** (always shipped) and **optional company-distributed infra** (agents, commands, hooks, MCPs, skills, templates — empty by default).

### Context — `context/` folder (13 canonical files + 3 optional addons)

**Layer 1 — Identity:**
- `about_venture.md` — mission, history, what the company does
- `positioning.md` — category, narrative, worthy rivals
- `personas.md` — who it serves
- `primitives.md` — core technical/conceptual IP
- `origin-story.md` — why this venture exists, founding insight, what we learned the hard way

**Layer 2 — Operations:**
- `gtm.md` — go-to-market motion
- `offerings.md` — products / services catalog
- `pricing.md` — pricing model + tiers
- `culture.md` — values, decision frameworks, rituals
- `market.md` — competitive landscape, macro forces, where the puck is going

**Layer 3 — Brand + Voice:**
- `voice.md` — **required.** Voice and tone — how the venture speaks. Load-bearing for `onboarding-{company}` agent (it reads voice.md to calibrate its register) and for every Claude session writing in the company's name. If the operator can't articulate voice during the interview, Claude auto-drafts a first pass from `about_venture` + `positioning` + `brand` + `culture` and asks for confirmation before committing.
- `brand.md` — URL pointers to logos / fonts / palette / asset library (vault stores context, not binaries)
- `design.md` — visual design system (per Google's design.md spec)

**Optional addons (scaffolded as commented-out, uncomment to activate):**
- `coding-practices.md` — engineering standards, code review philosophy, commit conventions
- `tools-we-use.md` — internal stack reference
- `repos.md` — pointer list of company repos with 1-line descriptions

When operator runs `--sync`, `context/` content lands at `vault/00 - notes/context/ventures/{company}/`.

### Repo-root files (always)

- `README.md` — entry point for humans browsing the repo
- `CLAUDE.md` — company-side operating manual (voice, tradeoff rules, escalation triggers) — composes at runtime with operator's personal `INTENT.md`

### Optional company-distributed infra (top-level folders)

Beyond context, a company can distribute **its own infra** to operators who mount it. When `/company --sync` runs, these land at namespaced paths in the operator's vault:

| Template folder | Lands at (operator's vault) | Use case |
|---|---|---|
| `agents/` | `agents/{company}/` | Company-specific agents (e.g. `acme-board-prep`, `acme-onboarding`) |
| `plugins/<plugin>/` | `plugins/{company}/<plugin>/` | Company-distributed Claude Code plugins (each plugin a self-contained bundle — operator invokes its commands as `/<plugin>:<name>`, registered in the operator's marketplace at sync time) |
| `hooks/` | `hooks/{company}/` | Company-specific event hooks (e.g. UserPromptSubmit injectors) |
| `mcps/` | `mcps/{company}/` | Company-internal MCP servers (CRM, billing, internal tools) |
| `skills/` | `skills/{company}/` | Company-specific Agent Skills (registered into `~/.claude/skills` at sync time via `skills/setup.sh` / `.ps1` when the sync brings skill changes — see Step 5.5 of `--sync`) |
| `templates/` | `templates/{company}/` | Proposal / contract / deck shapes specific to the company |

**Empty folder = no shipment.** If `agents/` is empty (just README placeholder), operators mounting this company won't get any agents/{company}/ in their vault. Companies opt-in to each infra type as their needs evolve.

**Sync routing rule:** the sync command walks each top-level folder. For non-empty folders, content lands at `{dir}/{company-name}/` in the operator's vault (namespaced by company). For the `context/` folder, content lands at the canonical venture path (`vault/00 - notes/context/ventures/{company}/`) without `context/` prefix.

## Substrate adapters

`/company` reuses the substrate-adapter pattern from `/collaborate`. v1 ships two: **GitHub** (highly recommended) and **Google Drive**. Future adapters (Notion, Confluence, etc.) register following the same shape.

### GitHub adapter — **highly recommended** ✅

This is the canonical substrate for venture-context. `/company --create` defaults to GitHub and only falls back to Drive when the operator explicitly requests it (e.g., non-coder collaborators who don't have GitHub access).

**Why GitHub is preferred:**
- **Structural fidelity** — venture-context ships markdown files with YAML frontmatter, `_index.md` registries, folder hierarchy. Git preserves all of this *byte-identical*. Drive doesn't (see frontmatter caveat below).
- **Versioning + history** — every change is a commit. `/company --sync` knows exactly what changed since last sync via `git diff`. Drive has no equivalent.
- **Matches the AIOS folder convention** — `agents/{company}/`, `templates/{company}/`, `plugins/{company}/<plugin>/`, etc. — these only work cleanly when the source is git-versioned with the same structure.
- **Same upstream pattern as the framework + skills + MCPs** — Bucket 18's `.upstream-sync` freshness check applies identically. Drift, pull, diff — one mental model across surfaces.
- **Diff-driven collaboration** — teammates can PR changes to the venture-context; you review before pulling.
- **Auth + permissions** — granular access control via GitHub teams/collaborators; out-of-the-box CI on the venture-context repo if needed.

**Configuration:**
- **Source format:** `git@github.com:{org}/{repo-name}.git`
- **Recommended repo name:** `{org}/{company}-context` (e.g., `acme/acme-context`, `my-startup/my-startup-context`) — operator-instance, descriptive in-org. Inside a company's own org, the repo name should identify *which* venture's context this is; `venture-context` reads abstract there, `{company}-context` reads concrete.
- **Visibility:** private by default; operator decides who has push access
- **Sync mechanism:** `git clone --depth=50 --single-branch` into `/tmp/company-sync-{name}/`, diff against last hash in `.{name}-sync` tracker, apply changes
- **Tracker file:** `.{company}-sync` in the venture folder (e.g., `.acme-sync`)

### Google Drive adapter — supported, choose when needed

Pick Drive only when there's a real constraint pushing you there — most often when stakeholders editing the venture-context don't have GitHub access or fluency, or when the venture content already lives in Drive and migration costs more than it's worth.

**Known caveats:**
- **Frontmatter doesn't survive round-trip** (per `/collaborate` pilot 2026-05-09): YAML frontmatter gets stripped or reformatted when files round-trip through Drive's docs format. For Drive-substrate companies, frontmatter must be parsed by convention (first paragraph) rather than literal YAML — limits which framework features work cleanly.
- **No git diff** — sync compares `last_modified_iso` per file instead of commit hashes; can't show "what changed."
- **Folder structure conventions** are operator-enforced, not git-enforced — easier to drift.

**Configuration:**
- **Source format:** Drive folder URL (e.g., `https://drive.google.com/drive/folders/...`)
- **Sync mechanism:** list folder via Google Workspace MCP, fetch each `.md` file as Doc → markdown, compare to local
- **Tracker file:** `.{company}-sync` with `last_modified_iso` instead of `hash`

### During `--create` — substrate selection prompt

The interview asks: *"Which substrate? (1) **GitHub — highly recommended** ✅ (preserves YAML frontmatter, gives you version history, supports the full company-distributed infra layers from the AIOS folder convention). (2) Google Drive (only choose this if stakeholders editing the venture-context don't use GitHub)."* Default = GitHub unless the operator explicitly picks Drive. If they pick Drive, restate the frontmatter caveat + structural limitations before confirming, so the choice is informed.

## Default flow — `/company` (no args)

### Step 1 — Detect state

Read `USER.md` → `## Companies (mounted)`:

- **Table empty / section missing** → branch to "First company" flow (jumps to Step 3 with create-or-mount choice)
- **One company mounted** → offer: *"Sync `{name}` (last sync {date})? Or do something else (--create / --mount / --status)?"*
- **Multiple companies mounted** → offer: *"Sync which? `{name1}` / `{name2}` / `--sync-all` / something else?"*

### Step 2 — Quick path (sync existing)

If the operator picks sync, jump to the `--sync {name}` flow (see § Subcommand: --sync below).

### Step 3 — Multi-step path (create / mount / new operator)

Ask:

> *"Do you want to:*
> *(a) **Create** a new company from the AIOS company-template (interview-driven scaffold)*
> *(b) **Mount** an existing company repo/folder (you got an invite from a teammate)*
> *(c) **Status** — show what's currently mounted (read-only)"*

Then route to the corresponding subcommand.

## Subcommand: `--create`

Interview-driven scaffold for a new company. Walks the operator through the 12 core files (and optional addons), then pushes to a new remote.

### Step 1 — Substrate choice

- Detect available substrates by checking active MCPs (GitHub MCP active? Google Workspace MCP active?)
- Default recommendation: **GitHub** (frontmatter survives, version-controlled, PR-governed collaboration)
- Alternative: **Drive** (collaboration-native, non-coder-friendly, but frontmatter caveat applies)

Ask: *"Substrate? (github / drive)"*

### Step 2 — Remote location

**GitHub:**
- *"GitHub org or account?"* (e.g., `acme-co`, `my-startup`)
- *"Repo name? (default: `venture-context`)"* (press enter for default)
- *"Visibility? (private / public)"* (default: private)

**Drive:**
- *"Parent Drive folder URL? (where to create the company folder)"*
- *"Folder name? (default: `{company}-venture-context`)"*

### Step 3 — Pre-fill check (the /collaborate-inspired addition)

Ask:

> *"Got existing context to seed from? Options:*
> *(1) Existing vault folder (e.g. `vault/00 - notes/context/ventures/acme/`)*
> *(2) Local paths / URLs (Drive folder, GitHub README, existing docs)*
> *(3) Paste content directly*
> *(4) None — start fresh"*

If pre-fill source provided:
- Read sources, extract content for each of the 12 files
- Draft each file based on existing material
- Generate an audit report:

```
✅ Filled (N): about_venture · positioning · gtm · offerings · pricing · primitives · culture · design
🟡 Inferred from observed sources (M): personas (drawn from gtm.md customer references) · CLAUDE.md (drawn from INTENT.md venture-level overrides)
⚪ Pending (K): brand.md (no asset URLs in source — please provide) · README.md (template scaffold — ready as-is)
```

Operator reviews 🟡 inferred files + fills ⚪ pending before push.

### Step 4 — Walk the operator through files (if no pre-fill)

For each of the 13 canonical files in order (Layer 1 Identity → Layer 2 Operations → Layer 3 Brand+Voice), ask ONE focused question. Smart defaults provided. Operator answers; Claude drafts; operator refines.

Type `skip` to leave a scaffold for later. Type `open` to edit in editor. Type `short` for a 1-line answer that Claude expands.

**Special handling for `voice.md` (required, load-bearing):**

When the interview reaches `voice.md`, **don't accept `skip`.** Voice is load-bearing — the `onboarding-{company}` agent reads it to calibrate its register, and every Claude session writing in the company's name uses it as the canonical reference. A missing voice.md means a wrong-tone agent and wrong-tone external comms.

If the operator types `skip` or says "I don't have voice content yet," **auto-draft a first pass** from the already-filled context — typically `about_venture` + `positioning` + `brand` + `culture` — and present it back:

```
I drafted voice.md from your other context. Here's the gist:

  Voice in one line: "{derived line}"
  Posture: {4 derived attributes}
  Audiences: {1-3 derived calibrations from personas + gtm}
  Anti-voice: {2-3 things this voice explicitly is not}

This is a starting point — you'll refine over time. OK to commit
this draft? (yes / let-me-edit / show-me-the-full-file)
```

The auto-draft is honest about its source — it doesn't pretend to be the operator's voice, but it's a real first pass that gets the bundle to a complete state. Operator can refine in `voice.md` directly post-create.

**Special handling for `design.md` (required, load-bearing — same discipline as voice.md):**

`design.md` is the canonical brand interchange format (Google Labs `design.md` spec). It defines tokens — colors, typography, spacing, shadows — that EVERY downstream agent reads: `deck-builder`, `content-writer`, one-pager generators, future Stitch-based screen generators. A missing design.md means brand drift across all surfaces. Like voice.md, **don't accept `skip` on design.md.**

Branch based on whether the operator has design source material:

**Path A — Source-driven** (operator has website, brand PDF, existing collateral, design tokens already documented):

> *"Got design sources I can extract from? Options:*
> *(1) Live website URL (I'll scrape CSS + typography)*
> *(2) Existing brand PDF / design doc (provide path or URL)*
> *(3) Past collateral folder (let me look at deck/one-pager/site files for tokens)*
> *(4) Operator paste — type out the brand spec*

Invoke `design-md-author` agent (in `agents/aios/communication/`) with the source. It extracts tokens, asks 4-5 clarifying questions (primary color confirmation, type-pair preference, etc.), and writes `context/design.md`.

**Path B — Awesome-design-md fallback** (operator has nothing — *"start fresh"* or *"no brand assets yet"*):

> *"No worries — pick a base brand from the awesome-design-md catalog, then customize. Based on your company category ({gov / fintech / AI / consumer / etc.}), I suggest:*
> *(1) **{Brand A}** — rationale: {one line}. Preview: {URL}*
> *(2) **{Brand B}** — rationale. Preview: {URL}*
> *(3) **{Brand C}** — rationale. Preview: {URL}*
> *Pick one as your base. We'll customize 5-6 tokens so your brand is distinct."*

Catalog: [VoltAgent awesome-design-md](https://github.com/VoltAgent/awesome-design-md) (73 design systems, MIT-licensed). Heuristics same as the deck-builder Phase 0 path 3 ("Propose new design").

After base selected, walk the operator through 5-6 customizations:
1. **Primary color** — keep base or substitute (hex picker — what evokes the brand?)
2. **Accent color** — keep or substitute
3. **Dark theme support** — does the company need both light + dark variants? (yes/no — affects downstream deck-builder + others)
4. **Type pair** — display + body fonts (keep base pair, or pick from Google Fonts / system)
5. **Voice-adjacent visual tone** — formal / playful / bold / minimal (drives spacing + corner-radius defaults)
6. **Logo placeholder** — if operator has a logo path, embed; else placeholder SVG referencing the chosen color tokens

Result: `context/design.md` written with tokens + a comment-line at top: `# Sourced from awesome-design-md base: {brand} (https://github.com/VoltAgent/awesome-design-md/tree/main/design-md/{brand}). Customizations: ...`

**Path C — Defer** (operator says "later" / "I'll think about it"):

Don't push without design.md. Instead:
1. Drop a `.pending-design-md` marker in the company's context folder
2. Write a SCAFFOLD `context/design.md` with `# {{COMPANY}} Design System — PENDING` heading + placeholder token table
3. The scaffold + marker get pushed to remote (so the bundle is complete enough to mount)
4. `/aios:today` will surface the pending marker as a Phase 0 task every run until it's filled in (same pattern as quota-autopilot-capture)
5. Tell operator: *"Pushed with a design.md scaffold + pending marker. Your daily plan will nudge you until it's filled in — earlier you do it, less brand drift across downstream collateral."*

**Path D — Existing design.md exists** (in pre-fill source from Step 3):

Reuse it. Validate it has the canonical token sections (colors, typography, spacing, optional dark-theme variant). If sections are missing, surface the gaps + offer to fill via Path A or B for the missing pieces only.

The same "design.md is load-bearing" discipline applies on `--sync` for existing companies — if a company is mounted without design.md, `/aios:today` surfaces this on every run + offers to walk through it.

### Step 4.5 — Onboarding agent (bundle-ships-with companion)

After context files are drafted, **explicitly mention the onboarding agent + offer customization**. The operator must KNOW the agent ships and have a chance to adapt it before push — silent "copy + replace placeholders" leaves them blind to a load-bearing piece of their bundle.

Show this prompt:

```
Almost ready to push. One last thing: every venture-context ships with
an `onboarding-{company}.md` agent — the HR-Day-1 companion for anyone
who mounts {Company} later. It reads your `voice.md` to calibrate its
register, then walks operators through identity → products → personas
→ pricing → toolbox. Three paths (new hire / commercial brief /
structural overview) and a change-digest mode for post-sync calls.

Auto-fires after `/aios:company --mount`; offered after `--sync` with
substantive changes; spawnable anytime via `spawn onboarding-{company}`.

Three options for shipping it:

  (a) Ship the template as-is — placeholders auto-filled from your
      context. Generic shape, works for 80% of cases.

  (b) Let me adapt the template based on what you just filled in.
      I noticed {1-2 specific observations from the interview content
      — e.g., "your offering ladder has 5 distinct tiers with format
      multipliers; the agent's product-walk could mirror that
      structure" OR "your voice is bilingual ES/EN with fluent
      code-switching; I can wire that into the welcome flow's
      language-detection". Pull the observations from voice.md /
      personas.md / offerings.md you just drafted.}. I'll draft a
      customized version + show you the diff.

  (c) Skip — ship the template, you'll edit `agents/onboarding-
      {company}.md` directly post-create.

Default (a) if no answer in 60s.
```

**Branching:**

- **(a) As-is:** copy `agents/onboarding-{company}.md` from the scaffold, replace `{company}` / `{Company}` / `{org}` / `{YYYY-MM-DD}` placeholders with operator's actual values. Ship.

- **(b) Customized:** Claude reads the just-drafted `voice.md`, `about_venture.md`, `personas.md`, `offerings.md`. Suggests 2-4 specific customizations to the agent's flow — examples:
  - Welcome-flow opening phrasing matched to voice.md's register
  - Path A product-walk reordered to match the operator's actual offering ladder structure
  - Bilingual / multilingual code-switching rules if voice.md indicates them
  - Voice-specific examples in the change-digest section (drawn from positioning + brand)
  - Sign-off line in the company's tone (Sovra's "Bienvenido al equipo"; ChuyCepeda's "Clarity before velocity. AI amplifies what is already clear.")
  
  Show the diff. Operator accepts / edits / reverts to (a). Ship the accepted version.

- **(c) Skip:** copy template with placeholder replacement only. Ship. Operator can edit later.

**Always tell the operator they can edit the agent any time post-create** — it lives at `agents/onboarding-{company}.md` in the repo. Edits propagate to mounters on their next `/aios:company --sync`.

**Why offer (b):** the template is necessarily generic (it serves Sovra + ChuyCepeda + Acme + any future operator equally). But each company has a *distinct* voice + offering shape that the template can't anticipate. Claude has the just-filled context fresh in mind and can spot specific customizations that improve fit — it's a low-cost, high-value moment of polish.

### Step 5 — Push to remote

- `git clone The-AIOS/company-template /tmp/{company}-scaffold/`
- Overlay drafted files
- `git remote set-url origin {new-remote}`
- Commit + push

### Step 6 — Register in USER.md

Add a row to `## Companies (mounted)` with the new company's substrate + source + folder + today's sync date.

### Step 7 — Generate invite blob (the `/team-onboarding`-inspired output)

Display a copy-paste blob the operator can share with teammates:

```
📋 Invite for teammates — copy-paste this:

> Mount {Company} venture context in your AIOS vault:
> /company --mount {source-url}
> 
> Then run /company --sync {company} to pull the latest.
```

If `mcp__slack__*` is available, optionally offer: *"Want me to draft a Slack message to your team with this invite?"*

## Subcommand: `--mount {url}`

Register an existing company repo/folder in USER.md without scaffolding. This is the path for **teammates being onboarded** to a company already created by someone else.

### Step 1 — Detect substrate from URL

- `git@github.com:...` or `https://github.com/...` → GitHub adapter
- `https://drive.google.com/drive/folders/...` → Drive adapter
- Other → ask operator to confirm substrate

### Step 2 — Verify access

- **GitHub:** `git ls-remote {url}` — if fails, surface the auth/access issue clearly
- **Drive:** attempt to list folder via Google Workspace MCP — surface permission error if denied

### Step 3 — Determine company name

Default: extract from URL (`{org}/venture-context` → company = `{org}`). Override with `--name {custom}` if the operator wants a different short name.

### Step 4 — Initial sync

Run the equivalent of `--sync` against this newly-registered company. Pull all files. Land in `vault/00 - notes/context/ventures/{company}/`.

### Step 5 — Register in USER.md

Add row to `## Companies (mounted)`.

### Step 6 — Surface what was pulled

Show the operator a summary: which files landed, what's in `about_venture.md` headline, what CLAUDE.md says about how this company operates. Welcome them to the new layer.

### Step 7 — Auto-fire `onboarding-{company}` agent (if it ships in the bundle)

If `agents/onboarding-{company}.md` exists in the just-pulled bundle (canonical for new venture-contexts created via `--create`; back-fillable for older ones), **automatically spawn it**. The operator just chose to mount this company — that's the consent signal. No "want me to onboard you?" prompt; just open the welcome flow.

```bash
spawn onboarding-{company} "Walk me through {Company} — I just mounted."
```

If the bundle doesn't carry an onboarding agent (legacy venture-contexts, partial scaffolds), surface a one-liner instead:

> *"This bundle doesn't ship its own onboarding agent yet. Walk through `vault/00 - notes/context/ventures/{company}/README.md` for orientation, or ask 'tell me about {Company}' anytime."*

The auto-fire is the venture-context cousin of `/aios:cold-start-interview` → `onboarding-aios` (framework-level). Same pattern: when an operator chooses to step into a new context layer, the orientation companion meets them there.

## Subcommand: `--sync {name}`

Pull latest from one mounted company. Read-only — never writes back to the source.

### Step 1 — Read tracker

Read `vault/00 - notes/context/ventures/{name}/.{name}-sync`:
```
repo={source-url}
hash={last-synced-commit-or-modified-iso}
synced={date-of-last-sync}
substrate={github|drive|...}
```

### Step 2 — Clone or list

**GitHub:**
```bash
rm -rf /tmp/{name}-sync-check && \
  git clone --depth=50 --single-branch {url} /tmp/{name}-sync-check
```

**Drive:** list folder contents via Google Workspace MCP (`list_drive_items`).

### Step 3 — Diff against last sync

**GitHub:**
```bash
git -C /tmp/{name}-sync-check diff {stored_hash}..HEAD --name-only
```

If HEAD matches stored hash → "Your `{name}` context is current (synced `{date}`)." → cleanup → done.

**Drive:** compare modification timestamps per file.

### Step 4 — Show changes

For each changed file, surface the diff to the operator:

```
## {Company} context has updates

**Last synced:** {date} ({N} commits behind / {N} files changed)

### Changes detected:

**{filename}**
- Added: {what was added}
- Changed: {what changed}
- Removed: {what was removed}
```

### Step 5 — Apply (with confirmation)

Ask: *"Apply these updates to your vault?"*

If confirmed, route by file type:
- **Text files** (`.md`, `.svg`, `.css`, `.json`, `.js`, `.ts`, `.yml`, `.txt`) → Obsidian MCP `patch_note` or `write_note`
- **Binary files** (`.png`, `.jpg`, `.pdf`, `.woff`, `.ttf`) → Bash `cp` (Obsidian MCP can't handle binaries)

**Always skip:**
- `.{name}-sync` tracker (per-personal-vault control state — never overwritten by sync)
- `_index.md` and `about_business.md` if they exist at venture-folder root (user-owned — surface advisories instead)

### Step 5.5 — Register newly-synced company skills (ONLY if skills changed)

**Skills must be *registered*, not just landed.** Company skills land at `skills/{company}/` (Step 5 routing), but a file on disk isn't a loadable skill until it's symlinked into `~/.claude/skills`. `skills/setup.sh` (macOS/Linux) and `skills/setup.ps1` (Windows) do that — and their scan is **venture-aware by design** (`skills/*/*/SKILL.md`, registering every source folder *except* `anthropic`/`superpowers`), so `skills/{company}/` is already covered. The only missing piece is *invoking* the registrar after a sync brings skills — mirroring how company plugins are registered at sync time.

**Gate (per the operator note 2026-05-30):** run this **only if this sync added or changed a `skills/{company}/**/SKILL.md`** (check the Step 3 diff). If no skill files changed, **skip** — registration is idempotent, but running it when nothing changed is unnecessary work.

When skills did change, run the registrar (idempotent — skips names already linked; new symlinks load at next session start, not mid-session):
- **macOS / Linux:** `bash "$HOME/aios/skills/setup.sh"`
- **Windows:** try PowerShell 7, fall back to Windows PowerShell 5.1 (stock machines ship only the latter):
  ```bash
  if command -v pwsh >/dev/null 2>&1; then
    pwsh -File "$HOME/aios/skills/setup.ps1"
  else
    powershell -File "$HOME/aios/skills/setup.ps1"
  fi
  ```

Report: *"Registered {N} new {company} skill(s) into `~/.claude/skills` — restart Claude Code sessions to load them."*

### Step 5.6 — Register newly-synced company plugins (ONLY if a company plugin changed)

**Plugins must be *registered*, not just landed** — the mirror of Step 5.5 for skills. Company-distributed plugins land at `plugins/{company}/<plugin>/` (Step 5 routing), but a folder on disk isn't a loadable plugin until it's both **(a)** an entry in the vault's `.claude-plugin/marketplace.json` and **(b)** installed from the marketplace.

**Gate (mirror of 5.5):** run **only if** this sync added or changed a `plugins/{company}/<plugin>/.claude-plugin/plugin.json` (check the Step 3 diff). If no company *plugin* changed, **skip**.

**Precondition — the `the-aios` marketplace MUST be vault-sourced** (per SETUP §6: `claude plugin marketplace add ~/aios`). Registration only propagates if the marketplace tracks the live vault. Verify: `claude plugin marketplace list` → the `the-aios` source should be the **vault path**, not `~/.claude/plugins/marketplaces/the-aios` (a frozen copy). If it's still a frozen copy, re-point first:
```bash
claude plugin marketplace remove the-aios && claude plugin marketplace add ~/aios
# then reinstall already-installed plugins: claude plugin install aios@the-aios (+ any custom/venture already in use)
```

For each company plugin that landed/changed:
1. **Register in the vault's `marketplace.json`** — **MERGE, never byte-replace** (preserve every existing bundled/custom/company entry; same rule as `/aios:update`). Add an entry, reading `name`/`version`/`description` from the plugin's own `plugins/{company}/<plugin>/.claude-plugin/plugin.json`:
   ```json
   { "name": "<plugin>", "source": "./plugins/{company}/<plugin>", "version": "<from plugin.json>", "description": "…", "category": "productivity", "keywords": ["{company}"] }
   ```
2. **Refresh + install:**
   ```bash
   claude plugin marketplace update the-aios
   claude plugin install <plugin>@the-aios
   ```
3. Optionally add `"<plugin>@the-aios": true` to `enabledPlugins` in `~/.claude/settings.json`.

Report: *"Registered + installed {N} {company} plugin(s) — restart Claude Code sessions to load their commands."*

### Step 6 — Update tracker + advisory

Update the tracker at `vault/00 - notes/context/ventures/{name}/.{name}-sync` with new hash + today's date. **Always write to the venture-folder path — never to the vault root.** The tracker lives WITH the venture content it tracks; placing it at the root pollutes the operator's repo root and breaks the "read from venture folder" pattern that Step 1 uses to find it.

If `about_venture.md` changed, surface Tier-3 advisory: *"ℹ️ The `{name}` venture's `about_venture.md` changed. Per CLAUDE.md → Index Maintenance, consider refreshing the `{name}` entry in `vault/00 - notes/context/declared/about_business.md` (and `_index.md` if the one-liner shifted)."*

### Step 7 — Offer the change-digest (`onboarding-{company}` agent in digest mode)

If the sync was **substantive** (≥1 new file OR ≥3 modified files in `context/`/`agents/`/`templates/`/`plugins/`/`hooks/`/`mcps/`/`skills/`), AND the bundle ships `agents/onboarding-{name}.md`, **offer** (don't auto-fire) the digest:

```
🆕 Sovra-context shipped N changes since your last sync. Want a brief
   digest from the onboarding agent? (yes / skip)
```

If yes:
```bash
spawn onboarding-{name} "digest since {previous-hash}"
```

If no, continue. Trivial syncs (single non-substantive file change, no new files) skip the offer silently — never interrupt for a 1-line edit.

**Why offer, not auto-fire:** the operator ran `--sync` mid-task most likely — they may not want orientation now. The `--mount` case is different (operator just chose to enter the company, that's a clear consent signal). Sync = ongoing maintenance; consent posture stays opt-in.

### Step 8 — Clean up

```bash
rm -rf /tmp/{name}-sync-check
```

## Subcommand: `--sync-all`

Iterate over every row in USER.md `## Companies (mounted)` and run `--sync {name}` for each. Surface a summary at the end:

```
Sync summary:
- acme: ✅ 3 files updated
- beta-co: ✅ current (no changes)
- gamma-co: ⚠️ access denied (check permissions)
```

## Subcommand: `--status`

Read-only. Output:

```
## Companies (mounted) — status

| Company | Substrate | Last sync | Drift | Files |
|---|---|---|---|---|
| acme | github | 2 days ago | 3 commits behind | 12 |
| beta-co | github | today | current | 11 |
| gamma-co | drive | 5 days ago | 2 files modified | 14 |
```

Drift indicator is informational — does NOT auto-sync.

## Subcommand: `--invite {name}`

Generate the copy-paste blob for teammates (same shape as Step 7 of `--create`):

```
📋 Invite — copy-paste this to a teammate to onboard them:

> Mount {Company} venture context in your AIOS vault:
> /company --mount {source-url}
> 
> Then run /company --sync {name} to pull the latest.
```

Optionally offer to draft a Slack/email message with this content.

## Subcommand: `--dry-run`

Combine with `--create`, `--mount`, `--sync`, or `--sync-all`. Outputs the operation plan + simulated changes without writing.

## Relationship to other commands

- **`/collaborate`** — different purpose (shared co-creation spaces with bidirectional content). A space can EXIST within a mounted company; both can coexist.
- **`/aios:update`** — syncs the AIOS framework itself (commands, hooks, mcps, skills) from `The-AIOS/aios`. `/company` syncs your company's business context. Different repos, different concerns.
- **`/today`** — reads `## Companies (mounted)` to surface relevant venture context in Radar / Energy block.
- **`/housekeeping`** — Bucket 17 (CLAUDE.md + USER.md health check) verifies each mounted company's tracker + folder + access status.

## Rules

- **Read-only pull semantics.** `/company` never writes back to the source. Permissions live in GitHub/Drive (operator manages who has write access — out of AIOS scope).
- **Never overwrite the tracker file.** `.{name}-sync` is per-vault control state; ignore it in any diff/apply.
- **Tracker location is ALWAYS the venture folder.** `vault/00 - notes/context/ventures/{name}/.{name}-sync` — never `~/aios/.{name}-sync` (vault root). The tracker travels with the content it tracks. If you find a stray `.{name}-sync` at the vault root, that's a bug from an older sync run — move it to the venture folder (or recreate it there with the current hash) and delete the root copy.
- **Surface advisories for user-owned files.** `_index.md`, `about_business.md` — these are user-owned (full venture roster + voice). Show that they changed; don't auto-apply.
- **Always preview before applying.** Never silent-sync. Diff → confirm → apply.
- **Vault stores context, not binaries.** Heavy assets (images, fonts) live at their canonical home (Drive/CDN); `brand.md` holds URL pointers. If a sync brings in unexpected binary files, surface and ask before copying.
- **Multi-company aware.** When the operator says *"sync"* without naming a company, default to the only one if exactly one is mounted; otherwise ask which.
- Use `[[wiki-links]]` for all project names, context files, and ventures mentioned.

## See also

- `plugins/aios/commands/collaborate.md` — adjacent primitive (shared co-creation surfaces)
- `plugins/aios/commands/update.md` — sync the AIOS framework itself
- The-AIOS/company-template — the canonical scaffold repo
- `vault/00 - notes/context/ventures/` — where mounted companies land
