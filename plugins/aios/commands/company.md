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
| `skills/` | `skills/{company}/` | Company-specific Agent Skills |
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

### Step 4.5 — Auto-bundle the `onboarding-{company}` agent

Before pushing, copy `agents/onboarding-{company}.md` from the scaffold and replace its `{company}` / `{Company}` / `{org}` / `{YYYY-MM-DD}` placeholders with the operator's actual values. The agent ships with every new venture-context repo so mounters get the HR-Day-1 experience automatically. The agent reads `voice.md` at invocation time, so the auto-draft from Step 4 above directly determines how this agent will sound when teammates mount.

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

### Step 6 — Update tracker + advisory

Update `.{name}-sync` with new hash + today's date.

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
