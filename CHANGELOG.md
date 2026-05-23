# Changelog

> What changed in The AIOS framework, why, and what to do about it.
> Entries are newest-first. Each entry is tied to a git commit hash so `/aios:update` can show you only what's new since your last sync.
>
> **This is the canonical CHANGELOG for The AIOS.** The framework lives at [The-AIOS/aios](https://github.com/The-AIOS/aios). It is built from infrastructure that evolved in [chuycepeda/obsidian](https://github.com/chuycepeda/obsidian) from March → May 2026 (pre-extraction history preserved there).

---

## 2026-05-23 — Migration playbook: existing operators move from old framework to The-AIOS/aios

`hash: 9dd9ba1`

> **Read this entry top-to-bottom before executing anything.** It is the single migration playbook for any operator on the pre-extraction framework structure (`chuycepeda/aios` template or `sovrahq/internal-vault` team repo, both frozen at hashes ≤ 2026-05-21). The framework was extracted to a public canonical at `github.com/The-AIOS/aios`. This entry walks you through the full migration in **dependency-sorted phases (Phase 0 → Phase 9 + LAST)**. Later phases assume earlier phases succeeded.
>
> **One non-negotiable rule, baked into Phase 0:** the operator's content is sacred. `USER.md`, `INTENT.md`, `SARAH.md`, everything under `vault/`, and every `{layer}/custom/` extension MUST survive the migration intact. The migration replaces *framework* infrastructure (spec files, bundled agents/skills/hooks/mcps/templates, plugin manifests, tracker file). It must NOT touch operator content. Phase 0 takes a safety snapshot. Every later phase respects the sacred-files denylist. If a step looks like it might overwrite operator content, **stop and ask** — never silently proceed.

### State

The pre-extraction framework structure (`chuycepeda/aios` + `sovrahq/internal-vault`, three-repo topology) is frozen. Going forward the canonical infrastructure lives in three public repos under [The-AIOS](https://github.com/The-AIOS):

- **`The-AIOS/aios`** — the framework (commands, agents, skills, hooks, MCPs, templates, 7 root docs)
- **`The-AIOS/company-template`** — the venture-context scaffold used by `/aios:company --create`
- **`The-AIOS/.github`** — org-level community files (CONTRIBUTING, SECURITY, PR + issue templates)

For an existing operator, this means **infrastructure has moved** but **content stays put**. The migration's job is to repoint the framework-half (commands, tracker, plugin namespace, cache) at the new canonical, and to leave the operator-half (vault, declared context, observed context, projects, USER.md, INTENT.md) untouched.

**Cosmetic-but-load-bearing changes** that landed at extraction time and now propagate to every operator:
- Tracker file renamed: `.vault-update` → `.aios-update`
- Plugin namespace renamed: `vault-commands:*` → `aios:*` (so `/vault-commands:today` → `/aios:today`)
- Plugin location: top-level `commands/` → `plugins/aios/commands/` (canonical Claude Code convention)
- Path canonical: `~/aios/` is the framework-expected install path (operators with vaults at `~/obsidian/` add a symlink, sarah on Mac mini clones to `~/aios/` directly)
- `vault/.obsidian/` and `.claude/` are now fully operator-personal — gitignored, never overwritten by `/aios:update`
- `~/Downloads/` style universal-folder paths now allowed in shared infra (CI validator narrowing); `~/obsidian/`, `~/cowork/`, `~/code/the-aios/` flagged (operator-specific)
- Spawn wrappers now inject `--model claude-opus-4-7[1m]` by default (override via `$CLAUDE_MODEL`); `spawn-kill` pgrep tolerates injected flags + `pgrep -xq` exact-match avoids CursorUIViewService false-positive
- New: `/aios:company --create | --mount | --sync` for multi-venture context (the company-template flow)
- New: `agents/onboarding-aios.md` (framework orientation) + per-company `onboarding-{company}.md` (HR-Day-1 companion for mounters)
- New: `/aios:cold-start-interview` ritualizes Day-0 setup; `/today` first-run hands off to `onboarding-aios` automatically when about_me.md still has placeholders
- New: CI gates on framework repo (6-job) and venture-context repos (5-job: structure, frontmatter, credentials, wiki-links, personalization)

### Ask + Act — by phase

Each phase is **State → Ask → Act**. Phases are short on purpose — easier to verify between, easier to recover if interrupted.

**Execution order (load-bearing — follow this sequence, not the phase numbers):**

The phase numbers below are logical groupings (e.g., "Phase 3 = wrappers"). The actual execution order has a few inversions because some phases depend on the framework cascade (Phase 5) having landed canonical files first:

```
Phase 0  (Safety snapshot — MANDATORY first)
  ↓
Phase 1  (Path canonical: ~/aios symlink)
  ↓
Phase 2  (Tracker rename + repoint at The-AIOS/aios)
  ↓
Phase 2.5 (Vault structure normalization — moves operator extensions to {layer}/custom/, deletes legacy framework dirs)
  ↓
Phase 5  (Framework cascade via /aios:update — brings canonical files into the vault)
  ↓
Phase 3  (Spawn wrappers — re-install using the NOW-canonical install-wrappers.sh from Phase 5)
  ↓
Phase 4  (Plugin cache invalidation — uses the NOW-canonical aios@the-aios plugin source)
  ↓
Phase 6  (USER.md schema migration: ## Organization → ## Companies (mounted))
  ↓
Phase 7  (Vault scaffold restoration — empty subfolder placeholders)
  ↓
Phase 8  (Auto-memory namespace + path cleanup)
  ↓
Phase 9  (Discovery surface awareness — informational)
  ↓
LAST     (Restart Claude Code for plugin daemon reload)
```

The Claude session executing this playbook MUST follow the execution-order arrows, not the phase-number sequence. If you skip the ordering (e.g., run Phase 3 wrappers before Phase 5 framework cascade), you'll install the OLD wrapper script and have to reinstall after the cascade overwrites it — wasted work, possible confusion.

---

#### Phase 0 — Safety snapshot (MANDATORY, do this first)

**State:** The operator's current vault has content that must survive. Take an explicit snapshot before any structural change so recovery is one git command away.

**Ask:**
> *"Before I touch anything, I'm going to tag the current state of your vault as `pre-aios-migration-{YYYY-MM-DD}` and verify your `USER.md`, `INTENT.md`, `SARAH.md` (if present), and `vault/` are all tracked + committed. If anything's uncommitted, I'll surface it and stop until you decide. OK to proceed?"*

**Act:**

```bash
# Inside the operator's vault root (~/obsidian/ or ~/aios/ — wherever your local clone lives)
cd ~/obsidian 2>/dev/null || cd ~/aios

# 1. Verify nothing is uncommitted
DIRTY=$(git status --porcelain | wc -l)
if [ "$DIRTY" -gt 0 ]; then
  echo "⚠️  Uncommitted changes found. Surfacing before continuing:"
  git status --short
  echo ""
  echo "STOP — commit or stash these BEFORE migration. We will not silently overwrite."
  exit 1
fi

# 2. Take the safety tag
TAG="pre-aios-migration-$(date +%Y-%m-%d)"
git tag "$TAG"
echo "✓ Safety tag: $TAG (recover with: git reset --hard $TAG)"

# 3. Confirm sacred files are present + tracked
for f in USER.md INTENT.md CLAUDE.md; do
  test -f "$f" && git ls-files --error-unmatch "$f" >/dev/null 2>&1 \
    && echo "✓ $f tracked" \
    || echo "⚠️  $f not tracked (operator-personal but missing from git — verify before continuing)"
done
test -f SARAH.md && echo "✓ SARAH.md tracked (multi-machine operator setup detected)"

# 4. Confirm vault/ has content
VAULT_FILES=$(find "vault" -type f 2>/dev/null | wc -l)
echo "✓ vault/ contains $VAULT_FILES files (will be preserved as-is)"
```

If any step surfaces a warning, **stop and resolve before continuing**. Operator data integrity is the gating concern for the entire migration.

---

#### Phase 1 — Path canonical: `~/aios` symlink

**State:** The framework references `~/aios/` everywhere. Operators on the old structure typically have their vault at `~/obsidian/` (chuy's pattern) or `~/aios/` directly (more common for newer ops). If `~/aios` doesn't resolve, every later phase's `~/aios/...` reference fails with "no such directory."

**Ask:**
> *"I see your vault is at `{detected-path}`. I need `~/aios/` to resolve so the rest of the migration can use the canonical path. {If path is already ~/aios → silent pass}. {Else → I'll create a symlink `~/aios → {detected-path}`. Non-destructive, reversible, zero risk to your Obsidian app workspace state. OK?}"*

**Act:**

```bash
# Detect current vault path — check the common locations
VAULT_PATH=""
[ -e "$HOME/aios/vault/01 - calendar" ] && VAULT_PATH="$HOME/aios"
[ -z "$VAULT_PATH" ] && [ -e "$HOME/obsidian/vault/01 - calendar" ] && VAULT_PATH="$HOME/obsidian"

# Fallback: scan common alternative locations
[ -z "$VAULT_PATH" ] && for try in "$HOME/code/internal-vault" "$HOME/internal-vault" "$HOME/code/aios" "$HOME/Documents/aios" "$HOME/Documents/obsidian"; do
  [ -e "$try/vault/01 - calendar" ] && VAULT_PATH="$try" && break
done

# If still not found, ASK the operator for the path
if [ -z "$VAULT_PATH" ]; then
  echo "⚠️  Could not detect your vault root automatically."
  echo "    Tried: ~/aios, ~/obsidian, ~/code/internal-vault, ~/internal-vault, ~/code/aios, ~/Documents/aios, ~/Documents/obsidian"
  echo "    Stop here. Tell Claude where your vault lives, then re-run this phase pointing at the right path."
  exit 1
fi

echo "✓ Detected vault root: $VAULT_PATH"

# If already at ~/aios → silent pass
[ "$VAULT_PATH" = "$HOME/aios" ] && echo "✓ ~/aios already resolves" && exit 0

# Otherwise create the symlink
ln -s "$VAULT_PATH" "$HOME/aios"
echo "✓ ~/aios → $VAULT_PATH symlink created"

# Verify
test -e "$HOME/aios/vault/01 - calendar" && echo "✓ ~/aios resolves to vault content"
```

(Windows users: see SETUP.md → "Path portability" for the `mklink /J` directory junction equivalent.)

---

#### Phase 2 — Tracker rename + repoint: `.vault-update` → `.aios-update`

**State:** The OLD framework uses `.vault-update` at the vault repo root, with `repo=` pointing at the old team repo (typically `git@github.com:sovrahq/internal-vault.git` for team members or `git@github.com:chuycepeda/aios.git` for solo operators). The NEW framework reads `.aios-update` and expects `repo=git@github.com:The-AIOS/aios.git`.

**Ask:**
> *"Renaming the tracker file from `.vault-update` to `.aios-update` and repointing the `repo=` field at the public canonical `git@github.com:The-AIOS/aios.git`. The hash field stays at `initial` so the next `/aios:update` does a full comparison — that's intentional, it lets the new gate verify your local matches canonical even though most files do (since both repos descend from the same lineage). OK?"*

**Act:**

```bash
cd "$HOME/aios"

# Rename + repoint
if [ -f ".vault-update" ]; then
  mv .vault-update .aios-update
  echo "✓ .vault-update → .aios-update"
fi

# Rewrite the repo URL + reset hash to 'initial'
cat > .aios-update << EOF
repo=git@github.com:The-AIOS/aios.git
hash=initial
synced=$(date +%Y-%m-%d)
EOF
echo "✓ .aios-update repointed at The-AIOS/aios"
cat .aios-update
```

**Verification:**
```bash
grep -q "github.com:The-AIOS/aios" .aios-update && echo "✓ tracker repointed"
test ! -f .vault-update && echo "✓ old tracker gone"
```

---

#### Phase 2.5 — Vault structure normalization (CRITICAL — preserves operator extensions)

**State:** Pre-extraction framework had infrastructure folders **inside** `vault/` with numeric prefixes:

| Old location (legacy) | New location (canonical) | What's there |
|---|---|---|
| `commands/` (top-level) | `plugins/aios/commands/` | slash command specs |
| `vault/02 - templates/` | `templates/` (top-level) | reference templates |
| `vault/06 - agents/` | `agents/` (top-level) | task agents |
| `vault/03 - assets/` | `vault/02 - assets/` (renumbered) | operator assets |
| `vault/04 - export/` | `vault/03 - export/` (renumbered) | exported artifacts |
| `vault/05 - logs/` (if existed) | `vault/00 - notes/logs/` | activity logs + snapshots |

Phase 5 (`/aios:update`) lands the new locations but does NOT delete the old ones. Without explicit handling, the operator's working tree ends up with BOTH layouts in parallel — confused, possibly broken (commands at `commands/` collide with `plugins/aios/commands/`), AND any operator extensions (custom agents, custom templates) at old locations would be orphaned.

**Crucial: operator extensions get preserved**. The operator may have added their own agents at `vault/06 - agents/my-agent.md` or templates at `vault/02 - templates/my-template.md`. These must move into `{layer}/custom/` at the new top-level — never just deleted.

**Ask:**
> *"Your vault has the legacy framework layout (commands at top-level, agents + templates inside vault/, assets/export numbered differently). Phase 5 will land the new canonical layout at the new locations, but the OLD locations stay unless we clean them up. Before Phase 5 runs:*
>
> *1. I'll scan the OLD locations for any files that look like operator extensions (not framework canonicals).*
> *2. I'll MOVE those to the new canonical extension paths (`agents/custom/`, `templates/custom/`, etc.).*
> *3. The OLD folders themselves get deleted — Phase 5's `/aios:update` will populate the new top-level locations with the canonical content.*
>
> *Phase 0's safety tag is your recovery if anything looks wrong. Want me to walk through what I'd move first (show diff) before applying? (yes / just-do-it-the-defaults-are-safe)"*

**Act:**

```bash
cd "$HOME/aios"

# --- A. Inventory operator extensions in legacy locations ---

# Agents — anything in vault/06 - agents/ that's NOT a framework canonical (the bundled aios-*
# agents). Operator extensions get moved to agents/custom/. Framework canonicals get deleted
# (Phase 5 will bring the new versions in their new home).
LEGACY_AGENTS="vault/06 - agents"
LEGACY_TEMPLATES="vault/02 - templates"

# Helper: is this a framework canonical (ship in The-AIOS/aios's bundled set)?
#   We define "canonical" generously — any agent whose filename starts with the bundle prefixes
#   we know shipped in the OLD framework. Anything else = operator extension.
#   Concretely the old framework's canonical agents lived at vault/06 - agents/ and the file
#   names were things like sales-lead-hunter.md, content-writer.md, etc. We treat ALL of these
#   as candidates for preservation since we can't auto-distinguish operator additions reliably.
#   When in doubt → preserve. Operator can clean up extras post-migration.

mkdir -p agents/custom templates/custom

if [ -d "$LEGACY_AGENTS" ]; then
  echo "Found legacy agents at: $LEGACY_AGENTS"
  # Move ALL .md files (preserve generously; operator cleans up later if redundant)
  find "$LEGACY_AGENTS" -maxdepth 1 -name "*.md" -type f | while read f; do
    base=$(basename "$f")
    mv "$f" "agents/custom/$base"
    echo "  → agents/custom/$base"
  done
  # Move any subfolders (custom bundles, my-agents/, etc.)
  # Use `find` instead of bash glob `for sub in "$DIR"/*/` — the bash glob errors in
  # zsh's default nomatch behavior when the directory has no subfolders ("no matches found").
  # find -mindepth 1 -maxdepth 1 -type d is portable across bash + zsh + dash.
  find "$LEGACY_AGENTS" -mindepth 1 -maxdepth 1 -type d | while read sub; do
    name=$(basename "$sub")
    mv "$sub" "agents/custom/$name"
    echo "  → agents/custom/$name/"
  done
  rmdir "$LEGACY_AGENTS" 2>/dev/null && echo "✓ $LEGACY_AGENTS removed (empty after move)"
fi

if [ -d "$LEGACY_TEMPLATES" ]; then
  echo "Found legacy templates at: $LEGACY_TEMPLATES"
  find "$LEGACY_TEMPLATES" -maxdepth 1 -name "*.md" -type f | while read f; do
    base=$(basename "$f")
    mv "$f" "templates/custom/$base"
    echo "  → templates/custom/$base"
  done
  find "$LEGACY_TEMPLATES" -mindepth 1 -maxdepth 1 -type d | while read sub; do
    name=$(basename "$sub")
    mv "$sub" "templates/custom/$name"
    echo "  → templates/custom/$name/"
  done
  rmdir "$LEGACY_TEMPLATES" 2>/dev/null && echo "✓ $LEGACY_TEMPLATES removed"
fi

# --- B. Delete the top-level legacy `commands/` directory ---
# All command specs are now under plugins/aios/commands/. The OLD top-level commands/ folder
# has nothing the operator should preserve — these are framework canonicals only, and the
# new locations come via /aios:update.
if [ -d "commands" ] && [ ! -d "plugins/aios/commands" ]; then
  echo "Removing legacy top-level commands/ (will be replaced via /aios:update)"
  rm -rf commands
  echo "✓ legacy commands/ removed"
fi

# --- C. Renumber vault asset + export folders ---
# vault/03 - assets/ → vault/02 - assets/  (move only if no destination yet)
if [ -d "vault/03 - assets" ] && [ ! -d "vault/02 - assets" ]; then
  mv "vault/03 - assets" "vault/02 - assets"
  echo "✓ vault/03 - assets/ → vault/02 - assets/"
fi
# vault/04 - export/ → vault/03 - export/
if [ -d "vault/04 - export" ] && [ ! -d "vault/03 - export" ]; then
  mv "vault/04 - export" "vault/03 - export"
  echo "✓ vault/04 - export/ → vault/03 - export/"
fi
# vault/05 - logs/ → vault/00 - notes/logs/
if [ -d "vault/05 - logs" ]; then
  mkdir -p "vault/00 - notes/logs"
  mv "vault/05 - logs"/* "vault/00 - notes/logs/" 2>/dev/null || true
  rmdir "vault/05 - logs" 2>/dev/null && echo "✓ vault/05 - logs/ → vault/00 - notes/logs/"
fi
```

**Important — what survives + what gets discarded:**

- ✅ **Operator agents** (any `.md` files in `vault/06 - agents/`) → moved to `agents/custom/`
- ✅ **Operator templates** (in `vault/02 - templates/`) → moved to `templates/custom/`
- ✅ **Operator assets + exports** — renumbered folders, content intact
- ✅ **Operator logs** in `vault/05 - logs/` → folded into `vault/00 - notes/logs/`
- ❌ **Legacy framework agents/templates** at OLD locations — got moved to `custom/` defensively. After Phase 5 lands the canonical new framework agents (which include the originals updated), operator can compare `agents/custom/{old-name}.md` vs `agents/aios-*/{updated-name}.md` and delete the redundant `custom/` copy if it's a duplicate.
- ❌ **Top-level `commands/`** — deleted unconditionally (operator never edits these; they're framework canonical, now at `plugins/aios/commands/`)

If at any point this phase looks risky to apply mass-wise, the operator can also do it incrementally per directory. Phase 0's safety tag is the fallback.

**Verification:**
```bash
test ! -d "vault/02 - templates" && echo "✓ legacy templates dir gone"
test ! -d "vault/06 - agents" && echo "✓ legacy agents dir gone"
test ! -d "commands" && echo "✓ legacy top-level commands/ gone"
test -d "agents/custom" && echo "✓ agents/custom/ exists (preserved operator extensions if any)"
test -d "templates/custom" && echo "✓ templates/custom/ exists"
```

---

#### Phase 3 — Spawn wrappers + universal hooks (re-install)

> **Important ordering note:** Phase 3 runs AFTER Phase 5 brings the canonical `hooks/claude-identity/install-wrappers.sh` into the operator's vault. Running it before Phase 5 would install the OLD wrapper script. The migration's Phase 5 → Phase 3 ordering ensures the operator installs the canonical wrapper exactly once.

**State:** Pre-extraction wrappers shipped under a different path + lacked the `--model` flag injection, the `pgrep -xq` IDE-detection fix, and the `spawn-kill` pgrep-tolerance update. The current canonical installer is `hooks/claude-identity/install-wrappers.sh` — idempotent, timestamped-backup, auto-rollback on failure.

**Ask:**
> *"Re-running the wrapper installer at `~/aios/hooks/claude-identity/install-wrappers.sh`. This is idempotent: it backs up your `~/.zshrc` (timestamped) and reinstalls the canonical wrapper block. After it lands, your `spawn` will inject `--model claude-opus-4-7[1m]` by default; `spawn-kill` will match cmdlines with `--model`; IDE detection will use `pgrep -xq` (no Cursor false-positives). OK to run?"*

**Act:**

```bash
bash "$HOME/aios/hooks/claude-identity/install-wrappers.sh"

# Verify in interactive zsh (wrappers load on shell startup)
zsh -i -c 'type spawn spawn-kill _claude_with_respawn 2>&1 | head -3'
```

**Universal event hooks** (UserPromptSubmit, etc.) are wired via `~/aios/.claude/settings.json`. If your `.claude/settings.json` was committed in the old framework, it's now operator-personal (per the new `.claude/` denylist). Verify the hooks paths still resolve at `~/aios/hooks/...`. The installer doesn't touch `.claude/settings.json` — that's operator-personal.

---

#### Phase 4 — Plugin cache invalidation: `vault-commands@local` → `aios@the-aios`

**State:** Pre-extraction, slash commands shipped under the `vault-commands:` plugin namespace (e.g., `/vault-commands:today`, `/vault-commands:close-day`). Post-extraction, the namespace is `aios:` (e.g., `/aios:today`). Your local Claude Code cache at `~/.claude/plugins/` may still hold the OLD `vault-commands` plugin source — at best it's dead weight, at worst it causes namespace collisions.

**Ask:**
> *"I need to (a) uninstall the legacy `vault-commands@local` plugin if it's still registered, (b) confirm the new `aios@the-aios` plugin is registered. The new plugin pulls from `The-AIOS/aios/plugins/aios/`. OK?"*

**Act:**

```bash
# Inspect current state
claude plugin list 2>&1 | grep -E "vault-commands|aios" || true

# Remove legacy plugin if present (operator-confirm before destructive op)
claude plugin uninstall vault-commands@local 2>/dev/null || true

# Install / refresh the new plugin from the canonical marketplace
claude plugin install aios@the-aios

# Verify
claude plugin list | grep aios@the-aios && echo "✓ aios plugin registered"
```

**Restart Claude Code AFTER this phase** if the plugin source rotation hasn't taken effect (the plugin daemon caches plugin source paths). The /aios:update spec calls this out as a hard precondition — restart-required steps go LAST in any single playbook run; here we tolerate it mid-flow only because subsequent phases edit framework files, not Claude Code's runtime.

---

#### Phase 5 — Framework infra cascade (`/aios:update` first real run)

**State:** With the tracker repointed (Phase 2) and the plugin re-installed (Phase 4), the standard `/aios:update` flow now works. It will:
1. Clone `The-AIOS/aios` to `/tmp/`
2. Diff against your local framework files (commands, agents/aios-*/, skills/, hooks/, mcps/, plugins/aios/, templates/)
3. Apply Tier 1 (Replace) changes — bundled infra files
4. Surface Tier 2 (Suggest) — `commands/*.md` + `CLAUDE.md`, your call per-file
5. Surface Tier 3 (Advisory) — template evolution flags

**The operator-personal denylist is hard-enforced**: `USER.md`, `INTENT.md`, `SARAH.md`, anything under `vault/00 - notes/{context,projects,ideas,reflections,logs}/`, anything under `vault/01 - calendar/`, `vault/02 - assets/`, `vault/03 - export/`, `vault/04 - backups/`, all `{layer}/custom/` folders, all `{layer}/<company>/` folders, `.aios-update`, `.claude/` (entire folder), `vault/.obsidian/` (entire folder) — `/aios:update` MUST refuse to write to any of these. If it tries, that's a bug. Surface it; don't proceed.

**Ask:**
> *"Running `/aios:update` for the first time against The-AIOS/aios. This will surface what's changed across commands, agents, skills, hooks, MCPs, templates, and bundled plugins. I'll walk you through each tier; you decide what to apply for Tier 2 (your customizable files)."*

**Act:**

```bash
# Hand off to the canonical /aios:update flow
```

Then run `/aios:update` as the natural next step. Walk through the Tier 1 / Tier 2 / Tier 3 prompts. **Stop the migration here if anything looks wrong** — better to investigate than to over-write.

---

#### Phase 6 — USER.md schema migration: `## Organization` → `## Companies (mounted)`

**State:** Pre-extraction `USER.md` had a `## Organization` section with a single `Team repo` field — designed for ONE team's shared infrastructure. Post-extraction, multi-venture support landed: `## Companies (mounted)` table with one row per mounted company (per-company tracker `.{company}-sync`, per-company source URL, per-company venture folder).

**Ask:**
> *"Your USER.md has a `## Organization` section (legacy single-team shape). I'll migrate it to the new `## Companies (mounted)` table. Your existing team-repo URL becomes a `Source` cell in the table. If you have multiple ventures to mount (advisors typically do), the new shape lets you list them all. OK to migrate?"*

**Act:** (Claude reads `USER.md`, identifies the `## Organization` block, rewrites it as a `## Companies (mounted)` row. Operator-edit if needed. **Never overwrite the rest of USER.md** — only the Organization → Companies block.)

Example transformation:

```diff
- ## Organization
-
- Team repo: git@github.com:sovrahq/internal-vault.git
- Venture folder: vault/00 - notes/context/ventures/sovra/

+ ## Companies (mounted)
+
+ > Each mounted company has its own venture folder + substrate config.
+ > `/aios:company` reads this table to know what to sync.
+
+ | Company | Substrate | Source | Venture folder | Last sync |
+ |---|---|---|---|---|
+ | sovra | github | `git@github.com:sovrahq/sovra-context.git` | `vault/00 - notes/context/ventures/sovra/` | YYYY-MM-DD |
```

**Note:** if the operator's old team repo was `sovrahq/internal-vault`, the new pointer is `sovrahq/sovra-context` (the new venture-context repo). The team repo's content was split: framework → `The-AIOS/aios`, venture-specific → `sovrahq/sovra-context`. If they don't have access to sovrahq/sovra-context yet, leave the URL empty and ask them to request access; the row can still register the venture folder for local-only use.

---

#### Phase 7 — Vault scaffold restoration + missing folders

**State:** New scaffold ships `.gitkeep` placeholders for vault folders that should exist on fresh installs but may be empty on long-running operator vaults: `vault/00 - notes/logs/observed-snapshots/`, `vault/00 - notes/logs/role-logs/`, `vault/02 - assets/generated/`, `vault/03 - export/{reports/learned,reports/weekly,reports/monthly,reports/role,talks,meetings,writing/1-drafts,writing/2-ready,writing/3-published}/`.

These folders are needed for `/aios:learned`, `/aios:weekly-learnings`, `/aios:role-report`, the PDF generator, the writing pipeline, and the snapshot system. First invocation of any of these without the folder = "no such directory" error.

**Ask:**
> *"Some export + log subfolders aren't on disk yet. They'll be needed by certain commands (`/aios:learned`, `/aios:role-report`, PDF generator, writing pipeline). I'll create the empty scaffold (`.gitkeep` placeholders only — no file content touched). OK?"*

**Act:**

```bash
cd "$HOME/aios"
for d in \
  "vault/00 - notes/logs/observed-snapshots" \
  "vault/00 - notes/logs/role-logs" \
  "vault/02 - assets/generated" \
  "vault/03 - export/reports/learned" \
  "vault/03 - export/reports/weekly" \
  "vault/03 - export/reports/monthly" \
  "vault/03 - export/reports/role" \
  "vault/03 - export/talks" \
  "vault/03 - export/meetings" \
  "vault/03 - export/writing/1-drafts" \
  "vault/03 - export/writing/2-ready" \
  "vault/03 - export/writing/3-published"; do
  mkdir -p "$d"
  [ ! -f "$d/.gitkeep" ] && touch "$d/.gitkeep"
done
echo "✓ scaffold folders ensured"
```

---

#### Phase 8 — Auto-memory namespace + path cleanup

**State:** Claude's auto-memory (under `~/.claude/projects/{cwd-slug}/memory/`) may still reference the legacy `vault-commands:` plugin namespace OR the old `~/obsidian/` path in feedback entries written before extraction.

**Ask:**
> *"Auto-memory entries reference some legacy patterns: `vault-commands:*` (now `aios:*`) and possibly hardcoded `~/obsidian/` paths (now `~/aios/`). I'll grep auto-memory for these and update where safe. Memory rewrites are mechanical (s/vault-commands:/aios:/g, s/~/obsidian/~/aios/g), but I'll surface the diff before applying. OK?"*

**Act:**

```bash
MEM_DIR="$HOME/.claude/projects"
# Find any .md memory files mentioning legacy patterns
grep -rln "vault-commands:" "$MEM_DIR" 2>/dev/null
grep -rln "~/obsidian/" "$MEM_DIR" 2>/dev/null
```

Show the operator the affected files (filenames + match lines). With confirmation:

```bash
find "$MEM_DIR" -name "*.md" -type f -exec sed -i.bak \
  -e 's|vault-commands:|aios:|g' \
  -e 's|~/obsidian/|~/aios/|g' \
  {} \;
# .bak files preserved for safety; remove with `find $MEM_DIR -name '*.bak' -delete` after verification
echo "✓ memory entries updated; .bak files preserved"
```

If the operator already has a `feedback_aios_namespace.md` entry noting the legacy/canonical rename, leave that one alone — it's documenting the rename, not asserting the old name.

---

#### Phase 9 — Discovery surface awareness (informational)

**State:** Several new framework pieces landed that the operator may not know to use yet:

| New capability | What it does | Where to learn |
|---|---|---|
| `/aios:company --create \| --mount \| --sync` | Multi-venture context distribution | `CHEATSHEET.md §1` + `commands/company.md` |
| `/aios:collaborate` | Shared work spaces (substrate-pluggable: Drive/GitHub/local) | `CHEATSHEET.md §1` |
| `onboarding-aios` agent | Day-0 framework orientation, programmatic-trigger from /today first-run | `agents/aios-personal/onboarding-aios.md` |
| `onboarding-{company}` agents | Per-company HR-Day-1 (ships in every venture-context repo) | `agents/onboarding-{company}.md` in mounted bundles |
| `/aios:cold-start-interview` | Ritualized Day-0 setup with auto-onboarding handoff | `commands/cold-start-interview.md` |
| CI gates on framework + venture-context repos | 6-job (framework) / 5-job (context) validation on PRs | Their respective `.github/workflows/validate.yml` |
| Antifragile #61 — `gh pr checkout` cross-repo hijack rule | Don't `gh pr checkout` from inside your vault — pulls foreign content into your working tree | `vault/00 - notes/context/observed/antifragile.md#61` (operator-personal) — universal lesson for any operator with multi-repo workflows |
| `.claude/` + `vault/.obsidian/` are now fully operator-personal | Never overwritten by `/aios:update`; gitignored | `/aios:update` operator-personal denylist |

**Ask:**
> *"Want a quick tour of any of these? I can spawn `onboarding-aios` for the framework-level walkthrough, or just point you at the doc per capability. Or skip — you'll discover these naturally as `/today` surfaces them."*

**Act:** Operator's choice. Default: skip — `/today` will surface what's relevant when it's relevant (vault-update freshness check, company-context freshness check, CHEATSHEET pointers).

---

#### LAST — Restart Claude Code

**State:** Some changes during this migration (plugin rotation, hook source path changes) only take full effect after a Claude Code restart. The plugin daemon caches plugin source paths in memory; the hook subprocess re-spawns each invocation, but the strings telling the hook *where* to look are read once at startup.

**Ask:**
> *"All migration steps complete. Last step: restart Claude Code so the plugin daemon reloads with the new `aios@the-aios` plugin source. Want to restart now?"*

**Act:** Operator restarts Claude Code (Cmd+Q on macOS, then relaunch). Verify post-restart:

```bash
zsh -i -c 'type spawn 2>&1 | head -1'         # → "spawn is a shell function"
claude plugin list | grep aios@the-aios       # → present
ls ~/aios/.aios-update                         # → present
test -e ~/aios/vault/01\ -\ calendar          # → resolves
```

---

### Verification (run at the end)

```bash
cd ~/aios

# 1. Safety tag exists
git tag | grep "pre-aios-migration" && echo "✓ safety tag preserved (recover with: git reset --hard {tag})"

# 2. Sacred files intact
for f in USER.md INTENT.md CLAUDE.md; do
  test -f "$f" && echo "✓ $f present" || echo "❌ $f MISSING — investigate before continuing"
done
test -f SARAH.md && echo "✓ SARAH.md present (multi-machine setup)"

# 3. Tracker correct
grep -q "github.com:The-AIOS/aios" .aios-update && echo "✓ tracker repointed"
test ! -f .vault-update && echo "✓ legacy tracker removed"

# 4. Path canonical resolves
test -e ~/aios/vault/01\ -\ calendar && echo "✓ ~/aios resolves"

# 5. Wrappers loaded
zsh -i -c 'type spawn spawn-kill 2>&1' | grep -q "shell function" && echo "✓ wrappers loaded"

# 6. Plugin namespace correct
claude plugin list 2>&1 | grep -q "aios@the-aios" && echo "✓ aios plugin registered"

# 7. Vault content intact (sanity — should be many files)
echo "vault file count: $(find vault -type f 2>/dev/null | wc -l) (must be > 0)"

# 8. Operator extensions preserved
for layer in agents skills hooks mcps templates plugins; do
  test -d "$layer/custom" && echo "✓ $layer/custom/ preserved"
done
```

If any verification check fails, **recover via the safety tag from Phase 0** and surface the issue:

```bash
git reset --hard pre-aios-migration-{YYYY-MM-DD}
```

---

### What this entry does NOT change

Operator content is sacred. The migration is repointing infrastructure, not rewriting vault contents. Specifically:

- ✅ `vault/00 - notes/` — declared/observed context, projects, ideas, logs, reflections — untouched
- ✅ `vault/01 - calendar/` — daily notes, weekly plans — untouched
- ✅ `vault/02 - assets/`, `vault/03 - export/`, `vault/04 - backups/` — untouched
- ✅ `USER.md`, `INTENT.md`, `SARAH.md` — only the USER.md `## Organization` → `## Companies (mounted)` schema migration (Phase 6); operator confirms before write
- ✅ `agents/custom/`, `skills/custom/`, `plugins/custom/`, `hooks/custom/`, `mcps/custom/`, `templates/custom/` — preserved
- ✅ `vault/.obsidian/` — fully operator-personal post-extraction; never touched
- ✅ `.claude/` — fully operator-personal; never touched
- ✅ Any `agents/{company}/`, `plugins/{company}/`, etc. company-namespaced infra — preserved (and now formally part of the `/aios:company --sync` distribution model)

### FYI — for the curious

The pre-extraction history of the framework lives in [chuycepeda/obsidian](https://github.com/chuycepeda/obsidian) (where it evolved March-May 2026). [chuycepeda/aios](https://github.com/chuycepeda/aios) and [sovrahq/internal-vault](https://github.com/sovrahq/internal-vault) were the operator-template and team-vault distribution surfaces respectively; both are frozen at the 2026-05-21 extraction point and now point at this canonical CHANGELOG entry as their forwarding address. The full extraction story is captured in the framework's `HISTORY-PRE-2026-05-21.md` (if you want the narrative arc) and in this CHANGELOG's first two entries (the path-portability and initial-release entries).

If anything in this migration surprised you, broke, or felt rough — that's exactly the feedback the post-extraction framework needs. File at [The-AIOS/aios/issues](https://github.com/The-AIOS/aios/issues) and reference this CHANGELOG entry's hash.

---

## 2026-05-21 (evening) — Path portability: ~/aios canonical + auto-symlink fallback

`hash: b165c08`

### State

The framework's 20+ infrastructure files (commands, MCPs, hooks, agents, READMEs) reference `~/aios/` as the canonical install path. Existing operators (Chuy, Sarah, Zineb, Sovra teammates) run from `~/obsidian/` per the pre-extraction convention. Without a redirect, the next `/aios:today` would fail trying to read `~/aios/vault/01 - calendar/...` that doesn't exist on disk.

### Ask

If `~/aios` does not exist on this machine, ask the operator:

> *"I see this vault is at `~/obsidian/`. The framework now expects `~/aios/`. I'll create a symlink `~/aios → ~/obsidian` — non-destructive, reversible, and zero risk to your Obsidian app workspace state, git remote name, open files, or any scripts still referencing `~/obsidian/`. OK to proceed?"*

If `~/aios` already exists and points to this install → silent pass, no action.
If `~/aios` already exists and points elsewhere (conflict) → surface the conflict and let the operator resolve before continuing. Never auto-resolve.

### Act

After the operator confirms, run the OS-appropriate command:

**macOS / Linux / WSL / Git Bash:**
```bash
ln -s "$HOME/obsidian" "$HOME/aios" && ls -la "$HOME/aios" | head -1
```

**Windows PowerShell** (requires Developer Mode or admin — one-time Win 10+ toggle):
```powershell
New-Item -ItemType SymbolicLink -Path "$HOME\aios" -Target "$HOME\obsidian"
```

**Windows CMD fallback** (no admin needed; directory junction; same-volume only):
```cmd
mklink /J "%USERPROFILE%\aios" "%USERPROFILE%\obsidian"
```

Then verify:
```bash
test -e "$HOME/aios/vault/01 - calendar" && echo "✓ symlink resolves — ~/aios → ~/obsidian"
```

If verification passes → done. The operator continues normal flow; every framework reference to `~/aios/...` now resolves to their actual `~/obsidian/` vault.

### Why symlink, not `mv ~/obsidian ~/aios`

The `mv` would force a coordinated rename across: Obsidian app workspace.json + plugin data caches, git remote name (`chuycepeda/obsidian` would mismatch the local path), open files / in-flight syncs, IDE bookmarks, and any script still referencing `~/obsidian/`. Too risky for what is fundamentally a path-resolution problem. The symlink solves the resolution problem with zero side effects and stays reversible (`rm ~/aios` undoes it).

### Going forward

Operators cloning the framework fresh land at `~/aios/` natively (no symlink needed). `SETUP.md → § Path portability` and `/aios:cold-start-interview` (Pre-step) auto-create the symlink for anyone who clones to a different path. The symlink convention is the framework's install-anywhere fallback, of which today's `~/obsidian → ~/aios` migration is the largest case.

---

## 2026-05-21 — Initial public release: AIOS extracted from chuycepeda/obsidian

`hash: 71ae219`

### What this entry is

This is the **first canonical entry** for The AIOS as a standalone public framework. If you're discovering this repo for the first time — welcome. If you arrived here because your previous `/aios:update` origin pointed at `chuycepeda/aios` or `sovrahq/internal-vault`, this entry is also your **migration playbook**.

> **Three progressive stages, all compounding** — the AIOS philosophy in one frame:
> 1. **Automate — *Gain speed, do faster*.** Daily plans, drafts, syntheses — 30 min becomes 30 sec. *Week 1.*
> 2. **Amplify — *Gain bandwidth, do more*.** Agents draft proposals, write in your voice, research while you sleep — you stop being the bottleneck. *Month 1.*
> 3. **Agency — *Gain autonomy, do agentic*.** AI co-workers act on your behalf with judgment, within trust boundaries you've defined. *Quarter 1, deepening across years.*

---

### What's in this initial release

The AIOS framework — generic, operator-agnostic infrastructure that runs on top of [Claude Code](https://claude.com/claude-code) and produces a personalized agent operating system on your machine.

**Top-level structure (all infra at root, Anthropic-standard-compatible):**

```
The-AIOS/aios/
├── CLAUDE.md          # System behavioral contract (universal)
├── README.md          # Repo entry point
├── SETUP.md           # First-machine install guide
├── CHANGELOG.md       # This file
├── LICENSE            # GPL v2+ (WordPress-style — open commons + commercial layer on top)
├── commands/          # 24 commands (/today, /close-day, /7plan, /company, ...)
├── agents/            # 28 task agents organized into 6 plugin bundles
├── hooks/             # Claude Code event hooks + spawn wrappers
├── mcps/              # 10 bundled MCP servers (Google Workspace, Slack, GitHub, Stitch, NotebookLM, ...)
├── plugins/           # Claude Code plugins shipped with the framework
├── skills/            # Reusable capabilities (Agent Skills standard)
├── templates/         # Vault templates (project, daily, agent, etc.)
└── docs/              # Migration map + supplementary docs
```

**Agents (28 total) organized into 6 plugin bundles:**

- `agents/aios-sales/` (4) — Lead generation, proposals, CRM, brand monitoring
- `agents/aios-strategy/` (3) — Market research, advisory, deep dives
- `agents/aios-finance-legal/` (4) — Accounting, legal review, invoicing, compliance
- `agents/aios-engineering/` (4) — Code review, documentation, bug triage, building
- `agents/aios-communication/` (7) — Content, decks, emails, meeting prep, reports, design.md authoring
- `agents/aios-personal/` (6) — Study, journaling, growth-companion, decision-journaler, onboarding-aios, crisis-mode
- `agents/custom/` — Your operator-specific extensions (never overwritten by `/aios:update`)

Each bundle has its own README scoping what it covers + when to install. Operators install only the bundles they need.

**Bundled MCPs (10 servers):**

Google Workspace · Slack · Atlassian · GitHub · Stitch · NotebookLM · Playwright · Nano Banana (Gemini image gen) · PDF Generator · Spotify DJ (lifestyle, optional)

See `mcps/_index.md` for the canonical list + setup instructions. Run `bash mcps/setup.sh` on first install.

---

### What to do — migration playbook (Claude-executable)

> **For Claude running `/vault-update` or `/aios:update` against this CHANGELOG:** this entry IS the migration script. Walk the operator through it step by step in State → Ask → Act format. Hard preconditions short-circuit early; restart-required steps go LAST.

#### Step 0 — Hard precondition (skip rest if not applicable)

**State:** the operator's `~/obsidian/.vault-update` `repo=` field. If it already points at `git@github.com:The-AIOS/aios.git` → skip the rest of this entry (operator already migrated). If it points at `chuycepeda/aios` or `sovrahq/internal-vault` → proceed.

**Ask:** *"Your `.vault-update` shows you're syncing from `{old-repo}`. AIOS moved to `The-AIOS/aios` on 2026-05-21. Want me to walk you through the migration (~15 min, includes folder moves, plugin rename, and a Claude Code restart)?"*

**Act:** if yes, proceed to Step 1.

#### Step 1 — Update the upstream pointer

**State:** `~/obsidian/.vault-update` + `~/obsidian/USER.md` `## Organization` section.

**Ask:** *"I'll update your `.vault-update` `repo=` line to `git@github.com:The-AIOS/aios.git`, set `hash=initial` to force a full sync, and replace `USER.md` `## Organization` with the new `## Companies (mounted)` table. OK?"*

**Act:**

1. Rewrite `.vault-update` to:
   ```
   repo=git@github.com:The-AIOS/aios.git
   hash=initial
   synced=never
   ```
2. In `USER.md`, replace the entire `## Organization` block with a `## Companies (mounted)` section (table format) — use the operator's existing venture folder as the first row. See the new USER.md template in The-AIOS/aios for the schema.

#### Step 2 — Pull new infrastructure (Tier 1 sync)

**State:** local infra still references the old structure (vault-commands plugin, vault/06 - agents/, vault/02 - templates/).

**Ask:** *"Now I'll clone The-AIOS/aios to /tmp/, diff against your local, and replace Tier 1 paths (commands/, hooks/, mcps/, plugins/, skills/, templates/, agents/aios-*/, top-level docs). Your operator-specific extensions (anything under `custom/` in any layer) are preserved. Proceed?"*

**Act:** standard `/aios:update` Tier 1 flow — `git clone --depth=50 --single-branch git@github.com:The-AIOS/aios.git /tmp/vault-update-check`, diff, apply changes for each Tier 1 path. Skip every `custom/` subfolder (`agents/custom/`, `skills/custom/`, `commands/custom/`, `hooks/custom/`, `mcps/custom/`, `plugins/custom/`, `templates/custom/`) — those are operator-specific.

#### Step 3 — Folder migration (promote templates + agents to top-level)

**State:** operator's vault has `vault/02 - templates/`, `vault/06 - agents/` (legacy locations), plus `vault/03 - assets/`, `vault/04 - export/`, `vault/05 - backups/` (legacy numbering).

**Ask:** *"AIOS now keeps templates and agents at the TOP LEVEL (infra), not inside vault/. I'll move your existing templates and agents to top-level folders, renumber vault subfolders to be continuous (00/01/02/03/04), and preserve your custom additions in `*/custom/`. This is reversible — I'll keep a backup. OK?"*

**Act (in order):**

1. **Templates migration** — `vault/02 - templates/{file}.md` → `templates/{file}.md`. If a file with the same name already exists at top-level templates/ (from the Tier 1 sync), MERGE: keep the new canonical version; if the operator's old version differs, ALSO copy to `templates/custom/{name}-legacy.md` for review.
2. **Agents migration** — for each `vault/06 - agents/{name}.md`:
   - If `{name}` matches a bundled agent in `agents/aios-*/`, **drop** the legacy copy (the bundle version is canonical now)
   - If `{name}` is operator-custom (was in `vault/06 - agents/my-agents/`), move to `agents/custom/{name}.md`
   - Otherwise, move to `agents/custom/{name}.md` and flag for review
3. **Vault renumbering** — `git mv vault/03 - assets vault/02 - assets`, `git mv vault/04 - export vault/03 - export`, `git mv vault/05 - backups vault/04 - backups`. The old `vault/02 - templates/` and `vault/06 - agents/` are now empty — `rmdir`.
4. **Sweep stale references** — `grep -rln 'vault/02 - templates\|vault/06 - agents\|vault/03 - assets\|vault/04 - export\|vault/05 - backups' --include='*.md' --exclude-dir=.git` and update each to the new paths. Same for non-prefixed `02 - templates/` / `06 - agents/`.

#### Step 4 — Plugin marketplace rename + versioning (vault-commands@local → aios@the-aios + version 0.1.0)

**State:** `~/.claude/plugins/marketplaces/local/.claude-plugin/marketplace.json` + plugin directories + `~/.claude/settings.json` enabledPlugins reference `vault-commands@local`. The marketplace is named `local`, the plugin has no declared version (cache dir = `unknown`), and the command namespace is `/vault-commands:*`.

**Ask:** *"Three renames in one step: plugin `vault-commands` → `aios`, marketplace `local` → `the-aios`, and add `version: 0.1.0` so the cache stops landing under `/unknown/`. All your `/vault-commands:today` etc. become `/aios:today`, and the plugin reference becomes `aios@the-aios`. I'll update all manifests, rename the directories, update `~/.claude/settings.json` (enabledPlugins + extraKnownMarketplaces), and update `~/obsidian/.claude/settings.local.json` permissions. Restart required at the end. Proceed?"*

**Act:**

1. **Rename marketplace + plugin directories + purge stale cache:**
   ```bash
   mv ~/.claude/plugins/marketplaces/local ~/.claude/plugins/marketplaces/the-aios
   mv ~/.claude/plugins/marketplaces/the-aios/plugins/vault-commands ~/.claude/plugins/marketplaces/the-aios/plugins/aios
   rm -rf ~/.claude/plugins/cache/local  # rebuilds at new path on next plugin reload
   ```
2. **Update `marketplace.json`** at `~/.claude/plugins/marketplaces/the-aios/.claude-plugin/marketplace.json`:
   - `"name": "local"` → `"name": "the-aios"`
   - Plugin entry: `"name": "vault-commands"` → `"name": "aios"`, add `"version": "0.1.0"`, update `"source": "./plugins/aios"`.
3. **Update `plugin.json`** at `~/.claude/plugins/marketplaces/the-aios/plugins/aios/.claude-plugin/plugin.json`:
   - `"name": "vault-commands"` → `"name": "aios"`
   - Add `"version": "0.1.0"`
4. **Update `~/.claude/settings.json`:**
   - `enabledPlugins`: `"vault-commands@local": true` → `"aios@the-aios": true`
   - `extraKnownMarketplaces`: rename key `"local"` → `"the-aios"`, update `source.path` to `/Users/{you}/.claude/plugins/marketplaces/the-aios`
5. **Update `~/obsidian/.claude/settings.local.json`** — every `Skill(vault-commands:X)` permission → `Skill(aios:X)`.
6. **Rename `commands/vault-update.md` → `commands/update.md`** — invokes cleanly as `/aios:update` instead of `/aios:vault-update`.
7. **Populate the new cache** with the renamed source-of-truth commands:
   ```bash
   mkdir -p ~/.claude/plugins/cache/the-aios/aios/0.1.0/commands
   cp ~/obsidian/commands/*.md ~/.claude/plugins/cache/the-aios/aios/0.1.0/commands/
   cp ~/obsidian/commands/*.md ~/.claude/plugins/marketplaces/the-aios/plugins/aios/commands/
   rm -f ~/.claude/plugins/marketplaces/the-aios/plugins/aios/commands/{company-sync,vault-update}.md  # remove stale renamed-away files
   ```

#### Step 4b — Canonical plugin layout (commands/ → plugins/aios/commands/)

**State:** plugin source still lives in top-level `commands/` folder in your personal vault. Marketplace manifest at `commands/marketplace.json`. Plugin manifest at `commands/plugin.json`. Doesn't match Anthropic's canonical Claude Code plugin layout (cf. [claude-for-legal](https://github.com/anthropics/claude-for-legal), [claude-plugins-official](https://github.com/anthropics/claude-code-plugins)).

**Ask:** *"AIOS is moving its plugin source to the canonical Anthropic layout: `commands/` becomes `plugins/aios/commands/`, manifests move to `.claude-plugin/marketplace.json` (root) and `plugins/aios/.claude-plugin/plugin.json`. This makes us tooling-compatible with the broader Claude Code plugin ecosystem. I'll git-mv your files (history preserved), update the runtime cache, and clean up. Proceed?"*

**Act (in your personal vault):**

1. **Restructure source-of-truth folders:**
   ```bash
   cd ~/obsidian
   mkdir -p .claude-plugin plugins/aios/.claude-plugin
   git mv commands/marketplace.json .claude-plugin/marketplace.json
   git mv commands/plugin.json plugins/aios/.claude-plugin/plugin.json
   git mv commands/*.md plugins/aios/commands/  # ALL .md files
   git mv commands/custom plugins/aios/commands/custom
   rmdir commands
   ```
2. **Enrich `.claude-plugin/marketplace.json`** with the canonical fields (these are advisory; the existing entry already works):
   - `displayName: "AIOS — Daily Ritual & Strategic OS"` (shown in plugin lists)
   - `license: "GPL-2.0-or-later"` · `repository`, `homepage` (GitHub URL) · `keywords` (10 discovery tags)
3. **Update runtime cache** to mirror the new source layout:
   ```bash
   cp ~/obsidian/.claude-plugin/marketplace.json ~/.claude/plugins/marketplaces/the-aios/.claude-plugin/marketplace.json
   cp ~/obsidian/plugins/aios/.claude-plugin/plugin.json ~/.claude/plugins/marketplaces/the-aios/plugins/aios/.claude-plugin/plugin.json
   cp ~/obsidian/plugins/aios/commands/*.md ~/.claude/plugins/marketplaces/the-aios/plugins/aios/commands/
   cp ~/obsidian/plugins/aios/commands/*.md ~/.claude/plugins/cache/the-aios/aios/0.1.0/commands/
   ```
4. **Remove Sovra-branded `plugins/pdf-generator/` from framework** (if it leaked in from an older sync — it's now operator-vault-only, namespaced as `plugins/sovra/pdf-generator/` per the company-namespacing convention):
   ```bash
   # Only in framework repo (The-AIOS/aios) — NOT in operator vault
   # In operator vault, IF you have it, rename:
   cd ~/obsidian && [ -d plugins/pdf-generator ] && git mv plugins/pdf-generator plugins/sovra/pdf-generator
   ```

#### Step 5 — Refresh Obsidian UI cache (optional but recommended)

**State:** `vault/.obsidian/workspace.json` (gitignored, per-machine) may reference old paths (`04 - export/...`, `06 - agents/...`, `02 - templates/...`).

**Ask:** *"Your Obsidian's workspace.json tab cache has stale paths from before the folder renumbering. I'll sed-replace the old paths with the new ones so tabs open correctly when you reopen Obsidian. OK?"*

**Act:**

```bash
sed -i.bak \
  -e 's|"04 - export/|"03 - export/|g' \
  -e 's|"05 - backups/|"04 - backups/|g' \
  -e 's|"06 - agents/|"agents/|g' \
  -e 's|"02 - templates/|"templates/|g' \
  vault/.obsidian/workspace.json && rm vault/.obsidian/workspace.json.bak
```

#### Step 6 — Final sanity check + RESTART REQUIRED

**State:** all migration work landed but Claude Code's running session still has the OLD plugin loaded in memory.

**Ask:** *"Last step — restart Claude Code so the renamed `/aios:*` plugin loads. Want me to commit + push your vault first?"*

**Act:**

1. Commit + push the operator's vault (their personal repo) with all the changes.
2. **Tell the operator (don't try to do it for them):** *"Quit and restart Claude Code now. In your fresh session, try `/aios:today` to verify. Welcome to the new AIOS shape."*
3. After their restart, suggest they run `/aios:housekeeping` — Bucket 17 (CLAUDE.md + USER.md health check) will surface any remaining drift.

#### Step 7 — (Optional) Multi-company setup

If the operator had a single company mounted via the old `/company-sync` (now retired), they can either:
- Leave their existing venture folder as-is (it remains valid in the new shape)
- Migrate to the new multi-company model via `/aios:company --create` against `The-AIOS/company-template` (see Phase 1c below). This gives them a proper venture-context repo at `{org}/venture-context` instead of the mixed sovrahq/internal-vault setup.

---

### What to do — first-time setup (new operators)

> **This section is for users discovering AIOS for the first time.** If you're migrating from a previous AIOS repo, see the migration playbook above.

1. Clone this repo as the substrate for your personal vault scaffold:
   ```bash
   git clone git@github.com:The-AIOS/aios.git ~/obsidian
   cd ~/obsidian
   ```

2. Read `START-HERE.md` for the post-clone walkthrough (philosophy + three-repo model + Day 1 expectations).

3. Read `SETUP.md` for first-machine install (Claude Code, MCPs, dependencies).

4. Tell Claude: *"Set me up — read SETUP.md and walk me through it."* The first session does the heavy lifting; you answer questions, Claude does the work.

5. After setup, run your first `/aios:today` — that's the daily ritual that anchors everything else.

---

### Phase 1c — `/aios:company` (formerly `/company-sync`) + `The-AIOS/company-template` repo (in this release)

The AIOS now supports mounting **multiple companies** into your vault via the new `/aios:company` command. Each company has its own venture-context repo (typically `{org}/venture-context` on GitHub or a Drive folder). Operators install multi-substrate adapters via the same `/aios:collaborate` adapter pattern.

**Canonical company-template repo:** [The-AIOS/company-template](https://github.com/The-AIOS/company-template) — scaffolds 12 files (about_venture, positioning, personas, gtm, offerings, pricing, primitives, design.md, brand.md, culture, CLAUDE.md, README) when you run `/aios:company --create`.

See `commands/company.md` for the full subcommand surface (`--create`, `--mount`, `--sync`, `--sync-all`, `--status`, `--invite`, `--dry-run`).

---

### What's new vs. the pre-extraction state (high-leverage changes)

These are the structural improvements that landed in the 2026-05-21 cutover. Each is documented separately in its own changelog entry below — this initial entry is the umbrella.

1. **Multi-company model** — new `/aios:company` (multi-substrate, multi-company) replaces the older single-company `/company-sync`. `USER.md` shifts from a single `## Organization` block to a `## Companies (mounted)` table that holds N rows.
2. **Agents restructured into 6 plugin bundles** at top-level `agents/` (was flat at `agents/`). Per-bundle README scoping. Operator extensions in `agents/custom/`.
3. **5 new agents:** growth-companion, onboarding-aios, design-md-author, decision-journaler, crisis-mode — all in `aios-personal/` and `aios-communication/`.
4. **Anthropic-official integration** — every agent that has an authoritative Anthropic-shipped specialist references it via `## See also` (anthropics/financial-services, claude-for-legal, claude-code-security-review, etc.). Reference, don't bundle — keeps AIOS lean while making Anthropic's deeper layers discoverable.
5. **design.md spec adopted** — `design-md-author` agent generates design.md per [Google's design.md spec](https://github.com/google-labs-code/design.md) (14.5K⭐). References VoltAgent/awesome-design-md (82K⭐) for inspiration.
6. **Three Progressive Stages framing** — added to The-AIOS org profile README as the canonical narrative of how AIOS compounds.
7. **`/housekeeping` Bucket 17** — comprehensive CLAUDE.md + USER.md health check (inspired by anthropics/claude-plugins-official/claude-md-management, reimplemented inline so AIOS works standalone).
8. **Agent Skills standard compliance** — agents/skills follow [anthropics/skills](https://github.com/anthropics/skills) (138K⭐) format. Cross-platform compat with Claude Code, Codex, Gemini CLI, Cursor, Antigravity.
9. **Stitch optional integration** — `/aios:cold-start-interview` surfaces Stitch (UI generation) for operators building user-facing software.

---

### Pre-extraction history

The infrastructure in this repo evolved in `chuycepeda/obsidian` from March → May 2026. The full development history — every commit, every PR, every Co-Authored-By trail — is preserved there.

See [HISTORY-PRE-2026-05-21.md](./HISTORY-PRE-2026-05-21.md) for the lineage pointer.

---

### What's next

- 2026-05-22+ — operator validation: confirm Sarah and Zineb successfully migrated their vaults to point at this repo
- After confirmations — archive `chuycepeda/aios` and `sovrahq/internal-vault` (those repos remain accessible read-only)
- Then continue normal AIOS infrastructure evolution under The-AIOS/ org

---
