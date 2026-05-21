# Changelog

> What changed in The AIOS framework, why, and what to do about it.
> Entries are newest-first. Each entry is tied to a git commit hash so `/aios:update` can show you only what's new since your last sync.
>
> **This is the canonical CHANGELOG for The AIOS.** The framework lives at [The-AIOS/aios](https://github.com/The-AIOS/aios). It is built from infrastructure that evolved in [chuycepeda/obsidian](https://github.com/chuycepeda/obsidian) from March → May 2026 (pre-extraction history preserved there).

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

#### Step 4 — Plugin marketplace rename (vault-commands → aios)

**State:** `~/.claude/plugins/marketplaces/local/.claude-plugin/marketplace.json` + plugin directories + `~/.claude/settings.json` enabledPlugins reference `vault-commands@local`. The COMMAND namespace is currently `/vault-commands:*`.

**Ask:** *"The plugin marketplace renames from `vault-commands` to `aios`. All your `/vault-commands:today` etc. become `/aios:today`. I'll update the manifest files, rename the plugin directories, update `~/.claude/settings.json` enabledPlugins, and update `~/obsidian/.claude/settings.local.json` permissions. You'll need to restart Claude Code at the end. Proceed?"*

**Act:**

1. **Rename plugin directories:**
   ```bash
   mv ~/.claude/plugins/marketplaces/local/plugins/vault-commands ~/.claude/plugins/marketplaces/local/plugins/aios
   mv ~/.claude/plugins/cache/local/vault-commands ~/.claude/plugins/cache/local/aios
   ```
2. **Update marketplace.json + both plugin.json files** — change `"name": "vault-commands"` → `"name": "aios"`, update `source: "./plugins/aios"`. Three files total.
3. **Update `~/.claude/settings.json`** — `"enabledPlugins"` key: rename `"vault-commands@local": true` → `"aios@local": true`.
4. **Update `~/obsidian/.claude/settings.local.json`** — every `Skill(vault-commands:X)` permission → `Skill(aios:X)`.
5. **Rename `commands/vault-update.md` → `commands/update.md`** — invokes cleanly as `/aios:update` instead of `/aios:vault-update`.

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
