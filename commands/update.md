---
tags:
  - vault-commands
  - command
  - sync
  - infra
description: >-
  Pull latest shared infrastructure from the team repo (commands, templates,
  settings)
allowed-tools: >-
  mcp__obsidian__*, Bash(git:*), Bash(rm:*), Bash(diff:*), Bash(cat:*),
  Bash(cp:*), Read, Edit, Grep
---

# /aios:update — Team Infrastructure Sync

You are syncing this person's vault infrastructure with the team's source of truth. Read `USER.md` → `## Organization` → **Team repo** to find the repo URL, and `### /aios:update` for command personalizations. If no Organization section exists, tell the user to configure it in USER.md. This covers commands, templates, settings, and docs — NOT personal content.

## Three sync tiers

### Tier 1: Replace (team wins)
Files where the team version is always correct. Overwrite without merge.
- `README.md` (repo root)
- `START-HERE.md` (repo root — first-time orientation)
- `SETUP.md` (repo root)
- `CHEATSHEET.md` (repo root — day-to-day operating index)
- `TOOLS.md` (repo root — human-facing guide to all vault capabilities)
- `CHANGELOG.md` (repo root)
- `LICENSE` (repo root — GPL v2+ canonical text from gnu.org)
- `NOTICE` (repo root — AIOS contributors copyright + grant)
- `FORTRESS.md` (repo root — two-machine operator setup guide)
- `HISTORY-PRE-2026-05-21.md` (repo root — pre-extraction lineage pointer; cosmetic to ship but harmless)
- `.gitignore` (repo root — single source of hygiene for the whole repo, including secret-leak patterns)
- `templates/aios-*` and `templates/*.md` at top level (NEVER overwrite `templates/custom/` — operator-specific extensions)
- `skills/*` EXCEPT `skills/custom/` (full folder replace for bundled skills; preserve operator extensions)
- `hooks/*` EXCEPT `hooks/custom/` (pipeline executor, markitdown converter, claude-identity wrappers)
- `vault/.obsidian/*.json` (Obsidian config baseline — app.json, appearance.json, backlink.json, community-plugins.json, core-plugins.json, daily-notes.json, graph.json, hotkeys.json; NEVER touch `vault/.obsidian/workspace.json` which is per-machine UI state and gitignored)
- `vault/.obsidian/snippets/*` (CSS fixes)
- `mcps/*` EXCEPT `mcps/custom/` (vendored MCP servers — code + README; preserve operator-installed MCPs)
- `agents/aios-*/` (bundled agent definitions — 6 bundles: sales, strategy, finance-legal, engineering, communication, personal — NEVER overwrite `agents/custom/` which holds operator-specific extensions)
- `plugins/*` EXCEPT `plugins/custom/` (self-contained plugins — full folder replace per plugin; preserve operator plugins)
- `commands/aios-*` and `commands/*.md` at top level EXCEPT `commands/custom/` (canonical slash commands; preserve operator commands)

### Tier 2: Suggest (show diff, user picks)
Files the user may have personalized. Show per-section diffs, let them cherry-pick.
- `commands/*` (all command files, repo root)
- `CLAUDE.md` (vault-level instructions)

### Tier 3: Flag (advisory only)
Detect when a template evolved but the user's filled-in version is missing new sections. No files touched — just a heads-up.
- Compare `templates/about_me-template.md` sections → `00 - notes/context/declared/about_me.md`
- Compare `templates/about_business-template.md` sections → `00 - notes/context/declared/about_business.md`
- Compare `templates/working_style-template.md` sections → `00 - notes/context/declared/working_style.md`
- Compare `templates/personal_voice-template.md` sections → `00 - notes/context/declared/personal_voice.md`
- Compare `templates/role-expectations-template.md` sections → `00 - notes/context/declared/role-expectations.md`
- Compare `USER.md` (team template) sections → user's `USER.md` (flag new sections the user doesn't have yet)
- Compare `templates/project-template.md` sections → any project note (general advisory)

## Tracker file

Read `.vault-update` from the repo root.

```
repo={team repo URL from USER.md}
hash={last synced commit hash}
synced={date of last sync}
```

If the file doesn't exist, create it with the repo URL (from USER.md `## Organization`) and set hash to `initial` (forces a full comparison).

## Steps

### 1. Clone and check for changes

Read the team repo URL from `USER.md` → `## Organization` → **Team repo**.

```bash
rm -rf /tmp/vault-update-check && git clone --depth=50 --single-branch {team_repo_url} /tmp/vault-update-check 2>&1
```

**Note:** If SSH fails, try converting to HTTPS format (e.g. `git@github.com:org/repo.git` → `https://github.com/org/repo.git`).

Get current HEAD:
```bash
git -C /tmp/vault-update-check rev-parse HEAD
```

If HEAD matches stored hash → "Your vault infrastructure is current (synced {date})." → clean up → done.

### 1.5. Show changelog context

Read `CHANGELOG.md` from the cloned repo root (`/tmp/vault-update-check/CHANGELOG.md`).

**If the file doesn't exist:** skip silently (backwards compatible with repos that don't have a changelog yet).

**If the file exists:**
1. Parse all `## ` entries (each entry starts with `## YYYY-MM-DD — title`)
2. Extract the `hash:` line from each entry (format: `` `hash: {short_hash}` ``)
3. For each entry (newest first), check if it's already synced:
   ```bash
   git -C /tmp/vault-update-check merge-base --is-ancestor {entry_hash} {stored_hash}
   ```
   - Exit code 0 → entry was already synced → stop scanning (all older entries are also synced)
   - Exit code 1 → entry is new → collect it
   - **Exit code 128 (hash not found in cloned repo)** → cross-repo case (e.g., CHANGELOG references team-vault hashes but the user syncs from `chuycepeda/aios`). The byte-identical-CHANGELOG invariant means the hash exists in another repo but not the one being synced. **Fall back to local-CHANGELOG content comparison:**
     - Read the user's LOCAL `CHANGELOG.md` (in the vault, not the clone)
     - Search for the fetched entry's date header (e.g., `## 2026-05-11 —`) and full title line
     - If the entry exists verbatim in local → already synced → stop scanning
     - If absent or different → new entry → collect it
     - This makes the comparison content-based rather than hash-based when the hash is unreachable, preserving correctness across cross-repo cascades.
4. If there are new entries, display them before any diffs:

```
## What's new since your last sync ({stored_date})

### {entry title}

**What changed:**
{bullet list from entry}

**Action required:**
{action items from entry}

---
{repeat for each new entry}

Proceeding with file-by-file review...
```

Show only the **What changed** and **Action required** sections from each entry — skip **Why** and **FYI** for brevity during sync (the full details are in CHANGELOG.md in the team repo).

After showing changelog entries, copy the full CHANGELOG.md into the vault:
```bash
cp /tmp/vault-update-check/CHANGELOG.md ~/obsidian/vault/06\ -\ backups/CHANGELOG.md
```
This makes the changelog visible inside Obsidian for reference.

If any changelog entries have **Action required** items, collect them from ALL new entries (not just the latest — a teammate who hasn't synced in 2 weeks may have 3+ entries worth of actions). Aggregate and **deduplicate** — if multiple entries say "migrate project notes to Current State table," list it once.

The action items are written as instructions for YOU (Claude) to execute — not for the user to do manually. Present them as a numbered list, then execute them:

```
## Action items from changelog

I found {N} action items across {M} changelog entries since your last sync:

1. {action — what Claude will do}
2. {action — what Claude will do}
3. {action — what Claude will do}

I'll run through these now. Say "go" to execute all, or pick specific numbers to skip.
```

After the user says "go" (or picks), **execute each action item directly** — read files, migrate notes, run commands, check configs. Don't just list what needs to happen; do it. This is the Proactive Execution principle applied to vault-update.

### 2. Find what changed

```bash
git -C /tmp/vault-update-check diff {stored_hash}..HEAD --name-only -- \
  "README.md" \
  "SETUP.md" \
  "TOOLS.md" \
  "CHANGELOG.md" \
  "CLAUDE.md" \
  ".gitignore" \
  "templates/" \
  "skills/" \
  "hooks/" \
  "vault/.obsidian/snippets/" \
  "mcps/" \
  "plugins/" \
  "agents/" \
  "commands/"
```

**Note:** `README.md` and `SETUP.md` live at the repo root (not inside `vault/`). Adjust read/write paths accordingly — these are not Obsidian notes, use `Read`/`Write` tools, not `mcp__obsidian__*`.

If no files changed in these paths → update hash → done.

If files changed → categorize each into its tier and continue.

### 3. Process Tier 1 (Replace)

For each changed Tier 1 file:
1. Read the remote version from `/tmp/vault-update-check/{path}` (only `vault/`-relative paths get the `vault/` prefix; root paths like `README.md`, `SETUP.md`, `hooks/`, `mcps/`, `plugins/`, `skills/` sit at the clone root).
2. Show a brief summary: "{file}: updated ({one-line description of change})"
3. After showing all Tier 1 changes, ask: "Apply Tier 1 updates? (These are reference files — templates, docs, graph settings.)"
4. If confirmed: overwrite using the right tool for the path:
   - `.md` files **inside** `vault/` → `mcp__obsidian__write_note` (keeps the Obsidian graph consistent)
   - `.md` files **outside** `vault/` (root-level: `README.md`, `SETUP.md`, `TOOLS.md`, `CHANGELOG.md`, anything under `hooks/`, `mcps/`, `plugins/`, `skills/`) → `Bash cp` or the `Write` tool
   - All other extensions (`.json`, `.css`, `.py`, `.sh`, `.plist`, `.yml`, etc., wherever they live) → `Bash cp` (preserves file mode — load-bearing for executable scripts under `hooks/`)
   - New subdirectories that don't exist locally (e.g. a freshly added `hooks/{subdir}/`) → `mkdir -p` first, then `cp` each file inside

### 4. Process Tier 2 (Suggest)

**Content-level comparison.** The user's vault and the team repo are separate repos — there's no git relationship after setup. So don't assume the team version is always "more complete." The user may have customized commands with content the team repo doesn't have. Compare content, not git history. For each changed Tier 2 file:

1. Read both the **remote version** from `/tmp/vault-update-check/vault/{path}` and the **local version** from the vault
2. Compare section by section (split on `## ` headings)
3. Classify each difference:
   - **New section from team** (exists in remote, not in local): "NEW section added: `## {heading}`" — show the full section content
   - **Modified section** (exists in both, content differs): "CHANGED: `## {heading}`" — show a clear before/after diff of the specific lines that changed
   - **User-only section** (exists in local, not in team): Don't auto-keep. Ask: "YOUR section `## {heading}` — not in team repo. (1) Keep it — it's your personalization, (2) Delete it — it's outdated, (3) Show me the content — I'll decide." This prevents stale or accidentally copied sections from persisting forever.
   - **Possible rename** (user has a section the team doesn't, AND the team has a section the user doesn't, AND they cover similar topics): Flag the likely rename: "Team may have renamed `## {old heading}` → `## {new heading}`. (1) Replace with team's version, (2) Keep yours, (3) Show me both." Detect by comparing section topics — e.g., "Book / study progress" and "Growth routines update" both relate to evening learning.
   - **User section is richer** (both exist, but user's has extra content): "⚠️ Your `## {heading}` has content the team version doesn't. Applying the team version would REMOVE your additions. Showing both — you pick."
   - **Unchanged section**: skip silently

**Safety rule:** If a section exists in both versions but the user's version is longer or has content the team's doesn't, **always warn before replacing.** The two repos have no git relationship — after setup the user pushes to their own remote, never to the team repo. So richer local content = user personalization, not a merge conflict. Never silently overwrite a richer user section with a shorter team one.

4. Present each file's changes as a numbered list:
```
### commands/today.md — 2 changes

1. NEW section: `## Meeting Notes Routing`
   {show content}

2. CHANGED: `## Steps` — line 14
   Before: "Read calendar events for today"
   After:  "Read calendar events for today and tomorrow"

Your sections not in team repo:
- `## Rhythm` — (1) Keep (personalization), (2) Delete (outdated), (3) Show content

Apply changes to today.md? [all / pick numbers / skip]
```

5. Based on user response:
   - **all**: apply every new/changed section
   - **pick numbers**: apply only selected changes
   - **skip**: leave file untouched

6. To apply a **new section**: use `mcp__obsidian__patch_note` to insert the section at the appropriate position (after the preceding section heading from the remote version)
7. To apply a **changed section**: use `mcp__obsidian__patch_note` with the local section content as `oldString` and remote section content as `newString`
8. After applying, if the command file changed, sync to plugin pipeline:
   ```bash
   cp "commands/{file}" ~/.claude/plugins/marketplaces/the-aios/plugins/aios/commands/{file}
   cp "commands/{file}" ~/.claude/plugins/cache/the-aios/aios/0.1.0/commands/{file}
   ```

### 5. Process Tier 3 (Flag)

For each template that changed in Tier 1:
1. Extract `## ` headings from the updated template
2. Read the corresponding local content file (e.g., `about_me.md` for `about_me-template.md`)
3. If the content file is missing headings that exist in the template:
   ```
   ### Advisory: template evolved

   `about_me-template.md` now has these sections your `about_me.md` doesn't:
   - `## My intent layer` — tradeoff rules, decision boundaries, communication rules

   No action taken. Consider adding these sections when you have time.
   ```
4. If all template sections are present in the content file: skip silently

### 6. Sync plugin cache, update tracker, and clean up

**After all Tier 2 command changes are applied**, ensure the full plugin pipeline is current:
```bash
# Sync ALL command files to both plugin locations (not just changed ones — ensures consistency)
cp ~/obsidian/commands/*.md ~/.claude/plugins/marketplaces/the-aios/plugins/aios/commands/
cp ~/obsidian/commands/*.md ~/.claude/plugins/cache/the-aios/aios/0.1.0/commands/
```

Update `.vault-update` (repo root) with new HEAD hash and today's date.

```bash
rm -rf /tmp/vault-update-check
```

## Output format

**If current:**
> Your vault infrastructure is current (synced 2026-03-07, hash abc1234).

**If updates available:**
```
## Vault infrastructure has updates

**Last synced:** {date} ({N} commits behind)

### What's new (changelog)
{Relevant changelog entries — What changed + Action required only. If no CHANGELOG.md exists, skip this section.}

### Tier 1 — Replace (team reference files)
{list of files with one-line descriptions}

### Tier 2 — Suggest (your customizable files)
{per-file section diffs with apply options}

### Tier 3 — Advisory (template evolution)
{flagged missing sections, if any}
```

**If network error:**
> Could not reach {team_repo_url}. Check your git access and try again.

## Rules

- **Never touch personal content.** Declared context (except about_business, handled by `/company`), observed context, projects, calendar, ideas, logs — all off limits.
- **Tier 2 is always opt-in.** Never auto-apply command or CLAUDE.md changes. Always show the diff first and let the user pick.
- **Preserve personalizations.** Sections that exist locally but not in the team repo are the user's customizations. Flag them as "keeping" but never delete.
- **Sync the plugin pipeline.** When a command file is updated, always copy to marketplace source AND plugin cache.
- **Clean up temp clone.** Always `rm -rf /tmp/vault-update-check` at the end, even on error.
- **One command at a time for Tier 2.** Don't batch all command diffs into one wall of text. Show one file, get confirmation, then the next.
- **Self-update detection.** Before processing any Tier 2 files, check if `vault-update.md` itself changed. If it did: (1) apply the update to all 3 locations (commands/ source, marketplace, cache), (2) tell the user: "vault-update just updated itself. Re-running with the new version now." (3) Stop processing and re-invoke `/aios:update`. This ensures the new logic handles all other files. If it didn't change, proceed normally.
- **Protect user personalizations.** The user's vault and team repo are separate repos with no git relationship. If the user's section is richer than the team's, warn before replacing — that's their work, not a stale copy.
- **New command files.** If the team repo has a command file that doesn't exist locally, treat it as Tier 1 (just add it) since there's nothing to merge.
- **Deleted command files.** If the team repo removed a command, flag it: "Team removed `{command}.md`. Delete your local copy too? [yes/keep]"
- Use [[wiki-links]] for all project names, context files, and ventures mentioned.

## Relationship to /company

These two commands are complementary:
- **/company** — mounts and syncs company narrative, positioning, branding, design.md, CLAUDE.md operating manual, and business context. Multi-substrate, multi-company. Run before creating company content.
- **vault-update** — syncs infrastructure: commands, templates, settings, docs. Run when the team ships tooling improvements.

They share the same repo (from USER.md `## Organization`) but track separate hashes and touch different files. Running one does not affect the other's tracker.
