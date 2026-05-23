---
tags:
  - aios
  - command
  - on-demand
description: Vault housekeeping — proposals to merge, archive, drop carries, refresh indexes, repair links, tidy antifragile, verify plugin cache, audit permissions
allowed-tools: mcp__obsidian__*, Read, Grep, Glob, Bash
---

# /housekeeping — Vault Housekeeping

Periodic care of the vault as it grows. Produces a review packet across 14 buckets — link repairs, index refresh, project merges, archival, carry cleanup, task dedup, table trim, INTENT.md drift, antifragile cleanup, permissions audit, plugin-cache verification, antifragile compact, USER.md drift, missed reports — with proposals the user approves before anything is applied. Writes a log of what was proposed, approved, and applied.

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

Gather evidence across **all 12 buckets — no skipping.** "Deferred to tooling" is banned; the scanning IS the tooling. If a bucket surfaces low signal, state that explicitly with evidence ("scanned N items, 0 merge candidates found") — don't hand-wave.

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

The `plugins/aios/commands/` repo folder is the source of truth. Two derived locations must stay in sync — the plugin marketplace and the runtime cache:

- `~/.claude/plugins/marketplaces/the-aios/plugins/aios/commands/{name}.md`
- `~/.claude/plugins/cache/the-aios/aios/0.1.0/commands/{name}.md`

**Scan:** for each `plugins/aios/commands/{name}.md` in the repo, `diff` against both derived locations. Surface any drift:

- **Repo file present, marketplace/cache file missing** → command was added but never synced
- **Files exist in all 3 but content differs** → command was edited in source but not propagated
- **Marketplace/cache file exists, repo file missing** → command was deleted in source but stale copy lingers in plugin paths

**Auto-apply candidates** (low-stakes, deterministic):
- Repo → marketplace + cache copy when repo is the only authoritative source. Use `cp ~/aios/plugins/aios/commands/{name}.md ~/.claude/plugins/marketplaces/the-aios/plugins/aios/commands/` and the equivalent for cache. Confirm post-copy that all 3 files match (`diff -q`).

**Propose-only candidates** (need user judgment):
- Plugin paths have content the repo doesn't — possible accidental delete, or in-progress refactor. Ask before removing.

**Evidence discipline:** show the actual `diff -q` output per drifted command. "`plugins/aios/commands/today.md` differs from cache" is more useful than "today is out of sync."

**Why this matters:** the plugin cache is what Claude actually reads at runtime. Drift between source and cache means edits to `plugins/aios/commands/*.md` don't take effect — silent breakage, hard to debug.

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
