---
tags:
  - aios
  - command
  - on-demand
description: Vault housekeeping — proposals to merge, archive, drop carries, refresh indexes, repair links, tidy antifragile, verify plugin cache, audit permissions
allowed-tools: mcp__obsidian__*, Read, Grep, Glob, Bash
---

# /housekeeping — Vault Housekeeping

Periodic care of the vault as it grows. Produces a review packet across 23 buckets — link repairs, index refresh, project merges, archival, carry cleanup, task dedup, table trim, INTENT.md drift, antifragile cleanup, permissions audit, plugin-cache verification, antifragile compact, USER.md drift, missed reports, antifragile→USER.md graduation, radar health, CLAUDE.md+USER.md health, upstream freshness, observed-context lifecycle, skill-registration verification, file placement drift, agent-output gate health, truth-surface drift — with proposals the user approves before anything is applied. Writes a log of what was proposed, approved, and applied.

**When to run:** monthly as a rhythm, or whenever the vault feels heavy (lots of carries, too many active projects, stale snapshots). `/today` will suggest it when triggers fire.

**Why it exists:** a growing vault accumulates structural entropy — projects drift from "active" to "dormant," carries become guilt instead of plans, tasks duplicate across project notes, index tables grow columns no one reads. The vault compounds value over time only if its structure stays legible. This is the recurring care that keeps it that way.

**Not this command's job:**
- Behavioral avoidance patterns → `/drift`
- Unwritten patterns across notes → `/emerge`
- Idea → permanent note promotion → `/graduate`
- Cross-domain bridges → `/connect`

`/housekeeping` is spatial. It reorganizes what already exists.

## Steps

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /housekeeping` for any user overrides. Apply them to the buckets below.

### Phase 0 — First-run signal

Check if `00 - notes/logs/command-logs/housekeeping-*.md` exists. If not, this is the **first run** on this vault — expect a heavier proposal packet (accumulated entropy from all prior usage). Note this in the Summary so the user knows subsequent runs will be lighter. On first run, prioritize proposals that unblock patterns (project merges, archived-project task migration) over low-stakes mechanical fixes.

### Phase 1 — Scan (build the proposal packet)

Gather evidence across **all 23 buckets — no skipping.** "Deferred to tooling" is banned; the scanning IS the tooling. If a bucket surfaces low signal, state that explicitly with evidence ("scanned N items, 0 merge candidates found") — don't hand-wave.

#### Bucket 1: Link repairs

1. Scan all notes for mentions of project names, context files, ventures, and people that exist as notes but aren't wiki-linked.
2. Find orphaned notes — zero incoming AND zero outgoing links.
3. Find broken wiki-links — `[[target]]` where `target.md` doesn't exist.
4. **Auto-categorize broken refs** into 4 buckets (so judgment is low-friction):
   - **Template placeholders** (`[[wiki-links]]`, `{{project-N}}`, etc.) — IGNORE silently.
   - **Forward-refs to unshipped content** (e.g., Substack post slugs `04-claude-code-for-teams` with matching draft in `substack/`) — IGNORE, will auto-resolve when the content ships.
   - **Product/entity names without dedicated notes** (e.g., `[[ProductX]]` referenced in prose but no `ProductX.md` exists) — propose **downgrade to plain text** OR **create stub**.
   - **Real orphans** (references to notes that existed under a different filename, or notes that were renamed/deleted) — propose **redirect** (using alias syntax to preserve display: `[[actual-file|display text]]`) or **leave as historical intent** if the ref lives in old daily notes/reflections recording what was considered.
5. Propose adds:
   - **Auto-apply candidates** — unambiguous additions (e.g., project name appears as plain text, single matching note exists).
   - **Orphan-connection candidates** — notes with zero incoming/outgoing links needing judgment on what to connect to.

#### Bucket 2: Index refresh

Scan every `_index.md` file in the vault. For each one:

1. List the folder's actual contents (files + subdirectories).
2. Read the index file and extract what it claims exists.
3. Compare:
   - Files in folder but NOT in index → **add**
   - Files in index but NOT in folder → **remove** (unless archived — archived stays)
   - Files in both but with wrong metadata (status, description outdated) → **update**

**Known index files:**
- `00 - notes/projects/_index.md` — project listing + snapshots
- `00 - notes/ideas/_index.md`
- `00 - notes/reflections/_index.md`
- `00 - notes/context/declared/_index.md`
- `00 - notes/context/observed/_index.md`
- `00 - notes/context/ventures/_index.md`
- `00 - notes/logs/_index.md`
- `templates/_index.md`
- `03 - export/_index.md` + subfolders
- `agents/_index.md` (canonical registry) + `agents/custom/_index.md`

Also refresh project snapshots in `00 - notes/projects/_index.md` — cross-check against each active project note's `## To-Dos`, `## Current State`, and last 7 days of daily notes. Update context paragraphs that have drifted.

#### Bucket 3: Project merges (NEW)

Compare pairs/triplets of active projects for overlap signals:

- Shared `venture` + `stakeholders` frontmatter
- Shared tags (e.g., both tagged `{venture}` + `{topic}`)
- Session notes in the last 30 days reference each other with `[[wiki-links]]` ≥ 3 times
- To-do lists contain tasks that could live in either project

If overlap is significant, propose:
- **Merge A into B** — A becomes a section of B (e.g., if A's scope is ≤30% of B's scope)
- **Parent/child** — A is a sub-project of B (both keep their notes, but A's `venture` adds B as secondary)
- **Split concern** — A and B share a concept; extract the shared concept into a new note both reference

#### Bucket 4: Project archival (NEW)

For projects with `status: active`:

1. Check last modified date of the project note.
2. Check sessions notes — any dated entry in last 30 days?
3. Check daily notes over the last 30 days — was this project referenced or had tasks?
4. Check calendar events — any meetings tagged this project in last 30 days?

If zero activity across all four signals for 30+ days → propose archive (change `status: archived`, remove from active snapshots, add to archived table).

**Exception:** if the project frontmatter has `dormant-ok: true`, skip (some projects are intentionally long-arc).

#### Bucket 5: Carry cleanup (NEW — expands old behavior)

Scan the most recent daily note's Parking lot + Carries forward sections. For each carried item:

- **Ask for the reason first, not the count.** Before proposing escalation/park based on carry count alone, check if the carry has a `reason:` tag (e.g. `_(carried ×8, reason: strategic-deferral)_`). If it does, respect it — a ×17 tagged `strategic-deferral` is intentional prioritization, not avoidance. Only propose action when the reason is **missing** or the reason itself has gone stale (e.g. `blocked-on-partner-response` but no ping in 30+ days).
- **×6+ without a reason tag:** propose **ask user for reason** before anything else. Carry count alone is not a verdict. Present: "{task} carried ×{N} without reason. Pick: `strategic-deferral` / `blocked-on-{who}` / `needs-challenge` / `park`." Once tagged, the count stops triggering.
- **×10+ with a stale reason OR no reason after being asked:** propose **explicit park** (move to project note Ideas section, remove from carry chain). This is the last-resort escalation — only after the user has had a chance to tag.
- **Ownership reassignment:** items whose natural owner (per project stakeholders) is NOT the user → propose **reassign** (move to project note's owner-tagged tasks, optionally draft a handoff message).
- **Dedup within parking lot:** two carries with same core task name differ only in emoji/prefix → propose **collapse** to one item with the highest carry count.
- **Scheduled vs overdue:** items tagged `scheduled W{N}` where W{N} has passed → propose **either reschedule or drop**.

#### Bucket 6: Task dedup across projects (NEW)

Scan all active project notes' `## To-Dos` sections. Find tasks that appear in 2+ project notes (same core task name, ignoring tags/emojis). For each:

- Determine which project is the canonical owner (usually: the one with the stakeholder match, or the one where the task was first added).
- Propose **keep in canonical project, remove from others**.

Avoid false positives: truly independent tasks happening to share words are fine (e.g., "Follow up" in two projects = different follow-ups). Require at least 2+ significant words (excluding stop words) or high similarity.

#### Bucket 7: Index table trim (NEW)

For every dataview table in `_index.md` files:

- Scan the table's columns and the actual column values across all rows.
- If a column is **empty across all rows** → propose removal.
- If a column has **identical values across all rows** → propose removal (not informative).
- If a column was added for a feature that's no longer live → propose removal.

Only propose trim for columns that are genuinely dead weight. Don't trim columns with occasional sparse data — those might become valuable as the vault grows.

**Dataview path-validity check (rename-cascade catch).** For every `FROM "folder/path"` clause in any `_index.md` dataview block, verify the referenced folder actually exists in the vault. A `FROM` pointing at a renamed/moved folder fails *silently* — the table just renders empty, so a stale path can sit broken for weeks unnoticed (caught 2026-06-15: 17 `FROM "04 - export/…"` clauses across 5 export indexes still pointed at the old folder after it was renamed to `03 - export` — the meetings index had been silently empty for weeks). For each `FROM` whose folder is missing: propose the corrected path if an obvious rename target exists (same basename under a different parent — e.g. `04 - export` → `03 - export`), else flag it for the operator. This is the structural sibling of Bucket 19's reference-integrity layer (which catches dead *command* refs in observed context); this one catches dead *folder* refs in dataview queries. Cheap grep, high silent-failure payoff.

#### Bucket 8: INTENT.md drift + autonomy opportunity gaps (NEW)

Read `INTENT.md` and propose:

- **Staleness** — check the `Updated:` date. If > 14 days old, flag for review. Check focus pillars: are they still what's actually driving work in daily notes + weekly plans? If a pillar has gone silent for 30+ days (no tasks tagged with its emoji) → surface it.
- **Autonomy-level promotion candidates** — for each domain in `## Autonomy levels` currently set to `draft` or `ask`: scan the last 30 days of daily notes and sessions. If the user **consistently approved actions without rewrites** in that domain (e.g., every Slack-internal-reply was sent as-drafted, every project-note-update was accepted) → propose **promote level** (`draft` → `autonomous`, `ask` → `draft`). Evidence-based trust progression.
- **Autonomy-level demotion candidates** — same scan but for domains currently `autonomous`: if actions were frequently rewritten / cancelled / corrected → propose **demote level** with specific examples.
- **Venture overrides** — are there new ventures in `00 - notes/context/ventures/*/` that aren't yet in `## Venture-level overrides`? Propose **add override section** with a starter template.
- **Tradeoff rules** — are new tradeoff decisions showing up in close-day decision journals that aren't yet encoded in `## Global tradeoff rules` or venture-level tradeoff rules? Propose **add rule**.
- **Explicitly NOT doing** — for each parked item, scan daily notes + session-insights for any recent mention. If a parked item has been mentioned / revisited / worked on in the last 30 days → propose **reactivate or reaffirm** (the user either changed their mind or should confirm the park).
- **Escalation triggers** — check if any trigger in the andon-cord table has fired in the last week but didn't produce the documented response (e.g., carry ×6+ didn't force a decision). Propose **review trigger logic** or **add context for exceptions**.
- **Anti-values** — any anti-value being violated in recent patterns (per `session-insights.md` or `patterns.md`)? Surface it as a growth-edge proposal, route to `growth.md`.

**Evidence discipline:** always cite specific files / dates / counts. "Last 14 Slack-internal replies sent as-drafted, 0 rewrites" beats "Slack internal feels autonomous."

#### Bucket 9: Antifragile cleanup (NEW)

Read `00 - notes/context/observed/antifragile.md`. Audit it for structural drift — content quality is rarely the problem; structure decays as entries get appended at the bottom regardless of where they belong. Look for:

- **Numerical / chronological order broken** — entries should be readable top-to-bottom by both number and date. Surface any entries out of sequence.
- **Section interleaving** — meta-patterns and numbered entries should live in distinct sections. Surface meta-patterns that ended up inside the patterns list (or vice-versa).
- **Stale meta-patterns** — the meta-patterns section captures cross-cutting themes. Scan recent entries (last 10+) for cross-cutting patterns that were articulated INLINE ("Related to #X" notes) but never lifted up into the meta section. Propose adding them.
- **Duplicates** — literal or near-duplicate meta-pattern statements (e.g., the same "shortcut that corrupts the source of truth" appearing twice). Propose dedupe.
- **Category-tag drift** — early entries may use short tags like `[PROCESS]`, `[ARCH]`; later ones use descriptive uppercase like `[INVISIBLE RUNTIME ASSUMPTION]`. Surface inconsistency. Propose standardizing on the descriptive form (preserves nuance).
- **Calibration logs going stale** — for entries that include trajectory data (e.g., entry #19 calibration log of estimate-vs-actual), check if any ratio data has been added recently. If user has tracked velocity twice in the last 30 days but didn't log it, propose appending the data points.

**Evidence discipline:** quote the exact section, list the entry numbers out of order, name the duplicate phrasing. "Entries appear in order 1-11, then meta, then 12-13, then 16, then 14-15, then 17-28" beats "antifragile feels disordered."

**Don't propose:** content edits to entries themselves, deletions of any entry (the file's "never delete" rule is sacred), or adding new entries (those happen at the moment of failure, not during housekeeping).

#### Bucket 10: Permissions audit (NEW)

Read `~/.claude/settings.json` (global) and the project's `.claude/settings.local.json` (vault-specific). Scan for:

- **Earned auto-approves** — recent permission prompts that were approved repeatedly. Source: scan the last 7 days of `~/.claude/projects/*/sessions/*.jsonl` for `permission_request` events that resolved as `allow` or `allow_always`. If a Bash command pattern (or MCP tool) was approved 3+ times in different contexts, propose adding it to `allow`.
- **Pattern consolidation** — multiple specific entries that could collapse into one wildcard. Examples: `Bash(git log)` + `Bash(git log *)` → just `Bash(git log *)`. `Bash(npm install)` + `Bash(npm install foo)` + `Bash(npm install bar)` → `Bash(npm install *)`. Propose only when the broader pattern is no riskier than the union of specific ones.
- **Stale specifics** — extremely narrow entries that almost certainly won't recur (e.g., `Bash(rm /tmp/specific-file-xyz.txt)`, `Bash(curl https://very-specific-one-time-url)`). Propose removal.
- **Missing deny-list entries** — destructive commands the user has implicitly avoided that should be hard-denied (`Bash(rm -rf /)`, force-push to main, etc.). Propose adding to `deny` if not already there.
- **MCP-tool churn** — MCP tools in `allow` that don't correspond to currently-installed MCP servers (run `claude mcp list` to compare). Propose removal.
- **Permissions that surfaced as gaps during the period** — if any command in this housekeeping run failed with "Permission denied" and the user manually approved via `!`, surface those as candidates for `allow`.

**Format the proposal:** show diff-style — "remove X, add Y, consolidate {A, B, C} → D" — so the user can scan in seconds. Include the audit-log evidence (the timestamp + count of approvals) for each earned auto-approve.

**Don't propose:** anything in the `deny` list — those are sacred. Permissions related to writing system files outside the user's home dir. Anything that would broaden access to credential stores (Keychain, ssh-keygen private keys, gcloud auth tokens).

**Apply mode:** when the user approves, write the diff to `.claude/settings.local.json` (or wherever the existing setting lives). Never overwrite — always merge. If the file structure has been hand-tuned, preserve order and comments where possible.

#### Bucket 11: Plugin cache verification (NEW)

The `plugins/aios/commands/` repo folder is the source of truth. The runtime **cache** must stay in sync with it. A **marketplace** copy is a *second* derived location **only on a GitHub-source install**:

- `~/.claude/plugins/cache/the-aios/aios/<version>/commands/{name}.md` (the *installed* version dir — glob `the-aios/aios/*/commands/`, never a fixed version; the plugin bumps but this path must not pin a version) — **always present, runtime-authoritative.**
- `~/.claude/plugins/marketplaces/the-aios/plugins/aios/commands/{name}.md` — **only exists on a GitHub-source marketplace install.**

> **Detect the marketplace source type FIRST** (`claude plugin marketplace list`). The **primary AIOS mode is a directory-source marketplace** (`the-aios` registered as `Directory → ~/aios`) — that's what carries ventures + `custom/`; a GitHub-source clone would miss them. On a **directory-source** install the marketplace *reads `~/aios` in place*: the `marketplaces/the-aios/…` path **does not exist**, the repo folder IS the marketplace source, and there is **nothing to copy or compare** there. So: if `marketplaces/the-aios/plugins/aios/commands` is absent (directory-source), **verify the cache only and skip the marketplace check entirely** — do not report the absent marketplace dir as drift. Only when that dir exists (GitHub-source) does the marketplace comparison apply.

**Scan:** for each `plugins/aios/commands/{name}.md` in the repo, `diff` against the cache (and the marketplace **only if its dir exists**). Surface any drift:

- **Repo file present, cache file missing** (or marketplace-missing on a GitHub-source install) → command was added but never synced
- **Files differ between repo and a present derived location** → command was edited in source but not propagated
- **A present derived file has no repo counterpart** → command was deleted in source but stale copy lingers

**Auto-apply candidates** (low-stakes, deterministic):
- Repo → cache copy (always), and repo → marketplace copy **only if the marketplace dir exists**. Guard both with `[ -d ]`: `mp=~/.claude/plugins/marketplaces/the-aios/plugins/aios/commands; [ -d "$mp" ] && cp ~/aios/plugins/aios/commands/{name}.md "$mp/"` + the cache-glob equivalent. Confirm post-copy that the synced locations match (`diff -q`). On directory-source there's nothing to copy — the source is live.

**Propose-only candidates** (need user judgment):
- Plugin paths have content the repo doesn't — possible accidental delete, or in-progress refactor. Ask before removing.

**Evidence discipline:** show the actual `diff -q` output per drifted command. "`plugins/aios/commands/today.md` differs from cache" is more useful than "today is out of sync."

**Why this matters:** the plugin cache is what Claude actually reads at runtime. Drift between source and cache means edits to `plugins/aios/commands/*.md` don't take effect — silent breakage, hard to debug.

> **Sibling check:** skills have the same source-of-truth-vs-registered-location problem. **Bucket 20** verifies AIOS skills are symlinked into `~/.claude/skills` (and registers the missing ones, collision-safe).

#### Bucket 12: Antifragile compact + promotion (NEW — extends Bucket 9)

Bucket 9 (antifragile cleanup) addresses **structural drift** (ordering, interleaving, duplicate meta-patterns). This bucket addresses **growth control** — preventing antifragile.md from becoming a write-only log that nobody scans because it's too long.

**The "never delete entries" rule is sacred.** This bucket works *within* it: consolidate via promotion + annotation, not deletion. Three operations:

**Promote scalable lessons → meta-patterns.** Scan numbered entries. When 3+ entries name the same underlying pattern in different surface forms (different incidents, same root cause), propose lifting to a clearly-stated meta-pattern in the meta-patterns section. Source entries stay where they are; they get a `→ See meta-pattern: {short-name}` annotation. Evidence required: cite the entry numbers + quote the shared root-cause phrasing across them.

**Promote meta-patterns → core principles.** When a meta-pattern is confirmed by 5+ source entries AND has been stable (no contradictions) for 3+ months, propose promotion to a `## Core Principles` section at the top of the file. Top of file becomes the distilled durable insights; meta-patterns stay as evidence; entries stay as historical record. The 3-tier structure: Core Principles (top) → Meta-patterns (middle) → Numbered Entries (bottom, chronological).

**Mark obsolete entries.** When an entry references a configuration/MCP/setup/file path that no longer exists in the vault, propose annotating with a `> **Superseded {YYYY-MM-DD}:** {why — e.g., MCP renamed, file restructured, rule absorbed into core principle X}` block at the top of the entry's body. **Don't delete the entry.** If 5+ such superseded entries accumulate, propose creating an `## Archived / Superseded` section at the end of the file and moving them there for easier scanning of the active middle.

**Volume guard.** Surface `antifragile.md` line count. If >500 lines OR >50 entries, propose a triage pass before next housekeeping run. Without this guard, the file grows into a library nobody reads.

**Evidence discipline:** quote the exact sentence(s) that converge across entries; cite entry numbers; for obsolete checks, name the exact missing path/MCP. "Entries #14, #22, #38 all describe 'shortcut that corrupts source-of-truth' under different categories — propose meta-pattern lift" beats "antifragile feels redundant."

**Don't propose:** deletions of any entry (preserves the historical record), content rewrites of existing entries (their original phrasing IS the evidence), promotions for fewer than 3 source entries (premature; not yet a real pattern).

#### Bucket 13: USER.md drift check (NEW)

**Skip gracefully if `USER.md` doesn't exist** — single existence check at the start. Bare-bones users running with defaults won't have one; the bucket reports `0 proposals` and moves on.

Read `USER.md` and propose updates where the file has aged into one of these debt patterns:

- **Rule overlap** — two or more rules in the same `### /command` section cover related-but-distinct behavior that would read tighter under a parent heading. Propose grouping when 2+ rules share a problem domain (e.g., three sibling rules added in one design pass → group under one bolded sub-heading).
- **Stale rule** — a rule added >60 days ago that hasn't been referenced/applied in the most recent 30 daily notes. Cross-check by grepping the rule's key signal phrase against recent dailies. Propose archive or removal.
- **Date-stamp normalization** — rules with inline phrases like *"(added YYYY-MM-DD — Q1 fix for ...)"* could collapse to a trailing `_(YYYY-MM-DD)_` suffix. Cosmetic but removes ~5 words per rule and standardizes the audit trail.
- **Section length** — any single `### /command` section that's grown >150 lines without internal bolded sub-headings is dense. Propose grouping rules under bold sub-headings (e.g., `**Carry handling**`, `**Calendar adaptation**`) without changing rule content.
- **Promotion candidate** — a USER.md rule that's stabilized over 60+ days, fires reliably, AND is generic enough (no user-specific names, paths, ventures) could move from USER.md → `commands/{name}.md` as a default rule for any user. Propose with one-line justification of why it's general-purpose now. **This is the feedback loop that lets USER.md discoveries flow back upstream into the shared template.**
- **"No overrides" stub age** — `### /command` sections that have read *"No overrides — use default behavior"* for 90+ days are stable enough to potentially remove from USER.md (the command runs the default whether or not USER.md mentions it). Propose removal of stubs older than 90 days; keep the section if the user wants the discoverability surface.
- **Schema drift between USER.md and `commands/{name}.md`** — if a command has added new behavioral hooks (new placeholders, new section headings, new rules) the matching USER.md section doesn't reference, surface the gap so the user can decide whether to override or accept the default. Compare `commands/{name}.md` against `USER.md` → `### /{name}` for each command.

**Evidence discipline:** cite specific line numbers + dates + rule names. *"Lines NNN-NNN contain three sibling rules added YYYY-MM-DD — group under one heading"* beats *"the /today section is long."*

**Don't propose:** deletions of rules without a graceful path (always offer "archive to logs/" before "delete"), or schema-drift fixes that would force-rewrite the user's USER.md (suggest the diff, let the user decide).

**Why this bucket exists:** USER.md is the personalization-of-truth surface — it's where rules live until they're stable enough to promote upstream. Without periodic audit, it accumulates the same debt patterns any long-lived config file does: overlap, staleness, length-without-structure. The promotion-candidate pattern is the most important: it's how end-user discoveries (rules that worked in your USER.md) flow back upstream into `commands/*.md` for everyone.

#### Bucket 14: Missed reports audit (NEW)

Walk `vault/03 - export/reports/` and detect period-reports that should exist but don't. **Audit-only** — delegates generation to the canonical commands (`/weekly-learnings`, `/learned`, `/role-report`). This bucket detects gaps + proposes the command invocations to fill them; it doesn't re-implement the generators.

**Detection window** (defaults):
- Weekly: last 4 closed weeks (Mon-Sun fully in the past)
- Monthly: last 2 closed months
- Quarterly / semester / year: most recent closed period of each

Older gaps are silently skipped — assume intentional cadence choice. User can always force a backfill manually by invoking the relevant command with the period argument.

**Audit checks per closed week** (W{N}):
- `01 - calendar/{YYYY-MM}/{YYYY}-W{NN}-summary.md` exists?
- `vault/03 - export/reports/weekly/Week{N}-AI-OS.html` exists?
- If either is missing AND the week has at least 3 daily notes → propose `/weekly-learnings <week-id>` (one run generates both summary.md + HTML).

**Audit checks per closed month:**
- `vault/03 - export/reports/monthly/Month{N}-AI-OS-{Month}.html` exists? → propose `/weekly-learnings month <Month>`
- `vault/03 - export/reports/role/{Month}-{Year}-role-report.html` exists? (only check if `vault/00 - notes/context/declared/role-expectations.md` exists in this vault) → propose `/role-report <Month> <Year>`
- `vault/03 - export/reports/learned/{Month}-{Year}-learned.html` exists? (only check if at least one `/learned` HTML has been generated before in this vault — proves the user uses this cadence) → propose `/learned month <Month> <Year>`

**Audit checks per closed quarter / semester / year** (most recent only):
- `Q{N}-AI-OS.html`, `H{N}-AI-OS.html`, `Year-AI-OS-{Year}.html` in `vault/03 - export/reports/weekly/` → propose `/weekly-learnings quarter` / `semester` / `year` for the missing periods.

**Skip rules (the cadence is the user's call):**
- Pre-vault-adoption periods (before earliest existing report OR earliest daily note) → out of scope. Don't propose reports for weeks/months when the vault didn't exist yet.
- Zero `/learned` reports anywhere → don't propose learned (user doesn't use this cadence).
- Zero role-reports AND no `role-expectations.md` → don't propose role.
- A week with fewer than 3 daily notes → don't propose weekly (insufficient source material; likely a travel week or intentional gap).

**Proposal table format:**

| # | Type | Period | Command | Source confirmed |
|---|------|--------|---------|------------------|
| 14.1 | Weekly | W17 (Apr 20-26) | `/weekly-learnings W17` | 5 daily notes present, no summary.md, no HTML |
| 14.2 | Weekly | W18 (Apr 27-May 3) | `/weekly-learnings W18` | 4 daily notes, no summary.md, HTML exists (sarah bonus run) |
| 14.3 | Monthly | April 2026 | `/weekly-learnings month April` | 4 weekly summaries present |
| 14.4 | Role | April 2026 | `/role-report April 2026` | role-expectations.md present, 22 daily notes |

**Apply step — two modes:**

1. **Propose-only (default):** approval surfaces the command list. User runs each manually when ready. Best for selective backfill.
2. **Run sequentially:** approval chains the invocations in order — `/housekeeping` invokes each canonical command one after another in the same session, waiting for each to complete before moving on. Best for catch-up passes after travel/break weeks. Triggered by `approve-and-run` or `approve all + chain` in the approval phase.

Either mode preserves separation of concerns: `/housekeeping` audits + sequences; the canonical commands (`/weekly-learnings`, `/learned`, `/role-report`) do the actual generation.

**Evidence discipline:** *"W17 daily notes 2026-04-20 through 2026-04-26 present; no summary.md; no HTML — both can be generated in one /weekly-learnings W17 run"* beats *"April is missing reports."*

**Why this bucket exists:** reports are easy to skip — a busy Friday means `/weekly-learnings` doesn't fire; a busy end-of-month means the auto-trigger gets missed; a travel week eats the cadence. Without audit, the `export/reports/` folder becomes Swiss cheese over months. Catching gaps inside the housekeeping rhythm keeps the export surface honest.

#### Bucket 15: Antifragile → USER.md graduation candidates (NEW)

The companion to Bucket 12. Where Bucket 12 promotes structure *within* `antifragile.md` (meta-patterns → core principles section), this bucket promotes patterns *out* of `antifragile.md` into `USER.md` as behavioral rules — closing the loop between learning surface (antifragile entries) and teaching surface (USER.md rules the session reads at startup).

**The principle:** when a meta-pattern accumulates enough evidence that the failure mode is stable and predictable, the rule should graduate from observation to instruction. Antifragile is for learning; USER.md is for teaching. Each graduation reduces the chance of the same failure recurring.

**Detection (scan in this order):**

1. Parse `00 - notes/context/observed/antifragile.md` meta-patterns section. Each meta-pattern has a header (e.g., `### Q. The "I-know-better..."`) and an `- Entries: #N, #M, ...` line listing source entries.

2. For each meta-pattern, count entries + compute last-entry recency:
   - Count = total entries referenced in the `- Entries:` line
   - Recency = most-recent entry's date (parse the `(MMM DD)` or `(YYYY-MM-DD)` suffix in each entry's title)

3. **Flag a meta-pattern as graduation candidate when BOTH:**
   - Entry count ≥ 4
   - Most recent entry ≤ 30 days ago

4. **Skip meta-patterns that already show a `→ Graduated to USER.md on YYYY-MM-DD` flag** in their description. One graduation per pattern; subsequent recurrences signal the rule isn't being followed, not that re-graduation is needed.

**For each flagged meta-pattern, draft a rule:**

Synthesize a ≤100-word behavioral rule from the pattern description + the source entries' system-fix sections. The rule should be:
- **Mechanical, not interpretive** — describe what to do/not do in observable terms
- **Trigger-action shape** — "When X, do Y (not Z)"
- **Cite the pattern letter + entry count** in a trailing italic line: *"Graduated from antifragile meta-pattern {letter} ({N} source entries, most recent {date})"*

**Proposal table format:**

| # | Meta-pattern | Entries | Recurrence | Proposed rule | Action |
|---|---|---|---|---|---|
| 15.1 | Q. "I-know-better-than-the-explicit-signal" | 5 (#29, #39, #43, #46, #51) | last 13 days | [draft ≤100-word rule] | [ ] graduate |
| 15.2 | T. "Recovery operation semantics" | 4 (#38, #49, #50, #53) | last 1 day | [draft] | [ ] graduate |

**Apply step (when user approves):**

1. **Check USER.md for `## Personal antifragile graduations` section.** If missing, auto-create at the bottom of USER.md (before `## Command personalizations` if present, otherwise at end) with this intro:
   ```markdown
   ## Personal antifragile graduations

   > Behavioral rules graduated from `antifragile.md` meta-patterns. Each rule emerged from ≥4 entries clustering around the same failure mode. Read at session start as part of USER.md.
   ```

2. **Append the rule to that section** with the format:
   ```markdown
   ### {short rule name}

   {rule body}

   _Graduated from antifragile meta-pattern {letter} ({N} entries, {date} recurrence)._
   ```

3. **Mark source antifragile entries with graduation flag.** For each entry referenced by the graduated meta-pattern, add this line at the top of the entry's body (right after the title, before `**What happened:**`):
   ```markdown
   > **→ Graduated to USER.md → ## Personal antifragile graduations → "{rule name}" on YYYY-MM-DD.**
   ```

4. **Annotate the meta-pattern description** with the same graduation flag inline.

5. **Snapshot `antifragile.md` before editing** (per CLAUDE.md observed-context rules). Save to `00 - notes/logs/observed-snapshots/{YYYY-MM}/{YYYY-MM-DD}-antifragile.md` (suffix `b/c/...` if same-day snapshots already exist).

**Evidence discipline:** show the entry numbers, dates, and the synthesized rule text. *"Meta-pattern Q has 5 entries (most recent #51, 1 day ago) — proposed rule reads: '{exact text}'"* beats *"Q is ready to graduate."*

**Don't propose:** graduations for fewer than 4 entries (premature), graduations of patterns where the most recent entry is >30 days old (stale, may have self-resolved), or rules that aren't shippable as `≤100 words mechanical-not-interpretive` (refine the synthesis first).

**Why this bucket exists:** antifragile.md grows monotonically. Without graduation, the file becomes a write-only log: lessons captured but never encoded as instruction. The graduation step is what makes the system *actually* antifragile — each graduated rule reduces the future failure rate for its pattern. Patterns that keep recurring after graduation signal a rule defect (re-investigate the rule, don't add another entry).

#### Bucket 16: Radar Health Audit (NEW)

Detect the **"Radar-but-not-Rhythm"** drift pattern: projects that are `status: active` (so they surface on the daily Radar) but haven't actually appeared in any Rhythm block over a meaningful window. These projects collect "awareness" without execution — the operator nods at them daily but never schedules a window. Over time, this is how active drifts into not-actually-active without anyone naming it.

**The principle:** awareness without execution is drift. `/today`'s Radar→Rhythm nudge (see `plugins/aios/commands/today.md` § Radar→Rhythm nudge) catches 7-day-old gaps at the daily level. This bucket catches the *systemic* version: projects that have been Radar-only for **30+ days**, which signals either (a) the project should be honestly demoted to `status: maintenance`, or (b) the operator needs to re-commit by scheduling a window or a re-orientation session.

**Detection (scan in this order):**

1. List all `status: active` projects from `00 - notes/projects/` (read frontmatter).

2. For each, scan the last 30 daily notes (`vault/01 - calendar/{YYYY-MM}/{YYYY-MM-DD}.md`) for the project's `[[wiki-link]]` OR a task line tagged `_(project-slug)_` in any Rhythm block (Morning / Afternoon / Evening — not Radar table, not Parking lot, not Carries forward).

3. **Flag as Radar-only when:**
   - Project is `status: active`
   - Zero Rhythm-block presence in the last 30 daily notes
   - Project is NOT in watch-mode (priority text doesn't contain "watch" / "waiting" / "blocker: external" — watch-mode projects are legitimately Radar-only)

4. **Skip projects flagged within the last 14 days** by a prior `/housekeeping` run (avoid nudge fatigue — give the operator time to either schedule or demote before re-flagging).

**Proposal table format:**

| # | Project | Days Radar-only | Last priority noted | Recommended action |
|---|---|---|---|---|
| 16.1 | [[project-X]] | 42 | "{the single priority from project note}" | [ ] (a) schedule window this week · [ ] (b) demote to maintenance · [ ] (c) interview now |
| 16.2 | [[project-Y]] | 33 | "{the single priority}" | [ ] (a) schedule · [ ] (b) demote · [ ] (c) interview |

**Three response options per project:**

- **(a) Schedule window** — operator adds a calendar block this week (any window — even 30 min) to actually move the project. `/housekeeping` doesn't auto-schedule; it nudges the operator to do it.
- **(b) Demote to maintenance** — `/housekeeping` flips frontmatter `status: active` → `status: maintenance`, updates `_index.md` snapshot, removes from daily Radar. The honest move when the project genuinely doesn't deserve daily attention.
- **(c) Interview now** — trigger a mini-Radar-interview flow (operator confirms category + priority, like the 2026-05-20 full Radar cleanup). Useful when the project's status is ambiguous and a deeper re-evaluation is needed.

**Bulk-mode shortcut:** if the operator says "interview all flagged" at this bucket's review, run the mini-interview sequentially through each flagged project — same shape as the full Radar interview (category question → priority proposal → confirm). Output: updated project notes + updated `_index.md` + commit message capturing the cleanup.

**Why this bucket exists:** the Radar→Rhythm gap was identified 2026-05-20 during a full Radar interview cleanup. Without periodic re-detection, `status: active` becomes a sticky label that survives the project's actual relevance. This bucket forces a real decision — schedule, demote, or interview — instead of letting drift compound.

#### Bucket 17: CLAUDE.md + USER.md health check (NEW)

Comprehensive integrity check of the two operating files that govern every session: `CLAUDE.md` (the system's behavioral contract — universal to all operators) and `USER.md` (the operator's personalization layer). Inspired by [anthropics/claude-plugins-official → claude-md-management](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/claude-md-management) — reimplemented inline so AIOS works standalone (Anthropic plugin is additive, not required).

**The principle:** drift in CLAUDE.md or USER.md is silent and high-blast-radius. A broken wiki-link in a project note misroutes one task. A broken reference in CLAUDE.md misroutes every session for every operator on the template. This bucket catches both files' degradation before it spreads.

**Detection (scan in this order):**

**A. CLAUDE.md health (universal infra — affects every operator):**

1. **Wiki-link resolution** — for every `[[link]]` in CLAUDE.md, verify the target exists somewhere reachable (in `agents/`, `commands/`, `hooks/`, `templates/`, `vault/00 - notes/context/`, etc.). Flag broken links.
2. **Path references** — grep for hardcoded paths (`agents/...`, `agents/...`, `my-agents/...`, etc.) that may be stale post-restructure. Compare against current filesystem.
3. **Section completeness** — required sections present? `# Mandatory First Action`, `## Identity & Greeting`, `## Spawning Sessions`, `## I. Operating Principles`, `## II. Rituals`, `## III. Self-Update`, `## IV. Vault Map`, `## V. Infrastructure`, `## VI. Discipline`. Flag missing.
4. **Personal-slug leakage** — grep for patterns that look operator-specific (real operator usernames, real company slugs, real-person names) that shouldn't be in canonical infra. Flag for de-personalization.
5. **Index consistency** — `## IV. Vault Map → Index Maintenance` lists folders with `_index.md` files. Verify each listed folder actually has its `_index.md`. Flag mismatches.
6. **Command count consistency** — CLAUDE.md, README, SETUP, `commands/_index.md` may reference a command count. Recount actual commands in `commands/` and flag inconsistencies.

**B. USER.md health (operator personalization — operator-specific):**

1. **Identity table — session names match real practice** — read `## Identity` table, cross-check against recent daily notes' "Agent work" entries and session reports. If a listed identity has zero sessions in 30+ days, flag for review.
2. **Sources sections filled, not template placeholders** — verify `## Companies (mounted)`, `## Sources → Google accounts`, `## Sources → Communication`, `## Sources → Growth routines` have real values (not `{your-email}` / `{team-repo-url}` / etc).
3. **Anthropic accounts rotation** — verify `## Anthropic accounts` has at least one real entry and the format is parseable by `claude-switch`.
4. **Companies (mounted)** — once `/company` v2 ships: verify each row in `## Companies (mounted)` resolves to an actual venture folder + tracker file. Flag mismatches.
5. **Command personalizations consistency** — for each `### /{command}` section under `## Command personalizations`, verify the command file exists in `commands/`. Flag orphan personalizations (command was deleted but personalization remains).
6. **Growth routines source paths** — verify each routine's `Project:` wiki-link resolves to an existing project note.
7. **Excluded calendars / personal email** — verify `Excluded calendars` and personal Google account are reachable (or marked optional explicitly).
8. **Personal antifragile graduations** — if `## Personal antifragile graduations` has entries, verify each links to its source antifragile.md entry (the lineage trace).

**Proposal table format:**

| # | File | Issue | Severity | Recommended fix |
|---|---|---|---|---|
| 17.1 | CLAUDE.md:497 | Wiki-link `[[advisory-jane-doe]]` doesn't resolve (example only, OK to leave) | low | leave |
| 17.2 | CLAUDE.md:382 | Path `agents/` is stale (post-restructure now `agents/`) | high | [ ] update path |
| 17.3 | USER.md:74 | `{operator-personal}@example.com` listed as Personal email — verify still active | low | [ ] confirm |
| 17.4 | USER.md:134 | `### /old-command` personalization has no matching `plugins/aios/commands/old-command.md` | medium | [ ] remove orphan personalization |

**Severity levels:**

- **High** — broken refs, missing required sections, stale paths post-restructure. Affects session behavior.
- **Medium** — orphan personalizations, missing recent activity for listed identities. Suggests drift but not broken.
- **Low** — example-only links, unverified-but-plausible config. Informational.

**Cadence:** monthly minimum; trigger immediately after any major restructure (like the 2026-05-21 agents folder move). Auto-runs as part of post-migration sanity check on first `/housekeeping` after the cutover.

**Why this bucket exists:** CLAUDE.md and USER.md are the two highest-blast-radius files in the system. Bucket 13 already covered USER.md drift; Bucket 17 extends to CLAUDE.md + comprehensive cross-file checks (path consistency, ref resolution, section completeness, personal-slug leakage). The 2026-05-21 leakage cleanup (`813aa68`, `679843a`) caught 11 canonical files with personal-slug refs that had silently shipped — this bucket prevents that recurrence by running the check proactively, not reactively.

#### Bucket 18: Upstream source freshness (NEW)

The framework vendors content from upstream repos in two places: **skills** (source-grouped — `skills/aios/`, `skills/superpowers/`, `skills/anthropic/`, etc.) and **MCPs** (each `mcps/<name>-mcp/` may be vendored from an upstream repo). Each vendored folder ships with a `.upstream-sync` file declaring `repo=<github-url>`, `hash=<short-sha>`, `date=<last-sync>`, and optionally `subdir=<path-within-repo>` (for monorepo subdirs) and `note=<human-context>`. This bucket walks all `.upstream-sync` files in the framework, queries each upstream for its current HEAD, and surfaces drift.

**The principle:** vendoring upstream content only adds value if we actually track its evolution. Otherwise we ship stale forks while better versions exist publicly. Bucket 18 surfaces freshness signals so operators can choose to update.

**Detection (one pass, both surfaces):**

1. **Scan for `.upstream-sync`** — `find skills mcps -name '.upstream-sync' -not -path '*/custom/*'` returns every vendored source folder.
2. **For each `.upstream-sync` found:**
   - Parse `repo=`, `hash=`, `date=`, optional `subdir=`, optional `note=`.
   - Query the upstream: `gh api "repos/<org>/<repo>/commits/HEAD" --jq '.sha'` → current upstream HEAD.
   - Compare local vs upstream hash. If equal → mark `current`. If different → mark `behind`.
3. **For `behind` sources** — fetch the commit list since local hash:
   ```bash
   gh api "repos/<org>/<repo>/compare/<local>...HEAD" --jq '.commits[] | .commit.message'
   ```
   Show top 5 commit messages for change summary. If a `subdir=` is set, additionally filter the diff to that path: `gh api "repos/<org>/<repo>/compare/<local>...HEAD" --jq '.files[] | select(.filename | startswith("<subdir>/")) | .filename'` — operator sees only changes relevant to the vendored subset.
4. **For each modified file in the upstream:** propose per-file actions: pull / skip / mark-divergent (we intentionally forked it).

**Proposal table format:**

| # | Source | Type | Status | Behind by | Action |
|---|---|---|---|---|---|
| 18.1 | `skills/superpowers/` | skill | 🟡 behind | 7 commits | [ ] review changes |
| 18.2 | `skills/anthropic/` | skill | 🟢 current | — | — |
| 18.3 | `mcps/atlassian-mcp/` | mcp | 🟡 behind | 23 commits since 2026-05-21 | [ ] review (may require deps + restart) |
| 18.4 | `mcps/github-mcp/` | mcp | 🟢 current | — | — |

**For approved pulls (skills):**
- Update `skills/<source>/.upstream-sync` with new hash + date
- Apply the diff via `git mv` / `Write` for each changed file
- Surface license/attribution requirements (LICENSE files in upstream — copy if changed)

**For approved pulls (MCPs — extra care vs skills):**
- MCP code changes often touch `package.json` / `pyproject.toml` — propose dependency updates alongside source updates
- After applying, **flag restart-required**: the MCP server is a long-running subprocess held in memory by Claude Code (per `feedback_settings_read_semantics.md`); operator must `claude mcp restart <name>` or restart Claude Code entirely for code changes to take effect
- If upstream introduces breaking changes (renamed tools, changed schemas), surface them prominently — these affect every command/agent that calls the MCP
- Update `mcps/<name>-mcp/.upstream-sync` after successful pull

**AIOS-built MCPs (no `.upstream-sync` file):**
Some MCPs are AIOS-built, not vendored — `nano-banana-mcp`, `pdf-generator-mcp`, `spotify-dj-mcp`, `playwright-mcp`. These have no upstream to track; skip them. Same for npm-proxy MCPs like `stitch-mcp` (auto-updated via npm at install time, no vendoring).

**Cadence:** monthly minimum, or weekly if you're actively pulling from a fast-moving upstream like `obra/superpowers` or `modelcontextprotocol/servers`.

**Why this bucket exists:** the 2026-05-21 skills reorg + MCP attribution sweep made source tracking durable (vendored content lives at `<layer>/<source>/<thing>/` with a `.upstream-sync` manifest). The reorg only pays off if we close the loop — staying current with upstream. Without this bucket, the source folders become museum pieces. With it, AIOS becomes an active integrator of best-in-class skills + MCPs across the ecosystem.

#### Bucket 19: Observed-context lifecycle health (NEW)

**The principle:** the observed-context lifecycle is two-layered — Tier A (patterns, preferences, business, antifragile) receives routed content from session-insights gardening; Tier B (growth, profile, ecosystem) is synthesized one layer above from Tier A + antifragile + daily notes. The forward mechanism (`/close-day`'s session-insights gardening + Tier A routing + Tier B digest) keeps both layers alive day-to-day. But silent drift can still accumulate when `/close-day` is skipped, when routing-execution gets perfunctory, or when individual operators run with older command versions. This bucket is the backstop: a periodic health check that surfaces backlog in both layers.

**Detection (three layers):**

**Tier A layer — Reinforced routing backlog:**
1. Parse `vault/00 - notes/context/observed/session-insights.md` `## Reinforced` section.
2. For each entry, extract the date stamp + `Route to:` tag (if any).
3. Compute days since the entry's date.
4. Flag as backlog if:
   - Entry has `Route to:` tag AND days_since > 7 → "stale Reinforced, route now"
   - Entry has no `Route to:` tag AND days_since > 14 → "untriaged Reinforced, needs target file decision"

**Tier A layer — hard cap enforcement (count check, not just age).** The buffer has explicit caps (CLAUDE.md: **Emerging ≤10, Reinforced ≤5**). The age checks above catch *stale* entries; this catches an *overflowing* buffer regardless of age — a buffer over cap means gardening is falling behind (insights aren't being routed/reinforced fast enough), which silently degrades the compounding. Count the `## Emerging` and `## Reinforced` entries; if either exceeds its cap, flag it (`"Emerging at {N}/10 — route or drop {N-10} before the buffer cannibalizes signal"` / `"Reinforced at {N}/5 — route the oldest to its target file"`). The fix is mechanical (route the routable, drop the resolved), same as the backlog flags above.

**Tier B layer — observation freshness:**
1. For each of `growth.md`, `profile.md`, `ecosystem.md`:
   - Read frontmatter `updated:` date.
   - Compute days since.
2. Flag as backlog if:
   - File >30 days stale AND `/close-day` has fired in last 7 days (forward digest should have updated; missing update suggests substance bar failing OR digest skipped)
   - File contains "Day-0 stub" markers (only frontmatter + seed text) AND vault is >30 days old → "fresh stub never written despite vault accumulating content"

**Reference-integrity layer — dead command / namespace refs:**

Observed-context files (especially `vault-routine.md`, which is read at *every* session start) drift silently when the framework renames a command or its plugin namespace — the operator's evolved copy keeps teaching the old token long after canonical moved on. This layer catches that class.

1. Build the **live command set** from `plugins/aios/commands/*.md` basenames (the authoritative current command list), plus the known subcommand forms (`company --sync`, etc.).
2. Scan every file under `vault/00 - notes/context/observed/*.md` (and `declared/*.md`) for command/namespace tokens: the literal dead namespace `vault-commands:` and any `aios:{cmd}` / `` `/{cmd}` `` reference whose `{cmd}` is **not** in the live set.
3. Classify each hit:
   - **Dead namespace** (`vault-commands:*`) → renamed to `aios:*` — unambiguous, propose the swap.
   - **Renamed command** (`{cmd}` absent from live set but maps to a known successor — e.g. `sovra-sync` → `company --sync`, `vault-update` → `update`) → propose the rename. Maintain the successor map inline; when unsure of the successor, flag for operator decision rather than guessing.
   - **Historical narration** (the dead token appears inside prose *describing* a past change — common in `antifragile.md`, whose "never delete, supersede" rule means old entries legitimately quote old names) → **do NOT propose a rewrite of the narration**; only flag *active instructions* (e.g. "→ invoke `Skill(vault-commands:close-session)`") that still tell a future session to call a dead token. The test: is the token an *instruction the session would act on*, or a *record of what happened*? Fix the former, leave the latter.

**Proposal table format:**

| # | Layer | File / Entry | Status | Backlog | Action |
|---|---|---|---|---|---|
| 19.1 | Tier A | `session-insights.md` → "Slide-creation as MCP edit surface" | 🟡 Reinforced + Route to: tagged | 11 days unrouted | [ ] route now (auto) |
| 19.2 | Tier A | `session-insights.md` → "Some other entry" | 🔴 Reinforced + no Route to: | 22 days untriaged | [ ] triage target file |
| 19.3 | Tier B | `growth.md` | 🟡 stale | 31 days, last close-day 1 day ago | [ ] run Tier B digest catch-up |
| 19.4 | Tier B | `ecosystem.md` | 🔴 stub | seed text only, vault 78 days old | [ ] write from accumulated business.md + daily notes |
| 19.5 | Ref | `vault-routine.md` (×19) | 🔴 dead namespace | `vault-commands:*` (renamed to `aios:*`) | [ ] swap namespace (auto) |
| 19.6 | Ref | `vault-routine.md` | 🟡 renamed command | `aios:vault-update` → `aios:update` | [ ] rename (auto) |
| 19.7 | Ref | `antifragile.md` #N | 🟡 dead ref in active instruction | `Skill(vault-commands:close-session)` | [ ] fix token only — leave the surrounding lesson |
| 19.8 | Tier A | `session-insights.md` `## Emerging` | 🔴 over cap | 13/10 entries | [ ] route routable + drop resolved to ≤10 |

**For approved Tier A routings:**
- Same logic as `/close-day`'s Tier A routing enforcement (snapshot target files, write the entries, remove from buffer, add `<!-- ROUTED -->` comment).
- Routing-execution is mechanical — substance bar already passed at Reinforced promotion.

**For approved Tier B catch-up:**
- Same logic as `/close-day`'s Tier B observation pass + the Phase 9.7 catch-up from the migration playbook.
- Snapshot all touched files, read feed-in sources, apply substance bar (timeline / uniqueness / evidence / essentiality), write autonomously.

**For approved reference fixes:**
- Snapshot the touched observed-context file first (per CLAUDE.md observed-context rules).
- Dead-namespace + renamed-command swaps are mechanical text replacements — apply them across the file.
- For active-instruction dead refs in `antifragile.md`, fix **only the token**, never the surrounding lesson (the "never delete, supersede" rule protects the lesson; the dead pointer inside it is a correctness fix, not a deletion).
- Never rewrite historical narration — a record of "we renamed X → Y" must keep quoting the old name to stay legible.

**Cadence:** weekly minimum (the forward mechanism in `/close-day` should keep both layers alive — Bucket 19 is the backstop for when daily ritual is skipped, when an old command version is in use, or when an operator wants explicit verification).

**Why this bucket exists:** observed-context drift is invisible until you measure it (caught in chuy's vault 2026-05-23: growth.md 31d stale, profile.md 82d stale, ecosystem.md 63d stale, AND 5 Reinforced session-insights sat 11-49 days marked "Ready to route" but never executed). The forward `/close-day` mechanism (Tier A routing enforcement + Tier B observation pass) addresses the same gap proactively, but Bucket 19 is the periodic floor-check that ensures the forward mechanism is actually firing. Without it, an operator who skips `/close-day` for a week loses both layers silently. The reference-integrity layer was added after a 2026-06-15 catch: an operator's `vault-routine.md` still taught the dead `vault-commands:*` namespace (renamed to `aios:*` weeks earlier) on every session start — canonical's seed was clean, but the operator's evolved copy never caught the rename. A renamed command or namespace is silent rot in exactly the files read at startup; this layer makes it self-surface instead of waiting for an audit.

#### Bucket 20: Skill registration verification (NEW — sibling to Bucket 11)

Bucket 11 verifies the **command** plugin cache. This bucket is its sibling for **skills**: it catches AIOS skills that are authored in the repo but never registered into the skills-dir Claude actually loads — the exact gap that made `accessibility-compliance` return *"I don't have that skill"* before `skills/setup.sh` existed.

**Source of truth:** every skill folder under `skills/<source>/<skill>/` **except** `anthropic/` and `superpowers/` (those are marketplace-provided and live in `~/.claude/skills` already — never re-register them).
**Registered location:** a symlink at `~/.claude/skills/<skill>/` pointing back into the repo (the mechanism `skills/setup.sh` creates).

**Scan:** for each AIOS-origin skill, classify:

- **Authored but unregistered** → skill exists in `skills/` but `~/.claude/skills/<name>` is absent → **not loadable**. This is the primary thing to catch.
- **Name collision** → `~/.claude/skills/<name>` exists but is *not* a symlink into this repo's `skills/` (a real dir, or a symlink to a different source) → a different skill already owns that name.
- **Dangling symlink** → `~/.claude/skills/<name>` is a symlink into `skills/` but its target no longer exists (skill was renamed/removed in the repo).

Show the actual evidence: `ls -la ~/.claude/skills/<name>` per finding — "`accessibility-compliance` authored in `skills/aios/` but no symlink in `~/.claude/skills`" beats "some skills unregistered."

**Auto-apply candidates** (low-stakes, deterministic — **zero-collision**):
- Register unregistered skills by running `bash skills/setup.sh` (`pwsh skills/setup.ps1` on Windows). It is idempotent and **collision-safe by design** — it skips any name already present in `~/.claude/skills` (including the marketplace `anthropic`/`superpowers` folders), so it can only *add* missing AIOS skills, never clobber an existing one. Confirm post-run with `ls ~/.claude/skills/<name>`.

**Propose-only candidates** (need user judgment — never auto-resolve):
- **Name collisions** → an existing different skill owns the name. `skills/setup.sh` already skips these silently; surface them so the operator can decide (rename the AIOS skill, or accept that the existing one wins). Never overwrite.
- **Dangling symlinks** → propose removal (the source is gone), but ask — could be a mid-rename state.

**Restart-required:** yes — the skills-dir is read at **session start**, so after registering, the operator must **restart their Claude Code sessions** for the newly-linked skills to load.

**Why this matters:** a skill that isn't symlinked is invisible — agents that name it in their `## Skills` block silently get nothing, and the operator hits *"I don't have that skill."* This bucket is the periodic floor-check that every AIOS-origin skill is actually loadable, mirroring what Bucket 11 does for commands.

#### Bucket 21: File placement drift (NEW)

Audits the vault against the **File Placement Router** (CLAUDE.md § IV) — the router exists so every session places files semantically; this bucket catches what slipped through.

**Scan:**

- **Species mismatch** → a file living in a zone whose question it doesn't answer. The classic: a human-authored, compounding note inside `00/logs/` (logs is for script/system output ONLY). Test each `logs/` root file: written by a script? If no → propose move (usually `reflections/` or a project note). Also check the reverse: machine output accumulating outside `logs/`.
- **Folder-birth candidates (rule of 3)** → 3+ loose files of the same species sitting in a parent without a semantic subfolder. Evidence: list the candidate files + propose the subfolder name (plain noun, species not dates).
- **Unsanctioned bespoke rooms** → custom folders under `00 - notes/` lacking an `_index.md`. Bespoke rooms are legitimate (a family cookbook, a poetry archive) — but deliberate: propose adding the `_index.md`, never removal.
- **Source/deliverable splits** → deliverable sources (filled HTML, deck sources) living only outside the vault (`/tmp`, Downloads) or only as PDF. Propose persisting the source per the router's export rule.

**Propose-only — never auto-move.** Placement is semantic judgment; the operator approves each move. On approval: `git mv`, update wiki-links pointing at the old path (grep first), update affected `_index.md` files.

**Why this bucket exists:** placement drift is invisible until retrieval fails — the file exists but nobody finds it because it lives where it was *born*, not where it'll be *asked for*. Caught 2026-06-04 in the reference vault: a strategy-rich conference capture filed in `logs/` next to a machine-written bridge beacon — same folder, opposite species. The router (CLAUDE.md § IV) is the forward mechanism; this bucket is the periodic backstop.

#### Bucket 22: Agent-output gate health (NEW — comprehension-debt sibling)

Comprehension debt (CLAUDE.md § VI) compounds when the operator trusts a gate that no longer catches what it should. This bucket is the periodic spot-check: sample agent-shipped work and verify the test/review/build that approved it actually catches the failure mode the operator cares about. **"Gates rot"** — a suite that stays green while the behavior silently broke is worse than no gate, because it manufactures false confidence. Where the `/close-session` comprehension ledger catches un-grasped *output*, this catches un-verified *gates*.

**The principle:** an unattended loop is an unattended attack surface; the defense is periodically confirming the gate still gates. The operator can't keep comprehension debt low if the thing supposedly catching agent mistakes has quietly stopped doing so.

**Detection (scan in this order):**

1. Identify project repos with autonomous / agent-driven changes in the last 30 days — commits by spawned workers, other agent sessions, or `/aios:update`, or projects whose Current State notes recent agent activity.
2. For each, sample N (default 2–3) recently-merged agent-authored changes.
3. For each sample, surface **what gate approved it** (test suite / typecheck / lint / build / human review) and pose the operator the spot-check question: *"does this gate actually catch the failure mode you care about here, or did it just pass?"*

**Permission re-audit cadence (links Bucket 10).** Bucket 10 audits permission *content*; this adds the *clock* the comprehension-debt security note calls for — surface any project whose `.claude/settings.json` permissions haven't been reviewed in **30+ days**, and propose a Bucket-10 pass on it. (A loop tested read-only that quietly gained a write permission "for convenience" is the canonical scope-creep this catches.)

**Proposal table format:**

| # | Change (agent-shipped) | Approving gate | Spot-check verdict | Action |
|---|---|---|---|---|
| 22.1 | `[[project-X]]` auth refactor (#142) | test/auth suite | 🟢 catches the real failure | — |
| 22.2 | `[[project-Y]]` webhook handler (#88) | lint + build only, no behavior test | 🔴 hollow — passes but wouldn't catch a bad payload | [ ] add a payload test to project to-dos |
| 22.3 | `[[project-Z]]` `.claude/settings.json` | — | 🟡 permissions unreviewed 47 days | [ ] run Bucket 10 on this repo |

**Propose-only — never auto-resolve.** The verification is the operator's judgment; the model can't certify a gate catches a failure mode the operator cares about. Where a gate is found hollow, propose a concrete follow-up (strengthen the test, add the missing case) routed to the project's to-dos — don't edit the test here.

**Evidence discipline:** name the change, the exact gate, and what it would miss. *"#88 merged green on lint+build but has no test asserting webhook-signature rejection — a forged payload would pass"* beats *"webhook tests look weak."*

**Why this bucket exists:** comprehension debt has a prevention axis, not just a detection axis. The `/close-session` ledger surfaces what the operator hasn't grasped; this bucket confirms the automated gates they're *trusting instead of grasping* still earn that trust. Gates that rot turn "the loop has it covered" into a false statement no one notices until production.

#### Bucket 23: Truth-surface drift (NEW — ship-time truth-flip backstop)

The ship-time truth-flip contract (CLAUDE.md § Discipline) *prevents* drift at ship time; this bucket *detects* what slipped through anyway — a session that ended before flipping, a ship performed outside any session (browser upload, a counterparty acting), a label that was already wrong. Two lanes:

**Lane 1 — project-note freshness (every operator, zero config):**
1. For each **active** project note with a `Code` path in its Current State: compare the repo's last-commit date (`git -C {path} log -1 --format=%cs`) against the note's frontmatter `updated` / file-modified date.
2. Note older than its repo's recent activity → propose: *"note may lag reality — reconcile Current State + to-dos against the last {N} commits."*
3. Inverse heuristic for Drive/non-coding projects: `status: active` but the note untouched for 21+ days → propose an honesty check (still active, or `maintenance`?).

**Lane 2 — keyed-roadmap edge cases (only if any `type: roadmap` file exists in the vault; else report "no roadmap files — lane skipped, 0 proposals"):**
- **Stale live roadmap:** status live but no key flipped in 14+ days → propose: reconcile or archive (via the retirement checklist — zero open keys).
- **Archived with open keys:** `status: archived` but non-✅/❌ key rows remain → violation; propose re-homing each open key to its project note.
- **Keys outside roadmap files:** key-definition-shaped lines (`^- [A-Z]{2,4}-\d+ ·`) in files *without* `type: roadmap` frontmatter → drift-bait; propose stamping the frontmatter or de-keying the list.
- **Cross-file key collisions:** the same key defined in two live roadmap files → propose a prefix rename in the younger file.

**Proposal table format:**

| # | Finding | Evidence | Action |
|---|---|---|---|
| 23.1 | `[[project-X]]` note lags its repo | note updated {date} · repo last commit {date} (+{N} commits since) | [ ] reconcile |
| 23.2 | roadmap `{file}` stale-live | no key movement in {N} days | [ ] reconcile or archive |

**Propose-only.** Flips and re-homes are the operator's call at packet review.

**Why this bucket exists:** every prevention needs its detection twin. Without this sweep, one missed flip silently re-opens the gap between what the vault says and what reality did — exactly the drift class the truth-flip contract exists to close.

#### Bucket 24: Memory-pressure channeling (NEW — cache-vs-database hygiene)

Auto-memory (`MEMORY.md` + its note files) has a hard ceiling (~25KB / 200 lines). Past ~18KB or ~150 entries, a compaction that only *trims* silently drops durable context. This bucket catches the pressure early and proposes the non-lossy fix — channel WHAT to the vault, compact the HOW (CLAUDE.md § Context Hierarchy → *Memory-pressure channeling*).

1. Measure `MEMORY.md` size + index-entry count (`wc -c` + count of index lines).
2. If **> ~18KB OR > ~150 entries** → propose a **channeling pass**, not a bare compaction:
   - Triage the index: mark each entry *WHAT* (a fact with a canonical vault home) or *HOW* (tool/process rule).
   - For each WHAT: name its authoritative vault home (an observed-context file or the project note's Current State) via the File Placement Router.
   - Then compact the HOW residue (merge dupes, drop graduated rules).

**Proposal table format:**

| # | Finding | Evidence | Action |
|---|---|---|---|
| 24.1 | `MEMORY.md` near ceiling | {KB}KB · {N} entries (ceiling ~25KB / 200) | [ ] channeling pass (channel WHAT → vault, compact HOW) |
| 24.2 | `{memory-entry}` is WHAT, not HOW | duplicates `{vault-file}` (correlated staleness) | [ ] channel to `{home}`, remove from memory |

**Propose-only.** The operator confirms which entries channel where at packet review — memory-vs-vault authority is a judgment call.

**Why this bucket exists:** a full cache is a *silent* failure mode — above the ceiling the index loads only partially and the model quietly stops "remembering" whatever fell off the end, with no error to either party. Detecting the pressure *before* it tips, and channeling durable facts to their canonical home, keeps memory a lean HOW-cache and the vault the authoritative WHAT-database.

### Phase 2 — Present the packet

Categorize all findings into one review table:

```
## Housekeeping — {date}

### Summary
- Link repairs: {N} auto-applied, {M} proposals
- Index refresh: {N} updates
- Project merges: {N} proposals
- Project archival: {N} proposals
- Carry cleanup: {N} proposals
- Task dedup: {N} proposals
- Table trim: {N} proposals
- INTENT.md drift: {N} proposals
- Antifragile cleanup: {N} proposals (structural)
- Permissions audit: {N} proposals
- Plugin cache verify: {N} auto-applied, {M} proposals
- Antifragile compact: {N} proposals (promotions + obsolete-marks)
- USER.md drift: {N} proposals
- Missed reports: {N} proposals
- Radar health audit: {N} proposals
- CLAUDE.md + USER.md health check: {N} proposals
- Upstream source freshness: {N} sources behind, {M} sources current
- Skill registration verify: {N} auto-registered, {M} proposals (collisions/dangling)
- File placement drift: {N} proposals
- Agent-output gate health: {N} samples checked, {M} hollow gates / stale permission audits
- Truth-surface drift: {N} lagging notes, {M} roadmap flags

### 🟢 Auto-applied (no approval needed)
{Low-stakes mechanical fixes — link adds where unambiguous, snapshot timestamp updates, obvious [x] marks}

### 🟡 Proposals — approve per bucket or per item

#### Bucket N: {bucket name}
| # | Proposal | Why | Target | Action |
|---|----------|-----|--------|--------|
| 1 | {specific proposal} | {evidence} | [[file/project]] | [ ] approve |
| 2 | ... | ... | ... | [ ] approve |
```

### Phase 3 — Wait for approval

The user can respond three ways:

- **"approve all"** — apply every proposal
- **"approve buckets 1, 2, 5"** — apply those buckets only
- **"approve 1.1, 2.3, 5.4"** — apply individual items
- **"skip"** — apply nothing, just keep the log

Do not apply anything until the user gives explicit approval. The default is to wait.

### Phase 4 — Apply + log

For each approved proposal:

1. Execute the change (update frontmatter, move content, edit table, mark [x], etc.)
2. Commit the exact change that was made — don't expand scope.

Write a log to `00 - notes/logs/command-logs/housekeeping-{YYYY-MM-DD}.md` with:

```
# Housekeeping — {date}

## Summary
- {N} proposals across {M} buckets
- {N} auto-applied
- {N} approved + applied
- {N} declined / deferred

## Applied
{Per-bucket list of what actually happened — each entry includes the target, the change, the reason}

## Declined / Deferred
{Proposals the user skipped — valuable to keep as a record of "we considered this and decided not to"}

## Next candidates
{If any buckets surfaced items that need more data before they can be proposed next time — e.g., "X project needs 7 more days of dormancy before archival would be safe"}
```

Commit and push:

```bash
cd ~/aios && git add -A && git commit -m "Housekeeping {date}" && git push
```

## Rules

- **Propose, don't decide.** Except for trivially-safe fixes (unambiguous link adds, snapshot timestamp updates, obvious [x] sync), everything waits for approval.
- **Bucket 5 is the most sensitive.** A carry ×10+ that gets dropped is the user's time reclaimed — but also, rarely, a signal of real-but-hard work. Err on the side of "park explicitly" (preserved in Ideas) rather than "delete." Recoverable matters.
- **Bucket 3 + 4 (merges + archival) require user judgment.** Show evidence, don't argue — let the user decide.
- **Never skip the log.** Even if the user approves zero proposals, write the log with what was proposed and what was declined. That's the audit trail for "we considered X, decided not Y."
- **Use [[wiki-links]]** for all project names, context files, and ventures.
- **Run safely anytime.** The proposal-first design means no accidental destruction.
- Commit and push at the end: `Housekeeping {date}` in the commit message.

## Suggested cadence (from `/today` Command Discovery Engine)

| Trigger | Suggest `/housekeeping` |
|---|---|
| **15th of month** (default day-based rhythm) | "Mid-month. Time to tidy the vault." |
| **Parking-lot count > 15 carried items** | "{N} open carries. The vault is heavy." |
| **Active project count > 12** | "{N} active projects. Worth a merge/archive pass?" |
| **3+ project snapshots stale >14 days** | "3 snapshots haven't been touched in 2 weeks." |
| **`/close-day` project-hygiene fired 3+ times in a week** | "Project notes trending long. Housekeeping?" |

These are suggestions, not enforcement — the user decides when the vault feels ready.
