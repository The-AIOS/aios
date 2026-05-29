# Changelog

> What changed in The AIOS framework, why, and what to do about it.
> Entries are newest-first. Each entry is tied to a git commit hash so `/aios:update` can show you only what's new since your last sync.
>
> **This is the canonical CHANGELOG for The AIOS.** The framework lives at [The-AIOS/aios](https://github.com/The-AIOS/aios).

> ## ⚠️ Reading order
>
> Newest entries appear first below. **If you're migrating from the pre-2026-05-23 framework** (`{user}/aios` template or `{org}/internal-vault` team-repo lineage), scroll down to the **2026-05-23 — Migration playbook** entry and complete it BEFORE acting on any newer entries above it. Newer entries assume you've already migrated; running them on the legacy structure will produce confusion or fail.
>
> Already-migrated operators (anyone who's synced past `bc80cf1`) can read top-down normally — `/aios:update`'s hash-based scan correctly identifies the migration entry as already-applied and won't re-surface it.

---

## 2026-05-28 — INTENT.md: honest "guidance vs enforcement" disclaimer

`hash: PENDING`

> **Transparency over the comfortable omission.** INTENT.md is loaded into context every session and shapes the AI's judgment, autonomy, and focus — but loading is *soft* governance: it guides the model, it doesn't *stop* it, and adherence scales with the model you run. The framework never said this out loud, which risked operators believing a parked item or autonomy boundary in INTENT.md was a hard guarantee. It isn't. Added a calm, non-alarming note to the INTENT.md template explaining the distinction and pointing operators to the hard-enforcement layer: their AI tool's permission config (`deny` / `ask` / `allow`). Intent guides; permissions enforce; the strongest setups use both. This makes the trust model honest — you know exactly what the contract does and doesn't do.

### What changed

- `INTENT.md` (template) — new intro callout: *"How this contract works — and where it stops."* Explains that context-loading guides but doesn't enforce, that fidelity is model-dependent, and that non-negotiable boundaries should be elevated to hard permission rules (`deny` = never, `ask` = confirm first, `allow` = autonomous). Framed as empowerment ("here's how to make a boundary hard if you want"), not alarm.

### Action required

INTENT.md is **operator-personal** (hard denylist — `/aios:update` never overwrites it). So this won't auto-apply; it's a **surgical add** for the operator's Claude session:

1. **Detect:** check whether your `INTENT.md` already contains a "How this contract works — and where it stops" note (or equivalent guidance-vs-enforcement language).
2. **If absent → offer to add it:** insert the disclaimer callout right after the intro blockquote (before the `## Autonomy levels` section), matching the template wording. It's a universal note — no personalization needed. Confirm with the operator before writing (it's their trust contract).
3. **Optional, recommended follow-on:** if any of your INTENT.md boundaries are *genuinely non-negotiable* and map to a concrete tool/command, mirror them into `settings.json` → `permissions`: `deny` for "never," `ask` for "confirm first." (Most operators' `ask` list is empty — that's the highest-value tier for outward actions like sends/merges/deploys.)

**Restart-required:** none.

---

## 2026-05-28 — Capability-count drift guard (CI) + TOOLS.md skill-count fix

`hash: 09b1abf`

> **Counts in the docs had silently drifted from the bundled folders — now CI-enforced.** Adding the `infographic-builder` skill surfaced that several capability counts were stale: TOOLS.md said anthropic "9 skills" (actually 11) with a hand-listed superpowers subset (actually 14), and the new skill wasn't in the named table. Root cause: these counts are hand-maintained in multiple docs, so they drift whenever bundled content changes. **Fix is two-part:** (1) corrected TOOLS.md — added the `infographic-builder` row + fixed the source-folder counts to ground truth (aios 17 · anthropic 11 · superpowers 14 · **total bundled 42**); (2) a new **CI `counts` job** computes the bundled ground truth from the folders (excluding `custom/` + `{company}/` namespaces — "AIOS numbers, not sovra/custom") and fails the build if any doc claim disagrees. The drift class is now structurally prevented in this repo.

### What changed

- `TOOLS.md` — `infographic-builder` added to the Content & design skills table; source-folder line corrected: `anthropics/skills` 9→**11**, `obra/superpowers` stale-named-list→**14 skills**, added `Total bundled: 42`.
- `.github/workflows/validate.yml` — new `Capability counts` job. Computes `commands` (`plugins/aios/commands/*.md`), `agents` (`agents/aios/**`), `skills` (`skills/{aios,anthropic,superpowers}/*/`), `mcps` (`mcps/*-mcp/`) — bundled only, no custom/company — and asserts the count-bearing claims in TOOLS.md + README.md match. Reworded count sentences fail loudly (regex anchored on stable source names). No untrusted input (no `github.event.*`) — pure repo-file scan.

### Action required

`/aios:update` brings the corrected `TOOLS.md` (Tier 1). The CI job is canonical-repo-only (`.github/` doesn't sync to operator vaults), so there's nothing for operators to run — it just keeps the framework's own docs honest going forward.

**Note (separate repo, not covered here):** the public site (`the-aios.com`) carries its own count claims (commands/agents in `messages/*.ts` + `llms.txt`) and is a different repo CI can't see from here — those are corrected directly in the site repo. A cross-repo count guard is a possible future follow-up.

**Restart-required:** none.

---

## 2026-05-28 — `/aios:update` hardening: completeness reconcile + opt-in cleanup + full clone

`hash: 626e982`

> **Three fixes that make `/aios:update` trustworthy and self-healing post-migration — triggered by a real orphan bug.** A manually-edited `.aios-update` tracker (hand-bumped past un-pulled commits during a manual-cp consolidation) silently orphaned a whole feature (the `infographic-builder` skill + `/ingest` Step 6 from `e76432f`): because the missing content was an *ancestor* of the over-claimed stored hash, `/aios:update`'s tracker-diff (`stored..HEAD`) could never see it again. The command trusted the tracker as its sole source of truth, so one bad tracker write = permanent invisible gap. **(A)** A new **completeness reconcile** (Step 6.5, always runs) diffs the vault against canonical HEAD directly — making the tracker an *optimization*, not the source of truth — so a desynced tracker now self-heals on the next run. The tracker advances *only* on a clean, fully-applied run, and the spec now forbids hand-editing it (antifragile #65). **(B)** Duplicate cleanup — after-migration scaffolding that ran destructively on *every* sync — is now **opt-in (`--cleanup`) + report-then-confirm**, off the default path. **(C)** The clone dropped `--depth=50` (≈5 days at ~10 commits/day → unreachable `stored_hash` for any non-weekly syncer → backup-flood + degraded changelog scan) for a **full single-branch clone**.

### What changed

- `plugins/aios/commands/update.md`:
  - **New Step 6.5 — Completeness reconcile (ALWAYS runs).** `diff -rq vault /tmp/vault-update-check` across Tier-1 paths (excluding `custom/`/company/`.venv`/`__pycache__`/logs/auth). Any framework file that *differs* or is *missing* gets pulled (three-way backup decision, CRLF-normalized) + reported. Catches drift the tracker-diff structurally can't.
  - **Step 7 — tracker advances only on a clean, fully-applied run** (every apply + auto-exec succeeded AND reconcile clean). On failure: leave tracker put, report. Explicit rule: **never hand-edit `.aios-update`** (only the command writes it, as its final step).
  - **Step 5 — duplicate cleanup is now opt-in** (`/aios:update --cleanup`) + report-then-confirm; default skips it.
  - **Step 1 — full clone** (no `--depth`) so `stored_hash` + every changelog `entry_hash` stay reachable regardless of staleness.
  - Intro, frontmatter, output-format, and Rules updated to match.

### Action required

`/aios:update` self-applies this (it's an `update.md` change → the Step 2.5 self-update guard applies the new spec + re-invokes with it; the new Step 6.5 reconcile runs in the re-invoked pass). For the teammate's session:

1. **`/aios:update`** — pulls + self-updates. Watch for a new report line: *"Completeness reconcile: clean"* (or, if your tracker was ever desynced, *"recovered N framework file(s) the tracker-diff missed"* — that's the self-heal). No action on a clean reconcile.
2. **If you've ever hand-edited `.aios-update`:** stop — and run `/aios:update` once; the reconcile recovers anything the bad tracker orphaned. (Manual oracle if you suspect a gap: `diff -rq` your vault against a fresh clone across `plugins/skills/agents/hooks/templates` + root docs, excluding `custom/`.)
3. **Duplicate cleanup** no longer runs by default. If you want the post-migration dup scan, run `/aios:update --cleanup` (it reports + asks before removing).

**Restart-required:** none.

---

## 2026-05-28 — `/today` clean-pass: due-today task safety net (fresh tasks, not just carries)

`hash: fced66f`

> **`/today`'s drop-check had a hole: it guarded *carries* but not *fresh due-today tasks*.** The post-write "ZERO TOLERANCE" drop-check reconciled today's note only against the *previous* note's unchecked items — so a task added today (not a carry) that also wasn't a calendar event had **no safety net** and could silently fall out of the plan. Surfaced live 2026-05-28: two due-today ingest tasks + a wrapper task were dropped from the daily note on a narrative-heavy day (large backfill section crowded out the mechanical Google-Tasks merge). Fix: a new clean-pass step 3 cross-references the executor's `due == today` Google Tasks against what landed, and places any absent task (ingests/delegatable → Agents-can-handle) before commit.

### What changed

- `plugins/aios/commands/today.md` — post-write clean pass gains **step 3: Due-today task check**. Step 2 (carry drop-check) renamed for clarity; Review-items + commit-note steps renumbered 4/5. The commit-message hint now records `recovered N due-today tasks`.

### Action required

`/aios:update` applies it (Tier 1 — `plugins/aios/commands/`, auto-synced to the plugin cache). No restart; next `/today` runs the extended clean pass automatically. Operators who've noticed due-today tasks occasionally missing from their daily note on busy days: this closes that gap.

**Restart-required:** none.

---

## 2026-05-28 — Wrapper default model → Opus 4.8 (1M)

`hash: 8ecf6bb`

> **Claude Opus 4.8 shipped; the spawn-wrapper default follows.** The `spawn` / named-session wrappers launch children with an explicit `--model` flag (because `/config` and `/model` are session-scoped and don't propagate to spawned children). That default moves `claude-opus-4-7[1m]` → `claude-opus-4-8[1m]` — 1M-context Opus 4.8. The `$CLAUDE_MODEL` env override is unchanged (still how you pick Sonnet, a 3P provider, or non-1M Opus). **Scope is the wrappers only** — the vendored `skills/anthropic/claude-api/*` SDK references (which cite `claude-opus-4-7` in code samples + a price table) are intentionally untouched here; those track Anthropic's upstream skill and are a separate decision.

### What changed

- `hooks/claude-identity/install-wrappers.sh` — default `model_to_use="${CLAUDE_MODEL:-claude-opus-4-8[1m]}"` (+ the two explanatory comments).
- `hooks/claude-identity/install-wrappers.ps1` — `$modelToUse` default → `claude-opus-4-8[1m]`.
- `plugins/aios/commands/cold-start-interview.md` — identity-table description of the launch command → `--model claude-opus-4-8[1m]`.
- `CHEATSHEET.md` — "Override model" row default → `claude-opus-4-8[1m]`.

`_resume.py` is unaffected — it inherits the model from the running session's process args, never hardcodes it. `context-monitor.py`'s context-window detection keys on `"1M"`/`"opus"` in the display name, so it reports 1M for Opus 4.8 unchanged.

### Action required

`/aios:update` auto-applies the file replacements (Tier 1: `hooks/`, `plugins/aios/`, `CHEATSHEET.md`). Then, for the teammate's Claude session running the update:

1. **Re-run the wrapper installer** so the new default lands in your shell rc (this is the load-bearing step — the file change alone doesn't update your already-installed `spawn`/named-session functions):
   - macOS/Linux: `bash $HOME/aios/hooks/claude-identity/install-wrappers.sh`
   - Windows: `pwsh -File $HOME/aios/hooks/claude-identity/install-wrappers.ps1` (or `powershell -File ...` on stock Win11 — see 2026-05-27 entry). 
   
   The post-replace auto-execution rule fires this for you automatically when `install-wrappers.{sh,ps1}` is in the diff — confirm it ran (look for *"Wrappers re-installed"* in the update report).
2. **If you pin a model via `$CLAUDE_MODEL`** in your rc file, you're opted out of the default — no action; you stay on your pinned model. To adopt 4.8, update your `export CLAUDE_MODEL=...` line or remove it to take the new default.

**Restart-required (LAST):** open a new terminal so the refreshed wrapper functions activate — existing terminals hold the old `--model` flag in their function table until then.

---

## 2026-05-28 — Quiet-default autopilot + `aios/infographic-builder` skill (`/ingest` Step 6) + venture-name leak scrub

`hash: ded5e87`

> **Three ships consolidated for the day.** **(1) Autopilot redesigned: quiet by default.** The legacy kill+respawn path on quota swap is gone — sessions are no longer terminated and re-launched via osascript keystroke automation into the IDE (which caused alert beeps + focus contention on multi-session swaps, and a far worse failure mode discovered today: a single session with a malformed-image transcript could chain-burn every rotation account through the legacy auto-respawn loop). Now after a swap, `_watch.py` writes a `~/.claude/swap-notification.json` marker and `context-monitor.py` renders a minimal red `🔄 cc→j` banner at the front of every active statusLine for 3 minutes. The running session **auto-transitions to the new account on its next API turn via Keychain re-read — empirically ~30 seconds** (validated by a real cap event 2026-05-28 07:18:43). The README's prior "~1h until token refresh" claim was overly pessimistic. Opt-in env var `CLAUDE_AUTOSWAP_RESPAWN=1` preserves the legacy behavior for unattended overnight agents. **(2) New skill `aios/infographic-builder` + `/ingest` Step 6** distills a structured document into a single-file HTML one-pager with brand-aware theme selection (brand-first via venture `design.md` → fallback to [VoltAgent/awesome-design-md](https://github.com/VoltAgent/awesome-design-md)'s 73 brand design systems). **(3) Venture-name leak scrub** of `agents/aios/communication/deck-builder.md` + `plugins/aios/commands/cold-start-interview.md`; one hardcoded `~/obsidian` path replaced with `~/aios` (CI Migration-drift check passes again).

### What changed

**1. Autopilot: quiet by default (`hooks/claude-identity/_watch.py` + `context-monitor.py`)**

- **`_watch.py` no longer calls `_resume.py` on swap.** After a successful Keychain rotation, it writes `~/.claude/swap-notification.json` (`{from, to, ts, reason}`).
- **`context-monitor.py`** gets `get_swap_banner()`: if the marker is fresh (`SWAP_BANNER_TTL_SECS = 180`), prepends a red+bold `🔄 cc→j` banner to the statusLine. After 3 min, banner auto-suppresses; on the next swap, the marker is overwritten and the banner re-appears with the new from/to.
- **Legacy path preserved as opt-in:** set `CLAUDE_AUTOSWAP_RESPAWN=1` in the environment to restore the kill+`_resume.py`-respawn behavior. Only meaningful for unattended overnight agents that MUST keep working past the cap without a human-in-loop restart. For interactive use it's strictly noisier (the original alert-beep + focus-contention path).
- **README correction:** `hooks/claude-identity/README.md` § "Lessons learned the hard way" #4 claimed the running session keeps the old account's token "until the token refreshes naturally (~1h)." Empirically, Keychain re-read happens on the next API turn — ~30 seconds. The banner copy now reflects this (informational, no "restart" prescription).

**The bigger reason this shipped now — a real quota-drain failure mode it prevents:** Today's cap event surfaced a chain-burn the legacy `_resume.py` path created. A single session's transcript contained a malformed image → API returns "image could not be processed and was removed" on every turn → 78 burned turns at full cache-creation cost → account 1 capped → legacy auto-respawn fires → restarts the session into the **same broken transcript** → account 2 capped → loop. With quiet-default, the swap rotates Keychain and the loop ends — no respawn into the broken transcript, sessions are killed manually only if needed.

**2. New skill — `skills/aios/infographic-builder/SKILL.md` + `/ingest` Step 6**

A single-file skill (no `references/` — one flow, no conditional sub-modes) that composes existing capabilities (`anthropic/frontend-design` + `canvas-design`, `aios/data-presentation`, `anthropic/theme-factory`). Encodes a **7-section IA** (hero + stat callouts → narrative arc → contrasting forces → lessons → key contrast viz → quote + sources) plus a **non-negotiable fact-discipline rule** — only use what's in the source, never fabricate metrics/dates/percentages/compositional details.

**Theme hierarchy:** (1) explicit user reference → (2) brand-first via `vault/00 - notes/context/ventures/{venture}/design.md` → (3) fallback fetch from awesome-design-md (`https://raw.githubusercontent.com/VoltAgent/awesome-design-md/main/design-md/<slug>/DESIGN.md`) → (4) local theme-factory. Always tells the user which theme was picked and offers an override.

**Render checklist** requires: design tokens applied verbatim, markup generated directly (no JS template-string fill — `${placeholders}` leaks under pressure), dark/light toggle via CSS custom properties + FOUC-prevention inline script, SRI guidance for hosted/embedded use (Tailwind Play CDN acceptable only for local previews — no stable hash by design).

**`/ingest` Step 6:** after Step 5 (daily-note log), offers an opt-in infographic render via the new skill. Default output `03 - export/infographics/{YYYY-MM-DD}-{slug}.html`. Silent skip if declined or source too thin. Steps 1–5 unchanged.

**Counts refreshed:** `skills/_index.md` AIOS-bundled 16 → 17 (new Meta row); `TOOLS.md` count updated.

**3. Venture-name leak scrub (canonical hygiene + CI fix)**

- `agents/aios/communication/deck-builder.md`: `sovra-style` → `brand-locked` (3 sites); `Sovra Light Editorial` → `Light Editorial` (2 sites); the `sovragov-argentine` example slug → `acme-q1-launch`; one hardcoded `$HOME/obsidian/vault/...` path → `$HOME/aios/vault/...` (this was the trigger for the CI Migration-drift failure on commits `058a2e0`, `5c7ebe2`, `83f23b4` — now passes).
- `plugins/aios/commands/cold-start-interview.md`: `Sovra-style codebase` → `multi-repo codebase`.

### Action required

`/aios:update` auto-applies everything (Tier 1 replace for all changed files). For the teammate's Claude session running the update:

1. **`/aios:update`** — applies the new `_watch.py`, `context-monitor.py`, `deck-builder.md`, `cold-start-interview.md`, plus the morning ship (`infographic-builder/SKILL.md`, `ingest.md` Step 6, `_index.md`/`TOOLS.md` counts). The next `/ingest` invocation picks up Step 6 automatically.
2. **No action needed for default autopilot users.** The next time the autopilot rotates accounts, you'll see a red `🔄 cc→j` banner at the top of every active statusLine for 3 min; the running session keeps working on the new account automatically (Keychain re-read on the next API turn — usually within ~30 seconds).
3. **Unattended-agent users:** if you run overnight agents that need to keep working past their cap without a human-in-loop restart, set `CLAUDE_AUTOSWAP_RESPAWN=1` in those sessions' env to restore the legacy kill+respawn behavior. Leave the default for interactive use.
4. **Launchd safety-net health check.** Run `launchctl list | grep claude-quota-watch`. If empty, the agent isn't loaded — install + load it:
   ```bash
   rm -f ~/Library/LaunchAgents/com.*.claude-quota-watch.plist
   cp $HOME/aios/hooks/claude-identity/com.aios.claude-quota-watch.plist ~/Library/LaunchAgents/
   launchctl load ~/Library/LaunchAgents/com.aios.claude-quota-watch.plist
   ```
   This was a separate latent gap surfaced during the 2026-05-28 diagnosis — the stale `com.sovra.claude-quota-watch.plist` was sitting unloaded for some operators.
5. **Optional `/ingest` Step 6 personalization (never synced):** If you want venture-brand theme matching to take priority over the awesome-design-md fallback, add a `### /ingest` block to your `USER.md` documenting that preference. The default produces a polished result with no personalization.

**Restart-required:** none. `context-monitor.py` is re-invoked per statusLine refresh; `_watch.py` is re-invoked per launchd tick (or via the statusLine fast-path's `_cache.py` kick). Both pick up the new code on next invocation.

---

## 2026-05-27 — Windows install hardening v2: CRLF-safe compares, real-Python detection, PowerShell + SSH fallbacks

`hash: bdb8425`

> **Real Windows validation of yesterday's release surfaced four more silent failure modes.** The 2026-05-26 hardening was reasoned-about from macOS; running `/aios:update` end-to-end on a stock Windows 11 box exposed four gaps the Mac path can't see — all four were worked around in-session, so no vault was harmed, and all four are now fixed upstream. Theme: defaults that differ silently between macOS/Linux and Windows (line endings, the `python3` alias, which PowerShell ships, whether ssh-agent runs). Each one fails *quietly* — the operation appears to succeed while doing nothing, or adds latency without an error.

### What changed

**1. CRLF-safe content comparisons (`/aios:update`)**

- Windows Git's `core.autocrlf` rewrites LF→CRLF on checkout, so vault files carry `\r\n` while `git show {hash}:{path}` emits LF. The three-way backup-on-divergence compare (`diff -q local baseline`) then flagged **every** Tier 1 file as "differ" on byte-identical content → **11 false backups in `vault/04 - backups/` on every single sync**, draining the "your edits were preserved" report of all meaning.
- Fix: **every content comparison in `update.md` now strips `\r` before diffing** — `diff -q <(tr -d '\r' < a) <(tr -d '\r' < b)`. Applies to the three-way compare (§ Backup-on-divergence), the self-update guard (Step 2.5), and the duplicate-cleanup content-compares (§ Duplicate cleanup). A single CRLF note documents the rule once.

**2. Real-Python detection in `mcps/setup.sh` (completes the 2026-05-26 venv fix)**

- On Windows, `python3.exe` is the **Microsoft Store redirector stub** by default — invoking it opens a Store page and exits non-zero, so `python3 -m venv` no-ops while the `&& echo "✓"` chain reports success over an empty venv. This is the *first* half of the silent-install bug; yesterday's `vbin` helper fixed the *second* (`.venv/bin` vs `.venv/Scripts`) but couldn't help if the venv was never created.
- Fix: a `$PY` launcher probes `python3 → python → py -3` at script start and uses the first that actually runs (`$PY` stays unquoted so `py -3` word-splits). If none works, the script bails loudly with the exact remediation: install from python.org **and** disable the Store alias (Settings → Apps → Advanced app settings → App execution aliases → turn OFF `python.exe`/`python3.exe`). Node-only MCPs still set up regardless.

**3. PowerShell fallback (`/aios:update` post-replace auto-exec)**

- The auto-run step for the updated `install-wrappers.ps1` hard-coded `pwsh` (PowerShell 7), which is **not** installed by default — a stock Win11 ships only Windows PowerShell 5.1 (`powershell`). The installer simply failed.
- Fix: try `pwsh`, fall back to `powershell` (5.1 runs the `.ps1` unchanged).

**4. SSH→HTTPS rewrite on Git Bash (`/aios:update` clone)**

- `git@github.com:` clones assume a running ssh-agent. On Windows it usually isn't running, so every sync hung ~5-10s on the SSH timeout before the HTTPS fallback kicked in.
- Fix: detect MSYS/Cygwin (`$OSTYPE`) and rewrite `git@github.com:` → `https://github.com/` **before** cloning, skipping the timeout entirely. Non-Windows keeps the SSH-first-then-HTTPS-on-failure behavior.

### Action required

`/aios:update` auto-applies everything (`update.md` self-updates via the Step 2.5 guard; `setup.sh` is Tier 1 replace). For the teammate's Claude session running the update:

1. **`/aios:update`** — applies the CRLF-safe `update.md` (the self-update guard re-invokes with the new spec automatically) and the new `setup.sh`. From this sync forward, **Windows operators stop getting the 11-file false-backup flood.**
2. **Windows operators only — re-run `bash mcps/setup.sh`.** The `$PY` detector now creates real venvs instead of silently no-op'ing over the Store-alias stub. **Verify it worked:** each Python MCP dir should now have a non-empty `.venv/Scripts/` (`ls mcps/google-workspace-mcp/.venv/Scripts/`). If `setup.sh` prints the "No working Python found" banner, install Python from python.org and disable the Store execution alias, then re-run.
3. **Windows operators — optional cleanup:** if your 2026-05-26 sync left false backups in `vault/04 - backups/aios-update-2026-05-26/` (Tier 1 files that you never actually edited), they're safe to delete — they were CRLF false positives, not real personalizations. Spot-check one against upstream first if unsure.
4. **macOS/Linux operators:** no action — these are Windows-path fixes; your sync behavior is unchanged (the `tr -d '\r'` normalization is a no-op on LF-only files, and the SSH path is untouched on non-Windows).

**Restart-required:** none beyond the standard "open a new terminal" if the wrapper installer re-ran in step 1.

---

## 2026-05-26 — Structural consistency (templates/aios/), folder-aware cleanup, cross-platform install hardening

`hash: 9eedd2d`

> **Closes the gaps that multi-operator migration sessions surfaced this week.** Two operators independently hit the same classes of failure: (a) `templates/` was the odd layer out — bundled templates sat at the layer root while `agents/`, `skills/`, `plugins/` all used the `{layer}/aios/` + `custom/` + `<company>/` convention, so duplicate-cleanup had no clean rule for it; (b) the cleanup pass removed stray `.md` files but missed stray *directories* (pre-bundle skill folders are `{name}/` dirs, not flat files) and left hollow empty folders behind; (c) the Windows install path had three silent failure modes. This release makes one more layer consistent, makes cleanup folder-aware + empty-folder-aware, and hardens the cross-platform install. **`mcps/` and `hooks/` stay deliberately flat** (documented exemption — operator `~/.claude.json` registers absolute MCP paths and `settings.json` references hook paths directly; the blast radius of moving them isn't worth it, and the `-mcp` suffix already namespaces).

### What changed

**1. `templates/` → `templates/aios/` (structural consistency)**

- The 11 bundled templates moved from `templates/` root into `templates/aios/` (e.g. `templates/aios/about_me-template.md`), matching the `{layer}/aios/` (bundled) + `custom/` (operator) + `<company>/` (company-distributed) convention every other layer uses. `templates/_index.md` + `templates/README.md` stay at the layer root.
- Path references updated across `SETUP.md`, `START-HERE.md`, `cold-start-interview.md`, `update.md` (Tier 1 + Tier 3), and the seed `about_business.md`. CI (`validate.yml`) updated: the templates subdir check now allows `aios/` + `custom/`, and the frontmatter-validation glob is `templates/aios/*.md`.
- `_index.md` wiki-links (`[[about_me-template]]`) resolve by filename regardless of folder, so they're unchanged.

**2. Duplicate cleanup — folder-aware + empty-folder-aware (`/aios:update`)**

- **Folder-based dedup for `skills/`.** A skill is a `{name}/` directory containing `SKILL.md` — so the existing file-basename matching (every skill's file is `SKILL.md`) could never catch a stray skill folder. New step 3b: build the set of bundled skill-folder *names* (under `skills/aios|anthropic|superpowers/`), then scan `skills/*/` at root AND `skills/custom/*/` for folders matching a bundled name → stale-vs-personalized test on the folder's `SKILL.md` → remove. This is what left 60+ pre-bundle skill folders at `skills/` root after migration.
- **Empty-folder removal (new step 5).** After dup removal, `rmdir` any directory left empty (or containing only an orphaned `_index.md`). `{layer}/custom/` itself is preserved even when empty (operator namespace). Closes the "removed the files but left hollow folders" gap.

**3. Cross-platform install hardening (Windows)**

- **`install-wrappers.{sh,ps1}`: backtick-OPTIONAL USER.md identity parse.** The strict `` | `name` | `` regex silently fell back to a placeholder for operators who followed the README's plain `| name |` format. Now matches both. **Fallback name changed `claude` → `primary`** — a `claude()` shell function shadows the Claude Code CLI binary at the user prompt; `primary` never collides (and matches the spec's own doc comment).
- **`mcps/setup.sh`: cross-platform venv path** (`vbin` helper resolves `.venv/bin` on Unix, `.venv/Scripts` on Windows Git Bash). The hardcoded `.venv/bin/pip` does not exist on Windows; the `&& echo "✓"` chain short-circuited and operators saw "installed" while nothing did. Independent-block design (no `set -e`) preserved.
- **`cold-start-interview.md`: Git Bash junction branch.** `ln -s` on Git Bash silently creates a stale directory *copy* (MSYS default), not a real link — operators end up running a frozen pre-migration snapshot while the real install drifts ahead. Now detects MSYS/MINGW/CYGWIN and uses a real Windows junction (`mklink /J`). Stale `~/aios` copies flagged as CONFLICT.

**4. Hygiene + docs**

- **`.gitignore`:** added `.claude/` (operator-personal per-machine config, symmetric with `vault/.obsidian/`; framework ships none) + broadened logs to `**/*.log` so MCP debug logs don't accumulate diffs from accidental commits.
- **`mcps/_index.md`:** new "Where credentials live" section — MCP keys/tokens live in `~/.claude.json` + OAuth caches, both survive `/aios:update`/cleanup. A failed MCP is a local-state issue (stale token, missing `.venv`, port held by a stale process), not a lost-key issue — debug locally before any cloud console.
- **`mcps/google-workspace-mcp/TROUBLESHOOTING.md`** (new): the local-first Day-N recovery recipe (delete cached token → kill MCP process → retrigger → re-consent with `prompt=consent` in incognito) + Day-0 console setup + the 23-scope reference.

### Action required

`/aios:update` auto-applies everything (Tier 1 + cleanup). For the teammate's Claude session running the update:

1. **Detect OS** (`uname -s`): Darwin/Linux → bash variants; Windows → `pwsh` variants.
2. **`/aios:update`** — auto-applies all Tier 1 changes. Tier 1 brings the bundled `templates/aios/*.md`; the **recurring duplicate-cleanup pass** then (a) removes your old root-level `templates/*-template.md` copies — now duplicates of the `aios/` versions — preserving `templates/custom/` + any `templates/<company>/`, (b) removes stray pre-bundle skill folders at `skills/` root, (c) removes empty folders left behind. Net effect for templates = moved into `aios/`. Per-file log shows what was removed. (This cleanup is **general recurring logic** in `update.md` — it self-heals duplicate drift on every run; there is no one-time migration script in the command spec. The one-time steps for this release are these action items, not the command.)
3. **Infra-compare CLAUDE.md (verification — do this explicitly).** After the update, confirm the operator's `CLAUDE.md` is byte-identical to upstream and NOT a personalized leftover: `diff <(git -C /tmp/aios-upstream show HEAD:CLAUDE.md) "$HOME/aios/CLAUDE.md"` (or compare against the cloned upstream copy `/aios:update` already fetched). If they differ, the operator is on a stale or hand-edited `CLAUDE.md` — it's Tier 1 infra, so overwrite byte-identical (backup-on-divergence will have preserved any real edits to `vault/04 - backups/`). The point: `CLAUDE.md` must land as *infra* CLAUDE.md, never a user-leftover. Do the same spot-check for `README.md`, `SETUP.md`, `TOOLS.md`.
4. **Re-run the installers + verify the universal hooks are wired (not just the shell wrappers):**
   - **Shell wrappers (idempotent installer):** `bash $HOME/aios/hooks/claude-identity/install-wrappers.sh` (macOS/Linux) or `pwsh -File $HOME\aios\hooks\claude-identity\install-wrappers.ps1` (Windows). Picks up the backtick-optional USER.md parse + `primary` fallback. If your USER.md `## Identity` table uses plain `| name |` (no backticks), this is the run that finally binds your real session name instead of the placeholder.
   - **Event hooks (verify — the wrapper installer does NOT touch these). Check BOTH locations, they live in different places:**
     - `UserPromptSubmit` → `inject-datetime` ships at **project-level** `.claude/settings.json` (command form: `bash "$CLAUDE_PROJECT_DIR/hooks/inject-datetime.sh"`) — real clock injected into every prompt.
     - `statusLine.command` → `claude-identity.sh cache | context-monitor.py` lives at **user-level** `~/.claude/settings.json` — rate-limit cache + context display.
     - **Don't conclude "missing" from one file** — the datetime hook is NOT in `~/.claude/settings.json`; checking only there false-alarms (and risks adding a duplicate). Read both, and ensure each entry is present AND points at the correct current command: merge in what's missing, fix what's stale, and don't clobber unrelated settings (permissions, MCP registrations, a custom statusline). settings files are operator-personal + gitignored, so `/aios:update` can't wire them for you.
     - **Verify both fired:** open a fresh session, ask *"what's today's date?"* (datetime hook) and check the statusline shows context/quota (statusLine hook). Closes the gap where only the spawn wrappers were re-enforced on update while these could silently drift.
5. **Windows operators only:** if `ls ~/aios` shows pre-migration content (a stale directory copy, not a junction), remove it and re-create via the cold-start junction step (`cmd //c mklink /J`) or the PowerShell snippet. Then re-run `bash mcps/setup.sh` — the cross-platform venv paths now actually install instead of silently no-op'ing.

**Restart-required (LAST):** open a new terminal so the refreshed wrapper banner in your rc file activates — existing terminals hold the old function table.

---

## 2026-05-25 — Framework reorg: auto-apply /aios:update, agents/aios/ restructure, dual-write context rule

`hash: 1ae30e5`

> **Big day. Six structural shifts that consolidate the framework around one principle: *infra is infra — applied automatically, never asked.*** All were triggered by a live operator migration session that exposed three structural papercuts: (a) `/aios:update` asking operators to approve framework changes (slow, error-prone, false sense of control), (b) duplicate skills/agents leaking into `custom/` and at layer roots after every migration, (c) the flat `agents/aios-*` naming making operator-contribution flow harder than it should be. Plus polish from morning ships: cold-start wrapper refresh, claude-fallback recursion fix, and a CLAUDE.md dual-write rule for behavioral patterns.

### What changed

**1. `/aios:update` philosophy — auto-apply, never-ask (the largest behavior shift)**

- **Tier 2 (Suggest / show diff / user picks) eliminated.** Folded into Tier 1 (Mandatory Replace). `plugins/aios/commands/*` and `CLAUDE.md` are now Tier 1 — overwritten byte-identical to upstream. The "ask user before applying" flow is gone; the operator sees a report of what was done, not a multiple-choice menu.
- **Backup-on-divergence** is the safety net for operator customizations. Before overwriting any Tier 1 file that diverges from upstream, the operator's version lands in `vault/04 - backups/aios-update-{date}/{filename}`. They can salvage edits manually if needed.
- **Auto-execute scripts after replace.** When `hooks/claude-identity/install-wrappers.{sh,ps1}` is updated → the installer auto-runs. When plugin command files change → auto-sync to the 3-location plugin pipeline. Principle-based 4-class table in spec: installer/state-producer → run · plugin-sync target → cp · dep-installer → flag · library code → no action.
- **Duplicate cleanup** runs every `/aios:update` invocation (even when no upstream changes pending). Scans `{layer}/custom/*.md` for files duplicating bundled paths AND `{layer}/*.md` at layer-root for orphaned files that should be inside a bundled subfolder. **Backup-on-divergence applies** — if a custom-located file has the same name as a bundled file but DIFFERENT content (operator customized instead of renaming), the operator's version is backed up to `vault/04 - backups/aios-update-{date}/duplicates/` before removal. Byte-identical duplicates removed silently. Handles the migration-leftover symptom (`skills/<every-superpower>.md` AND `skills/superpowers/<every-superpower>.md`) without risking operator customizations.
- **Self-update auto-re-invokes** (bootstrap-safe). When `update.md` itself is in the diff: apply + sync to plugin pipeline, then auto-fire `Skill(aios:update)`. The inner run loads the new spec from the marketplace cache and processes everything cleanly. Termination guaranteed by content-comparison (after self-apply, local matches upstream → no recursion). Operator never sees a "please re-run" prompt — self-healing automatic.

**2. `agents/aios-*` restructure → `agents/aios/{bundle}/`**

- Flat naming retired. New layout: `agents/aios/{sales,strategy,finance-legal,engineering,communication,personal}/`. Cleaner mental model, easier for operator extensions and company-namespaced bundles to slot in. Mirrors the existing `skills/aios/`, `skills/superpowers/`, `skills/anthropic/` pattern.
- Agent-matching (CLAUDE.md `agents/**/{name}.md` recursive glob) works unchanged. Spawn wrapper has no hardcoded bundle paths.
- 14 docs updated to reflect the new path (README, CLAUDE, TOOLS, CHANGELOG, cold-start-interview, agents/_index, all bundle READMEs, security-engineer agent's keyword refs).

**3. CLAUDE.md polish**

- **Dual-write rule added** under § Context Hierarchy: when saving a feedback memory about behavioral patterns or operator preferences, also write to `vault/00 - notes/context/declared/working_style.md` (or about_me.md) and/or `vault/00 - notes/context/observed/preferences.md` (or patterns.md). Memory bootstraps; vault is source of truth. Tool quirks stay in memory only.
- **Light trim pass** — Agentic Culture table → compact list (10 principles preserved, prose compressed). Documentation map table → tighter columns. Vault Map structure tree → tighter comments. 429 → 410 lines, ~9.8K → ~9.1K tokens. All rules intact; verified by spot-check.

**4. Morning ships absorbed into the same date**

Earlier today shipped: (a) cold-start re-installs wrappers after Identity capture so the operator-chosen primary-session name actually binds (was: `claude()` fallback never refreshed); (b) `claude`-fallback recursion fix in `install-wrappers.{sh,ps1}` (bare `claude` would re-resolve to the function → infinite recursion; now `command claude` + `Get-Command -CommandType Application`); (c) `SARAH.md` operator-leak from the `/aios:update` denylist removed (general `{IDENTITY}.md` pattern instead).

### Action required

Two-phase rollout because the first `/aios:update` run uses your CURRENT (old) spec, then the new spec lands and takes over. Both phases are mostly automated.

**Phase 1 — current-spec run (one-time bootstrap):**

1. **Detect OS.** Check `uname -s`. If Darwin/Linux → bash variants below. If Windows → use the `pwsh` variants.
2. **`/aios:update`** — old logic. Pulls all changed Tier 1 files (the entire `agents/aios-*` → `agents/aios/{bundle}/` restructure, CLAUDE.md, README.md, TOOLS.md, CHANGELOG.md, cold-start-interview.md, all the agent-bundle READMEs). For Tier 2 (CLAUDE.md + `commands/update.md`) the old spec will ASK to approve — **approve both.** The new auto-apply spec lands at this step.
3. **Re-run the wrapper installer (idempotent safety):** `bash $HOME/aios/hooks/claude-identity/install-wrappers.sh` (macOS/Linux) or `pwsh -File $HOME\aios\hooks\claude-identity\install-wrappers.ps1` (Windows). Guarantees your shell banner is current even if a prior update brought the file but didn't run it. Safe to re-run — both installers are idempotent (timestamped backup, strip old block, append fresh).

**Phase 2 — new-spec run (auto-finishes the migration):**

4. **`/aios:update` (second invocation).** Now uses the new auto-apply spec. Tracker shows no Tier 1 changes pending (Phase 1 brought them), but the **duplicate cleanup pass runs anyway** — scans your `agents/custom/`, `skills/custom/`, `plugins/custom/`, `mcps/custom/`, `templates/custom/`, `hooks/custom/` AND each layer's top-level for files duplicating bundled paths. Auto-removes (with per-file log) any duplicates from the old flat-`agents/aios-*` era or from migration leftover. (Example shape — `skills/test-driven-development.md` alongside `skills/superpowers/test-driven-development.md`.)

**Phase 3 — restart-required step (LAST):**

5. **Open a new terminal.** The wrapper banner in `~/.zshrc` activates on shell start; existing terminals still hold the old function table. New terminal → `type {your-primary-session-name}` should resolve to the refreshed shell function with bundle-ID-based Antigravity IDE addressing.

After Phase 2, your vault is fully on the new framework: auto-apply `/aios:update`, agents/aios/ nested layout, no duplicates, fresh CLAUDE.md, fresh wrappers. Every subsequent `/aios:update` run is single-phase + auto-apply.

---

## 2026-05-24 — spawn wrapper: bundle-ID-based Antigravity IDE addressing (post-rename)

`hash: 11017df`

> **What broke.** After Antigravity's 2026-05 update, the IDE moved to a new bundle (`Antigravity IDE.app`, bundle ID `com.google.antigravity-ide`) whose main process is stock Electron (`comm = "Electron"`). The legacy `Antigravity.app` (bundle ID `com.google.antigravity` — a separate Claude-app product) often remains installed alongside. The spawn wrapper's detection used `pgrep -xq "Antigravity IDE"` (never matches — main process is Electron) with a fallback to `pgrep -xq "Antigravity"` (matches the legacy bundle). Result: AppleScript routed keystrokes to the wrong app → System Events rejected them → audible system beeps, no new terminal opened.
>
> **Fix.** Detection now uses `pgrep -fq "Antigravity IDE.app/Contents/"` (path-based, robust to process-name changes). AppleScript addressing now uses `tell application id "com.google.antigravity-ide"` + `tell (first process whose bundle identifier is "…")` — bundle ID is stable across renames, won't collide with the legacy Claude-app bundle.
>
> **Why this matters now.** Anyone running Antigravity IDE on macOS will hit silent spawn failures (beep, no tab) until they pull this fix. The legacy `Antigravity.app` is supported as a fallback for operators still on the pre-rename install.

### What changed

- `hooks/claude-identity/install-wrappers.sh` — detection (lines 282-301) + AppleScript generation (lines 321-338). Two-part fix: path-based detection + bundle-ID addressing.

### Action required

Run on every macOS machine using Antigravity IDE. Hard precondition: the operator is on macOS. Skip everything below for Windows / Linux operators (their `install-wrappers.ps1` doesn't use AppleScript and isn't affected).

1. **Detect.** Check `uname -s`. If not `Darwin`, skip the rest of this entry.
2. **Pull.** `/aios:update` has already replaced `hooks/claude-identity/install-wrappers.sh` (Tier 1). No further file action needed — just verify the new detection block is present: `grep -q 'pgrep -fq "Antigravity IDE.app/Contents/"' ~/aios/hooks/claude-identity/install-wrappers.sh && echo "✓ fix present" || echo "❌ fix missing, re-run /aios:update"`.
3. **Re-install wrappers (LAST — requires new terminal).** Run `bash ~/aios/hooks/claude-identity/install-wrappers.sh`. This refreshes `~/.zshrc`. Then **the operator opens a new terminal** for the change to take effect (the wrapper function is loaded at shell start). Verify in the new terminal: `type spawn` should show a shell function, and `spawn test-bundle-fix "say /exit"` should open a new IDE tab cleanly with no beeps.

---

## 2026-05-23 — Migration playbook: existing operators move from old framework to The-AIOS/aios

`hash: bc80cf1`

> **Read this entry top-to-bottom before executing anything.** It is the single migration playbook for any operator on the pre-extraction framework structure (`{user}/aios` template or `{org}/internal-vault` team repo, both frozen at hashes ≤ 2026-05-21). The framework was extracted to a public canonical at `github.com/The-AIOS/aios`. This entry walks you through the full migration in **dependency-sorted phases (Phase 0 → Phase 9 + LAST)**. Later phases assume earlier phases succeeded.
>
> **Note to the Claude session executing this playbook — be sharp, not robotic.** This playbook was crafted across multiple dry-runs (real sandbox migrations, real operator pushback, real catches). It encodes lessons that aren't visible from the surface text — phase ordering is load-bearing, the `cp -Rn` vs `mv` distinction in Phase 2.5 is collision-aware on purpose, the "Phase 0 first" rule survived three attempts to shortcut it. **Don't skip phases that look redundant** — most of them caught a real failure during testing. But also **don't follow blindly** — adapt the bash/PowerShell commands to the operator's actual environment (their detected `$VAULT_PATH`, their shell, their OS), surface anything that doesn't fit their situation, and **stop to ask whenever you're unsure** rather than guessing. The playbook tolerates pauses gracefully (every phase is reentrant); it does NOT tolerate silent skips or blind execution. If a command's intent is clear but its mechanics don't fit (e.g., operator is on PowerShell but only the bash variant is shown for that one micro-step), translate using your judgment + the patterns already established in earlier phases. If the intent itself isn't clear, surface it.
>
> **One non-negotiable rule, baked into Phase 0:** the operator's content is sacred. `USER.md`, `INTENT.md`, `SARAH.md`, everything under `vault/`, and every `{layer}/custom/` extension MUST survive the migration intact. The migration replaces *framework* infrastructure (spec files, bundled agents/skills/hooks/mcps/templates, plugin manifests, tracker file). It must NOT touch operator content. Phase 0 takes a safety snapshot. Every later phase respects the sacred-files denylist. If a step looks like it might overwrite operator content, **stop and ask** — never silently proceed.

### State

The pre-extraction framework structure (`{user}/aios` + `{org}/internal-vault`, three-repo topology) is frozen. Going forward the canonical infrastructure lives in three public repos under [The-AIOS](https://github.com/The-AIOS):

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
Phase 0    (Safety snapshot + vault-path detection — MANDATORY, zero-mutation)
  ↓
Phase 1    (Symlink creation — first structural change, using path from Phase 0)
  ↓
Phase 2    (Tracker rename + repoint at The-AIOS/aios)
  ↓
Phase 2.5  (Vault structure normalization — moves operator extensions to {layer}/custom/,
            renumbers vault folders surgically with collision-aware merge)
  ↓
Phase 4    (Plugin cache invalidation — uninstall vault-commands@local, add the-aios
            marketplace, install aios@the-aios. This makes /aios:update available.)
  ↓
Phase 5    (Framework cascade via /aios:update — now-installed plugin provides the
            command; cascade lands canonical files into the vault)
  ↓
Phase 3    (Spawn wrappers — re-install using the NOW-canonical install-wrappers.sh
            that Phase 5 just cascaded into the vault)
  ↓
Phase 6    (USER.md schema migration: ## Organization → ## Companies (mounted))
  ↓
Phase 7    (Vault scaffold restoration — empty subfolder placeholders)
  ↓
Phase 8    (Men-in-Black memory wipe — comprehensive old-world reference cleanup)
  ↓
Phase 8.5  (New day rising — onboarding-aios catch-up walkthrough, optional)
  ↓
Phase 8.6  (Venture-context mount — REQUIRED if you came from a team-vault distribution)
  ↓
Phase 9    (Discovery surface awareness — informational)
  ↓
Phase 9.7  (Tier B observation catch-up — REQUIRED for every operator, content-driven;
            synthesis of accumulated growth/profile/ecosystem content from
            session-insights + antifragile + daily notes. Substance bar self-
            regulates: fresh vaults write nothing, heavy-backlog vaults catch
            up the accumulated drift)
  ↓
LAST       (Restart Claude Code for plugin daemon reload)
```

The Claude session executing this playbook MUST follow the execution-order arrows, not the phase-number sequence. **The Phase 4 → Phase 5 → Phase 3 ordering is load-bearing:** Phase 4 installs `aios@the-aios` which provides the `/aios:update` command. Phase 5 calls `/aios:update`. Phase 3 needs the cascaded `hooks/claude-identity/install-wrappers.sh` from Phase 5. Run them in any other order and you'll hit "command not found" or install stale scripts.

**Exit codes are NOT load-bearing on their own.** Every phase's bash block runs in a subshell spawned by Claude's `Bash` tool — `exit 1` ends that subshell, not the migration. When a phase's STOP guard fires (non-zero exit, dirty git status, vault-not-detected, collision-remaining), the executing Claude session MUST notice the failure signal in the tool output and refuse to advance to the next phase until the operator resolves it. **Read every Bash result before moving on. If a phase printed `⚠️` or `STOP` — stop.**

---

#### Phase 0 — Safety snapshot + vault-path detection (MANDATORY, do this first)

**State:** The operator's current vault has content that must survive. Phase 0 is intentionally **zero-mutation**: detect where the vault lives + tag the current state so recovery is one git command away. No structural changes happen until Phase 1.

**Why split detection (here) from symlink (Phase 1):** the safety tag should be taken on the IMMUTABLE state — before any structural change. Detection is observation; the symlink is the first action. Two distinct concerns.

**Ask:**
> *"Before I touch anything: (1) I'll detect where your vault lives by scanning common locations, (2) tag the current state as `pre-aios-migration-{YYYY-MM-DD}`, (3) verify your sacred files (USER.md, INTENT.md, SARAH.md if present, CLAUDE.md) are all tracked + committed. If anything's uncommitted, I'll surface it and stop until you decide. OK to proceed?"*

**Act:**

```bash
# --- A. Detect vault path (no changes, pure observation) ---
VAULT_PATH=""
[ -e "$HOME/aios/vault/01 - calendar" ] && VAULT_PATH="$HOME/aios"
[ -z "$VAULT_PATH" ] && [ -e "$HOME/obsidian/vault/01 - calendar" ] && VAULT_PATH="$HOME/obsidian"

# Fallback: scan common alternative locations
[ -z "$VAULT_PATH" ] && for try in \
    "$HOME/code/internal-vault" "$HOME/internal-vault" \
    "$HOME/code/aios" "$HOME/Documents/aios" "$HOME/Documents/obsidian" \
    "$HOME/code/{org}/internal-vault" "$HOME/code/{user}/aios"; do
  [ -e "$try/vault/01 - calendar" ] && VAULT_PATH="$try" && break
done

if [ -z "$VAULT_PATH" ]; then
  echo "⚠️  Could not detect your vault root."
  echo "    Scanned: ~/aios, ~/obsidian, ~/code/{internal-vault,aios,{org}/internal-vault,{user}/aios},"
  echo "             ~/internal-vault, ~/Documents/{aios,obsidian}"
  echo ""
  echo "    STOP. Tell Claude the absolute path to your vault root (the folder containing"
  echo "    'vault/' + USER.md + .vault-update). Claude will set VAULT_PATH manually and"
  echo "    resume from this phase. Don't guess — wrong path silently corrupts the migration."
  exit 1
fi

echo "✓ Detected vault root: $VAULT_PATH"
echo "VAULT_PATH=$VAULT_PATH" > /tmp/aios-migration-state.env  # subsequent phases read from here

cd "$VAULT_PATH"

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

**State:** Phase 0 detected your vault path (`$VAULT_PATH`). The framework references `~/aios/` everywhere. If `$VAULT_PATH` is already `~/aios`, no action needed. Otherwise create a symlink so every later phase's `~/aios/...` reference resolves.

**Ask:**
> *"Your vault is at `{$VAULT_PATH}`. {If already ~/aios → silent pass}. {Else → I'll create a symlink `~/aios → {$VAULT_PATH}`. Non-destructive, reversible (`rm ~/aios` to undo), zero risk to your Obsidian app workspace state. OK?}"*

**Act:**

```bash
source /tmp/aios-migration-state.env  # picks up VAULT_PATH from Phase 0

# If already at ~/aios → silent pass
[ "$VAULT_PATH" = "$HOME/aios" ] && echo "✓ ~/aios already resolves" && exit 0
```

Then run the OS-appropriate symlink command:

**macOS / Linux / WSL / Git Bash:**
```bash
ln -s "$VAULT_PATH" "$HOME/aios" && ls -la "$HOME/aios" | head -1
```

**Windows PowerShell** (requires Developer Mode — one-time Win 10+ toggle):
```powershell
New-Item -ItemType SymbolicLink -Path "$HOME\aios" -Target $VAULT_PATH
```

**Windows CMD fallback** (no admin needed; directory junction; same-volume only):
```cmd
mklink /J "%USERPROFILE%\aios" "<your VAULT_PATH>"
```

Verify (any shell):
```bash
test -e "$HOME/aios/vault/01 - calendar" && echo "✓ ~/aios resolves to vault content"
```

---

#### Phase 2 — Tracker rename + repoint: `.vault-update` → `.aios-update`

**State:** The OLD framework uses `.vault-update` at the vault repo root, with `repo=` pointing at the old team repo (typically `git@github.com:{org}/internal-vault.git` for team members or `git@github.com:{user}/aios.git` for solo operators). The NEW framework reads `.aios-update` and expects `repo=git@github.com:The-AIOS/aios.git`.

**Ask:**
> *"Renaming the tracker file from `.vault-update` to `.aios-update` and repointing the `repo=` field at the public canonical `git@github.com:The-AIOS/aios.git`. The hash field stays at `initial` so the next `/aios:update` does a full comparison — that's intentional, it lets the new gate verify your local matches canonical even though most files do (since both repos descend from the same lineage). OK?"*

**Act:**

**macOS / Linux / WSL / Git Bash:**
```bash
cd "$HOME/aios"

# Rename + repoint
[ -f ".vault-update" ] && mv .vault-update .aios-update && echo "✓ .vault-update → .aios-update"

# Rewrite the repo URL + reset hash to 'initial'
cat > .aios-update << EOF
repo=git@github.com:The-AIOS/aios.git
hash=initial
synced=$(date +%Y-%m-%d)
EOF
echo "✓ .aios-update repointed at The-AIOS/aios"
cat .aios-update
```

**Windows PowerShell:**
```powershell
Set-Location "$HOME\aios"

# Rename + repoint
if (Test-Path .vault-update) { Move-Item .vault-update .aios-update }

# Rewrite tracker
@"
repo=git@github.com:The-AIOS/aios.git
hash=initial
synced=$(Get-Date -Format 'yyyy-MM-dd')
"@ | Set-Content -Path .aios-update -Encoding UTF8 -NoNewline
Write-Host "✓ .aios-update repointed at The-AIOS/aios"
Get-Content .aios-update
```

**Verification (any shell):**
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

# --- C. Renumber vault asset + export folders (SURGICAL — operator may have custom subfolders) ---
#
# These vault folders hold OPERATOR CONTENT, not framework canonicals. Renaming them must
# preserve every file + subfolder, including operator-custom organization. Collision case:
# operator may already have BOTH old + new locations (e.g., they migrated partially before,
# or framework auto-created the new one at some point). In that case, MERGE — never overwrite.

# Helper: surgical move that handles collision by recursive merge
surgical_move() {
  local SRC="$1"
  local DST="$2"
  if [ ! -d "$SRC" ]; then return 0; fi
  if [ ! -d "$DST" ]; then
    mv "$SRC" "$DST"
    echo "✓ $SRC/ → $DST/ (clean move)"
  else
    # Collision: merge SRC contents into DST. Use rsync-style recursive copy + verify before delete.
    echo "⚠ Both $SRC/ and $DST/ exist — merging contents."
    # Copy with -n (no-clobber) so DST's existing content wins on filename collision
    # Then remove SRC files that were copied; leave any non-copied (collisions) for operator review
    cp -Rn "$SRC"/. "$DST"/
    # Identify what was merged vs what stayed in SRC (didn't make it because of collisions)
    REMAINING=$(find "$SRC" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$REMAINING" = "0" ]; then
      rm -rf "$SRC"
      echo "✓ $SRC/ contents merged into $DST/ (clean)"
    else
      echo "⚠ $SRC/ still has $REMAINING files (filename collisions with $DST/). Operator must review + decide manually."
      echo "  Files in $SRC/ that didn't merge:"
      find "$SRC" -type f | head -20
      echo "  STOP here. Operator picks per-file. Recover via Phase 0's safety tag if needed."
    fi
  fi
}

surgical_move "vault/03 - assets"  "vault/02 - assets"
surgical_move "vault/04 - export"  "vault/03 - export"

# vault/05 - logs/ → vault/00 - notes/logs/ (special: target may exist as the new logs canonical)
if [ -d "vault/05 - logs" ]; then
  mkdir -p "vault/00 - notes/logs"
  # Same surgical merge pattern
  cp -Rn "vault/05 - logs"/. "vault/00 - notes/logs"/
  REMAINING=$(find "vault/05 - logs" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$REMAINING" = "0" ]; then
    rm -rf "vault/05 - logs"
    echo "✓ vault/05 - logs/ → vault/00 - notes/logs/ (clean)"
  else
    echo "⚠ vault/05 - logs/ still has $REMAINING files; operator must review."
  fi
fi
```

**Operator content posture**: this phase treats EVERY file inside the renumbered vault folders as operator content. No files get deleted, even on collision — they get *surfaced* for operator review. The safety tag from Phase 0 is your insurance if the merge result is wrong. Subfolders (operator-custom organization) survive the move because `cp -Rn` is recursive.

**Windows PowerShell equivalent** (for operators using PowerShell instead of Git Bash):

```powershell
# Move operator extensions to {layer}/custom/ — preserves files; per-file ErrorAction so
# filename collisions don't halt the move, allowing later inspection.
New-Item -ItemType Directory -Force -Path "agents/custom","templates/custom" | Out-Null

if (Test-Path "vault/02 - templates") {
  Get-ChildItem "vault/02 - templates" -File -Filter *.md | Move-Item -Destination "templates/custom/"
  Get-ChildItem "vault/02 - templates" -Directory | Move-Item -Destination "templates/custom/"
  Remove-Item "vault/02 - templates" -Recurse -ErrorAction SilentlyContinue
}
if (Test-Path "vault/06 - agents") {
  Get-ChildItem "vault/06 - agents" -File -Filter *.md | Move-Item -Destination "agents/custom/"
  Get-ChildItem "vault/06 - agents" -Directory | Move-Item -Destination "agents/custom/"
  Remove-Item "vault/06 - agents" -Recurse -ErrorAction SilentlyContinue
}
if (Test-Path "commands") { Remove-Item "commands" -Recurse -Force }

# Vault folder renumbering — surgical: only move if destination empty, otherwise merge
function Surgical-Move($src, $dst) {
  if (-not (Test-Path $src)) { return }
  if (-not (Test-Path $dst)) {
    Move-Item $src $dst
  } else {
    Copy-Item "$src\*" $dst -Recurse -Force:$false -ErrorAction SilentlyContinue
    $remaining = (Get-ChildItem $src -File -Recurse).Count
    if ($remaining -eq 0) { Remove-Item $src -Recurse } else { Write-Warning "$src still has $remaining files — review collisions manually" }
  }
}
Surgical-Move "vault/03 - assets" "vault/02 - assets"
Surgical-Move "vault/04 - export" "vault/03 - export"
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

**Post-Phase-5 cleanup hint** — after Phase 5 lands canonical agents into `agents/aios-*/` bundles, `agents/custom/` will likely contain duplicates (the legacy bundled agents that this phase preserved defensively). Surface the duplicate list for operator review:

```bash
# Build set of canonical agent basenames from the new aios-* bundles
CANONICAL=$(find agents -mindepth 2 -maxdepth 2 -path "*/aios-*/*.md" -type f -exec basename {} \; | sort -u)

# Find custom files whose basename matches a canonical
echo "Duplicates in agents/custom/ that have canonical counterparts in agents/aios-*/:"
find agents/custom -maxdepth 1 -type f -name "*.md" | while read f; do
  base=$(basename "$f")
  if echo "$CANONICAL" | grep -qx "$base"; then
    echo "  ⚠️ $f  ↔  agents/aios-*/{...}/$base"
  fi
done
```

Operator decides per-file: delete the `custom/` copy (canonical wins), keep it (operator had local edits to preserve), or rename it (it's a fork they want to keep separate). Don't auto-delete — operator authority is the calibration.

---

#### Phase 3 — Spawn wrappers + universal hooks (re-install)

> **Important ordering note:** Phase 3 runs AFTER Phase 5 brings the canonical `hooks/claude-identity/install-wrappers.sh` into the operator's vault. Running it before Phase 5 would install the OLD wrapper script. The migration's Phase 5 → Phase 3 ordering ensures the operator installs the canonical wrapper exactly once.

**State:** Pre-extraction wrappers shipped under a different path + lacked the `--model` flag injection, the `pgrep -xq` IDE-detection fix, and the `spawn-kill` pgrep-tolerance update. The current canonical installer is `hooks/claude-identity/install-wrappers.sh` — idempotent, timestamped-backup, auto-rollback on failure.

**Ask:**
> *"Re-running the wrapper installer at `~/aios/hooks/claude-identity/install-wrappers.sh`. This is idempotent: it backs up your `~/.zshrc` (timestamped) and reinstalls the canonical wrapper block. After it lands, your `spawn` will inject `--model claude-opus-4-7[1m]` by default; `spawn-kill` will match cmdlines with `--model`; IDE detection will use `pgrep -xq` (no Cursor false-positives). OK to run?"*

**Act:**

**macOS / Linux / WSL / Git Bash:**
```bash
bash "$HOME/aios/hooks/claude-identity/install-wrappers.sh"

# Verify in interactive zsh (wrappers load on shell startup)
zsh -i -c 'type spawn spawn-kill _claude_with_respawn 2>&1 | head -3'
```

**Windows PowerShell** (uses the `.ps1` installer that ships alongside the `.sh`):
```powershell
& "$HOME\aios\hooks\claude-identity\install-wrappers.ps1"

# Verify (wrappers load in PowerShell profile after install)
powershell -NoProfile -Command "Get-Command spawn,spawn-kill 2>&1 | Select Name,CommandType"
```

**Universal event hooks** (UserPromptSubmit, etc.) are wired via `~/aios/.claude/settings.json`. If your `.claude/settings.json` was committed in the old framework, it's now operator-personal (per the new `.claude/` denylist). Verify the hooks paths still resolve at `~/aios/hooks/...`. The installer doesn't touch `.claude/settings.json` — that's operator-personal.

---

#### Phase 4 — Plugin cache invalidation: `vault-commands@local` → `aios@the-aios`

**State:** Pre-extraction, slash commands shipped under the `vault-commands:` plugin namespace (e.g., `/vault-commands:today`, `/vault-commands:close-day`). Post-extraction, the namespace is `aios:` (e.g., `/aios:today`). Your local Claude Code cache at `~/.claude/plugins/` may still hold the OLD `vault-commands` plugin source — at best it's dead weight, at worst it causes namespace collisions. AND: the pre-extraction `{user}/aios` template + `{org}/internal-vault` team-vault both shipped `vault-commands` as a **local plugin** (no marketplace registration). The new `aios@the-aios` plugin lives on a **marketplace** that must be added before install will resolve.

**Ask:**
> *"I need to (a) uninstall the legacy `vault-commands@local` plugin if it's still registered, (b) add the `the-aios` marketplace (one-time per machine — the new framework canonical), (c) install `aios@the-aios` from that marketplace, (d) verify the new plugin landed. The new plugin pulls from `The-AIOS/aios/plugins/aios/`. OK?"*

**Act:**

```bash
# Inspect current state
claude plugin list 2>&1 | grep -E "vault-commands|aios" || true
claude plugin marketplace list 2>&1 | grep the-aios || true

# Remove legacy plugin if present (operator-confirm before destructive op)
claude plugin uninstall vault-commands@local 2>/dev/null || true

# Add the canonical marketplace. The CLI takes ONE positional arg <source>;
# the marketplace name is derived from the repo's .claude-plugin/marketplace.json
# (registers as "the-aios"). Idempotent — re-adding is a no-op.
claude plugin marketplace add https://github.com/The-AIOS/aios.git

# Verify marketplace landed BEFORE attempting install — install fails silently otherwise
claude plugin marketplace list | grep -q the-aios || {
  echo "⚠️ STOP — the-aios marketplace did not register. Cannot install aios plugin."
  echo "   Check: claude plugin marketplace list"
  echo "   Likely cause: stale Claude Code version (need 0.2+) or network/auth failure."
  exit 1
}
echo "✓ the-aios marketplace registered"

# Install / refresh the plugin from the now-registered marketplace
claude plugin install aios@the-aios

# Verify plugin landed
claude plugin list | grep -q "aios@the-aios" || {
  echo "⚠️ STOP — aios plugin did not install. /aios:* commands will be missing."
  exit 1
}
echo "✓ aios plugin installed from the-aios"
```

If `claude plugin install aios@the-aios` reports "marketplace not found," the `marketplace add` step didn't take — re-run it explicitly, check `claude plugin marketplace list`, then retry install. Don't skip verification: silent install failure surfaces as missing `/aios:*` commands in Phase 5, with no clear cause.

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
- Team repo: git@github.com:{org}/internal-vault.git
- Venture folder: vault/00 - notes/context/ventures/{venture}/

+ ## Companies (mounted)
+
+ > Each mounted company has its own venture folder + substrate config.
+ > `/aios:company` reads this table to know what to sync.
+
+ | Company | Substrate | Source | Venture folder | Last sync |
+ |---|---|---|---|---|
+ | {venture} | github | `git@github.com:{org}/{venture}-context.git` | `vault/00 - notes/context/ventures/{venture}/` | YYYY-MM-DD |
```

**Note:** if the operator's old team repo was `{org}/internal-vault`, the new pointer is `{org}/{venture}-context` (the new venture-context repo). The team repo's content was split: framework → `The-AIOS/aios`, venture-specific → `{org}/{venture}-context`. If they don't have access to {org}/{venture}-context yet, leave the URL empty and ask them to request access; the row can still register the venture folder for local-only use.

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

Run via Claude's `Bash` tool — works identically on macOS, Linux, and Windows (Git Bash, the AIOS-standard shell on Windows).

---

#### Phase 8 — The "Men in Black" memory wipe (comprehensive old-world cleanup)

**State:** Claude's auto-memory (under `~/.claude/projects/{cwd-slug}/memory/`) accumulated references across months of operator work that point at the OLD framework structure: legacy plugin namespace (`vault-commands:*`), legacy command names (`/vault-update`), legacy tracker filename (`.vault-update`), legacy paths (`~/obsidian/`, `vault/02 - templates/`, `vault/06 - agents/`, etc.), legacy team-repo references (`{org}/internal-vault`), and legacy plugin install names (`vault-commands@local`). Future Claude sessions reading these stale references will follow dead pointers and feel disoriented.

This phase is the **neuralyzer flash** — wipe the old-world references so memory aligns with the new structure. Pure mechanical rewriting; no semantic change to the lessons themselves.

**Ask:**
> *"Auto-memory has accumulated old-world references — legacy plugin namespace, command names, tracker filename, paths, vault structure, team-repo pointers. I'll do a comprehensive sweep + show you the affected files before applying. Mechanical rewriting only; the lessons in the memory entries stay intact, just their pointers update. OK?"*

**Act:**

```bash
MEM_DIR="$HOME/.claude/projects"

# --- A. Surface ALL legacy patterns in one scan ---
echo "Files with legacy references in auto-memory:"
grep -rln \
  -e "vault-commands:" \
  -e "vault-commands@local" \
  -e "/vault-update" \
  -e "\.vault-update" \
  -e "~/obsidian/" \
  -e "vault/02 - templates" \
  -e "vault/06 - agents" \
  -e "vault/05 - logs" \
  -e "vault/03 - assets" \
  -e "vault/04 - export" \
  -e "{org}/internal-vault" \
  -e "{user}/aios" \
  "$MEM_DIR" 2>/dev/null | sort -u
```

Show the operator the affected files. Then with confirmation, apply the full rewrite — this is Claude wiping its OWN auto-memory store, run via the `Bash` tool (Git Bash on Windows, native bash on macOS/Linux):

```bash
find "$MEM_DIR" -name "*.md" -type f -exec sed -i.bak \
  -e 's|vault-commands:|aios:|g' \
  -e 's|vault-commands@local|aios@the-aios|g' \
  -e 's|/vault-update|/aios:update|g' \
  -e 's|\.vault-update|.aios-update|g' \
  -e 's|~/obsidian/|~/aios/|g' \
  -e 's|vault/02 - templates|templates|g' \
  -e 's|vault/06 - agents|agents|g' \
  -e 's|vault/05 - logs|vault/00 - notes/logs|g' \
  -e 's|vault/03 - assets|vault/02 - assets|g' \
  -e 's|vault/04 - export|vault/03 - export|g' \
  -e 's|{org}/internal-vault|The-AIOS/aios|g' \
  -e 's|{user}/aios|The-AIOS/aios|g' \
  {} \;
echo "✓ memory wiped of old-world references"
echo "  .bak files preserved at *.bak in $MEM_DIR — verify with: find $MEM_DIR -name '*.md.bak'"
echo "  Once verified, remove with: find $MEM_DIR -name '*.bak' -delete"
```

**Important exceptions** — leave these untouched:
- `feedback_aios_namespace.md` (if present) — explicitly documents the rename; the literal "vault-commands:" inside it is *describing history*, not asserting current state.
- Any memory entry literally named or describing "pre-extraction" / "migration" / "framework rename" — these are documentation of the journey, not stale pointers.

Detect-skip these by checking the filename + content header. Spot-check the `.bak` files before final delete.

**Optional auxiliary cleanup** — same regex set applied to operator vault content:

```bash
# Operator vault content (daily notes, projects, reflections) may reference old patterns too
# Same sed batch, but the operator owns this content — APPLY ONLY WITH EXPLICIT YES per-file.
# This is more risky than the auto-memory wipe because vault content is operator-authored.
# Recommend: surface the file list + line numbers, let operator review case-by-case.

echo ""
echo "OPTIONAL: vault content with legacy references (operator's call per-file):"
grep -rln \
  -e "vault-commands:" \
  -e "/vault-update" \
  -e "vault/02 - templates" \
  -e "vault/06 - agents" \
  "$HOME/aios/vault" 2>/dev/null | sort -u
```

Operator decides per-file whether to rewrite — many vault references are historical (a daily note from March references "/vault-update", that's still correct in the historical context). The rule of thumb: rewrite EXECUTABLE references (project notes describing how to run things), leave HISTORICAL references (daily-note captures of what happened that day).

---

#### Phase 8.5 — New day rising 🌅

**State:** Old-world references are gone. The framework canonical is in place. Operator content is preserved with safety tags. Migration is structurally complete.

**Ask:** *"Migration done. Want me to spawn `onboarding-aios` to walk you through what's new? Or skip — you'll discover the new capabilities organically as `/today` surfaces them."*

**Act:** Operator's call. If they accept:

```bash
spawn onboarding-aios "Welcome me back — I just finished migrating from the OLD framework. Walk me through what's changed at the framework level."
```

The onboarding-aios agent will detect this is a returning-operator (sees old daily notes + working observed context), not a Day-0 fresh-install, and calibrate accordingly — focusing on what's *new* since the operator's pre-migration state rather than walking them through Day-1 basics they already know.

**Sign-off line** (in the operator's voice — Claude session adapts based on USER.md voice anchors):

> *"You're on the post-extraction AIOS now. Same vault, same daily rhythm, new framework canonical. Your `/today` tomorrow morning will look + feel almost the same — just running on cleaner pipes. Welcome back."*

---

#### Phase 8.6 — Venture-context mount (conditional — content-driven detection)

**State:** Pre-extraction, venture content (positioning, gtm, pricing, primitives, sales templates, venture-specific agents like `{venture}-{role}`) sometimes shipped INSIDE a team-vault repo (e.g. `{org}/internal-vault` bundled venture content). Post-extraction, venture content lives in its own per-venture repo (`{org}/{venture}-context`) and gets mounted into the vault as a namespaced bundle under `{layer}/{venture}/`. The mount step is what keeps that content synced with canonical going forward.

**Crucial distinction — this phase is for VAULTS WITH VENTURE CONTENT, not for any specific lineage:**
- A **team-vault clone** (e.g. from `{org}/internal-vault`) carries bundled venture content from before extraction → has unmounted venture content → needs mount
- A **personal-template clone** (e.g. from `{user}/aios`) is a clean personal vault with no bundled company → no venture content to mount → this phase no-ops
- A multi-machine operator's second clone with no bundled venture → no-ops

Mounting is per-vault, per-venture, and **per operator's intent**. Personal vaults stay personal. Don't mount company infra into a personal vault.

**Detect (content-driven, lineage-blind):**

```bash
cd "$HOME/aios"
VENTURES_DIR="vault/00 - notes/context/ventures"

UNMOUNTED=()
if [ -d "$VENTURES_DIR" ]; then
  find "$VENTURES_DIR" -mindepth 1 -maxdepth 1 -type d | while read v; do
    name=$(basename "$v")
    # A venture is "mounted" iff a sync tracker exists at .{name}-sync
    if [ ! -f ".${name}-sync" ]; then
      files=$(find "$v" -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
      [ "$files" -gt 0 ] && echo "$name"
    fi
  done > /tmp/aios-unmounted-ventures.txt
fi

if [ ! -s /tmp/aios-unmounted-ventures.txt ]; then
  echo "✓ No unmounted venture content detected. Phase 8.6 skipped — this vault has no company infra to sync."
  exit 0
fi

echo "⚠ Unmounted venture content detected (will drift from canonical):"
cat /tmp/aios-unmounted-ventures.txt | sed 's/^/  - /'
```

If the script prints "✓ No unmounted venture content detected" → **skip this phase entirely**. Operator has nothing to mount. Personal-template lineage operators will see this skip — that's the correct behavior.

**Ask (only if unmounted ventures were detected):**
> *"Your vault has unmounted venture content at `vault/00 - notes/context/ventures/{venture}/` for: `{list-from-detection}`. This content is currently a frozen snapshot from before the framework extraction. To keep it synced with canonical going forward, mount each venture via `/aios:company --mount <venture-context-url>`. Tell me the venture-context repo URL for each venture you want to sync (e.g. `git@github.com:{org}/{venture}-context.git` for your venture). If you don't want any of these synced (e.g. you no longer work on that venture), I can leave the frozen snapshot in place — it'll keep working, just won't get updates."*

**Act:** Per venture the operator names with its URL, run:

```bash
/aios:company --mount <venture-context-url>
```

`/aios:company --mount`:
- Clones the venture-context repo under `vault/00 - notes/context/ventures/{venture}/` (merges with operator's pre-existing content per its own conflict-resolution)
- Cascades any shipped infra into namespaced locations: `agents/{venture}/`, `plugins/{venture}/`, `templates/{venture}/`, etc.
- Writes a per-venture tracker (`.{venture}-sync`) so `/today` can later detect upstream changes
- Auto-fires the bundle's `onboarding-{venture}` agent for the HR-Day-1 welcome
- Surfaces any `agents/custom/{...}/{name}.md` files that now duplicate canonical `agents/{venture}/{...}/{name}.md` — operator decides per-file (keep custom if forked, delete custom if redundant)

**Verification:**
```bash
# For each mounted venture, both should exist
ls .{venture}-sync && ls "vault/00 - notes/context/ventures/{venture}" | head -5
```

**If the operator declines to mount a detected venture:** the frozen content stays in place. `/today` will not re-prompt every day; the operator can mount later via `/aios:company --mount` whenever they're ready. The phase's job is to surface the choice, not force it.

---

#### Phase 9 — Discovery surface awareness (informational)

**State:** Several new framework pieces landed that the operator may not know to use yet:

| New capability | What it does | Where to learn |
|---|---|---|
| `/aios:company --create \| --mount \| --sync` | Multi-venture context distribution | `CHEATSHEET.md §1` + `plugins/aios/commands/company.md` |
| `/aios:collaborate` | Shared work spaces (substrate-pluggable: Drive/GitHub/local) | `CHEATSHEET.md §1` |
| `onboarding-aios` agent | Day-0 framework orientation, programmatic-trigger from /today first-run | `agents/aios/personal/onboarding-aios.md` |
| `onboarding-{company}` agents | Per-company HR-Day-1 (ships in every venture-context repo) | `agents/onboarding-{company}.md` in mounted bundles |
| `/aios:cold-start-interview` | Ritualized Day-0 setup with auto-onboarding handoff | `plugins/aios/commands/cold-start-interview.md` |
| CI gates on framework + venture-context repos | 6-job (framework) / 5-job (context) validation on PRs | Their respective `.github/workflows/validate.yml` |
| Antifragile #61 — `gh pr checkout` cross-repo hijack rule | Don't `gh pr checkout` from inside your vault — pulls foreign content into your working tree | `vault/00 - notes/context/observed/antifragile.md#61` (operator-personal) — universal lesson for any operator with multi-repo workflows |
| `.claude/` + `vault/.obsidian/` are now fully operator-personal | Never overwritten by `/aios:update`; gitignored | `/aios:update` operator-personal denylist |
| Multi-machine operators: re-run this playbook on each machine | If you have a SARAH.md (Mac mini / second-machine setup), the migration is per-machine — symlink, plugin install, memory wipe all live on each machine's local Claude Code | Ssh into the second machine, `cd ~/aios` (or its equivalent), open `claude`, invoke this playbook |

**Ask:**
> *"Want a quick tour of any of these? I can spawn `onboarding-aios` for the framework-level walkthrough, or just point you at the doc per capability. Or skip — you'll discover these naturally as `/today` surfaces them."*

**Act:** Operator's choice. Default: skip — `/today` will surface what's relevant when it's relevant (vault-update freshness check, company-context freshness check, CHEATSHEET pointers).

---

#### Phase 9.7 — Tier B observation catch-up (REQUIRED for every operator, content-driven scope)

**State:** This migration upgrades `/close-day` and `/close-session` with a dedicated **Tier B observation pass** that fires every close-day going forward (see `plugins/aios/commands/close-day.md` § Tier B observation pass). Tier B = `growth.md`, `profile.md`, `ecosystem.md` — observations about the operator (not work mechanics), one synthesis layer above `session-insights.md`.

The forward mechanism is now in place — but operators with months of pre-migration vault history likely have **accumulated backlog**: Reinforced session-insights with growth/profile/ecosystem shape that were never routed up, antifragile entries that absorbed growth-narrative content, daily-note Observed sections never synthesized. Without a one-time catch-up, the forward mechanism starts on top of a buried foundation.

**Detect (content-driven, lineage-blind):**

```bash
cd "$HOME/aios"
TODAY_EPOCH=$(date +%s)

echo "=== Tier B staleness check ==="
for f in growth profile ecosystem; do
  path="vault/00 - notes/context/observed/$f.md"
  if [ -f "$path" ]; then
    updated=$(grep -E "^updated:" "$path" | head -1 | sed "s/updated: *['\"]\?//;s/['\"]\?$//")
    if [ -n "$updated" ]; then
      updated_epoch=$(date -j -f "%Y-%m-%d" "$updated" +%s 2>/dev/null || echo 0)
      [ "$updated_epoch" -gt 0 ] && days=$(( (TODAY_EPOCH - updated_epoch) / 86400 )) || days=999
      printf "  %-15s last updated: %s (%d days ago)\n" "$f.md" "$updated" "$days"
    fi
  fi
done
```

If any Tier B file is >30 days stale → this phase applies. If all <30 days → skip (no significant backlog).

**Ask:**
> *"Your Tier B observed-context files (growth/profile/ecosystem) have accumulated drift while session-insights + antifragile stayed hot. I'm going to do a one-time catch-up: read your last 2-3 months of session-insights, antifragile, daily-note Observed sections, and business.md additions, then synthesize what should have been routed up. I'll snapshot the files first, then write observations directly when they pass the substance bar (timeline / uniqueness / evidence / essentiality — same gate /close-day uses going forward). No approval prompts per observation — autonomous Radical Candor write, same posture as antifragile.md. The catch-up is ~10-15 minutes of read + write. OK to proceed?"*

**Act (Claude executes this whole flow):**

```bash
# 1. Snapshot all Tier B files before writes (recovery path beyond Phase 0's safety tag)
TODAY=$(date +%Y-%m-%d)
SNAP_DIR="vault/00 - notes/logs/observed-snapshots/$(date +%Y-%m)"
mkdir -p "$SNAP_DIR"
for f in growth profile ecosystem; do
  cp "vault/00 - notes/context/observed/$f.md" "$SNAP_DIR/${TODAY}-catchup-$f.md"
done
```

2. **Read source materials** (per-Tier-B-file feed-ins):
   - For `growth.md` ← all of `session-insights.md` (full read), last 10 entries of `antifragile.md` (some growth-shape content gets misrouted there — known cause-4 pattern), close-day `### Observed` sections from the last 30 daily notes
   - For `profile.md` ← cross-session identity signals in `session-insights.md` (consistent personality traits surfaced across 2+ sessions per CLAUDE.md trigger rule), any "## Core identity threads"-shape language in recent daily notes
   - For `ecosystem.md` ← all of `business.md` recent additions (venture relationship shifts), new people/connections named in last 60 days of daily notes, any new venture-mount activity (`.{venture}-sync` trackers)

3. **Apply substance bar — observation only fires when it passes ALL four tests** (same gate `/close-day` uses):
   - **Timeline test** — matters in 90 days, not just a today-mood
   - **Uniqueness test** — NOT already named in target file (paraphrasing = noise; novel synthesis = signal)
   - **Evidence test** — connects to 2+ sessions or clear cross-source pattern
   - **Essentiality test** — if removed in 90 days, file loses something real

4. **Write autonomously when bar passes** — Radical Candor voice, evidence-cited, no approval prompt per observation. Update frontmatter `updated:` date. Update footer attribution to name this as catch-up (so the historical signal is preserved): *"Last updated: {date} (Tier B catch-up after {N}-day gap — {N} new entries from accumulated session-insights + antifragile)"*

5. **What NOT to write:**
   - Single-session observations without 2+ evidence (leave in session-insights)
   - Sophisticated patterns observations dressed as self-growth (those go to patterns.md)
   - Existing edges paraphrased (extend existing entries instead — see growth.md edges that have "Update {date}" sub-entries for the pattern)
   - System rules for Claude (those go to antifragile.md, not growth.md)
   - Speculative identity traits not confirmed across 2+ sessions (leave for future observation)

6. **Surface the catch-up output to operator:**

   ```
   ### Tier B catch-up complete
   - growth.md   — {N} new edges (#X through #Y), {M} lines added, snapshot at {path}
   - profile.md  — {N} new threads, {M} lines added, snapshot at {path}
   - ecosystem.md — {N} new sections, {M} lines added, snapshot at {path}
   
   What did NOT pass the substance bar (held for future observation):
   - {count} single-session observations remain in session-insights.md (need 2+ evidence)
   - {count} growth-content remains in antifragile.md (judgment call — could route in future catch-up)
   
   Recovery: snapshots at vault/00 - notes/logs/observed-snapshots/{YYYY-MM}/{date}-catchup-*.md
   ```

7. **Commit + push** with a clear `chore(observed): Tier B catch-up — N growth + N profile + N ecosystem additions` message that summarizes the write.

**Time budget:** ~10-15 minutes for a vault with 60-90 days of accumulated history. Longer for older vaults (read scope scales linearly). The Claude session can run this concurrently with the operator doing something else — it's a read-heavy synthesis pass, not interactive.

**Why this phase is REQUIRED for every operator (regardless of vault age):**

The forward mechanism (`/close-day`'s session-insights gardening + Tier B digest) assumes Tier A files (patterns, preferences, business, antifragile) reflect routed content from session-insights AND that Tier B files (growth, profile, ecosystem) reflect current operator state. Two failure modes the catch-up resolves:

- **Backlog operators** (vaults months old, with multi-week Tier B drift or growth gaps): accumulated Reinforced entries never routed up, growth-shape content absorbed into antifragile by mistake, daily-note Observed sections never synthesized. Forward digest runs on top of a frozen baseline = stale observations propagate as if current.
- **Fresh-vault operators** (recently onboarded, minimal logged history): the digest fires, scans the (small) source material, finds nothing passes the substance bar, surfaces *"Tier B files are baseline — forward digest will populate organically"*. Zero writes, but the phase ran. The operator now knows the catch-up ritual exists and what it does — critical for their next /close-day to feel coherent.

Running the phase always (with content-driven scope) means the executing Claude session naturally adapts: heavy synthesis for old vaults, lightweight confirmation for fresh ones. The substance bar is what self-regulates — not an age threshold the playbook tries to predict.

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

