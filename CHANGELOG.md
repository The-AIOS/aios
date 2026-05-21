# Changelog

> What changed in The AIOS framework, why, and what to do about it.
> Entries are newest-first. Each entry is tied to a git commit hash so `/aios:update` can show you only what's new since your last sync.
>
> **This is the canonical CHANGELOG for The AIOS.** The framework lives at [The-AIOS/aios](https://github.com/The-AIOS/aios). It is built from infrastructure that evolved in [chuycepeda/obsidian](https://github.com/chuycepeda/obsidian) from March → May 2026 (pre-extraction history preserved there).

---

## 2026-05-21 — Initial public release: AIOS extracted from chuycepeda/obsidian

`hash: 3120add`

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

### What to do — if you're migrating from `chuycepeda/aios` or `sovrahq/internal-vault`

> **This section is the migration playbook for existing AIOS users.** If you're new, skip to "What to do — first-time setup."

**State:** your current `/aios:update` origin points at one of the two pre-extraction repos. Both repos continue to exist for now (will be archived only after migration confirmations come in). Your old vault content stays intact; only your **upstream infra pointer** changes.

**Ask:** before running anything, confirm — are you currently syncing from `chuycepeda/aios` or `sovrahq/internal-vault`? Check `~/obsidian/.vault-update` for the `repo=` line. If it shows one of those two URLs, proceed.

**Act:**

1. **Edit your `USER.md` → `## Organization` section.** Change the `Team repo:` line:

   ```diff
   - Team repo: git@github.com:sovrahq/internal-vault.git
   + Team repo: git@github.com:The-AIOS/aios.git
   ```

   (Or whichever URL you had — change the value, keep the key.)

2. **Update `~/obsidian/.vault-update`** to point at the new origin:

   ```diff
   -repo=git@github.com:sovrahq/internal-vault.git
   +repo=git@github.com:The-AIOS/aios.git
   hash=initial
   ```

   Setting `hash=initial` forces a full sync on the next run (recommended for the migration — your local infra is from the pre-extraction era).

3. **Run `/aios:update`** in your `~/obsidian` Claude session. It will pull the entire new infrastructure from The-AIOS/aios as the canonical state.

4. **What you'll see during the update:**
   - New top-level `agents/` directory (was `vault/06 - agents/` previously) — your custom agents in `my-agents/` are renamed to `custom/`
   - New top-level `templates/` directory (was `vault/02 - templates/` previously)
   - 5 new agents shipped (growth-companion, onboarding-aios, design-md-author, decision-journaler, crisis-mode)
   - `/vault-commands:*` namespace renamed to `/aios:*` (matches the new public brand). `/company-sync` command renamed to `/aios:company` and substantially upgraded (multi-substrate, multi-company)
   - `/housekeeping` gained Bucket 16 (Radar Health Audit) + Bucket 17 (CLAUDE.md + USER.md health check)
   - Per-agent "See also" sections referencing Anthropic-official repos (financial-services, claude-for-legal, claude-code-security-review, etc.)

5. **Run `/housekeeping` once after the update** — Bucket 17 will surface any drift between your USER.md/CLAUDE.md and the new canonical state. Address whatever it flags before resuming normal work.

6. **(Optional) Move your existing venture context.** If you had a venture mounted via the old `/company-sync` (now retired), you can either:
   - Leave it as-is locally (vault folder remains valid)
   - Migrate to the new `/aios:company` model via `/aios:company --create` against `The-AIOS/company-template` (separate repo, see Phase 1c below)

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
2. **Agents restructured into 6 plugin bundles** at top-level `agents/` (was flat at `vault/06 - agents/`). Per-bundle README scoping. Operator extensions in `agents/custom/`.
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
