---
tags:
  - aios
  - command
  - sync
  - infra
description: >-
  Pull latest shared infrastructure from The-AIOS/aios and auto-apply
  every change. Operator content is never touched; framework infra is
  always overwritten, scripts are re-run, and a tracker-independent
  completeness reconcile guarantees the vault matches canonical HEAD.
allowed-tools: >-
  mcp__obsidian__*, Bash(git:*), Bash(rm:*), Bash(mkdir:*), Bash(diff:*),
  Bash(cat:*), Bash(cp:*), Bash(mv:*), Bash(bash:*), Bash(pwsh:*),
  Read, Write, Edit, Grep
---

# /aios:update — Framework Infrastructure Sync (auto-apply)

Pulls the latest framework from The-AIOS/aios (or whatever upstream is tracked in `.aios-update`) and **auto-applies every change.** Framework infra is **mandatory** — every Tier 1 file is overwritten byte-identical to upstream. If the operator customized one, their version is backed up to `vault/04 - backups/aios-update-{date}/` first, then overwritten + the operator is told what was backed up. Scripts that were updated are **automatically re-executed** (e.g. wrapper installer) so the update lands complete, not just the files. After the replace + execute pass, a **completeness reconcile** (Step 6.5) diffs the vault against canonical HEAD directly — so a desynced tracker self-heals rather than silently orphaning content — and the tracker advances only on a clean, fully-applied run. Duplicate cleanup is **opt-in** (`--cleanup`, report-first); it's after-migration scaffolding, off the default path.

Read the framework upstream URL from `.aios-update` (`repo=` field). If `.aios-update` doesn't exist OR is missing the `repo=` field, default to `git@github.com:The-AIOS/aios.git` and ask the operator once to confirm. Also read `USER.md` → `### /aios:update` for command personalizations (if any).

> ⚠️ **Operator-personal files are NEVER overwritten.** Hard denylist (Tier 2 — see below): `USER.md`, `INTENT.md`, and any other `{IDENTITY}.md` at repo root (e.g. session-specific identity files), everything under `vault/00 - notes/{context,projects,ideas,reflections,logs}/`, everything under `vault/01 - calendar/`, `vault/02 - assets/`, `vault/03 - export/`, `vault/04 - backups/`, all `{layer}/custom/` folders, all `{layer}/<company>/` folders, `.aios-update`, `.claude/` (operator's per-machine Claude Code config), `vault/.obsidian/workspace.json` (operator's per-machine Obsidian UI state). Framework infra wins on its files; operator content wins on theirs.

## When to use

When the upstream framework has new commits. `/today` and `/close-day` auto-detect BEHIND state and auto-fire this command. You can also run it manually anytime.

## What gets updated

### Tier 1: Mandatory infra (always replaced, never asked)

Every file below is overwritten byte-identical to upstream. If the operator customized one, their version is backed up first (see § Backup-on-divergence below).

- **Root docs:** `README.md`, `START-HERE.md`, `SETUP.md`, `CHEATSHEET.md`, `TOOLS.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `LICENSE`, `NOTICE`, `FORTRESS.md`, `.gitignore`
- **CLAUDE.md** (vault-level instructions — moved here from Tier 2 on 2026-05-25 per the "infra is infra" principle)
- **Templates:** `templates/aios/` (bundled templates, e.g. `templates/aios/about_me-template.md`) — never `templates/custom/` or `templates/<company>/`. (Moved from the layer root into `templates/aios/` to match the `{layer}/aios/` + `custom/` + `<company>/` convention used by agents, skills, and plugins.)
- **Skills:** `skills/aios/`, `skills/anthropic/`, `skills/superpowers/` (never `skills/custom/`)
- **Hooks:** `hooks/*` except `hooks/custom/` (pipeline executor, markitdown converter, claude-identity wrappers)
- **MCPs:** `mcps/*` except `mcps/custom/` (vendored MCP servers — code + README)
- **Agents:** `agents/aios/` (bundled 6-bundle structure: `aios/sales/`, `aios/strategy/`, `aios/finance-legal/`, `aios/engineering/`, `aios/communication/`, `aios/personal/`) and `agents/_index.md`. Never overwrite `agents/custom/` or `agents/<company>/`.
- **Plugins:** `plugins/aios/**` (full plugin folder replace, INCLUDING `plugins/aios/commands/*` — these are framework commands, not operator content) except `plugins/aios/commands/custom/`
- **Other bundled plugins** at top level except `plugins/custom/`, `plugins/aios/`, and `plugins/<company>/`
- **Marketplace manifest:** `.claude-plugin/marketplace.json` — **MERGE, never byte-replace.** This file is dual-owned: the framework owns the bundled plugin entries (e.g. `aios`), but CLAUDE.md instructs operators to register their own `plugins/custom/<name>/` (and `/aios:company` registers `plugins/<company>/`) entries in the SAME file. Merge rule: parse both versions as JSON → take upstream's top-level fields + upstream's entries for bundled plugins → preserve every local entry whose `source` points into `./plugins/custom/` or a company namespace → write the union. A byte-replace here silently deregisters every operator/company plugin on every sync (caught 2026-06-05 registering the first `plugins/custom/` command).
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
git -C /tmp/aios-update-check show {stored_hash}:{path} > /tmp/aios-baseline-{flattened-path}

# Compare local vs baseline (line-ending-normalized — see CRLF note below):
diff -q <(tr -d '\r' < "$HOME/aios/{path}") <(tr -d '\r' < /tmp/aios-baseline-{flattened-path})
```

> **CRLF note (Windows).** On Windows, Git's `core.autocrlf` converts LF→CRLF on checkout, so vault files have `\r\n` line endings while `git show {hash}:{path}` (and the temp clone's working tree) may not — a raw `diff -q` then reports "differ" for byte-identical content, flooding `vault/04 - backups/` with false personalizations on every sync. **Every content comparison in this command strips `\r` before diffing** (`tr -d '\r'` via process substitution, as above). This applies to the self-update guard (Step 2.5) and the duplicate-cleanup content-compares (§ Duplicate cleanup) too — normalize line endings, then compare.

**Three outcomes:**

| Local vs baseline | Meaning | Action |
|---|---|---|
| **Identical** | Operator never touched this file — they just had an older synced version | **Overwrite silently. No backup.** The "diff vs upstream HEAD" is just stale, not personalization. |
| **Different** | Operator made local edits AFTER last sync | **Backup-on-divergence:** copy local to `vault/04 - backups/aios-update-{date}/{flattened-path}` BEFORE overwrite. Tell operator what was preserved. |
| **Baseline doesn't exist in clone** (cross-repo case, OR `stored_hash` is `initial`) | Can't establish baseline | **Conservative fallback:** treat as personalization → backup before overwrite. Better to over-backup once than risk losing operator edits. |

**Exempt from backup entirely — `CHANGELOG.md`.** It is append-only **canonical history, mandated byte-identical across every repo** (no operator ever personalizes it — there is nothing in it that is theirs to keep). A local diff on `CHANGELOG.md` is therefore *always* stale-not-personalized, even when the three-way compare reports "Different" (e.g. a WIP entry an operator's earlier session left mid-edit). So `CHANGELOG.md` is **always a clean overwrite, never backed up** — skip the three-way compare for it and never write it to `vault/04 - backups/`. (Backing it up just produces noise files that duplicate canonical history.)

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

- **Platform guard — auto-run ONLY the installer matching the operator's OS, never the other platform's.** Detect once: `case "$OSTYPE" in msys*|cygwin*|win*) IS_WIN=1 ;; *) IS_WIN=0 ;; esac` (or `uname -s`: `Darwin`/`Linux` = non-Windows). On macOS/Linux run only the `.sh`; on Windows run only the `.ps1`. This prevents a Mac/Linux session from attempting the `.ps1` (a stray `powershell: command not found` in the report, or a pointless write into an unused `pwsh` profile) — and a Windows session from attempting the `.sh`. The file still gets *copied* on every OS (Tier-1); only its *execution* is platform-gated.
- **`hooks/claude-identity/install-wrappers.sh` updated** → **macOS / Linux only** (`IS_WIN=0`; skip on Windows) → `bash $HOME/aios/hooks/claude-identity/install-wrappers.sh`. Don't ask. Idempotent (timestamped backup → strip prior banner → append fresh). Report: *"Wrappers re-installed. Open a new terminal to pick up changes."*
- **`hooks/claude-identity/install-wrappers.ps1` updated** → **Windows only** (`IS_WIN=1`; skip on macOS / Linux) → run with whichever PowerShell exists. `pwsh` (PowerShell 7) is **not** installed by default on Windows — a stock Win11 ships only Windows PowerShell 5.1 (`powershell`), which runs the `.ps1` fine. Try `pwsh`, fall back to `powershell`:
  ```bash
  if command -v pwsh >/dev/null 2>&1; then
    pwsh -File "$HOME/aios/hooks/claude-identity/install-wrappers.ps1"
  else
    powershell -File "$HOME/aios/hooks/claude-identity/install-wrappers.ps1"
  fi
  ```
  Same idempotency. (Hard-coding `pwsh` fails the install on a stock machine — surfaced by a Windows operator 2026-05-27.)
- **Any `hooks/claude-identity/install-*.sh` / `install-*.ps1` updated** (current + future installers in that path) → auto-run by the same rule, under the same platform guard (`.sh` on non-Windows, `.ps1` on Windows).
- **A bundled skill changed — any `skills/{aios,anthropic,superpowers}/**/SKILL.md` added/changed in the diff, OR `skills/setup.sh` itself updated** → run the skills registrar (an Installer/state-producer: it symlinks skills into `~/.claude/skills`; a newly-pulled bundled skill is NOT loadable until registered). Platform-guarded like the wrapper installer — `bash $HOME/aios/skills/setup.sh` on macOS/Linux; on Windows try `pwsh -File $HOME/aios/skills/setup.ps1` then fall back to `powershell -File …`. Idempotent (skips names already linked; the scan is venture-aware — `skills/*/*/SKILL.md` minus `anthropic`/`superpowers` source-peers). **Gate:** run ONLY when the diff touched a bundled `SKILL.md` or `skills/setup.sh` — not on every sync. Report: *"Registered {N} new skill(s) into `~/.claude/skills` — restart sessions to load them."* (Mirrors `/aios:company` Step 5.5, which does this for venture skills on sync.)
- **Any `plugins/aios/commands/*.md` updated** → sync to the plugin pipeline. **The marketplace copy applies ONLY to a GitHub-source install** — the **primary AIOS mode is a directory-source marketplace** (the local vault registered as `Directory → ~/aios`, which is what lets it carry ventures + `custom/` that a GitHub-source clone would miss). On a directory-source install the marketplace *reads `~/aios` in place*, the `marketplaces/the-aios/…` path **does not exist**, and the copy must skip silently. The cache is runtime-authoritative either way. **Guard both copies with `[ -d ]`** so directory-source no-ops cleanly:
  ```bash
  # GitHub-source only — directory-source has no marketplace dir (reads ~/aios in place). Guard → no-op on directory-source.
  mp="$HOME/.claude/plugins/marketplaces/the-aios/plugins/aios/commands"; [ -d "$mp" ] && cp $HOME/aios/plugins/aios/commands/*.md "$mp/"
  # cache path is VERSION-AGNOSTIC — glob the installed version dir (never hard-pin a version; the plugin bumps but this string outlives the bump). Guard handles the no-match case.
  for d in "$HOME"/.claude/plugins/cache/the-aios/aios/*/commands/; do [ -d "$d" ] && cp $HOME/aios/plugins/aios/commands/*.md "$d"; done
  ```
- **`mcps/setup.sh` or any other dep-installer updated** → surface in the report as a recommended manual step, with the exact command. Don't auto-run.

If a future framework update adds a new state-producing installer under `hooks/`, the principle extends naturally — add it to the rule above and it gets auto-run. Library scripts (`*.py` invoked indirectly) are picked up by their callers; no auto-execution needed.

## Duplicate cleanup (OPT-IN via `--cleanup` — see Step 5)

> **This runs only when the operator passes `--cleanup`, and even then it reports-then-confirms before removing anything (Step 5).** It is NOT part of the default sync. It was after-migration scaffolding; the structure is now stable. Kept available for the rare case, documented below.

Migration history left operators with duplicates: a skill (or agent) lives BOTH in the canonical bundled location AND in `custom/` (or at the layer's root). When `--cleanup` is passed, scan + (on confirm) clean:

For each layer in `agents`, `skills`, `plugins`, `mcps`, `templates`, `hooks`:

1. Build the set of bundled file basenames — every `.md` under `{layer}/aios/`, `{layer}/anthropic/`, `{layer}/superpowers/`, and (for plugins/) `{layer}/aios/commands/`. **Exclude `_index.md` from this set** — every folder gets its OWN `_index.md` as navigation metadata, they are NEVER duplicates of each other (`agents/aios/_index.md` is the bundled index; `agents/custom/_index.md` is the operator's index for their custom agents — both intentional, neither is a copy).
2. Scan `{layer}/custom/*` for any file whose basename appears in the bundled set AND is not `_index.md`. **For each match: apply the stale-vs-personalized test, then remove.**
   - **Content-compare** the local file (`{layer}/custom/{name}.md`) against the CURRENT bundled file (`{layer}/{bundled-subfolder}/{name}.md`). **Normalize line endings first** (`tr -d '\r'` both sides — see CRLF note in § Backup-on-divergence) so Windows CRLF checkouts don't read as differences.
   - **If byte-identical to current bundled** (after CRLF-normalization — true duplicate, no operator value): remove silently, no backup needed.
   - **If different from current bundled → check if it's a stale-bundled version** (not a personalization): scan recent upstream history for any past version of the bundled file matching this content. Use `git -C /tmp/aios-update-check log --all -p -- {bundled-path}` and compare against the past few revisions of the file. If a match is found in upstream history → the file is just a stale bundled copy (migration leftover) → remove silently, no backup.
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
# On Windows Git Bash, ssh-agent typically isn't running, so a git@ URL hangs
# ~5-10s before failing on EVERY sync. Detect MSYS/Cygwin and rewrite git@ → HTTPS
# up front to skip the timeout (surfaced by a Windows operator 2026-05-27).
clone_url="{team_repo_url}"
case "$OSTYPE" in
  msys*|cygwin*) clone_url=$(echo "$clone_url" | sed -E 's#git@github\.com:#https://github.com/#') ;;
esac
# FULL single-branch clone (no --depth). The three-way backup baseline
# (`git show {stored_hash}:path`) and the changelog ancestor-scan
# (`merge-base --is-ancestor {entry_hash} {stored_hash}`) both require the
# operator's stored_hash + every entry_hash to be REACHABLE in the clone.
# Canonical runs ~10 commits/day, so a shallow --depth=50 ≈ 5 days — any
# operator syncing less than weekly would have an unreachable stored_hash,
# triggering a backup-flood (conservative fallback fires on every Tier-1
# file) + degraded changelog detection. A full clone is text-only, lands in
# /tmp, and is deleted at the end — the depth optimization traded correctness
# for a clone-time saving that doesn't matter for an occasional command.
rm -rf /tmp/aios-update-check && git clone --single-branch "$clone_url" /tmp/aios-update-check 2>&1
```

If the SSH clone fails on a non-Windows machine, retry with the HTTPS form (`git@github.com:org/repo` → `https://github.com/org/repo`). Get current HEAD: `git -C /tmp/aios-update-check rev-parse HEAD`. If HEAD matches stored hash → run the **completeness reconcile** (§ Step 6.5 — catches drift even when the tracker says "current") → if also clean, "Your vault infrastructure is current (synced {date})." → clean up → done.

### 1.5. Show changelog context

Read `CHANGELOG.md` from the cloned repo root. If absent, skip silently. Otherwise:

1. Parse `## ` entries (each is `## YYYY-MM-DD — title` followed by `` `hash: {short_hash}` ``).
2. For each entry newest first, check if synced via `git -C /tmp/aios-update-check merge-base --is-ancestor {entry_hash} {stored_hash}` (exit 0 = synced, stop scanning; exit 1 = new, collect; exit 128 = hash unreachable in cloned repo → fall back to content-comparison against local CHANGELOG.md by date header + title).
3. If new entries exist, show them before applying changes — **lead with each entry's "What you can now do" section** (the plain-language capability read — this is the part that actually tells the operator what the new version unlocks; read it back to them, don't make them open the file), then **Action required** (skip Why/FYI for brevity; full details in CHANGELOG.md). Aggregate + deduplicate Action required across all new entries. If an entry predates the convention and has no "What you can now do" section, fall back to its "What changed" / "What you're getting".
4. Execute the action items inline as part of this run — don't list them and wait for the operator to ask. This command IS the implementation arm of CHANGELOG action items.
   - **After applying, close with a one-line-per-capability recap** — *"This update lets you: {do X}, {do Y}, {do Z}."* — so the operator leaves the sync knowing what they gained, not just that files changed. (This is the comprehension-debt guard for the framework's own release channel: an update the operator can't translate into a capability is debt, not a gift.)
5. **Treat every action item as CHECK-THEN-ACT (idempotent).** Each operator's session verifies its OWN current state against the item's precondition, then acts ONLY if the condition holds — and reports "already satisfied, no action" when it doesn't. Many fixes self-resolve or were fixed another way (a teammate who synced independently, a fresh install, a prior run, a manual fix). **Never run a destructive or state-changing action blindly** — a well-written action item carries its own check (e.g. *"run `claude plugin marketplace list`; re-point only if the source is a frozen copy"*). This is what makes the CHANGELOG safe to execute on every operator's machine, regardless of how they got to their current state.

### 2. Find what changed

```bash
git -C /tmp/aios-update-check diff {stored_hash}..HEAD --name-only -- \
  "README.md" "START-HERE.md" "SETUP.md" "TOOLS.md" "CHEATSHEET.md" \
  "CONTRIBUTING.md" "CHANGELOG.md" "CLAUDE.md" "LICENSE" "NOTICE" "FORTRESS.md" ".gitignore" \
  "templates/" "skills/" "hooks/" "mcps/" "plugins/" "agents/" \
  ".claude-plugin/" "vault/.obsidian/"
```

If no Tier 1 files changed in the tracker-diff → **still run the completeness reconcile (§ Step 6.5)** before declaring "current." The tracker-diff (`stored..HEAD`) is an *optimization*, NOT the source of truth — if the stored hash over-claims (e.g. a prior manual edit, or a previous run that advanced the tracker without fully applying), genuinely-missing files are *ancestors* of stored and invisible to this diff. The reconcile is the tracker-independent backstop. Only advance the tracker after the reconcile is clean.

### 2.5. Self-update guard (bootstrap-safe, auto-re-invokes)

**Before processing anything else, content-compare local `plugins/aios/commands/update.md` against the cloned upstream version.** This is the bootstrap-safety check: when `update.md` itself changes, the current run is executing OLD spec — we need the NEW spec to land + re-process everything, without operator action.

```bash
diff -q <(tr -d '\r' < "$HOME/aios/plugins/aios/commands/update.md") <(tr -d '\r' < /tmp/aios-update-check/plugins/aios/commands/update.md)
```

**Case A — Identical (no self-update needed):** local already matches upstream. Skip the rest of this step, proceed to Step 3 with current logic. This is the normal path AND the path taken by an auto-re-invocation (because the first run already applied update.md).

**Case B — Different (update.md was updated upstream):**

1. Apply the replace for `update.md` immediately:
   - Backup local to `vault/04 - backups/aios-update-{date}/update.md` (operator divergence preserved per the standard rule).
   - Overwrite local `plugins/aios/commands/update.md` from upstream.
2. Sync to the plugin pipeline (cache always; marketplace only if it's a GitHub-source install — directory-source reads `~/aios` in place, so its `marketplaces/…` path doesn't exist; both copies are `[ -d ]`-guarded):
   ```bash
   mp="$HOME/.claude/plugins/marketplaces/the-aios/plugins/aios/commands"; [ -d "$mp" ] && cp $HOME/aios/plugins/aios/commands/update.md "$mp/update.md"
   # cache path VERSION-AGNOSTIC — glob the installed version dir (was hard-pinned 0.1.0)
   for d in "$HOME"/.claude/plugins/cache/the-aios/aios/*/commands/; do [ -d "$d" ] && cp $HOME/aios/plugins/aios/commands/update.md "$d"; done
   ```
3. Clean up the temp clone (the re-invoke will re-clone fresh): `rm -rf /tmp/aios-update-check`.
4. **Auto-re-invoke the command** via `Skill(aios:update)`. The re-invocation loads the NEW spec from the plugin cache (just synced) and processes all changed files from a clean state.
5. **Exit the current run** after the re-invocation returns — its work is done by the inner run.

Report to operator at the end: *"`/aios:update` self-updated and re-ran automatically with the new spec — {summary of what the inner run processed}."* No operator action required; the outer run handed off cleanly.

**Why content-compare instead of a state-flag:** the content IS the state. On auto-re-invocation, local update.md is already byte-identical to upstream → Case A fires → no recursion. The pattern is self-terminating by design.

### 3. Apply ALL Tier 1 changes (auto-apply)

For each changed Tier 1 file:

1. **Diff local vs upstream HEAD.** If byte-identical, skip (no work needed — operator already has this version somehow).
2. **Three-way compare to decide on backup** (see § Backup-on-divergence above):
   - **`CHANGELOG.md` → skip this compare entirely: overwrite silently, never back up** (append-only canonical history — never a personalization).
   - Get baseline via `git -C /tmp/aios-update-check show {stored_hash}:{path}`.
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

### 5. Duplicate cleanup — OPT-IN only (`--cleanup`), report-first

**Does NOT run by default.** This was after-migration scaffolding (the 2026-05-23 restructure left duplicates between bundled folders and `custom/` + layer roots). Post-migration the structure is stable and duplicates don't recur, so running a *destructive* (backup-then-remove) scan on every sync is a standing risk (mis-removing an operator file) for a problem that no longer occurs.

- **Default (no flag):** skip entirely.
- **`/aios:update --cleanup`:** run the § Duplicate cleanup scan, but **report-first** — list every suspected duplicate (with the stale-vs-personalized verdict) and **ask the operator to confirm** before removing anything. Never auto-remove on the opt-in path either; the migration is over, so there's no longer a "just clean it" mandate that outweighs a confirm.

(Structural drift — files that *should* be present but aren't, or bundled files that diverged — is now caught by the Step 6.5 completeness reconcile, which is non-destructive. Cleanup is only for the narrow "duplicate of a bundled file sitting in the wrong place" case, which is a migration artifact.)

### 6. Tier 3 advisory flags

For each template that changed in step 3, compare its `## ` heading set to the operator's corresponding filled-in file. List missing sections without taking action. Same for the USER.md template.

### 6.5. Completeness reconcile (tracker-independent backstop) — ALWAYS runs

The tracker-diff (`stored..HEAD`, Step 2) is an optimization that assumes the stored hash honestly reflects what's in the vault. When it doesn't — a hand-edited tracker, or a prior run that advanced the tracker without fully applying — content that shipped *before* the over-claimed stored hash becomes an **ancestor** of stored and is permanently invisible to `diff stored..HEAD`. This step is the safety net: it compares the vault against the cloned canonical HEAD directly, so completeness never depends on the tracker being honest.

```bash
# Compare vault vs the fresh clone (which IS canonical HEAD) across Tier-1
# paths. The clone is already on disk.
#
# `diff -rq` emits TWO line shapes, and they need DIFFERENT handling:
#   "Files A and B differ"      → a framework file diverged           → DRIFT (pull)
#   "Only in <clone>/...: name" → framework file MISSING from vault   → DRIFT (pull)
#   "Only in <vault>/...: name" → operator/company/runtime EXTRA      → IGNORE (not in canonical; nothing to pull)
#
# So: DROP every vault-side "Only in" line wholesale (operator extras —
# custom/, company namespaces, .venv, __pycache__, auth, logs, .session —
# are never framework-drift-to-pull; an upstream DELETION is handled by
# Step 3.4, not here). Then drop runtime noise from what remains.
#
# NOTE the gotcha that bit the first version: `diff` writes "Only in DIR: name"
# with a COLON after the dir, so a `custom/` (slash) exclusion does NOT match
# "…/custom: name". Anchoring the drop on "^Only in $HOME/aios" sidesteps the
# whole slash-vs-colon problem — it filters by SIDE, not by token.
VAULT="$HOME/aios"
for p in README.md START-HERE.md SETUP.md TOOLS.md CHEATSHEET.md CONTRIBUTING.md CHANGELOG.md \
         LICENSE NOTICE FORTRESS.md .gitignore CLAUDE.md \
         templates skills hooks mcps plugins agents .claude-plugin; do
  diff -rq "$VAULT/$p" "/tmp/aios-update-check/$p" 2>/dev/null
done \
  | grep -vF "Only in $VAULT" \
  | grep -vE "/custom(/|: )" \
  | grep -vE "(/|: )(\.venv|__pycache__|node_modules|auth|\.DS_Store)(/|$)" \
  | grep -vE "\.(log|pyc)$|oauth|egg-info|\.session$"
# `/custom(/|: )` drops the operator namespace in BOTH line shapes — a
# `Files …/custom/_index.md … differ` (framework ships a custom/_index.md SEED;
# the operator's customized copy is Tier-2 denylist, never overwritten) AND any
# `Only in …/custom: name`. The vault-side `Only in $VAULT` drop already covers
# company namespaces (<company>/ folders aren't in canonical, so they only ever
# appear as vault-side extras, never as Files-differ).
# Whatever remains = genuine framework drift: differing framework files +
# framework files/dirs present in the clone but missing from the vault.
```

For each genuine framework drift surfaced (a Tier-1 file that **differs**, or a bundled file/dir present in the clone but **missing** from the vault — i.e. a `Files … differ` line or a clone-side `Only in /tmp/aios-update-check/…` line):
- Apply it exactly like a Step-3 Tier-1 file (three-way backup decision, then overwrite/add; CRLF-normalize the compare).
- Sync any recovered command file to the plugin pipeline (marketplace + cache).
- **Report it loudly** — this drift means the tracker was lying; name the files recovered so the operator knows a gap self-healed.

CRLF-normalize when comparing file *contents* (`tr -d '\r'`) per the § Backup-on-divergence CRLF note. **Vault-side `Only in` lines are dropped wholesale** — operator extensions (`custom/`), company namespaces (`<company>/`), and runtime (`.venv/`, `__pycache__/`, `*.log`, OAuth/auth caches, `.session`) live only in the vault, are never in canonical, and are never framework-drift-to-pull. (An upstream *deletion* — a file the vault has that canonical removed — is handled by Step 3.4's flag-don't-delete rule, not here.) Filtering by **side** (`^Only in $VAULT`), not by token, is what makes this robust — `diff` writes `Only in DIR: name` with a colon, so token patterns like `custom/` silently miss `…/custom: name`.

### 7. Advance tracker (only on a clean, fully-applied run) and clean up

**Only write `.aios-update` to the new HEAD hash if BOTH are true:** (a) every Step-3 apply + Step-4 auto-exec succeeded, and (b) the Step-6.5 reconcile came back clean (no remaining framework drift). If either failed, leave the tracker at its current value and report what's incomplete — a stale tracker is recoverable (next run re-pulls); an over-advanced tracker orphans content (the failure we're guarding against). Set `hash={HEAD}` + `synced={today}`.

**Then commit the framework-sync to the vault repo — the atomic apply→advance→commit that leaves the vault clean and pushable.** Without this, the vault sits *applied-but-uncommitted* after every update: un-pushable, and drifting from canonical for anyone who pulls the vault (e.g. a teammate on plain `git pull`). Commit **exactly the Tier-1 paths this run applied** (from Steps 3 + 6.5) plus `.aios-update`, via `aios-commit` — scoped, so the operator's in-flight vault *content* is untouched, and `aios-commit`'s plumbing bypasses the pre-commit guard by design:
```bash
cd ~/aios && ~/aios/hooks/aios-commit -m "sync: framework → {short-HEAD} (via /aios:update)" -- {the Tier-1 paths applied this run} .aios-update
```
If only the tracker advanced (no Tier-1 file changed), commit just `.aios-update`. **Framework-sync commits stay DISTINCT from operator session-work commits** (clean attribution), and `aios-commit --vault` at session-end / `/close-day` stays scoped to vault *content* — never framework infra, which is THIS command's domain. Finally `rm -rf /tmp/aios-update-check`.

> **The tracker is written ONLY by this command, as its final step, after a clean fully-applied run. NEVER hand-edit `.aios-update`** — hand-bumping it past un-pulled commits is exactly what creates permanent orphans (see `antifragile.md` #65).

## Output format

**If current (tracker matches AND reconcile clean):**
> Your vault infrastructure is current (synced {date}, hash {hash}). Completeness reconcile: clean.

**If the tracker said current but the reconcile recovered drift (the self-heal case):**
> Tracker claimed current, but the completeness reconcile found + recovered {N} framework file(s) the tracker-diff missed: {brief list}. Tracker was over-claiming; now reconciled to HEAD. (See antifragile #65 — this is the orphan-recovery backstop working.)

**If updates landed:**
```
## Framework updated to {new_hash} (was {old_hash}, {N} commits)

### What's new (changelog)
{action-item-bearing entries; What changed + Action required only}

### Applied (Tier 1)
{file list — grouped by area, e.g. "Root docs (3): README, CHANGELOG, TOOLS"}

### Backed up (your customizations preserved)
{any divergent file → backup path, e.g. "CLAUDE.md → vault/04 - backups/aios-update-2026-05-25/CLAUDE.md"}

### Scripts re-executed
{e.g. "install-wrappers.sh — wrappers refreshed. Open a new terminal."}

### Recovered by completeness reconcile (if any)
{framework files the tracker-diff missed but the Step-6.5 reconcile pulled — names + why it matters (tracker was over-claiming). Omit if reconcile was clean.}

### Duplicates cleaned (only if `--cleanup` was passed)
{duplicates removed after operator confirmation; omit entirely on the default path}

### Advisory (Tier 3 — template evolution)
{missing sections in declared context, if any}
```

**If network error:**
> Could not reach {team_repo_url}. Check your git access and try again.

## Rules

- **Auto-apply, never ask.** Tier 1 changes are mandatory infra — the command does not present diff approval flows. The operator sees a report of what was done, not a multiple-choice menu.
- **Backup-on-divergence is the safety net.** Operator customizations to Tier 1 files are preserved in `vault/04 - backups/aios-update-{date}/` but are NOT auto-restored. If they want their edits back, they manually merge from the backup.
- **Scripts must run.** A script update that doesn't get executed is half a sync. The wrapper installer is the canonical example — bringing the file without running it leaves the operator's shell on the old code path.
- **Completeness reconcile is the source of truth, not the tracker.** Step 6.5 always runs (even on the "current" path) — it compares the vault against canonical HEAD directly, so a desynced tracker self-heals instead of orphaning content. The tracker advances only on a clean, fully-applied run; it is NEVER hand-edited.
- **This command owns the framework-sync commit (atomic apply→advance→commit).** After a clean apply it commits exactly the Tier-1 files it applied + the tracker, via `aios-commit` (scoped). So the vault is always committed + pushable after an update — never applied-but-uncommitted — and a session-end / `/close-day` `aios-commit --vault` stays scoped to vault *content*, never framework infra. Framework-sync and session-work commits are separate concerns with separate owners.
- **Duplicate cleanup is opt-in (`--cleanup`) + report-first.** Post-migration scaffolding, off the default path. The bundled folder structure (`agents/aios/{bundle}/`, `skills/superpowers/`, etc.) is canonical; `custom/` is for genuinely operator-unique extensions only.
- **Tier 2 (operator content) is sacred.** Never touched. Includes everything under the denylist.
- **Self-update is auto-re-invoking + bootstrap-safe.** When `update.md` itself is in the diff, apply + sync to plugin pipeline FIRST, then auto-re-invoke `Skill(aios:update)`. The inner run loads the new spec, processes everything cleanly, returns. Content-comparison guards against recursion (after self-apply, local matches upstream → Case A fires → no loop). Operator sees one report from the outer run; no manual re-invocation needed. See Step 2.5.
- **Cross-repo cascades.** When CHANGELOG hashes don't exist in the cloned repo (common for operators syncing from a fork or downstream mirror), fall back to content-comparison via date header + title (see Step 1.5).
- **Clean up temp clone.** Always `rm -rf /tmp/aios-update-check` at end, even on error.
- Use `[[wiki-links]]` for project names, context files, ventures mentioned in the report.

## Relationship to /company

`/aios:update` syncs framework infra (commands, templates, hooks, agents, skills, etc.) from the framework upstream tracked in `.aios-update`. `/aios:company` mounts COMPANY venture-context from per-company repos tracked in `USER.md → ## Companies (mounted)`. Different layers, different trackers, never conflated. Running one does not affect the other.
