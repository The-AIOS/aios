---
tags:
  - aios
  - command
  - sync
  - infra
description: >-
  Pull latest shared infrastructure from The-AIOS/aios and auto-apply
  every change. Operator content is never touched; framework infra is
  always overwritten, scripts are re-run, duplicates are cleaned.
allowed-tools: >-
  mcp__obsidian__*, Bash(git:*), Bash(rm:*), Bash(mkdir:*), Bash(diff:*),
  Bash(cat:*), Bash(cp:*), Bash(mv:*), Bash(bash:*), Bash(pwsh:*),
  Read, Write, Edit, Grep
---

# /aios:update — Framework Infrastructure Sync (auto-apply)

Pulls the latest framework from The-AIOS/aios (or whatever upstream is tracked in `.aios-update`) and **auto-applies every change.** Framework infra is **mandatory** — every Tier 1 file is overwritten byte-identical to upstream. If the operator customized one, their version is backed up to `vault/04 - backups/aios-update-{date}/` first, then overwritten + the operator is told what was backed up. Scripts that were updated are **automatically re-executed** (e.g. wrapper installer) so the update lands complete, not just the files. After the replace + execute pass, the command scans for duplicates between operator's `custom/` folders and bundled folders and removes them.

Read the framework upstream URL from `.aios-update` (`repo=` field). If `.aios-update` doesn't exist OR is missing the `repo=` field, default to `git@github.com:The-AIOS/aios.git` and ask the operator once to confirm. Also read `USER.md` → `### /aios:update` for command personalizations (if any).

> ⚠️ **Operator-personal files are NEVER overwritten.** Hard denylist (Tier 2 — see below): `USER.md`, `INTENT.md`, and any other `{IDENTITY}.md` at repo root (e.g. session-specific identity files), everything under `vault/00 - notes/{context,projects,ideas,reflections,logs}/`, everything under `vault/01 - calendar/`, `vault/02 - assets/`, `vault/03 - export/`, `vault/04 - backups/`, all `{layer}/custom/` folders, all `{layer}/<company>/` folders, `.aios-update`, `.claude/` (operator's per-machine Claude Code config), `vault/.obsidian/workspace.json` (operator's per-machine Obsidian UI state). Framework infra wins on its files; operator content wins on theirs.

## When to use

When the upstream framework has new commits. `/today` and `/close-day` auto-detect BEHIND state and auto-fire this command. You can also run it manually anytime.

## What gets updated

### Tier 1: Mandatory infra (always replaced, never asked)

Every file below is overwritten byte-identical to upstream. If the operator customized one, their version is backed up first (see § Backup-on-divergence below).

- **Root docs:** `README.md`, `START-HERE.md`, `SETUP.md`, `CHEATSHEET.md`, `TOOLS.md`, `CHANGELOG.md`, `LICENSE`, `NOTICE`, `FORTRESS.md`, `.gitignore`
- **CLAUDE.md** (vault-level instructions — moved here from Tier 2 on 2026-05-25 per the "infra is infra" principle)
- **Templates:** `templates/aios/` (bundled templates, e.g. `templates/aios/about_me-template.md`) — never `templates/custom/` or `templates/<company>/`. (Moved from the layer root into `templates/aios/` to match the `{layer}/aios/` + `custom/` + `<company>/` convention used by agents, skills, and plugins.)
- **Skills:** `skills/aios/`, `skills/anthropic/`, `skills/superpowers/` (never `skills/custom/`)
- **Hooks:** `hooks/*` except `hooks/custom/` (pipeline executor, markitdown converter, claude-identity wrappers)
- **MCPs:** `mcps/*` except `mcps/custom/` (vendored MCP servers — code + README)
- **Agents:** `agents/aios/` (bundled 6-bundle structure: `aios/sales/`, `aios/strategy/`, `aios/finance-legal/`, `aios/engineering/`, `aios/communication/`, `aios/personal/`) and `agents/_index.md`. Never overwrite `agents/custom/` or `agents/<company>/`.
- **Plugins:** `plugins/aios/**` (full plugin folder replace, INCLUDING `plugins/aios/commands/*` — these are framework commands, not operator content) except `plugins/aios/commands/custom/`
- **Other bundled plugins** at top level except `plugins/custom/`, `plugins/aios/`, and `plugins/<company>/`
- **Marketplace manifest:** `.claude-plugin/marketplace.json`
- **Obsidian config baseline:** `vault/.obsidian/*.json` except `workspace.json`, plus `vault/.obsidian/snippets/*`

### Tier 2: Operator content (never touched — denylist)

See the callout at the top. Hard denylist — this command refuses to write to any path under it.

### Tier 3: Advisory only (template evolution flags)

When a template under `templates/aios/*-template.md` gains a new section, advise the operator that their corresponding filled-in file (`vault/00 - notes/context/declared/{file}.md`) is missing that section. No file is touched. Same for `USER.md` template gaining sections vs operator's USER.md.

## Backup-on-divergence (three-way compare — stale is NOT a personalization)

Before overwriting any Tier 1 file, do a **three-way compare** to distinguish operator personalizations from merely-stale files. The naive "local differs from upstream HEAD → backup" rule over-backs-up: an operator whose vault is N days behind has local files that differ from current upstream simply because they haven't synced yet, not because they personalized anything. Backing those up floods `vault/04 - backups/` with non-personalizations and noises the "your edits were preserved" report.

The right comparison: **local vs operator's last-synced BASELINE** (the version they had after their last successful `/aios:update`).

```bash
# For each changed Tier 1 file, get THREE versions:
#   (a) baseline — what upstream looked like at stored_hash (operator's last sync)
#   (b) local    — what's in operator's vault now
#   (c) upstream — what's at upstream HEAD (target of this update)

# Fetch baseline content from the same clone we already have (no second clone needed):
git -C /tmp/vault-update-check show {stored_hash}:{path} > /tmp/aios-baseline-{flattened-path}

# Compare local vs baseline:
diff -q "$HOME/aios/{path}" /tmp/aios-baseline-{flattened-path}
```

**Three outcomes:**

| Local vs baseline | Meaning | Action |
|---|---|---|
| **Identical** | Operator never touched this file — they just had an older synced version | **Overwrite silently. No backup.** The "diff vs upstream HEAD" is just stale, not personalization. |
| **Different** | Operator made local edits AFTER last sync | **Backup-on-divergence:** copy local to `vault/04 - backups/aios-update-{date}/{flattened-path}` BEFORE overwrite. Tell operator what was preserved. |
| **Baseline doesn't exist in clone** (cross-repo case, OR `stored_hash` is `initial`) | Can't establish baseline | **Conservative fallback:** treat as personalization → backup before overwrite. Better to over-backup once than risk losing operator edits. |

Files with NO upstream change → not even considered (`git diff` didn't list them).

Files where local == baseline (clean overwrites) → never appear in the report's "Backed up" section. Only true personalizations land there.

This makes the "Backed up (your customizations preserved)" report **meaningful** — every entry represents an actual operator edit worth their review.

## Post-replace auto-execution (scripts must RUN, not just copy)

After Tier 1 replace lands, automatically execute any updated script that **produces operator-environment state**, so the update is COMPLETE, not just file-deep. The principle:

| Class | What it is | Action when updated |
|---|---|---|
| **Installer / state-producer** | Idempotent scripts that write to `~/.zshrc`, `~/.claude/`, `~/Library/LaunchAgents/`, etc. — running them is the whole point | **Auto-run** |
| **Plugin sync target** | Markdown command files that need to land in `~/.claude/plugins/{marketplaces,cache}/...` to be active | **Auto-sync** (cp to both locations) |
| **Dep-installer** | Scripts that install system packages or write to shared paths (e.g. `mcps/setup.sh` installs venvs + Node deps) | **Flag as manual step** — operator decides which MCPs need refresh; running blindly is expensive |
| **Library code** | Scripts invoked by other commands (e.g. `hooks/pipeline-executor.py` — called by `/today` and `/close-day`) | **No action needed** — the next caller picks up the new code automatically |

Concrete rules for what's currently in the framework (the operator-environment-state class):

- **`hooks/claude-identity/install-wrappers.sh` updated** (macOS / Linux) → `bash $HOME/aios/hooks/claude-identity/install-wrappers.sh`. Don't ask. Idempotent (timestamped backup → strip prior banner → append fresh). Report: *"Wrappers re-installed. Open a new terminal to pick up changes."*
- **`hooks/claude-identity/install-wrappers.ps1` updated** (Windows) → `pwsh -File $HOME\aios\hooks\claude-identity\install-wrappers.ps1`. Same idempotency.
- **Any `hooks/claude-identity/install-*.sh` / install-*.ps1` updated** (current + future installers in that path) → auto-run by the same rule.
- **Any `plugins/aios/commands/*.md` updated** → cp to both plugin pipeline locations:
  ```bash
  cp $HOME/aios/plugins/aios/commands/*.md $HOME/.claude/plugins/marketplaces/the-aios/plugins/aios/commands/
  cp $HOME/aios/plugins/aios/commands/*.md $HOME/.claude/plugins/cache/the-aios/aios/0.1.0/commands/
  ```
- **`mcps/setup.sh` or any other dep-installer updated** → surface in the report as a recommended manual step, with the exact command. Don't auto-run.

If a future framework update adds a new state-producing installer under `hooks/`, the principle extends naturally — add it to the rule above and it gets auto-run. Library scripts (`*.py` invoked indirectly) are picked up by their callers; no auto-execution needed.

## Duplicate cleanup (after replace + execute)

Migration history left operators with duplicates: a skill (or agent) lives BOTH in the canonical bundled location AND in `custom/` (or at the layer's root). After every replace, scan + clean:

For each layer in `agents`, `skills`, `plugins`, `mcps`, `templates`, `hooks`:

1. Build the set of bundled file basenames — every `.md` under `{layer}/aios/`, `{layer}/anthropic/`, `{layer}/superpowers/`, and (for plugins/) `{layer}/aios/commands/`. **Exclude `_index.md` from this set** — every folder gets its OWN `_index.md` as navigation metadata, they are NEVER duplicates of each other (`agents/aios/_index.md` is the bundled index; `agents/custom/_index.md` is the operator's index for their custom agents — both intentional, neither is a copy).
2. Scan `{layer}/custom/*` for any file whose basename appears in the bundled set AND is not `_index.md`. **For each match: apply the stale-vs-personalized test, then remove.**
   - **Content-compare** the local file (`{layer}/custom/{name}.md`) against the CURRENT bundled file (`{layer}/{bundled-subfolder}/{name}.md`).
   - **If byte-identical to current bundled** (true duplicate, no operator value): remove silently, no backup needed.
   - **If different from current bundled → check if it's a stale-bundled version** (not a personalization): scan recent upstream history for any past version of the bundled file matching this content. Use `git -C /tmp/vault-update-check log --all -p -- {bundled-path}` and compare against the past few revisions of the file. If a match is found in upstream history → the file is just a stale bundled copy (migration leftover) → remove silently, no backup.
   - **Else** (different from current AND no match in upstream history): treat as real personalization → backup-on-divergence: copy operator's version to `vault/04 - backups/aios-update-{YYYY-MM-DD}/duplicates/{layer}-custom-{name}.md` FIRST, then remove.
   - Log either way: *"Removed `agents/custom/lawyer.md` — duplicate of bundled `agents/aios/finance-legal/lawyer.md`. [Backed up to vault/04 - backups/aios-update-2026-05-25/duplicates/agents-custom-lawyer.md — your version didn't match current or any past bundled; restore manually if you had intentional edits.]"* (bracketed clause only when backed up).
3. Scan `{layer}/*.md` at the top level (outside any subfolder). Skip `_index.md` (layer-root index is intentional, not an orphan). If a remaining top-level file's basename matches a bundled file → **same stale-vs-personalized test as step 2.** If byte-identical or matches a past bundled version → silent remove. Else → backup to `vault/04 - backups/aios-update-{YYYY-MM-DD}/duplicates/{layer}-root-{name}.md` then remove. Log: *"Removed `templates/project-template.md` — duplicate of bundled `templates/aios/project-template.md`."*
3b. **Folder-based layers (skills/) need directory-level dedup, not just file-level.** A skill is a `{name}/` directory containing `SKILL.md` — so basename-matching on `.md` files (steps 1-3) can't catch a stray skill folder (every skill's file is `SKILL.md`; the identity is the FOLDER name). For `skills/` specifically: build the set of bundled skill-folder names (`basename` of each dir under `skills/aios/`, `skills/anthropic/`, `skills/superpowers/`). Then scan **both** `skills/*/` at root (pre-bundle layout) **and** `skills/custom/*/` for any folder whose name matches a bundled skill-folder name. For each match, apply the same stale-vs-personalized test (content-compare the folder's `SKILL.md` against the bundled one + check upstream history) → remove the stray folder (silent if matched current/past bundled, backup-then-remove if it looks personalized). Never touch `skills/aios/`, `skills/anthropic/`, `skills/superpowers/`, `skills/custom/`-unique folders, or any `_index.md`. (This is the gap that left 60+ pre-bundle skill folders sitting at `skills/` root after migration — they were folders, so the file-basename passes skipped them.)
4. Skip files/folders genuinely unique to `custom/` — those are operator extensions and stay. **All `_index.md` files at any level are also preserved** — navigation metadata is per-folder, never a duplicate.
5. **Remove now-empty folders.** After steps 2-3b delete duplicate files/folders, a parent dir may be left empty (e.g. a `skills/{name}/` folder whose only content was a removed `SKILL.md`, or a `custom/` subfolder emptied of dups). Walk each touched layer and `rmdir` any directory that is now empty OR contains only an `_index.md` that references nothing. Do NOT remove `{layer}/custom/` itself even when empty — it's the operator's namespace and must persist for future extensions. Log: *"Removed empty folder `skills/old-skill/` (left after duplicate cleanup)."* (This is the gap where prior cleanups removed the `.md` files but left hollow folders behind.)

Skip layers without a `custom/` subfolder (no opportunity for duplicates there). **Bundled content for every layer lives under `{layer}/aios/` (+ source-peer bundles `anthropic/`, `superpowers/` for skills); the layer root and `custom/` should contain only `_index.md` + genuine operator extensions after cleanup.**

Aggregate the cleanup report: *"Cleaned N duplicates across {layer1, layer2, ...}: M removed silently (matched current OR past bundled version — stale migration leftovers), K backed up to `vault/04 - backups/aios-update-{date}/duplicates/` (didn't match any bundled version past or present — likely real personalizations, review)."*

## Tracker file

```
repo={framework upstream URL}
hash={last synced commit hash}
synced={date of last sync}
```

If the file doesn't exist, create it with `repo=git@github.com:The-AIOS/aios.git` and ask the operator once to confirm. Set `hash=initial` (forces full comparison on first run).

## Steps

### 1. Clone and check for changes

```bash
rm -rf /tmp/vault-update-check && git clone --depth=50 --single-branch {team_repo_url} /tmp/vault-update-check 2>&1
```

If SSH fails, try HTTPS format. Get current HEAD: `git -C /tmp/vault-update-check rev-parse HEAD`. If HEAD matches stored hash → "Your vault infrastructure is current (synced {date})." → clean up → done.

### 1.5. Show changelog context

Read `CHANGELOG.md` from the cloned repo root. If absent, skip silently. Otherwise:

1. Parse `## ` entries (each is `## YYYY-MM-DD — title` followed by `` `hash: {short_hash}` ``).
2. For each entry newest first, check if synced via `git -C /tmp/vault-update-check merge-base --is-ancestor {entry_hash} {stored_hash}` (exit 0 = synced, stop scanning; exit 1 = new, collect; exit 128 = hash unreachable in cloned repo → fall back to content-comparison against local CHANGELOG.md by date header + title).
3. If new entries exist, show them before applying changes — present **What changed** + **Action required** sections only (skip Why/FYI for brevity; full details in CHANGELOG.md). Aggregate + deduplicate Action required across all new entries.
4. Execute the action items inline as part of this run — don't list them and wait for the operator to ask. This command IS the implementation arm of CHANGELOG action items.

### 2. Find what changed

```bash
git -C /tmp/vault-update-check diff {stored_hash}..HEAD --name-only -- \
  "README.md" "START-HERE.md" "SETUP.md" "TOOLS.md" "CHEATSHEET.md" \
  "CHANGELOG.md" "CLAUDE.md" "LICENSE" "NOTICE" "FORTRESS.md" ".gitignore" \
  "templates/" "skills/" "hooks/" "mcps/" "plugins/" "agents/" \
  ".claude-plugin/" "vault/.obsidian/"
```

If no Tier 1 files changed → update tracker hash → still run **duplicate cleanup** (cleanup is independent of upstream changes — it cleans local migration drift) → done.

### 2.5. Self-update guard (bootstrap-safe, auto-re-invokes)

**Before processing anything else, content-compare local `plugins/aios/commands/update.md` against the cloned upstream version.** This is the bootstrap-safety check: when `update.md` itself changes, the current run is executing OLD spec — we need the NEW spec to land + re-process everything, without operator action.

```bash
diff -q "$HOME/aios/plugins/aios/commands/update.md" /tmp/vault-update-check/plugins/aios/commands/update.md
```

**Case A — Identical (no self-update needed):** local already matches upstream. Skip the rest of this step, proceed to Step 3 with current logic. This is the normal path AND the path taken by an auto-re-invocation (because the first run already applied update.md).

**Case B — Different (update.md was updated upstream):**

1. Apply the replace for `update.md` immediately:
   - Backup local to `vault/04 - backups/aios-update-{date}/update.md` (operator divergence preserved per the standard rule).
   - Overwrite local `plugins/aios/commands/update.md` from upstream.
2. Sync to BOTH plugin pipeline locations (marketplace + cache):
   ```bash
   cp $HOME/aios/plugins/aios/commands/update.md $HOME/.claude/plugins/marketplaces/the-aios/plugins/aios/commands/update.md
   cp $HOME/aios/plugins/aios/commands/update.md $HOME/.claude/plugins/cache/the-aios/aios/0.1.0/commands/update.md
   ```
3. Clean up the temp clone (the re-invoke will re-clone fresh): `rm -rf /tmp/vault-update-check`.
4. **Auto-re-invoke the command** via `Skill(aios:update)`. The re-invocation loads the NEW spec from the plugin cache (just synced) and processes all changed files from a clean state.
5. **Exit the current run** after the re-invocation returns — its work is done by the inner run.

Report to operator at the end: *"`/aios:update` self-updated and re-ran automatically with the new spec — {summary of what the inner run processed}."* No operator action required; the outer run handed off cleanly.

**Why content-compare instead of a state-flag:** the content IS the state. On auto-re-invocation, local update.md is already byte-identical to upstream → Case A fires → no recursion. The pattern is self-terminating by design.

### 3. Apply ALL Tier 1 changes (auto-apply)

For each changed Tier 1 file:

1. **Diff local vs upstream HEAD.** If byte-identical, skip (no work needed — operator already has this version somehow).
2. **Three-way compare to decide on backup** (see § Backup-on-divergence above):
   - Get baseline via `git -C /tmp/vault-update-check show {stored_hash}:{path}`.
   - If `local == baseline` → operator never touched it → overwrite silently, **no backup**.
   - If `local != baseline` → operator personalized → **backup-on-divergence:** copy local to `vault/04 - backups/aios-update-{YYYY-MM-DD}/{flattened-path}.md` BEFORE overwrite.
   - If baseline unreachable (cross-repo hash or `stored_hash=initial`) → conservative fallback: backup.
3. **Overwrite** using the right tool:
   - `.md` files **inside** `vault/` → `mcp__obsidian__write_note` (keeps Obsidian graph consistent)
   - `.md` files **outside** `vault/` (root + `hooks/`, `mcps/`, `plugins/`, `skills/`, `agents/`, `templates/`) → `Bash cp` or `Write`
   - All other extensions (`.json`, `.css`, `.py`, `.sh`, `.plist`, `.yml`) → `Bash cp` (preserves file mode — load-bearing for executable scripts under `hooks/`)
   - New subdirectories that don't exist locally → `mkdir -p` first, then `cp`
   - New files in `agents/aios/{bundle}/` or other bundled subfolders → `cp` to the matching local path
4. **Files deleted upstream:** flag with a question, don't auto-delete. *"Upstream removed `{path}`. Delete your local copy too? [yes/keep]."* Default: keep (operator may have reasons to retain locally).

### 4. Auto-execute post-replace scripts

See § Post-replace auto-execution above. For each script that was updated in step 3, run it now. Wait for it to finish, capture output, report success/failure.

### 5. Duplicate cleanup

See § Duplicate cleanup above. Always runs — even when no upstream changes landed. Removes migration-leftover duplicates between bundled folders and `custom/` + top-level orphans.

### 6. Tier 3 advisory flags

For each template that changed in step 3, compare its `## ` heading set to the operator's corresponding filled-in file. List missing sections without taking action. Same for the USER.md template.

### 7. Update tracker and clean up

Update `.aios-update` with new HEAD hash + today's date. `rm -rf /tmp/vault-update-check`.

## Output format

**If current and no duplicates:**
> Your vault infrastructure is current (synced {date}, hash {hash}). No duplicates found.

**If current but duplicates were cleaned:**
> Your vault infrastructure is current. Cleaned {N} migration-leftover duplicates: {brief list}.

**If updates landed:**
```
## Vault updated to {new_hash} (was {old_hash}, {N} commits)

### What's new (changelog)
{action-item-bearing entries; What changed + Action required only}

### Applied (Tier 1)
{file list — grouped by area, e.g. "Root docs (3): README, CHANGELOG, TOOLS"}

### Backed up (your customizations preserved)
{any divergent file → backup path, e.g. "CLAUDE.md → vault/04 - backups/aios-update-2026-05-25/CLAUDE.md"}

### Scripts re-executed
{e.g. "install-wrappers.sh — wrappers refreshed. Open a new terminal."}

### Duplicates cleaned
{any duplicates removed from custom/ or top-level orphans}

### Advisory (Tier 3 — template evolution)
{missing sections in declared context, if any}
```

**If network error:**
> Could not reach {team_repo_url}. Check your git access and try again.

## Rules

- **Auto-apply, never ask.** Tier 1 changes are mandatory infra — the command does not present diff approval flows. The operator sees a report of what was done, not a multiple-choice menu.
- **Backup-on-divergence is the safety net.** Operator customizations to Tier 1 files are preserved in `vault/04 - backups/aios-update-{date}/` but are NOT auto-restored. If they want their edits back, they manually merge from the backup.
- **Scripts must run.** A script update that doesn't get executed is half a sync. The wrapper installer is the canonical example — bringing the file without running it leaves the operator's shell on the old code path.
- **Duplicate cleanup is structural.** Always runs. The bundled folder structure (`agents/aios/{bundle}/`, `skills/superpowers/`, etc.) is canonical. `custom/` is for genuinely operator-unique extensions only.
- **Tier 2 (operator content) is sacred.** Never touched. Includes everything under the denylist.
- **Self-update is auto-re-invoking + bootstrap-safe.** When `update.md` itself is in the diff, apply + sync to plugin pipeline FIRST, then auto-re-invoke `Skill(aios:update)`. The inner run loads the new spec, processes everything cleanly, returns. Content-comparison guards against recursion (after self-apply, local matches upstream → Case A fires → no loop). Operator sees one report from the outer run; no manual re-invocation needed. See Step 2.5.
- **Cross-repo cascades.** When CHANGELOG hashes don't exist in the cloned repo (common for operators syncing from a fork or downstream mirror), fall back to content-comparison via date header + title (see Step 1.5).
- **Clean up temp clone.** Always `rm -rf /tmp/vault-update-check` at end, even on error.
- Use `[[wiki-links]]` for project names, context files, ventures mentioned in the report.

## Relationship to /company

`/aios:update` syncs framework infra (commands, templates, hooks, agents, skills, etc.) from the framework upstream tracked in `.aios-update`. `/aios:company` mounts COMPANY venture-context from per-company repos tracked in `USER.md → ## Companies (mounted)`. Different layers, different trackers, never conflated. Running one does not affect the other.
