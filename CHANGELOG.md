# Changelog

> What changed in The AIOS framework, why, and what to do about it.
> Entries are newest-first. Each entry is tied to a git commit hash so `/aios:update` can show you only what's new since your last sync.
>
> **This is the canonical CHANGELOG for The AIOS.** The framework lives at [The-AIOS/aios](https://github.com/The-AIOS/aios).

> ## Reading order
>
> Newest entries appear first. Read top-down — `/aios:update` surfaces only what is new since your stored hash, so you never need to hunt for your starting point.
>
> **Retired 2026-07-27:** the 1,002-line `2026-05-23 — Migration playbook` entry (moving off the pre-extraction `{user}/aios` / `{org}/internal-vault` lineage) was removed. It could only ever apply to operators who migrated in May 2026, and it was 45% of this file's lines — read in full by every `/aios:update` on every sync, forever, by everyone it could never apply to. Full text remains in git: `git show b98e84c:CHANGELOG.md`.

> ## Releases → entries
>
> Entries here are **date-keyed**. Releases are **tagged in git** with full notes, and published as GitHub Releases. A release contains every entry dated up to and including its tag date, back to the previous release:
>
> - **Unreleased** — entries dated after `2026-07-25`
> - **[v0.4.0](https://github.com/The-AIOS/aios/releases/tag/v0.4.0)** — tagged `2026-07-25` — covers `2026-05-26` → `2026-07-25`
> - **[v0.2.0](https://github.com/The-AIOS/aios/releases/tag/v0.2.0)** — tagged `2026-05-25` — covers `2026-05-24` → `2026-05-25`
> - **[v0.1.0](https://github.com/The-AIOS/aios/releases/tag/v0.1.0)** — tagged `2026-05-21` — first tagged shape; predates every entry still in this file
>
> **`0.3.0` was never cut** (`0.2.0` → `0.4.0` directly), so a missing 0.3.0 is not a gap in your history.
>
> Two version numbers exist and they are **not** the same thing: the **framework** version in `plugins/aios/.claude-plugin/plugin.json`, and **AIOS Glass** (the editor extension, versioned independently on Open VSX). Both happen to read `0.4.0` right now — where an entry says "Glass", it means the extension.
>
> The release number is a milestone marker for humans. **What you actually have is the hash in `.aios-update`**, which is finer-grained — a vault normally sits *between* releases, and `/aios:update` works off that hash, never off the version.

> ## How to read (+ author) "Action required"
>
> Every **Action required** is written as **CHECK-THEN-ACT, idempotent** — your session verifies its *own* current state first and acts **only if needed**, no-op-ing (and saying so) when the fix is already in place. The same entry may reach you, a teammate who synced independently, a fresh install, or a machine that already self-healed — so a blind "run this" would be unsafe; a self-check is not. **Authors:** write actions that carry their own check (state the precondition + the test, e.g. *"run X; act only if Y"*), put any restart/reload step LAST, and never assume the reader's starting state.

> ## Author every entry with a "What you can now do" section
>
> A changelog that only lists *what changed* pushes comprehension-debt onto the operator — they'd have to read a skill's source to know what it does for their day. So every entry leads with a **"What you can now do"** section: the new capabilities in **plain language, with a concrete example**, phrased as things the operator can *do* now — not a component inventory. Keep the full component list too (for the record), but lead with the practical read, and flag the load-bearing behavioral changes worth an actual read. `/aios:update` surfaces this section to the operator after applying an entry, so their own Claude session tells them what the new version unlocks. **The rule:** *translate every shipped change into a capability the operator can use — or it isn't really shipped to them, just to the repo.*

---

## 2026-07-27 — Four checks that reported a state they never examined

`hash: c29d296 · fc17ef9 · 5b408cc · 487eaeb`

> **The day's theme, because it is one bug wearing four costumes.** A Windows installer printed four green checks over a profile PowerShell could not parse. `/aios:update` read `diff`'s "I could not run" as "the file differs". `aios-commit` explained a failed push by naming a cause it never read. And a CI negative control — written specifically to catch vacuous checks — was itself vacuous. Each one *reported a state it never actually measured*, and each was invisible on the happy path, because a passing check looks identical whether it is discriminating or empty. Two of the four came in from operators who diagnosed them independently.

### The Windows installer half

> **What this delivers.** On Windows, `install-wrappers.ps1` has been corrupting the profile it writes. The file is stored **UTF-8 without a BOM** and carries 11 non-ASCII characters — so Windows PowerShell 5.1, which assumes the system ANSI codepage for a BOM-less script, mangles every em dash *while parsing the installer itself*, before a single byte is written. One of those em dashes lives inside a `Write-Host` string; the ANSI decode turns its third byte into `”`, PowerShell treats curly quotes as string delimiters, and the profile stops parsing mid-string. The whole file is then dead at shell startup: `spawn`, `spawn-kill` and the operator's own session shorthand all vanish. The installer's four verification checks passed the entire time, because they `-match` for text rather than asking whether the result is valid PowerShell. The file's own header says *"ASCII-only on purpose"* and explains this exact hazard — nothing enforced it, so it drifted. Reported with a live reproduction in [#8](https://github.com/The-AIOS/aios/issues/8).

**What you can now do:**
- **Open a new terminal on Windows and actually have `spawn`.** If your profile is currently broken — a wall of `Token 'is' unexpected` / `Missing closing '}'` on startup — re-run `powershell -File ~/aios/hooks/claude-identity/install-wrappers.ps1` and it rewrites the block cleanly. Windows PowerShell 5.1 (the only edition a stock Windows 11 ships) is the affected one; pwsh 7 assumes UTF-8 and was always fine, which is why this survived so long.
- **Trust "installed successfully" to mean the shell can run it.** The installer now parses the finished profile with `[Parser]::ParseFile` before declaring victory, prints the real parse errors with line numbers when they exist, and **rolls back to the timestamped backup it already writes**. It had everything it needed to catch this; it just never asked. A content check answers *"is the text there"*, never *"can PowerShell run this"* — and this failure class is silent precisely because those two answers diverge.
- **Stop losing a manual repair to a routine sync.** Because `/aios:update` auto-runs this installer whenever it appears in the diff, a Windows operator who had hand-fixed their profile got it re-broken by the next sync, with no action of their own. That loop is closed.
- **Get a Windows lane in CI at all.** `install-wrappers.ps1` shipped twice on regex inspection alone — the last entry admits it: *"regex-verified against the same case matrix but not execution-verified — no PowerShell on the authoring machine."* The second of those shipped a file 5.1 cannot parse. There is now a `windows-latest` job that runs the installer end-to-end under 5.1, parse-checks the profile it produced, opens a fresh shell to confirm the functions are really defined, and re-runs it to prove idempotency.

**Component list:** `hooks/claude-identity/install-wrappers.ps1` → ASCII-only restored (11 characters: em dashes → `--`, one `→` → `->`); parse gate + rollback added to the verification block; `-Encoding UTF8` on all three `Get-Content` reads (the profile round-trip, the verification read, and the `USER.md` read in `detect_primary_session`, where an accented session name would otherwise be mangled) · `hooks/inject-datetime.ps1`, `hooks/install-git-hooks.ps1`, `skills/setup.ps1` → same ASCII-only restoration; their non-ASCII sits in comments so it never broke parsing, but the invariant should hold repo-wide rather than per-file · `.github/workflows/validate.yml` → new `windows_installer` job: edition guard (the lane is worthless under pwsh 7), a **negative control** proving a BOM-less em dash genuinely fails to parse under 5.1, the repo-wide ASCII-or-BOM check, the end-to-end install, a fresh-shell function probe, and an idempotency re-run.

**Verification:** executed on Windows 11, Windows PowerShell 5.1.26100.8875, es-MX locale — the edition and codepage that reproduce it. **Before:** the installer prints four green checks and `[ok] Wrappers installed successfully` over a profile with 12 mojibake characters that does not parse. **After:** `profile parses cleanly: 1`, profile is ASCII-only, a fresh `powershell` gets all four functions, a second run leaves exactly one `spawn` definition. **Rollback path tested directly** by re-injecting a single em dash into the fixed installer and running it: the four content checks still pass, the parse gate reports `0`, the real parse errors print with line numbers, the backup is restored, and the profile hash is byte-identical to before the run — exit `1`.

**Action required (CHECK-THEN-ACT, idempotent):**
1. **Windows only, and only if your profile is broken.** Check first: `powershell -Command "$e=$null; [System.Management.Automation.Language.Parser]::ParseFile($PROFILE,[ref]$null,[ref]$e)|Out-Null; if($e){'BROKEN'}else{'OK'}"`. If it says `OK`, no-op — nothing to do. macOS/Linux → never affected; `install-wrappers.sh` moves bytes through `awk` and `cat >>` without ever decoding them.
2. **Only if it said `BROKEN`:** `/aios:update` applies the fixed installer and auto-runs it, which repairs the profile in place. If you'd rather not sync yet, run it directly: `powershell -File ~/aios/hooks/claude-identity/install-wrappers.ps1`. Either way the parse gate now refuses to leave you with a broken file.
3. **Reopen your terminal (last step).** Open shells keep the old profile until they're restarted.

### The sync half — `/aios:update` and `aios-commit`

> **What this delivers.** `/aios:update` compared files with `diff -q <(tr …) <(tr …)` in three places. `diff` exits `0`=same, `1`=differ, **`2`=trouble**, and all three sites read it as a boolean — so a comparison that never ran became "the file differs". Under a sandboxed tool call it never runs, because `diff` needs a seekable regular file and spools a `/dev/fd` pipe to its own temp file, which the sandbox denies. A real sync reported a phantom self-update *and* a phantom personalization in the same run. Separately, `aios-commit` answered every failed push with `"push deferred (offline or remote diverged)"` — a diagnosis asserted without reading the error. It sent two sessions to investigate a divergence that did not exist while the real blocker was network egress, and it promised a retry that cannot happen inside a sandbox, where the next `aios-commit` fails identically. Nothing anywhere swept the deferral, so "it pushes next time" had no mechanism behind it at all.

**What you can now do:**
- **Trust what `/aios:update` tells you it found.** Comparisons are content hashes now (`tr -d '\r' | shasum -a 256`) — they stream, so there is no temp file and nothing for a sandbox to deny, and a failed read is distinguishable from a real difference. An inconclusive compare is **reported as inconclusive** instead of being written up as an edit you never made.
- **Stop losing an update to a stopped sync.** No compare outcome aborts the run. An inconclusive one takes the conservative-but-applying branch — back up, then apply — because a sync that stops leaves the vault half-applied while one that applies with a loud label is recoverable by reading the report.
- **Find out why a push actually failed.** The failure is classified — blocked egress · offline · diverged · auth — and the git error is always printed. The egress case names the fix, and warns it will not retry itself.
- **Ask a session to watch a video and have it know what to do.** New **`watch-video`** skill. The two local media hooks were only reachable through `/aios:ingest` — and **a hook has no semantic match**, so a session asked to *"watch this video"* found nothing and improvised. The skill routes them: `hooks/transcribe.py` for long-form audio (MarkItDown single-shots audio to Google Web Speech — fine for a sentence, useless for a 49-minute interview) and `hooks/video-watch.py` for the **visual** channel a transcript throws away — slides, code, diagrams, terminals, on-screen text — layered *on top of* the transcript, never instead of it. Carries the one real flag decision (`--reader ocr` for verbatim text · `vlm` for structure · `both`), the macOS gating with its cross-platform fallback, and the failure modes (a clean transcript is not evidence that something shown wasn't said; sampled frames are a sample, not a record).
  **It deliberately does NOT file anything.** Its output is understanding held in the session — no note, no frontmatter, no cross-links, working files in `/tmp` and never in `vault/`. Watching is cheap and repeatable; filing is a decision, and `/aios:ingest` remains the only path that makes a source permanent. The skill hands off to it rather than half-implementing it. *(No second skill for MarkItDown: it is a two-argument wrapper with no judgment to teach, and its territory — PDF/docx/pptx/xlsx — is already covered semantically by the `document-skills` plugin, so a competing skill would win the wrong triggers and cost every session context for nothing.)*
- **Untrack a file you just gitignored, through the sanctioned commit path.** `aios-commit` gained **`--untrack <path>`** (repeatable, combines with normal paths). It records the path's *removal* from tracking while **leaving the file on disk** — the "I gitignored something that was already tracked" case, which `git add` structurally cannot express: it stages what the working tree has, so a file that still exists gets re-added, and once the path is ignored git refuses to add it at all. Previously that forced a raw `git commit` past the attribution guard. Now: `aios-commit -m "…" --untrack .glass -- .gitignore` commits the ignore rule and the untrack together.
- **Never end a day on a silently unpushed vault.** A failed push leaves `.git/aios-push-pending`, and **every subsequent `aios-commit` sweeps it** — retrying the stranded push before doing anything else. It lives in the primitive rather than in the commands, so it covers every path that commits, including ones nobody thought to wire up. Critically it runs *before* the "nothing to commit" early-exit, which is exactly how a stranded commit used to stay stranded: that exit never reached the push. `--no-push` skips the sweep; a still-blocked retry keeps the marker for the next run and never fails the commit.
- **Keep your private ignores through a first-time `.gitignore` migration.** The legacy path failed *open*: every error produced an empty carry list, indistinguishable from "this operator has no personal rules", so their private-data ignores were dropped. An unreachable baseline now carries **all** prior rules and says so — an over-carried `.gitignore` is noisy and reviewable; a dropped one silently makes secrets committable.

**Component list:** `plugins/aios/commands/update.md` → `h_file`/`h_git` streaming-hash compares replace all three `diff <(…)` sites (`h_git` probes with `cat-file -e` first, because a failed `git show` prints nothing and `sha256("")` is a real hash that would compare equal to an empty file); self-update recursion bounded by `AIOS_UPDATE_REINVOKED` rather than by the compare succeeding; `.gitignore` legacy migration fails toward noise; the temp-clone path stays a literal `/tmp/aios-update-check` **on purpose** — `${TMPDIR:-/tmp}` looks more portable and is worse, because `$TMPDIR` resolves differently in a sandboxed vs un-sandboxed call, which is what made the reconcile report "0 drift" having compared nothing · `hooks/aios-commit` → push-failure classification + `.git/aios-push-pending` marker, exit stays `0` in every branch since the commit did succeed; **the sweep lives inside `aios-commit` itself** — before the no-changes early-exit, skipped under `--no-push` — rather than being pasted into the ritual commands, so it is one implementation covering every code path with nothing to drift · `.github/workflows/validate.yml` → the negative control's em dash was written as `` `u{2014} ``, a PowerShell 6+ escape that degrades to the literal text `u{2014}` under 5.1, so the file carried no non-ASCII and the control passed on nothing.

**Verification:** `tests/aios-commit.test.sh` 10/10 under bash 3.2.57 (the shell CI runs on macOS) + `bash -n` clean. CI 11/11 on the merge. The Windows lane now prints its ANSI codepage: it is **1252**, and the end-to-end BOM-less em dash *does* fail there — so the runner's codepage was never a contributing cause, only the pwsh-6 escape was. That was measured rather than assumed, and it contradicted the first diagnosis, which the commit history records.

**Action required (CHECK-THEN-ACT, idempotent):**
4. **Only if you run Claude Code with the Bash sandbox enabled AND see `PUSH BLOCKED (no network egress)`.** Check first: `git -C ~/aios rev-list --count @{u}..HEAD` — `0` means nothing is stranded, no-op, stop here. If something *is* stranded, check which transport your vault uses, because **the fix differs and the wrong one does nothing**: `git -C ~/aios remote get-url origin`.
   - **HTTPS remote** (`https://github.com/…`) → add the git **transport** host to `~/.claude/settings.json` → `sandbox.network.allowedDomains`. It must be `github.com`; **`api.github.com` is the REST host and does not cover `git push`**, which is why an allowlist that looks like it permits GitHub blocks the one thing `aios-commit` needs. While you are there, drop hosts you do not use — an unused entry is open egress buying nothing.
   - **SSH remote** (`git@github.com:…`) → **the allowlist will not help you, so do not bother adding one.** Measured 2026-07-27 on a real vault: results are *identical* with and without a `github.com` entry — HTTPS egress already worked, and SSH still failed with `nc: authentication method negotiation failed`. A domain allowlist governs **domains, not transports**, and `ssh` cannot negotiate with the sandbox's egress proxy at all. Two honest options: **(a)** exclude the commit primitives from the sandbox in `~/.claude/settings.json` → `sandbox.excludedCommands`, so they run outside it — `"~/aios/hooks/aios-commit *"`, its absolute-path form, **and** the compound `"cd ~/aios && ~/aios/hooks/aios-commit *"` (matching is by command *prefix*, and the canonical invocation starts with `cd`, so it needs its own entry), plus the same pair for `aios-note-append` (it is the **outer** command in `/close-session`, so an exclusion on `aios-commit` never reaches it). Verified: a sandboxed `aios-commit` then prints `pushed.` while a plain `git ls-remote` in the same call stays blocked — the escape is scoped to the two primitives, not general egress. **(b)** Do nothing. The marker + the sweep built into `aios-commit` handle it; you push once with network access and the next `aios-commit` clears the backlog on its own. Pick (a) for convenience, (b) if you would rather not grant any sandbox exception.
5. **Only if you have stranded commits right now:** `git -C ~/aios push` with network access, then `rm -f "$(git -C ~/aios rev-parse --absolute-git-dir)/aios-push-pending"`. From here `aios-commit` does this for you on its next run — no ritual required.
6. **Optional, and only if `.glass/` is tracked in your vault — untrack AIOS Glass's per-machine UI state.** `.gitignore` now ignores `.glass/` (framework section), but **an ignore rule does not untrack a file that is already tracked**, so anyone who previously committed it keeps seeing a permanently dirty tree. Check first: `git -C ~/aios ls-files .glass/ | head -1` — **empty output means nothing to do, stop here.** If it prints something, one command does it — **`aios-commit` gained `--untrack` for exactly this** (see below): `cd ~/aios && ~/aios/hooks/aios-commit -m "chore: untrack .glass machine-local UI state" --untrack .glass`. The files stay on disk untouched; only the index changes. **Behavior change worth knowing:** `.glass/` will no longer sync between your machines — correct for what it holds (absolute `workspaceFolders` paths, font sizes, folder sort orders, scratch session notes), but say so out loud rather than discover it. Symptom this fixes: a single font-size nudge showing as one uncommitted change forever, which is how an operator learns to ignore `git status`.

### The housekeeping half — `/aios:housekeeping` stops crying wolf about your antifragile file

> **What this delivers.** Bucket 12's volume guard still read *">500 lines OR >50 entries"* — a threshold `/aios:compact` had already re-based to **~45k tokens / ~120 entries with condense as the primary lever**, precisely because entry count decouples from cost once entries are terse. Two specs disagreeing about one file means one of them is wrong on every run: measured on a real vault at **716 lines / 89 entries / ~36.9k tokens**, the old guard flagged on *both* counts while `compact.md` correctly reported *within bounds, skip*. A standing false alarm living inside the bucket that exists to catch false alarms. Separately, **every entry in `antifragile.md` states a system fix, and no bucket ever checked whether that fix shipped** — an entry claiming *"system fix: X"* where X was never applied is a check that cannot fail, inside the file about checks that cannot fail (**#88**).

**What you can now do:**
- **Stop being told to triage a healthy file.** The volume guard now uses `/aios:compact`'s bound and measures **tokens** (`wc -c ÷ 3.7`) alongside entries, flagging only past **~45k tokens or ~120 entries**. Within bounds it says so and proposes nothing. The entry above the guard records *why* the number moved, so it can't quietly drift back.
- **Trust that a resize can never cost you a lesson.** If the bound *is* exceeded, the guard hands the pass to `/aios:compact` Step 3.5 and states its ordering explicitly: **condense first** (the primary lever — once entries are terse, removal frees almost nothing and costs real wisdom), tombstone **only** entries the file itself marks graduated/merged/superseded (keeping number + title so every `#N` reference resolves), and **surface anything unmarked for you to confirm — never act on inference**. Entry numbers are identity; never renumbered.
- **Find out whether your antifragile fixes actually shipped.** New **Bucket 26 — fix-verification**: it extracts the claimed artifact from an entry's fix line, probes for it, and reports. It is **report-only with no write path at all** — it never edits, annotates, tombstones, reorders, condenses, deletes or adds an entry. A finding is a *question*, never an action, because "the fix isn't there" has three causes it cannot distinguish: regressed · moved · or the wording was always aspirational. Only you know which.
- **Never mistake a sample for an audit.** Bucket 26 samples (recent 15 + any entry naming a path/command/flag/hook) rather than sweeping everything, so **every run must state coverage unconditionally** — entries in file · sampled · present · absent · uncheckable · skipped-as-out-of-sample, with the numbers required to reconcile. A clean packet can no longer read as full coverage, which is the same false-completeness shape the bucket hunts.

**Component list:** `plugins/aios/commands/housekeeping.md` → Bucket 12 volume guard re-based to `compact.md`'s token bound + condense-before-removal ordering made explicit + the threshold-change rationale recorded inline · new **Bucket 26** (report-only fix-verification, sibling to Bucket 22 which asks the same question of tests rather than lessons), placed as its own bucket rather than folded into Bucket 9 so its read-only contract is *stated* rather than inferred from Bucket 9's structure-only disclaimer.

**Verification:** dry-run on a live 89-entry `antifragile.md` **before** the change shipped, per the operator's explicit precondition. **Zero entries removed or rewritten under either the old or the new guard** — counted, not asserted, with the counter itself poisoned to prove it can return non-zero. All four preservation guardrails re-grepped intact (`"never delete entries" is sacred` · `deletions of any entry` · `no content rewrites — original phrasing IS the evidence` · `never delete without a snapshot`). Bucket 26's negative control fires against an impossible artifact, so it is not vacuous. **The dry run also caught a defect in the new spec before it shipped:** a naive probe scored a **100% false-positive rate** on the trial vault — bare filenames joined to a root miss anything in a subdirectory, and `find` does not follow symlinks without `-L` while `~/aios` is commonly a symlink, so the probe traversed nothing and every entry read ABSENT. Corrected to resolve by basename with `find -L`; result on the same file: 10 present · 0 absent · 5 uncheckable. Both traps are now documented in the bucket, with the heuristic *if your first pass flags most of what it checks, suspect the probe, not the file*.

**Action required:** **None.** Both changes are to a command you invoke — no file in your vault is touched by this entry, and `/aios:housekeeping` remains propose-only at the packet review. The next run will simply stop flagging a healthy `antifragile.md` and will start reporting fix-verification coverage.

---

## 2026-07-26 — The fix for the last bug renamed an operator's shell function (uppercase session names)

`hash: 2addb2e`

> **What this delivers.** Yesterday's validator (`98a017c`) stopped a globbing `*buddy*` from reaching your shell rc. It also accepted **lowercase only** — so an operator whose primary session is `ALI` failed the check, fell through to the fallback, and had the installer **rewrite `ALI()` to `aios()` in his rc**. Months-old shorthand, gone on update, from an installer reporting success. Nothing errors; the only way to notice is spotting that a function you type every day has vanished. **Case was never the hazard** — glob and shell-special characters are (`*`, `_emphasis_`, spaces, quotes, `;`, `$()`), and `ALI() { … }` is a perfectly valid non-globbing function name in zsh and bash alike. Reported by an operator with the diagnosis, the one-character fix, and both-direction verification already done.

**What you can now do:**
- **Keep an uppercase or mixed-case session name.** `ALI`, `Ali`, `app-walker`, `buddai` all survive; `*buddy*`, `_example_`, `my name`, `a;b`, `a$(id)` and leading/trailing hyphens still fall back to `aios`. If your rc was rewritten, re-run the installer and your name comes back.
- **Hear it when the installer disagrees with you.** The fallback is no longer silent: a name that fails validation prints `install-wrappers: session name "…" from USER.md is not a plain name — using "aios" instead.` on **stderr** (stdout is the return value, so a message there would *become* the session name). An example row the parser correctly skips stays silent — nothing was rejected, so there's nothing to announce.
- **Get the same protection on Windows — for the first time.** `install-wrappers.ps1` had **no validator and no example-row skip at all**, so the original `*buddy*` bug was never fixed there. It matters more on Windows: the name is interpolated into *generated code* (`function $PRIMARY_NAME {` plus three `-Name '$PRIMARY_NAME'` arguments inside single quotes), so a name carrying a quote or brace doesn't just misname a function — it breaks or rewrites the profile. Both installers now share one rule.
- **Trust that this file is tested at all now.** `detect_primary_session` had **zero** coverage — which is exactly why a lowercase-only test set never exercised a capital. It now has 20 assertions in CI, on ubuntu **and** under bash 3.2, the stock-Mac shell this installer actually writes to.

**Component list:** `hooks/claude-identity/install-wrappers.sh` → validator widened to `[!A-Za-z0-9-]` (hyphen rules untouched); a non-empty rejected name is announced on stderr · `hooks/claude-identity/install-wrappers.ps1` → gains the example-row skip **and** an equivalent anchored validator (`^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$`) with `Write-Warning` (warning stream — cannot contaminate the return value the way `Write-Output` would) · `tests/install-wrappers.test.sh` (new) → 20 assertions pairing *valid names survive* with *hostile ones still rejected*, plus stdout-not-polluted and example-row-stays-silent · `.github/workflows/validate.yml` → the suite runs in `primitives` and in the bash-3.2 macOS lane.

**Verification:** the test fails on the pre-fix code (4 failures: both uppercase cases + the silent fallback) and passes 20/20 after, on bash 5.3.9 **and** 3.2.57. The `.ps1` change is **regex-verified against the same case matrix but not execution-verified** — no PowerShell on the authoring machine. A `pwsh` lane on the ubuntu runner is the honest next step and is not yet built.

**Action required (CHECK-THEN-ACT, idempotent):**
1. **Only if your `USER.md` identity name contains uppercase:** check whether your shell function was renamed — `grep -n 'aios()' ~/.zshrc ~/.zprofile 2>/dev/null` (Windows: look for `function aios` in `$PROFILE`). If you find `aios` where you expect your own name, re-run the installer for your platform, then `source ~/.zshrc` (or reopen PowerShell). All-lowercase name → never affected, no-op.
2. **Nothing else.** The validator change is strictly *wider*; no previously-accepted name is now rejected.

---

## 2026-07-26 — The wrapper installer was breaking your shell startup, quietly, on every install

`hash: 98a017c`

> **What this delivers.** If a new terminal has ever greeted you with `no matches found: *buddy*`, that was us. `install-wrappers.sh` reads your primary session name from `USER.md`'s Identity table — and it read the EXAMPLE row, which is marked *"EXAMPLE ONLY (Claude: ignore these)"*. That marker is for Claude; the reader is `awk`, which cannot take a hint. It stripped the backticks, kept the markdown emphasis, and wrote `*buddy*` into your shell rc as a session name. zsh reads that as a glob pattern, so every new terminal errored on startup — from an installer that reported success. Found because an operator's own setup session read the installer's output and questioned it.

**What you can now do:**
- **Open a terminal without an error.** If your rc carries a bogus primary-session block, re-run `bash ~/aios/hooks/claude-identity/install-wrappers.sh` — it rewrites the block, and the name it writes is now validated.
- **Trust the name it picks.** Example rows are skipped (markdown emphasis is this file's example convention), and whatever the parser returns, only a plain session name may reach your shell — lowercase letters, digits and hyphens, no leading or trailing hyphen. Anything else falls back to `aios`. The parse will be wrong again someday; the validator makes that mean "fell back to aios" instead of "every terminal errors".
- **Have your own identity asked for, not guessed at.** Every vault ships the same `CLAUDE.md`, so a setup session offered a newcomer the framework author's Substack as a candidate for *their* site. It asked rather than assumed, which was right — but it should never have been a candidate. The citation is now marked as the author's, and `/aios:cold-start-interview` is explicit: identity comes from you and from `context/declared/`, never from a file that is byte-identical in every vault.

**Component list:** `hooks/claude-identity/install-wrappers.sh` → `detect_primary_session` skips emphasis-wrapped cells and validates the result against `[a-z0-9-]` with no leading/trailing hyphen, falling back to `aios`; verified against the shipped template (now `aios`, previously `*buddy*`), a real identity row (`buddai`), and a hostile row containing glob characters (`aios`) · `CLAUDE.md` → the Agentic Culture citation is attributed to the framework's author, with a note to Claude that it is never evidence about the operator · `plugins/aios/commands/cold-start-interview.md` → the same rule, stated where identity is actually gathered.

**Action required (CHECK-THEN-ACT, idempotent):**
1. **Check whether your shell rc carries the bad name:** `grep -n 'primary-session' ~/.zshrc ~/.zprofile 2>/dev/null` and look for a name wrapped in `*` or `_`. Also just open a new terminal — if it prints `no matches found`, that is this bug.
2. **Only if it does:** re-run `bash ~/aios/hooks/claude-identity/install-wrappers.sh`, then `source ~/.zshrc`. The block is rewritten in place; nothing else in your rc is touched.
3. **If your primary session name comes out as `aios` and you wanted something else:** put a real row in `USER.md` → `## Identity` (plain, no `*emphasis*` — that marks a row as an example) and re-run the installer.

---

## 2026-07-25 — Setup no longer ends half-wired: the update tracker and the plugin

`hash: b832474`

> **What this delivers.** Two gaps that only a genuinely new machine could reveal — both invisible to anyone who already has a working vault, because their vault was wired years of commits ago. A newcomer finished the whole 11-step setup and landed with the update surface reporting *"no config"* and the framework unable to notice its own releases. Found by running the setup end to end on a fresh macOS account.

**What you can now do:**
- **Know when the framework moves, from your first day.** Setup now writes `.aios-update` with the exact commit you installed from. Until now that file was only ever written by `/aios:update` — which a fresh install never runs — so a new operator had no way to learn they were behind except being told. A brand-new install is the one moment the hash is known for certain, so it is recorded then. `repo=` deliberately points at the FRAMEWORK upstream, not your own vault remote: the question it answers is *"has the framework moved"*, not *"have I pushed"*.
- **Run `/aios:today` on the first try.** Plugin registration (`claude plugin marketplace add ~/aios && claude plugin install aios@the-aios`) was missing from the step list entirely. The rituals ARE the plugin's commands, so a setup that skipped it ended with an operator whose very first instruction failed — the worst possible first impression, and a silent one.
- **Answer the cold-start interview by picking, not composing.** Wherever a question has recognisable answers — role, industry, how you work, which bundles — the session now offers a short numbered list with a *"let me describe it"* escape. Someone meeting AIOS for the first time does not yet know the vocabulary it wants, and a blank prompt asks them to guess it. Free text stays wherever a list would flatten the answer.

**Component list:** `SETUP.md` → new step 4 (write `.aios-update`, with the reason it is not optional and a `cat` to confirm the hash is a real 40-character commit rather than a placeholder — a placeholder reads as "you are behind" forever) · new step 5 (register the AIOS plugin) · step 10 gains the choice-first interview directive · the list renumbers to 13, and the two cross-references that pointed into it were corrected with it (the MCP callout's "step 4" → 6, the defaults paragraph's "§7" → §9). Section references (§10, §11) point at document sections and were unaffected.

**Action required (CHECK-THEN-ACT, idempotent):**
1. **If you set up before today, you probably have no update tracker.** Check: `cat ~/aios/.aios-update`. If it is missing, or its `hash=` is not a 40-character commit, write it once —
   ```bash
   printf 'repo=git@github.com:The-AIOS/aios.git\nhash=%s\nsynced=%s\n' \
     "$(git -C ~/aios rev-parse HEAD)" "$(date +%F)" > ~/aios/.aios-update
   ```
   If it already has a real hash, no-op — `/aios:update` maintains it from here.
2. **Confirm the plugin is registered:** `claude plugin list | grep -i aios`. If nothing matches, `claude plugin marketplace add ~/aios && claude plugin install aios@the-aios`. If `/aios:today` already works for you, this is already true.
3. **Nothing to restart.** Both are state, not code.

---

## 2026-07-25 — Setup installs what you need, not everything we bundle (ten MCPs → one)

`hash: 2e9fb2c`

> **What this delivers.** Setting up AIOS used to begin by installing **all ten bundled MCPs** — `bash mcps/setup.sh` was step 3 of SETUP.md and step 1 of `/aios:mcps-setup`. On a fresh machine that is multiple Chrome-for-Testing downloads, several Python venvs, a pip editable install that fails on this repo's own `pyproject` layout, and minutes of output in which a long download is indistinguishable from a hang and one failure reads as a crash. Observed on a genuinely new account: the operator could not tell whether setup had finished, stalled, or broken — and concluded it was stuck. None of it was needed. The only MCP the vault actually requires is the **Obsidian** one, which is a published package registered directly with `claude mcp add` and is not in `mcps/` at all — so the bulk install could never satisfy the check it appeared to serve. Slack, Atlassian, Google Workspace, image generation and the rest are convenience, and `/aios:mcps-setup` already asks *"want this?"* one at a time. Installing all ten before anyone was asked inverted that command's own premise.

**What you can now do:**
- **Finish setup in the first few minutes instead of waiting on downloads you did not ask for.** Setup now registers the Obsidian MCP and stops: `claude mcp add obsidian -- npx -y @mauricio.wolff/mcp-obsidian@latest ~/aios/vault`. Everything else waits until you want it.
- **Install exactly one MCP, whenever you decide you want it.** `bash mcps/setup.sh slack-mcp` installs just that one — idempotent, no effect on the other nine. `bash mcps/setup.sh --list` shows what is bundled. With no arguments it still installs everything, so nothing is taken away from anyone who prefers that; it is now an explicit choice rather than the default.
- **Trust `/aios:mcps-setup` to ask before it spends your time.** The opt-in question now comes *first*, and only a yes triggers that MCP's dependency install. It also warns you when one is heavy (NotebookLM and Playwright each download a Chromium build), so a slow install never reads as a hang, and a failed optional integration no longer stops the walkthrough.
- **Set up from the AIOS App without hitting any of this.** The app's Setup tab repairs the Obsidian MCP with the one-line registration instead of the ten-MCP script it used to run — a button that could not fix the check it was attached to.

**Component list:** `mcps/setup.sh` → optional MCP-name arguments (`bash mcps/setup.sh <name>…`), `--list`, a `want()` gate on all ten per-MCP blocks, and a header stating why selection exists; no-argument behaviour byte-for-byte unchanged · `SETUP.md` → step 3 registers the Obsidian MCP and carries an explicit **do not run the bulk install here** callout; the end-to-end flow's step 2 likewise · `plugins/aios/commands/mcps-setup.md` → §1 rewritten from *"install dependencies first"* to *"do NOT bulk-install anything"*, per-MCP dependency install moved into the opt-in flow ahead of auth/register (several per-MCP flows reference a `.venv/bin/python` that does not exist until it runs), heavy-install warning, continue-on-failure, and a stale *"already registered during setup.sh"* line removed. Selection verified: a named run touches only that MCP, a bare run is unchanged.

**Action required (CHECK-THEN-ACT, idempotent):**
1. **Confirm the Obsidian MCP is registered** (it is what the vault needs, and older setups may have assumed the bulk script provided it): `claude mcp list | grep -i obsidian`. If nothing matches, register it — `claude mcp add obsidian -- npx -y @mauricio.wolff/mcp-obsidian@latest ~/aios/vault` (substitute your vault path if you cloned elsewhere). If it already appears, no-op.
2. **Nothing to undo.** Any MCP you already installed stays installed and registered; this changes what setup *starts* with, not what exists. Your venvs are untouched.
3. **Only if you have been putting off an integration:** `bash mcps/setup.sh --list`, then `bash mcps/setup.sh <name>` for the one you want, then `/aios:mcps-setup` to authenticate and register it.

---

## 2026-07-25 — Tier 0 named: the folders that live in canonical and never reach your vault

`hash: 4aa6be3`

> **What this delivers.** Two folders — `tests/` and `.github/` — exist in the canonical repo but are **never synced to an operator vault**. That has always been true, and until now nothing anywhere *said* so: they were excluded purely by **omission** from `/aios:update`'s Tier-1 allowlist. An operator who noticed `tests/` on GitHub, ran `/aios:update`, and didn't find it in their vault had no document to consult — the behaviour was correct but unexplained. Worse, the omission is invisible to whoever edits the allowlist next, and there's a live precedent for that biting: the Tier-1 **root-docs** rule started as a hardcoded list, silently missed `AGENTS.md` / `EXTENSION-MAP.md` / `LICENSE-AUDIT.md`, and was correctly generalized to *"every other `*.md` at the repo root."* Apply that same reasonable instinct one level up — *"why is the layer list hardcoded? let's diff all top-level dirs"* — and CI scaffolding ships into every vault on the next sync. This entry converts *safe by accident* into *safe by declaration*.

**What you can now do:**
- **Understand why a folder you can see on GitHub isn't in your vault.** `update.md` now has a **§ Tier 0** section beside Tiers 1–3 naming the category, its two members, and the reason: they serve **CI and contributors**, not operators. Your vault has no CI, so shipping them would add files you can neither run nor maintain. If you ever wondered whether your sync was incomplete — it wasn't.
- **Add a canonical-only folder without it becoming folklore.** Contributing a `benchmarks/`, `fixtures/`, or docs-site build that shouldn't reach vaults? Name it in § Tier 0 in the same PR. The section also states the converse: Tier 0 is *not* a parking spot for undecided content — anything that should reach operators belongs in Tier 1.
- **Rely on CI to enforce it, not just prose.** A new guard fails the build if either folder enters Step 2's sync pathspec or the Step 6.5 reconcile loop — *and* if the § Tier 0 section is ever deleted. Documentation that can silently vanish isn't a guarantee, so the guard protects the doc too.
- **Run the hook regression suite yourself** (contributors): `tests/` stays canonical-only, so run it from your clone of the framework repo — `/bin/bash tests/aios-commit.test.sh` — not from your vault, where it deliberately doesn't exist.

**Component list:** `plugins/aios/commands/update.md` → new **§ Tier 0: Repo infrastructure (canonical-only — never reaches a vault)**, placed between Tier 2 and Tier 3, with the explicit standing instruction to denylist `tests/` + `.github/` if the pathspec or reconcile ever goes directory-generic · `.github/workflows/validate.yml` → new *"Tier-0 canonical-only folders are not in the /aios:update sync path"* step in the **Repo structure** job (three assertions: not in the pathspec, not in the reconcile loop, § Tier 0 still documented). Guard verified in both directions — it fails on a reconcile-loop entry, fails on a pathspec entry, fails when the section is removed, and passes clean otherwise.

**Action required (CHECK-THEN-ACT, idempotent):**
1. **Nothing to run.** This is spec + CI only; no vault file behaves differently. Confirm the doc landed after syncing: `grep -c '^### Tier 0' plugins/aios/commands/update.md` → `1`.
2. **Only if you were confused by a missing folder:** verify your vault is genuinely complete rather than assuming — `/aios:update` and check that its Step 6.5 completeness reconcile reports clean. `tests/` and `.github/` being absent is correct and is not drift.
3. **Only if you contribute framework infra:** read `update.md` → § Tier 0 before adding any new top-level folder, so the sync classification is a decision rather than an accident.

---

## 2026-07-25 — `/close-session` silently lost its capture on stock-bash Macs — fixed, and the class is now CI-guarded

`hash: afe0832`

> **What this delivers.** Two canonical hooks expanded a possibly-empty array as `"${arr[@]}"` under `set -u`. On **bash 3.2** — the bash Apple still ships at `/bin/bash`, and what `#!/usr/bin/env bash` resolves to on a stock Mac — that counts as an *unbound variable*, so the script aborts. It failed **mid-operation**, which is what made it expensive: `aios-note-append` died *after* writing the session block into your daily note and *before* committing it, so `/close-session` looked like it worked, committed nothing, and the natural retry **duplicated the block**. Separately, the very first commit in a fresh repo failed outright (`PARENTS` is empty with no `HEAD`). Reported and fixed by an operator who hit it in a real `/close-session`; the maintainer machines could not reproduce it, because their `env bash` is Homebrew 5.x — which is exactly why the CI guard below matters more than the two-line fix.

**What you can now do:**
- **Run `/close-session` on a stock Mac and actually get your capture committed.** If you'd seen a bare `NOPUSH[@]: unbound variable` — or found session blocks sitting uncommitted in a daily note, sometimes twice — that's this bug, and it's gone. Nothing to clean up going forward; if you have a duplicated block from a past retry, delete the extra one by hand.
- **Initialize AIOS commit primitives in a brand-new repo.** `aios-commit` can now create the *first* commit in a fresh repo (previously: `PARENTS[@]: unbound variable` → `commit-tree failed`).
- **Trust that this class can't come back silently.** CI now runs the commit-primitives suite twice — on ubuntu (bash 5) **and** under real bash 3.2 on macOS — with `bash` pinned on PATH so the hooks themselves are serviced by 3.2, not just the test harness. Verified honestly: with the fix reverted, the two new cases fail; with it in place, 10/10 pass on both 3.2 and 5.3.
- **Know the rule when you write a hook.** `CONTRIBUTING.md` now has a *Shell portability* section: any array that can legitimately be empty uses `${arr[@]+"${arr[@]}"}`. Arrays with a proven length guard don't need it — don't widen a diff speculatively.

**Component list:** `hooks/aios-commit:124` (`PARENTS`) + `hooks/aios-note-append:62` (`NOPUSH`) → portable empty-safe expansion, with inline comments explaining *why* the form looks odd so it doesn't get "cleaned up" later (community PR #6) · `tests/aios-commit.test.sh` → two new cases covering the root-commit and default-push paths, neither of which the suite previously exercised (every existing call passes `--no-push`, so `NOPUSH` was never empty) · `.github/workflows/validate.yml` → new `primitives_bash32` job (macos-latest, PATH-pinned to `/bin/bash`, asserts `BASH_VERSINFO[0] -eq 3` so the lane can't go vacuous) · `CONTRIBUTING.md` → *Shell portability* section + the stale *"There is no CI in this repo today"* claim corrected to describe the 10 jobs that actually run.

**Action required (CHECK-THEN-ACT, idempotent):**
1. **Nothing to run — `/aios:update` applies both hooks.** Verify: `grep -c 'arr\[@\]+' hooks/aios-note-append` returns a non-zero count. *(Corrected 2026-07-27: this originally also named `hooks/aios-commit` and said both should be non-zero. `aios-commit` returns `0` — it guards array length explicitly instead, so it never needed the idiom. The file was always correct; the verification string was wrong, which would have sent anyone who ran it hunting a bug that does not exist.)*
2. **Only if you saw the failure:** check today's and recent daily notes for a duplicated `## Session —` block from a retry, and delete the extra. `grep -c '^## Session' "vault/01 - calendar/$(date +%Y-%m)/$(date +%F).md" 2>/dev/null` — compare against how many sessions you actually closed.
3. **Only if you author hooks:** read `CONTRIBUTING.md` → *Shell portability*, and run `/bin/bash tests/aios-commit.test.sh` locally before proposing hook changes — that's the 3.2 path CI now enforces.

---

## 2026-07-25 — Your execution surface is a CHOICE: the AIOS App **or** the IDE + Glass

`hash: a041056`

> **What this delivers.** SETUP.md described Antigravity IDE + AIOS Glass as required, with Glass called *"a core part of the AIOS, not an optional extra."* That was true when the IDE was the only way to point-and-click the AIOS. It stopped being true when the **AIOS App** shipped — and it was about to cause a concrete failure, not just read as stale. The app hands setup off to a Claude session, and **that session reads this doc**: its step 1 would have walked an app user through downloading a whole IDE they don't need and installing an extension that duplicates the window they were already looking at. A newcomer cannot tell that's unnecessary, because the doc said *required*. Obsidian stays required on every path (it's what the bundled Obsidian MCP talks to); the **execution** surface is now an explicit pick-one.

**What you can now do:**
- **Set up the AIOS without installing an IDE at all.** If you use the AIOS App, that IS your execution surface — skip Antigravity and skip AIOS Glass entirely. Concretely: `brew install --cask obsidian`, drag the app's `.dmg` to Applications, install Claude Code, done. Two apps, not three-plus-an-extension.
- **Trust a Claude-driven setup not to misroute you.** Step 1 of the Claude-facing sequence now tells the session, in as many words, *not* to send an operator who arrived from the app off to install an IDE or Glass. Say *"set up my AI-OS"* from the app and you'll be walked through your own path.
- **Still choose the IDE deliberately, and know why.** Antigravity + Glass remains the right pick if you also write code or want the AIOS docked beside a real editor — the doc now says that instead of implying the app path doesn't exist. Both surfaces drive the same vault through the same Claude Code, so it's a preference, not a fork, and either can be added later without redoing anything.
- **Know where you stand on Windows and Linux.** The app is macOS-only today, so the IDE + Glass is your surface there. That was previously implicit; it's now stated in both OS blocks.

**Component list:** `SETUP.md` → the Claude-facing 11-step block (step 1: one execution surface, plus the explicit instruction not to misroute app users) · *"The two things you'll use daily"* (renamed from *"Two apps you'll use daily — both required"*; two overlapping tables merged into one that carries both the choice and the reasons) · the AIOS Glass note (scoped to the IDE path, with an explicit skip for app users) · the **macOS** block (split into *Obsidian, always* + *one execution surface, a) or b)*, with the app's releases URL) · the **Windows** and **Linux** blocks (IDE stated as the only surface, with the reason).

**Action required (CHECK-THEN-ACT, idempotent):**
1. **Nothing to run — `/aios:update` applies the doc.** Verify if you like: `grep -c 'pick this \*\*or\*\*' SETUP.md` should return `2`.
2. **Only if you previously followed the old prerequisites AND you use the AIOS App:** you may have installed Antigravity and AIOS Glass you don't need. Nothing is broken — both surfaces coexist happily on one vault — so remove them only if you want the disk space back. Check what you actually have: `ls -d /Applications/Antigravity*.app 2>/dev/null || echo "no IDE installed — nothing to do"`.
3. **No restart needed** — this is documentation.

---

## 2026-07-25 — `/aios:compact` can actually hold the antifragile bound (condense, don't just delete)

`hash: 7d71f79`

> **What this delivers.** `antifragile.md` is read at *every* session start, so it carries a size bound — but the bound couldn't be met. Running the real thing on a vault at **88 entries / ~64k tokens** exposed the gap: Step 3.5's only lever was *removal*, and the two tiers it could remove from were nearly empty. Explicitly-marked entries freed ~4k tokens; the pre-90-day entries the spec would surface for confirmation averaged **5.6 lines each** — already tombstone-sized, so deleting all 28 would have freed ~8k while orphaning five `#N` pointers cited from USER.md and two commands. The weight was never in the old entries; it was in the **recent, load-bearing** ones the spec correctly says to keep (60 entries averaging 13 lines). A bound that can only be met by deleting the wisdom you're supposed to keep isn't a bound — it's a standing false alarm. This entry adds the missing lever (**condensation**) and re-bases the threshold on the thing that actually costs (**tokens**, not entry count).

**What you can now do:**
- **Get your antifragile file under budget without losing a single lesson.** `/aios:compact` now condenses verbose entries into tight *what-broke / why / fix* triplets instead of only deleting. Real run on this vault: **88 entries / ~64k tokens → 88 entries / ~33k tokens** — every entry number, the full meta-pattern index, and all exact commands, paths and hashes preserved. Roughly half the per-session read cost, zero wisdom removed.
- **Stop the alarm crying wolf.** The old bound (~50 entries / ~40k tokens) treated entry count as a first-class limit; it was only ever a proxy for size. The bound is now **~45k tokens (≈1,000 lines), or ~120 entries — whichever trips first**, so a file of many *terse* entries reads as healthy, which it is.
- **Trust that your `#N` cross-references survive a compaction.** Entry numbers are now explicitly identity: graduated/superseded entries get **tombstoned** (number + title + pointer retained), never renumbered. If your USER.md says *"Antifragile #17"* or a project note links `[[antifragile]] #42`, it still resolves after the pass — and the command now verifies exactly that (entry-set unchanged, index intact, no dangling `#N`, load-bearing commands still grep-able) before it writes.

**Component list:** `plugins/aios/commands/compact.md` → Step 3.5a (token-primary threshold + the `wc -c ÷ 3.7` / `grep -c` measurement recipe), Step 3.5c (**three tiers** — tombstone · **condense** · surface-for-confirmation — plus the pre-write verification checklist), Step 3.5d (report tokens AND entries), and two Rules (condense-as-a-lever; entry-numbers-are-identity-never-renumber). `CLAUDE.md` → § III Self-Update, antifragile **Bounded** clause — token-primary bound + the two levers, with *condensation is the primary lever* stated explicitly.

**Action required (CHECK-THEN-ACT, idempotent):**
1. **Nothing to run — `/aios:update` applies both files.** They're framework infra; this sync puts them live in your vault. Verify if you like: `grep -c '45k tokens' CLAUDE.md plugins/aios/commands/compact.md` should return 1 for each.
2. **Check whether your own antifragile is over the new bound, and compact if so.** `F="vault/00 - notes/context/observed/antifragile.md"; echo "$(( $(wc -c < "$F") / 3700 ))k tokens, $(grep -c '^### [0-9]' "$F") entries"` — if it's over ~45k tokens or ~120 entries, run `/aios:compact` (Step 3.5 is size-gated and fires on any invocation, independent of which month you're compacting). If you're under, it no-ops and says so.
3. **No restart needed** — command specs are read per-invocation. If your plugin cache is version-pinned and lagging, `claude plugin update aios@the-aios` refreshes it.

## 2026-07-25 — Every session knows the command bus (verbs, addressing, and a self-documenting inbox)

`hash: 658a2d1`

> **What this delivers.** The bus shipped on 07-23 worked — but only for a session willing to excavate it. Two real failures showed the gap: one session spent **six tool calls** grepping Glass's source to derive the `send` schema before it could message a peer, and another looked for a live session with **`pgrep`**, got a name that lies for a *resumed* session, and nearly declared a working peer dead. Both are knowledge gaps, not mechanism gaps — the bus was fine; nothing told sessions how to *address* each other or what the other two verbs even were (CLAUDE.md documented `spawn` only). This entry closes that in three layers: the **always-loaded contract** gains the `send`/`kill` verbs plus the addressing rule, the **orchestration-ladder skill** gains a full bus reference and the trigger phrases that actually match ("message session X", "who's running", "reply to whoever spawned me"), and the **inbox now documents itself** — Glass writes `~/.aios/spawn-inbox/README.md` on activation, so the component implementing the dispatch is the only thing describing it and the doc can't drift from the handler.

**What you can now do:**
- **Message another session without archaeology.** Say *"send a message to vivid-otter"* and your session already knows the verb and schema — it writes `{"action":"send","name":"vivid-otter","prompt":"hi from over here"}` into `~/.aios/spawn-inbox/` and Glass delivers it into that terminal as a new prompt. No grepping the extension source first. `{"action":"kill","name":"vivid-otter"}` retires it the same way.
- **Stop wrongly declaring live sessions dead.** The contract now names the one source of truth: live names come from the **session registry** `~/.claude/sessions/*.json` (`name` · `pid` · `status` · `sessionId`) — never `pgrep`, never a terminal tab's title, because a *resumed* session keeps whatever its tab was called. Example: a coordinator checking on a worker it spawned two hours ago finds it by registry name and gets a real answer, instead of an empty `pgrep` and a wrong conclusion.
- **Let a spawned worker answer you.** A worker replies to its coordinator with `send` to the coordinator's registry name, so the loop closes even when the coordinator is long-lived or resumed — agents hold real multi-turn conversations rather than fire-and-forget.
- **Read the bus reference at the point of need.** `~/.aios/spawn-inbox/README.md` (written by Glass 0.4.4, refreshed every activation) carries the three verbs with exact JSON, the addressing rule, how to reply, and the gotchas that each cost a bug — one-line prompts, "file vanished = picked up, not succeeded" (verify from the target's transcript at `~/.claude/projects/*/<sessionId>.jsonl`), and same-window reach.
- **Get the right skill to fire.** `orchestration-ladder` used to describe itself only as a *choose-a-primitive* lens, so a plain "say hi to session X" never loaded it. Its triggers now include session-to-session messaging, checking who's live, killing a worker, and replying to a spawner.

**Component list:** `CLAUDE.md` → *Spawning Sessions* — two new bullets: the `send`/`kill` verbs (with schemas) and the addressing rule (registry-is-truth, one-line prompts, consumed≠succeeded, transcript verification). `skills/aios/orchestration-ladder/SKILL.md` — widened `description` triggers (session-to-session messaging, who's-live, kill, reply-to-spawner) + a new **The command bus — how sessions actually reach each other** section (three verbs, addressing, replying, four failure modes, and the pointer to the self-written README). **AIOS Glass 0.4.4** (Open VSX) — writes/refreshes `~/.aios/spawn-inbox/README.md` on activation beside the `mkdirSync` that creates the inbox, plus a smoke guard so a refactor can't silently drop it.

**Action required (CHECK-THEN-ACT, idempotent):**
1. **Nothing for the framework half — `/aios:update` already applied it.** The CLAUDE.md contract and the skill are framework files; they're live in your vault as of this sync. Verify if you like: `grep -c 'action":"send' CLAUDE.md` should be ≥ 1.
2. **Update AIOS Glass to 0.4.4 for the self-documenting inbox — `/aios:update` does NOT deliver it.** Glass ships via **Open VSX**, and `~/.aios/spawn-inbox/` is machine-local runtime state, not a repo path, so nothing in this tree can place that README — Glass writes it, which is exactly why it can't drift from the handler. Check your installed version first; skip if already ≥ 0.4.4. Without it you still have the full contract (layers 1 + 2) — you just don't get the copy that lives in the folder.
3. **Restart the IDE (last step).** The README appears — or refreshes to match the running handler — on Glass's next activation.

## 2026-07-23 — Agent orchestration through AIOS Glass: the spawn-inbox command bus

`hash: fbcce4f`

> **What this delivers.** The day's real fix — it **supersedes the same-day settings-patch attempt below (`2baa2d4`)**, which didn't hold in auto mode. A recent Claude Code update broke agent-invoked `spawn` two ways at once: its **Bash sandbox** silently dropped the osascript keystrokes `spawn` used to open an IDE terminal (the keystroke-*leak* that hyperfrustrated operators — keystrokes landing in the wrong window), and its **auto-mode classifier** now gates `spawn`/`spawn-kill` outright, reading them as "launch/kill an autonomous agent" and denying with a **silent red dot, no prompt**. The classifier can't be talked, configured, or self-modified past agents-spawning-agents — by design (an agent can't author its own autonomy grant). So the fix moves the mechanism out of the agent's hands entirely: **an agent orchestrates real terminal sessions through the AIOS Glass command bus** — it drops a JSON request in `~/.aios/spawn-inbox/` and Glass (a user-trusted IDE extension) fulfils it **natively** (`vscode.createTerminal` / `sendText`) — no synthetic keystrokes, no gate. *Request, don't spawn.*

**What you can now do:**
- **Orchestrate real terminal sessions from inside a Claude session — through AIOS Glass.** An orchestrating agent can spawn a named worker, kill it, or send a prompt into a live one by dropping a small JSON file in `~/.aios/spawn-inbox/`; Glass launches, closes, or messages the session natively. Example: your coordinator writes `{"name":"researcher","task":"Sweep the Q3 filings","tier":"mechanical"}` and a `researcher` terminal boots on the cheaper model — then `{"action":"send","name":"researcher","prompt":"also check their pricing page"}` nudges it mid-run, and `{"action":"kill","name":"researcher"}` closes its tab cleanly. The optional `model`/`tier` dials spend to the work — *mechanical → cheap/fast, judgment → frontier*.
- **No more silent red dot when an agent tries to spawn.** Agent-invoked `spawn`/`spawn-kill` trips the auto-mode classifier (denied, no prompt). Agents now route through the Glass inbox — or, when Glass isn't present, `spawn` fails **loudly** with the exact inbox path and the operator-fallback (the Glass "Spawn a session" button, or a pasted `spawn`) instead of leaving you staring at a worker that never appears. See CLAUDE.md → *Spawning Sessions* for the contract.
- **Spawned workers are first-class, Glass-visible sessions.** A worker that inherited its parent's child-session marker used to be invisible in Glass's Running card, with no saved transcript and not resumable. Workers are now forced to persist — each registers the moment it starts and keeps its full transcript. Example: `spawn accountant` and it appears immediately in the Running list with a live status dot, resumable later like any session.
- **Pick the model per delegated worker — the orchestration-ladder skill now covers it.** The skill's spawn axis is rewritten around the command bus, plus a new *Choosing the model* section: subagent (`model` param), dynamic workflow (`agent(prompt,{model,effort})` per stage), spawn (`model`/`tier` in the inbox request) — *Calibrate-Don't-Choose* across all three.

**Component list:** `hooks/claude-identity/install-wrappers.sh` + `.ps1` — `spawn` boots the worker in-place inside a Glass-made terminal (marked `AIOS_GLASS_TERM`); `_claude_with_respawn` clears the inherited `CLAUDE_CODE_CHILD_SESSION` marker + forces session persistence; the earlier `ensure_sandbox_exclusion` settings-patch is **removed** (didn't deliver in auto mode). `CLAUDE.md` → *Spawning Sessions* — the agent-spawn contract. `skills/aios/orchestration-ladder/SKILL.md` — command-bus axis + *Choosing the model* section + anti-pattern. **AIOS Glass 0.4.2** (Open VSX) — the spawn-inbox command bus (spawn/kill/send + model/tier), transcript/registry fix across all launch paths, configurable `killBehavior`, settings-parity guard.

**Action required (CHECK-THEN-ACT, idempotent):**
1. **Update AIOS Glass to 0.4.2 — the critical step, and `/aios:update` does NOT deliver it.** Glass ships via the **Open VSX Registry**, not this repo. In Antigravity / VS Code / Cursor → Extensions → *AIOS Glass* → Update (auto-update also picks it up on reload). Without 0.4.2 the inbox doesn't exist and agents can't orchestrate sessions. Check your installed version first — skip if already ≥ 0.4.2.
2. **Re-run the wrapper installer** — `bash hooks/claude-identity/install-wrappers.sh` (macOS/Linux) or `powershell -File hooks/claude-identity/install-wrappers.ps1` (Windows). Idempotent; re-appends the updated `spawn`/`_claude_with_respawn`. (`/aios:update` auto-runs this.)
3. **RESTART your Claude Code sessions LAST** so the new wrappers + a clean session env load.

> **Supersedes `2baa2d4` (below).** That same-day fix added `sandbox.excludedCommands` (and later `permissions.allow` / `autoMode.allow`) to un-gate `spawn`. It didn't hold: in auto mode the classifier evaluates an *excluded* command regardless of allow-rules, and an agent cannot author its own autonomy grant (the self-modification guard blocks it — correctly). The command bus is the real fix; the settings-patch is removed from the installer, and any dead `autoMode.allow` rule is left for the operator to clear (it's harmless).

## 2026-07-23 — Spawn survives Claude Code's Bash sandbox (silent keystroke-drop fix)

`hash: 2baa2d4`

> **What this delivers.** A recent Claude Code auto-update turned **Bash-tool sandboxing on by default** (macOS `sandbox-exec`). A sandboxed process can read the accessibility tree but its **synthetic keystrokes to another app are silently dropped** — so agent-invoked `spawn` drove the IDE command palette into the void: no terminal, no worker, *no error*. Since agent-invoked spawn is the basis of orchestration, this quietly broke fleets. The wrapper installer now self-heals the operator's machine-local config, and `spawn` itself fails **loudly** instead of silently when the palette never opens.

**What you can now do:**
- **Spawn workers from an agent session again — without hand-editing anything.** Re-run the wrapper installer (`hooks/claude-identity/install-wrappers.sh`, or `.ps1` on Windows) and it ensures `~/.claude/settings.json` carries `sandbox.excludedCommands: ["spawn *", "spawn-kill *", "osascript *"]` — the sandbox stays ON globally, only the orchestration commands run un-sandboxed so their keystrokes land. Example: after re-running the installer and restarting your session, `spawn accountant "review Q1"` opens a real IDE terminal exactly as it did before the regression.
- **Get told what's wrong instead of staring at nothing.** If a spawned worker never appears within ~12s, `spawn` now prints the exact diagnosis (the sandbox dropped its keystrokes) and the surgical fix — instead of failing silently.

**Component list:** `hooks/claude-identity/install-wrappers.sh` — new `ensure_sandbox_exclusion()` (python3; backs up to `settings.json.bak-sandbox`, merges, never clobbers an existing `enabled` value or other excludes) run at install time, plus a post-spawn `pgrep` verification loop that warns loudly on silent failure · `hooks/claude-identity/install-wrappers.ps1` — PowerShell-native mirror (no python3 dependency; `osascript *` kept for cross-platform list-parity, harmless no-op on Windows).

**Action required (CHECK-THEN-ACT, idempotent):** Re-run the wrapper installer for your OS — `bash hooks/claude-identity/install-wrappers.sh` (macOS/Linux) or `powershell -File hooks/claude-identity/install-wrappers.ps1` (Windows). It reads your `~/.claude/settings.json` first and **only adds** the three exclusions if missing (no-ops with "already excluded — no change" when you're already fixed), backing up before any write. **Then RESTART your Claude Code sessions LAST** so the sandbox config reloads — sandbox settings are read at session start, not live. If you never invoke `spawn` from inside an agent session, this is optional: a human-typed `spawn` in a normal terminal was never sandboxed and never broke.

## 2026-07-22 — Personal-account setup guide for the Google Workspace MCP

`hash: 7ac52f6`

> **What this delivers.** A battle-tested, step-by-step guide for wiring the bundled **Google Workspace MCP to a personal Google account** — the setup an *agent machine* needs when the agent has its own gmail (its own Drive/Calendar/Tasks/Gmail, plus anything **shared with** it). Written from a live fortress-machine setup, so it front-loads the two 403 traps that eat the most time.

**What you can now do:**
- **Give a fortress/agent machine its own Google identity in ~15 minutes.** Follow `mcps/google-workspace-mcp/personal-account-setup.md`: create an External-consent project *under the personal account*, add it as a Test user (no app verification needed — Testing is the correct permanent state), create a Desktop OAuth client, and register the MCP with `--single-user` + a `600`-protected secret file. Example: give your overnight agent a gmail, share a Drive folder with it, and its sessions can read/file documents there — without touching your primary account's OAuth.
- **Debug the classic failures from a table** — `403 org_internal`, `403 access_denied`, `redirect_uri_mismatch`, the silent "consent URL never prints" stdout-buffer trap, "scope has changed", and remote-consent via `ssh -L 8000:localhost:8000`.

**Component list:** new `mcps/google-workspace-mcp/personal-account-setup.md` · pointer added in `mcps/_index.md` (next to the TROUBLESHOOTING reference).

**Action required:** none — the guide lands with your next `/aios:update` (docs only, no wiring changes to existing setups). Read it only when you're ready to give an agent its own Google account.

## 2026-07-21 — Race-safe session close (AI-2) · update-completeness · tracked `.obsidian`

`hash: 742f049`

> **What this delivers.** Closing sessions is now **structurally race-safe** — many sessions can wrap up at once (a Glass "Close all" broadcast, or several manual closes) without scrambling each other's git attribution or clobbering the daily note. The fix is a new commit primitive, `aios-commit`, that replaces the old "never `git add -A`" *discipline* with a *poka-yoke*: the unsafe broad commit is now **impossible**, not just discouraged.

**What you're getting — canonical framework:**
- **`aios-commit`** — the one sanctioned commit path (`hooks/aios-commit`). Per-repo **mutex** (serialises concurrent commits), stages ONLY the paths you name via a **throwaway index** (*the working tree is never touched* — Obsidian's live copy is safe), **self-scans for secrets**, and **defers the push** on offline / diverged-remote (never orphans a commit). A **`--vault`** mode sweeps the session's changed vault paths for you — **space- AND rename-safe** (no more `git status | awk` truncating `vault/00 - notes/…` and staging nothing).
- **`aios-note-append`** — a locked merge-append helper: N sessions closing at once each land their daily-note block *in turn* (per-file lock), ordered and clobber-free.
- **`/close-session --auto`** — a non-interactive self-close (infers its label, skips prompts) so a broadcast completes and returns to idle. Vault sessions merge-append their block; project/worker sessions write their own report to the **one canonical dir `~/aios/.claude/`** — so a session in *any* repo gets harvested, with no dependency on registering it.
- **`/close-day` is now the single writer of observed context.** Under a broadcast, every close-session *defers* its Tier A/B routing into its own surface; close-day harvests them all and routes **once** — so parallel closes can't race on `growth.md` / `patterns.md` / etc.
- **Self-update stamp fix** — every observed-context write now bumps its `updated:` frontmatter, co-located with the mandatory snapshot. The staleness alarm reads *only* that stamp, and it had drifted up to 17 days — so the "reliable backstop" was being fed stale data. Fixed at the choke point (the snapshot rule).
- **CLAUDE.md** — § Discipline's two `git add -A` commands are replaced with `aios-commit --vault` (the discipline→structural swap this release exists for).
- **`/aios:update` now commits its own applied files** (atomic apply→advance→commit, via `aios-commit` scoped to exactly the Tier-1 files it applied + the tracker). So after any update the vault is always committed + pushable — never sitting applied-but-uncommitted (which would drift the vault from canonical for anyone who pulls it). Framework-sync commits stay distinct from session-work commits, and `aios-commit --vault` stays scoped to vault *content*.
- **Update-completeness fix — `/aios:update` now ships EVERY root doc, not a hardcoded subset.** Three reference docs — **`AGENTS.md`** (portable operating contract for non-Claude tools · Codex/Cursor/Aider), **`EXTENSION-MAP.md`** (the how-to-extend reference: bundled/custom/company × every infra type), **`LICENSE-AUDIT.md`** (the open-core license boundary) — had shipped to canonical but **silently never reached vaults**: they weren't in `/aios:update`'s enumerated root-docs list, and the completeness reconcile used the *same* list, so the backstop shared the primary's blind spot. Now **Step 6.5's reconcile diffs *every* root `*.md` generically** (+ an explicit existence test — a bare `diff` on a missing file only errors to stderr, which is exactly why the gap was invisible), a **CI guard** fails the build if a syncable root doc isn't in the sync list, and the three docs are wired into the doc map (CLAUDE.md · README · CONTRIBUTING · NOTICE). A new root doc can never be added-but-not-shipped again. *(`USER.md`/`INTENT.md` are explicitly excluded from the reconcile — they're your filled-in files, never overwritten with the templates.)*
- **`vault/.obsidian/` is now tracked** (config · plugins · graph layout · navigator state) — portable across machines; only the per-click pane-layout (`workspace.json` / `workspace-mobile.json`) stays ignored, and `aios-commit --vault` sweeps the rest so it never nags as uncommitted. Resolves the tracked-but-ignored contradiction where already-committed `.obsidian` files kept showing modified under a broad ignore.
- **Regression test for the commit primitives** (`tests/aios-commit.test.sh` → new CI job) — locks the `--cached` no-op, the `--vault` space/rename-safe sweep + machine-local excludes, scoped staging, the secret-scan, and note-append before-marker/end-append, so these can't silently regress.
- **`.gitignore` now MERGES on update (dual-owned, like `marketplace.json`)** — the last update-preservation gap. `.gitignore` was a plain Tier-1 overwrite, so an operator's personal ignores (e.g. a private-reports rule) were dropped on every sync (surviving only in a backup). Now canonical `.gitignore` ends with an `# ═══ AIOS-OPERATOR-IGNORES ═══` marker; operators put personal rules **below** it, and `/aios:update` merges (upstream framework rules + your below-marker lines preserved — proven idempotent). The reconcile excludes `.gitignore`/`marketplace.json` so operator lines don't flag as perpetual drift.

**What you're getting — AIOS Glass v0.4.1:**
- A **"Close all"** title-bar button (shown only when a session is running): a multi-select picker of every live session — **all selected by default**, each with its true status dot (🟢 idle · 🟡 working · 🔵 needs-input). Broadcasts `/close-session --auto`; two optional post-actions — **run `/close-day`** (in your primary session) and **kill the terminals** (every selected *except* your primary). Plus a **"Launch primary"** fix (reveals a running primary by pid-ancestry instead of no-op'ing).

> ⚠️ **Update your Glass extension to v0.4.1** (Open VSX). The "Close all" button needs *this* canonical update's `--auto` close-session + single-writer `/close-day` to work end-to-end — ship them together.

**📋 What you can now do (the practical read):**
- **Wrap up your whole fleet in one move** — hit **Close all** in Glass, pick which sessions, and each one captures itself (its daily-note block, or its own report in `~/aios/.claude/`) and returns to idle — safely, in parallel. Optionally consolidate the day and kill the terminals in the same pass; your primary session is always protected.
- **Stop worrying about concurrent commits** — you-in-Obsidian, agent sessions, and routines can all commit at once now; `aios-commit` serialises them and each commit carries only its own author's paths. The old "never `git add -A`" rule is enforced *structurally*, not by memory.
- **Trust the staleness alarm again** — `growth` / `profile` / `ecosystem` staleness is measured from *real* edits (the `updated:` stamp is maintained on every write), so `/today` and `/close-day` stop crying wolf on files that were actually just updated.
- **Trust that updates ship everything** — `AGENTS.md`, `EXTENSION-MAP.md`, `LICENSE-AUDIT.md` (which had been stranded in canonical) now land in your vault, and the reconcile catches *any* future root doc automatically. Ask *"how do I add an agent/skill?"* → I route you to `EXTENSION-MAP.md`; *"what can I redistribute?"* → `LICENSE-AUDIT.md`.

**Action required (CHECK-THEN-ACT, idempotent):**
1. **Install the commit guard** — this is what turns the discipline into enforcement. Run the installer for **your OS** (it sets the repo's `core.hooksPath` + puts `aios-commit` on PATH; idempotent — re-running is safe):
   - **macOS / Linux:** `bash ~/aios/hooks/install-git-hooks.sh`
   - **Windows:** `pwsh -File $HOME\aios\hooks\install-git-hooks.ps1` — and **if `pwsh` isn't found** (a stock Win11 ships only Windows PowerShell 5.1, not PowerShell 7), use `powershell -File $HOME\aios\hooks\install-git-hooks.ps1` instead. The guard scripts themselves are bash and run under **Git Bash** (Git for Windows always ships it; git invokes hooks via `sh` on every platform), so the `.ps1` only does the per-machine `git config` + writes an `aios-commit.cmd` shim to `$HOME\bin` — **ensure `$HOME\bin` is on your PATH**.

   After install, a raw `git commit` is blocked with a pointer to `aios-commit` (bypass once with `AIOS_HUMAN=1 git commit …` if you ever must — it still secret-scans). Verify: a raw `git commit` in `~/aios` is now refused.
2. **Command updates** (`/aios:close-session`, `/aios:close-day` changed) — refresh the plugin cache: `claude plugin update aios@the-aios`. No-op if already current.
3. **[Glass — separate surface]** Update **AIOS Glass to v0.4.1** from **Open VSX** (Antigravity / OSS editors; publishes to Open VSX only), then restart the editor to load it — this is what gives you the **Close all** button.
4. **Verify the three formerly-stranded reference docs landed.** This same `/aios:update` should have pulled them (via the new generic reconcile); confirm:
   ```bash
   for f in AGENTS.md EXTENSION-MAP.md LICENSE-AUDIT.md; do [ -f "$HOME/aios/$f" ] && echo "✓ $f" || echo "✗ MISSING $f"; done
   ```
   All ✓ → done. Any ✗ MISSING → re-run `/aios:update`; Step 6.5's reconcile pulls it (report it if it doesn't — that would mean the reconcile itself regressed). **Also:** put any personal `.gitignore` rules **below the `# ═══ AIOS-OPERATOR-IGNORES ═══` marker** — `/aios:update` now MERGES `.gitignore` (framework rules updated, your below-marker rules preserved), so they survive updates. Rules that must never reach ANY clone (a secret, an OAuth cache) still belong in `.git/info/exclude`.
5. **[do last — restart]** Restart your Claude Code session so the updated CLAUDE.md loads.

---

## 2026-07-20 — Tier-A authoring cut + AIOS Glass v0.4.0 (the extension, not the framework)

`hash: f2787d7`

> **What this delivers.** A consolidated "Fable-week authoring" cut — specs designed across the Fable weeks, authored into canonical in ONE coherent release — paired with a new **AIOS Glass** extension version. Bundled deliberately (one release, one changelog) so operators get one coherent update, not a drip of dozens of entries.

**What you're getting — canonical framework:**
- **New skills (2):** `deep-research` (multi-source research harness — the engine behind the strategy agents) · `orchestration-ladder` (agent → parallel → workflow decision lens). Plus a **CI skill-resolution gate** that fails the build if any bundled agent references a skill that isn't shipped (already caught two latent dangling refs).
- **Agents:** `animation-composer` (NEW — owns the deck-animation component library) · `study-buddy` → the **Study Atlas** format (one interactive `{slug}-atlas.html` + one `{slug}-source.md` spine, replacing the old brief-pile) · `deck-builder` → presenter-notes + backlog + click-nav-default-off (**+ mobile tap-nav auto-on** — touch / coarse-pointer devices always get tap-right-advances / tap-left-back, so a phone user isn't stuck on slide 1) + `S` deck-search · `onboarding-aios` → concierge + install-doctor (detects App/terminal/IDE, troubleshoots installs + updates).
- **Framework internals:** observed-context **Tier-B staleness** hardening (`/aios:close-day` + `/aios:today` + CLAUDE.md) · **memory-pressure channeling** doctrine (CLAUDE.md § Context Hierarchy + `/aios:housekeeping` **Bucket 24** — when auto-memory nears its ceiling, channel WHAT to the vault before compacting HOW, so a full cache never silently drops durable context) · **stewardship-skill wiring** (4 previously-orphaned skills — `sustainable-cadence` · `leverage-points` · `commons-governance` · `comprehension-debt` — now named at the judgment moment across 10 agents + 6 commands; the CI gate enforces it) · **spawned-output placement discipline** (spawn briefs name the output destination; `reflections/analysis/` default landing zone + `/aios:housekeeping` **Bucket 25**).
- **Ingest — media comprehension (macOS enhancements to `/aios:ingest`):** `transcribe.py` (long-form local audio/video via mlx-whisper — MarkItDown's one audio weakness) + `video-watch.py` + `ocr-image.swift` (reads the video *screen* — slides/code/diagrams MarkItDown discards entirely; on-device Apple Vision OCR + `claude -p` VLM, Fortress-clean, no API key). **MarkItDown stays the universal cross-platform default** — these are surgical macOS add-ons; non-Mac never regresses (MarkItDown handles everything it already did, YouTube captions included).
- **Small fixes + reference docs** *(the "quality-of-life" pile — individually minor, collectively the friction that wears you down):* spawn-installer guards (a stale shell that mis-binds `--tier`/`--model` args now fails loudly instead of spawning a junk worker · palette-leak Escape guard) · `orchestration-ladder` decision-lens skill · `AGENTS.md` portable contract · `LICENSE-AUDIT` · `EXTENSION-MAP`.
- **Community-contributed fixes** *(thank you — imported with credit, PRs #5 + #2):* the spawn installer's AppleScript comments now escape their backticks (raw `` `activate` `` was command-substituted at spawn runtime → stderr noise) [#5] · the account-swap autopilot now sends its notification + in-session banner **only on a successful swap** — a single-account rotation attempt no longer falsely announces a swap that didn't happen [#2].

**What you're getting — AIOS Glass (new extension version):**
- Explorer **per-folder sort** (name / last-modified, persisted per folder) · **smart-route** terminal default · **kill-guard** (always-confirm on close) · **session post-its** (create · view · delete · harvest-on-kill) · **status card** (framework/vault/account/skills-commands wiring) · Explorer **i18n** (es/pt-br).

> ⚠️ **Update your Glass extension.** This canonical release ships alongside a new AIOS Glass version. VS Code / Antigravity extension auto-update is unreliable — so **canonical is the channel that tells you**: a new Glass is out, update it (Action required, step 5).

**📋 What you can now do (the practical read — new capabilities in plain language).**
*You shouldn't have to read a skill's source to know what it adds to your day.* Concretely, this version lets you:
- **Ingest a video and have Claude read the SCREEN, not just the audio** *(macOS)*. Paste a talk and say *"ingest this and **read the slides** — there's code on screen"*: Claude grabs the transcript AND reads each slide verbatim — the `~1e24 FLOPS · 6,000 GPUs · $2M` on a slide the narrator never spoke aloud, the code with `C001` intact — then files the merged result. Slide decks, coding screencasts, and whiteboard talks stop losing half their signal. *(Plain `/ingest <video>` stays audio-only + fast — the screen layer is opt-in, triggered by "read the slides / code on screen.")*
- **Transcribe long-form audio/video locally** *(macOS)* — a 49-min interview or lecture, on-device (mlx-whisper), any length, no third party. *(MarkItDown still handles short clips + YouTube captions on every platform — it stays the default.)*
- **Ask "what should I write / build / do next?" and get researched, ranked answers** — the new `deep-research` skill maps your existing vault first (no repeats), sweeps the field, and returns ranked angles each with a *why* + *how*. Try: *"what should our next post be about?"* Your strategy agents (consultant, market-researcher…) now run this under the hood.
- **Study a book into one living atlas, not a scattered pile of briefs** — `study the next chapter` grows one interactive `{book}-atlas.html` you navigate + revisit, instead of loose chapter notes.
- **Stop losing context when auto-memory fills up** — as memory nears its ceiling, Claude now offers to *channel* durable facts into your vault (their real home) before compacting, instead of silently dropping whatever falls off the end.
- **Trust Claude to reach for the right judgment-lens at the right moment** — `/drift` won't mislabel paced or quality-gated work as avoidance · `/7plan` checks the week is *sustainable* + high-leverage · `/challenge` tests whether you're intervening at a low-leverage point. *(That's `orchestration-ladder` + the stewardship wiring — you never invoke them; they make Claude wiser at the decision moments, so a one-shot task doesn't balloon into a workflow and a 20-file migration doesn't get crammed into one agent.)*
- **In AIOS Glass** *(update the extension from Open VSX — Action step 5)*: **sort any folder** — Vault, Framework, or any subfolder at any depth — by name or newest, and each folder remembers its own choice · a **Health card** shows at a glance whether your framework, vault, account, and skills/commands are wired (with one-click fixes) · **kill-guard** confirms before you close a busy session so you never lose in-flight work · jot and read **post-its** on your live sessions · the calendar shows **ISO week numbers** (toggle in the cog) · the file tree now speaks **es / pt-BR**.

**The full surface area** (for the record — everything agent-authored + coordinator-verified this cut): 2 new skills (`deep-research` · `orchestration-ladder`) + a CI gate · 1 new agent (`animation-composer`) · 4 enhanced agents (`study-buddy` · `deck-builder` · `onboarding-aios` + stewardship wiring on 10) · CLAUDE.md + command changes (Tier-B staleness · memory-channeling `/housekeeping` B24 · spawned-output B25 · stewardship on 6 commands) · the 2 macOS ingest hooks · small fixes + docs (`AGENTS.md` · `LICENSE-AUDIT` · `EXTENSION-MAP` · spawn-installer guards) · 2 community PRs imported with credit (#5 · #2) · Glass (separate extension).

> **Worth an actual read** (these change how every session behaves): the **CLAUDE.md deltas** (memory-channeling · aggregate observed-context · spawned-output routing) + the **`/close-day` hard-gate** — the Tier-B observed-context refresh is now a *required* close-day output, so your `ecosystem`/`profile`/`growth` files can't silently rot. Everything else is additive or opt-in.

**Action required (CHECK-THEN-ACT, idempotent):**
1. **New skills** — register them after this sync: `bash ~/aios/skills/setup.sh` (idempotent; wires `deep-research` + `orchestration-ladder` into `~/.claude/skills`). No-op if your setup auto-runs it.
2. **Command updates** (`/aios:today`, `/aios:close-day`, `/aios:housekeeping` changed) — refresh the plugin cache so you run the new versions: `claude plugin update aios@the-aios`. No-op if already current.
3. **Spawn wrapper fixes** — only if you use `spawn`: re-run `bash ~/aios/hooks/claude-identity/install-wrappers.sh`, then `source ~/.zshrc` in open shells. No-op if already current.
4. **[do last — restart]** Restart your Claude Code session so the updated CLAUDE.md loads.
5. **[Glass — separate surface]** Update the AIOS Glass extension in Antigravity (or your OSS editor) from **Open VSX** — the extension publishes to Open VSX only. (Extensions auto-update but need a manual editor restart to load the new version.)

---

## 2026-07-13 — Mount-guard: a PreToolUse hook that blocks editing company-context mounts

`hash: 55403f8`

> **What this heals.** Files under `vault/00 - notes/context/ventures/{v}/` are *mounts* of a `{v}-context` source repo — they arrive via `/aios:company --sync`. Editing the mount directly feels natural (it's right there in your vault), but the edit is silently reverted on the next sync and never reaches the source of truth other operators pull from. This is a documented trap that still recurred — twice, in the maintainers' own vault — because the guardrail lived in *recall* (a rule you had to remember before editing). This update moves it to *enforcement*.
>
> **What you're getting:**
> - **`hooks/guard-venture-mount.py`** — the framework's first PreToolUse hook. On any Edit/Write/MultiEdit/NotebookEdit to a `context/ventures/{v}/` path carrying a `.{v}-sync` marker, it blocks and points you at the `{v}-context` source repo + `/aios:company --sync {v}`. Design guarantees: **fail-open** (any error, or a `ventures/` folder with no marker, → allows — it can never brick editing), **deterministic** (editing a mount is always wrong → ~nil false-positives), **escape hatch** (`AIOS_ALLOW_MOUNT_EDIT=1`), and the sync path is exempt (rsync runs via Bash, not Edit/Write).
> - **SETUP.md §10 Hook C** + **`hooks/_index.md`** — wiring + docs.
>
> **Action required (CHECK-THEN-ACT, idempotent):**
> 1. Confirm the script synced: `test -f ~/aios/hooks/guard-venture-mount.py && echo ok`. Prints nothing → your sync didn't complete; re-run `/aios:update`.
> 2. Wire it **only if not already wired.** Check `~/.claude/settings.json` for a `hooks.PreToolUse` entry calling `guard-venture-mount.py`. If absent, merge this in — alongside your existing `UserPromptSubmit`, do **not** replace the `hooks` object:
>    ```json
>    "PreToolUse": [
>      { "matcher": "Edit|Write|MultiEdit|NotebookEdit",
>        "hooks": [ { "type": "command", "command": "python3 ~/aios/hooks/guard-venture-mount.py", "timeout": 10 } ] }
>    ]
>    ```
>    Windows: use `python` instead of `python3`. No-op if already present.
> 3. **[do last — restart]** Restart your Claude Code session so the PreToolUse hook loads — scripts sync live, but hook *registration* only loads at session start, so until you restart the guard is inert. After restart, verify: ask Claude to edit any `context/ventures/{v}/*.md` — it should refuse with a source-repo pointer. (No company mounts? Nothing to test; the hook stays a silent no-op for you.)
>
> Background: `antifragile.md` #81 — guardrail placement (recall vs enforcement); the twice-recurring mount edit is what motivated moving the check into the harness.

---

## 2026-07-13 — Ship-time truth-flip: the anti-drift contract (project notes stay honest in real time; keyed roadmaps opt-in)

`hash: 99c02e8`

> **What this heals.** Every vault accumulates the same silent gap: work ships, but the surface that tracks it finds out at the next close-day — or never. A session finishes something and moves on; the project note keeps saying "pending"; the daily note, the weekly plan, and an `_index` snapshot each hold their own version of the status; and days later nobody is sure which one is true without re-checking git. Drift like this was caught at scale in a real ground-truth audit (14 repos + 11 live surfaces vs. their tracking labels — a dozen items were done in reality but "pending" on paper, and one "shipped" build had never left a local branch). This update makes the fix structural instead of heroic.
>
> **What you're getting:**
> - **CLAUDE.md § Discipline → "Ship-time truth-flip — the anti-drift contract."** Every tracked item has exactly ONE *truth surface* — for almost everything, **that's the project note you already have; nothing to configure.** The rule: the session that ships something updates its truth surface **in that same session** (not at close-day); daily notes / weekly plans / snapshots only *reference* it; `/close-day` + `/close-session` become **reconcilers** that verify and flag misses instead of being the only place status catches up. Includes the edge rules: spawned workers report ships in their capture and the coordinator flips at harvest; ships that happen outside any session (a browser upload, an external party acting) are flipped by the first session that learns of them.
> - **`/aios:close-day` + `/aios:close-session`** each gain one reconcile step wired to the contract.
> - **`/aios:housekeeping` Bucket 23 — truth-surface drift (buckets 22 → 23).** The detection twin: flags active project notes that are *older than their own repo's latest commits* ("note may lag reality"), plus roadmap-file edge cases. Zero config; lanes that don't apply to you report themselves skipped.
> - **`templates/aios/roadmap-template.md` — the opt-in instrument.** For a big multi-project push that wants ONE prioritized surface over many notes: a *keyed roadmap* (stable per-family keys like `AB-1` — keys are identity, list order is priority, never renumber), self-declared via `type: roadmap` frontmatter, optional `ledger:` for a ship-CHANGELOG. When the push ends, a retirement checklist (close every key, then `status: archived`) hands ownership back to project notes automatically. **If you never instantiate it, nothing about your vault changes** — no ledger is required anywhere, because for unkeyed work *the git commit is the ledger*.
>
> **Action required (CHECK-THEN-ACT, idempotent):** none — this lands entirely through the synced files; defaults preserve current behavior everywhere. *(Optional, only if you run a large push:* instantiate `templates/aios/roadmap-template.md`, grep first so your key prefixes don't collide.*)* No restart needed.

---

## 2026-07-12 — `spawn --model <id>` / `-Model`: pin an explicit model, no global-env hack

`hash: 971bfc8`

> **`spawn` could pick a *tier* (`--tier mechanical|judgment`) but not an arbitrary model.** Pinning a temporary or specialist model — e.g. Fable during an extension window — meant `export CLAUDE_MODEL` in your `~/.zshrc`, spawn, then remember to revert. Miss the revert and *every* future terminal silently launches on the pinned model. This adds a first-class flag that reuses the wrapper's existing per-spawn export path, so there's no global state to leak.
>
> **What changed:**
> - **`spawn --model <id>`** (and `--model=<id>`; Windows **`-Model <id>`**) — position-independent, parsed alongside `--tier`. Sets the spawned session's model directly and **overrides `--tier`** when both are passed. Exported as `CLAUDE_MODEL` in that spawn's launcher only (the wrapper already did this for `--tier mechanical` — `--model` just lets you name *any* model). Example: `spawn --model claude-fable-5 researcher "..."`.
> - **CLAUDE.md § Spawning Sessions** — documents the flag + why it exists (kills the global-`~/.zshrc` dance and its stranding footgun).
> - Both installers updated: `install-wrappers.sh` (bash/zsh) + `install-wrappers.ps1` (PowerShell).
>
> **Action required (CHECK-THEN-ACT, idempotent):** after `/aios:update` lands the new `hooks/claude-identity/install-wrappers.*`, check whether your live `spawn` already has the flag — macOS/Linux: `type spawn | grep -q -- '--model' && echo have || echo need`. If `need`, **re-run the installer** (`bash ~/aios/hooks/claude-identity/install-wrappers.sh`; Windows: `pwsh ~/aios/hooks/claude-identity/install-wrappers.ps1`) — idempotent (backup → strip → append → verify → auto-rollback). **LAST:** `source ~/.zshrc` / open a new terminal so the updated function loads (open shells keep the old one until re-sourced).

---

## 2026-06-30 — Team-archetypes lens + comprehension-debt (compose the fleet · guard your understanding of it)

`hash: 5a53c36`

> **Two complementary additions, both about keeping a growing agent fleet healthy.** One gives you a lens to *compose* the fleet by lifecycle posture; the other guards *your understanding* of what that fleet ships without you.
>
> **Team-archetypes (#3, `6b45dd3`):**
> - New **`skills/aios/team-archetypes`** — Cherny's five product archetypes (Prototyper / Builder / Sweeper / Grower / Maintainer); compose a team OR an agent fleet by lifecycle posture matched to product stage (with a `references/` source file).
> - **Two new engineering agents** closing the lifecycle gap the lens exposed: **`growth-engineer`** (Grower) + **`refactor-engineer`** (Sweeper). Bundled agents 31→33.
> - **`archetype:` tags** on agents (posture, orthogonal to domain capability); `/7plan` + `/emerge` can now check the deployed mix matches a project's stage. A YAML-frontmatter CI fix for two prior skills is folded in.
>
> **Comprehension-debt (#4, `5a53c36`):**
> - New **`skills/aios/comprehension-debt`** — keep the operator's understanding from falling behind what their agents ship (the gap between what the vault/repos *contain* and what the operator *understands*). The defensive complement to *Arc sessions*; framed explicitly as the **operator's** risk, not the model's — the risk sharpens *as the loops get better*.
> - **CLAUDE.md § VI** principle (recap-first offer; the *"could you defend, debug, or decide on this right now?"* test) + the Agentic-Culture sticky reminder corrected to *"our leadership culture"* (model + operator co-orchestrate — a genuinely shared referent).
> - **`/close-session`** — comprehension-ledger step: recap the session's agent-authored changes as a bullet list FIRST (you can't ask about what you don't know shipped), then *offer* to walk through them; un-grasped work carries forward as debt, not done.
> - **`/aios:housekeeping`** — Bucket 22 (agent-output gate health): spot-check that gates still catch the failure modes you care about ("gates rot") + a 30-day permission re-audit clock.
> - Skill counts bumped across both additions (`skills/aios/` 20→22; total bundled 45→47).
>
> **Plus — marketplace source-type fix (`/aios:update` + `/housekeeping` Bucket 11):** both commands hard-assumed a **GitHub-source** marketplace and hardcoded `~/.claude/plugins/marketplaces/the-aios/…` for the command-sync copy. But the **primary AIOS mode is a directory-source marketplace** (`the-aios` registered as `Directory → ~/aios`) — that's what carries ventures + `custom/` a GitHub clone would miss. On directory-source that path doesn't exist, so the marketplace copy silently no-op'd and Bucket 11 would mis-flag the absent dir as drift. Fix: the marketplace copy is now `[ -d ]`-guarded (cache is runtime-authoritative either way), and Bucket 11 detects the source type and verifies the **cache only** on directory-source. Found dogfooding this very update.
>
> **Action required:** None — `/aios:update` delivers both skills, the two new agents, the CLAUDE.md + command edits, and the index updates automatically (skills + root docs are Tier-1 sync; bundled command/agent edits self-sync; the skills registrar re-runs). **One reload, LAST:** after the update applies, **restart your Claude Code sessions** so the new skills + agents load. If you'd locally edited any touched bundled file, your version is backed up before overwrite — standard Tier-1 behavior.

---

## 2026-06-25 — CONTRIBUTING.md at repo root + 3 bundled "other-wing" skills (systems/stewardship lenses)

`hash: 996a86d`

> **The framework had no contribution guide of its own.** The onboarding agent pointed operators at an org `.github/CONTRIBUTING.md` that didn't exist, and a dead `the-aios.com/manual` URL (404 in prod) was linked from several docs. This adds a real `CONTRIBUTING.md` at repo root, fixes the surrounding doc drift, and teaches `/aios:update` to deliver it.
>
> **What changed:**
> - **New `CONTRIBUTING.md`** at repo root — organized around two contribution flavors: **non-technical** (no PR — report a problem-*class* via Issue/email/Discussion; lightweight RFC for design forks) and **technical** (PR — canonical to `The-AIOS/aios`, or company-distributed via `/aios:company`). Covers `custom/`-first, the promotion path, how-to-add each infra layer, the testing/evidence bar + a before-you-PR checklist, personal hygiene (zero operator data), commit/CHANGELOG conventions, and licensing.
> - **`/aios:update` now syncs `CONTRIBUTING.md`** as a Tier-1 root doc — added to the root-docs list, the tracker-diff, and the Step-6.5 completeness reconcile (so it lands on every vault and self-heals if missing).
> - **Doc pointers corrected:** the CLAUDE.md doc-map, README, START-HERE, and `onboarding-aios` now point to `CONTRIBUTING.md` at repo root (was: a non-existent org `.github` file).
> - **Manual URL fixed everywhere:** `the-aios.com/manual` (404) → `https://www.the-aios.com/#manual` (the manual is now a homepage section). 8 references across README, CHEATSHEET, CONTRIBUTING, `onboarding-aios`, `cold-start-interview`.
> - **License reference corrected:** the framework is uniformly **GPL-2.0-or-later** (`onboarding-aios` had wrongly described the install as "Apache-2.0"; Apache applies only to vendored third-party dirs like `skills/anthropic/`).
>
> **Also shipped — 3 new bundled skills (`skills/aios/`), the "other-wing" systems/stewardship lenses** (the worldview-neutral mechanisms extracted to core; any lineage/worldview stays in an operator's own `USER.md`/template):
> - **`leverage-points`** — Donella Meadows' lens for *where* to intervene in a system (push toward goals/rules/paradigm, away from parameters/buffers). The systems-science backing for "fix the system, not the symptom."
> - **`sustainable-cadence`** — the operator's capacity/pace as a first-class design input; a test for telling *paced* work (legitimate quality gate / rhythm) apart from *avoidance*. The generative complement to the (all-defensive) anti-values.
> - **`commons-governance`** — Elinor Ostrom's 8 commons design principles applied to AIOS shared substrate: multi-operator vaults, collaboration spaces, company-synced infra, and multiple agents writing one repo.
> - Each ships a `references/` file citing the public source work. A new **sticky reminder** in `CLAUDE.md` ("the operator's capacity is a design input…") hooks the cadence lens. Skill counts bumped (`skills/aios/` 17→20; total bundled 42→45).
>
> **Action required:** None for the docs — `/aios:update` delivers `CONTRIBUTING.md`, the corrected root docs, and the 3 new skills automatically (root docs + `skills/` are Tier-1 sync; bundled command edits self-sync; the skills registrar re-runs on this update). **One reload:** after the update applies, **restart your Claude Code sessions** so the 3 new skills load. If you'd locally edited any of these root docs, your version is backed up before overwrite — standard Tier-1 behavior.

---

## 2026-06-24 — Plugin/marketplace registration hardened (version-agnostic paths · vault-sourced marketplace · venture-plugin + bundled-skill auto-registration)

`hash: d1fb9bf`

> **One root cause, several faces: the *install silently lagged the source*.** Across the plugin pipeline, paths + registrations were frozen at setup-time and never tracked the live vault — all failing *silently*. Symptoms: a hard-pinned `0.1.0` cache path that broke the moment a machine reached `0.2.0`; a marketplace registered as a *frozen copy* of the vault (never tracked version bumps, never saw custom/venture plugins); newly-pulled bundled skills landing unregistered. Surfaced by a teammate on 0.2.0. The through-line fix: **the vault is the single source of truth, and every registration lane now tracks it.**
> - **Version-agnostic plugin-cache path** — both `cp` sites in `/aios:update` (bulk command-sync + the Step-2.5 self-update guard) + the `/housekeeping` cache-verify now **glob the installed version dir** (`the-aios/aios/*/commands/`, `[ -d ]`-guarded). No path pins a version again.
> - **Marketplace is vault-sourced** — SETUP §6 now does `claude plugin marketplace add ~/aios` (the **vault** directly; `add` copies *selectively* — only `marketplace.json` + referenced plugin dirs, ~540K, not the multi-GB vault). The vault's `marketplace.json` is one growing catalog across all three plugin layers; later additions register there and load via `marketplace update` + `install`. Never hand-copy a frozen marketplace dir again.
> - **Venture plugins auto-register** — `/aios:company` new **Step 5.6** registers each synced company plugin into the vault's `marketplace.json` (MERGE) + refresh + install — the plugin mirror of Step 5.5 (skills).
> - **Bundled skills auto-register on update** — `/aios:update` now gated-auto-runs `skills/setup.sh` when a bundled `SKILL.md` changes (symlinks into `~/.claude/skills`). The three lanes are now all sound: **plugins** (marketplace, vault-sourced) · **skills** (symlink registrar, auto-run on update + sync) · **agents** (glob — needs nothing).
>
> **Action required (check-then-act — your session verifies its OWN state, acts ONLY if needed; no-op if already correct):**
> The version-agnostic + skills fixes **auto-apply** (`/aios:update` pulls the corrected command files) — nothing to do. The marketplace re-point is the one stateful check:
> 1. **CHECK:** `claude plugin marketplace list` → the `the-aios` `Source:`.
>    - **Your vault** (`Directory (…/aios)`) → already correct, **do nothing** (fresh install, or already re-pointed).
>    - **A frozen copy** (`Directory (…/.claude/plugins/marketplaces/the-aios)`) → re-point (step 2).
> 2. **Re-point (only if frozen):**
>    ```bash
>    claude plugin marketplace remove the-aios
>    claude plugin marketplace add ~/aios
>    claude plugin marketplace update the-aios
>    claude plugin install aios@the-aios
>    # + reinstall any custom/venture plugins you use: claude plugin install <name>@the-aios
>    ```
> 3. **VERIFY:** Source is now your vault + `claude plugin list` shows the current `aios@the-aios` version (no version is hard-pinned — it picks up whatever the vault's `marketplace.json` declares). Restart sessions to load. **Safe on every machine** — check-first, not a blind command.

### What changed
- `plugins/aios/commands/update.md` (`011b5ae`, `5c27c47`, `d1fb9bf`) — version-agnostic plugin-cache `cp` (both sites); auto-run `skills/setup.sh` on bundled-skill change; CHANGELOG action-items are check-then-act.
- `plugins/aios/commands/housekeeping.md` (`011b5ae`) — Bucket 11 cache-verify path → version-agnostic.
- `SETUP.md` (`d57a437`) — §6 registers the **vault** as the marketplace source (was: hand-built frozen copy).
- `plugins/aios/commands/company.md` (`d57a437`) — new Step 5.6 (register + install synced venture plugins; vault-sourced precondition).

## 2026-06-18 — "Agents can handle" consistency: no over-count, 🚀 on handoff, maximize toward delegation

`hash: d082998`

> **The Glass "go with agents" count over-reported — it showed tasks that were already done.** Root cause: the `## Agents can handle` bullets are a checkbox-less *mirror* of tasks that also live in your Rhythm/ship list. The ledger strikes the canonical copy when work lands; nothing ever marked the mirror, so it looked perpetually pending. Three coordinated fixes (the Glass side — cross-section done-detection — shipped in the extension; this is the framework-contract half).
> - **`/today` generation is now clean + self-maximizing.** The section is rebuilt fresh each day from genuinely-open delegatable tasks (the upstream gather from `projects/_index.md` + Google Tasks + calendar is unchanged), **excluding anything already `[x]`/struck** — so done tasks never reappear. New **maximize pass**: when the delegatable list is sparse (≤1) or empty, it augments toward ~2–3 — first from real open project to-dos not yet surfaced, then up to 2 context-grounded `_(suggested)_` research/prep tasks — under hard guardrails (never fabricate specifics, respect INTENT.md parked items, honesty-over-filling, cap +2).
> - **CLAUDE.md ledger now maintains the mirror.** On "go with agents" (conversational, same as the Glass button) → stamp 🚀 on each spawned line. On completion → strike the mirror `~~…~~ ✅` by core identity. Glass reads struck mirrors *and* struck canonicals, so striking either drops the count.
> - **`/close-day` reconciles + excludes.** A new pass strikes any mirror whose canonical is done; the checked-items and carry scans now explicitly **exclude** the section (it's a regenerated mirror, never a carry/sync source).
>
> **What to do:** nothing — autonomous, fires inside `/today` and `/close-day`. `/aios:update` pulls the updated commands + CLAUDE.md.

### What changed
- `plugins/aios/commands/today.md` — § Agents can handle: generation hygiene (exclude done, never-carry), the maximize/complementary pass with guardrails; carry-extraction step now excludes the section.
- `CLAUDE.md` — § Live daily-note ledger: mirror-maintenance rules (🚀 on go-with-agents; strike-by-identity on completion).
- `plugins/aios/commands/close-day.md` — checked-items scan excludes the section; new Agents-can-handle reconciliation pass.

---

## 2026-06-16 — /close-day v2.1: Emerging-cap enforcement + surgical buffer excision + anti-skip principle

`hash: 3baa41a`

> **Three fixes to `/close-day`, closing the gaps surfaced by running v2 on a heavy day.** v2 made **Reinforced→Routed** load-bearing (downstream leak fixed); the `## Emerging` buffer was still unbounded (observed ~31 vs the ≤10 cap), buffer excision was fragile hand-editing, and there was a (rejected) instinct to "lighten" close-day on quiet days.
> - **Emerging-cap enforcement** (new, *additive* pass — does NOT touch the proven Reinforced/Tier-B/observed flow): when Emerging > 10, reinforce 2nd-instances, expire stale entries by an *inverse substance bar* (age + no-2nd-instance + not-90-day-relevant + not-essential; "when unsure, keep"), restore ≤10 or surface each over-cap entry's disposition.
> - **Surgical excision helper** `hooks/route-insight.py` — removes exactly one `### ` buffer entry (refuses on no/ambiguous match), snapshot-first + validate-after, abort+restore on mismatch. Tier A routing + the new Emerging pass call it instead of fragile multi-line hand-edits.
> - **Anti-skip principle** — encoded near the routing sections: close-day is the compounding ritual; the work is done so there's no token opportunity cost; never gate/skip routing/digest/gardening to save tokens (they self-scale — a quiet day finds nothing and is naturally cheap). *Lightness is an outcome of an empty buffer, never a goal.*
>
> **What to do:** nothing — autonomous, fires inside `/close-day`. `/aios:update` pulls the updated command + the new helper.

### What changed
- `plugins/aios/commands/close-day.md` — anti-skip principle (Observed-context section); `route-insight.py` wired into Tier A removal; new `### Emerging-cap enforcement` section after the Tier B pass.
- `hooks/route-insight.py` (new) — surgical session-insights entry excision (snapshot + validate + abort-on-mismatch); tested on a buffer copy + dry-run on the live file.

---

## 2026-06-15 — CLAUDE.md compacted under the 40k-char load limit (no behavioral change)

`hash: b63c9dd`

> **CLAUDE.md crossed the 40k-char limit** at which Claude Code truncates/warns on load — meaning the *tail* of your behavioral contract risked being silently dropped at session start. (Today's audit-driven additions — spawn `--tier`, arc sessions, capability-recalibration — pushed it to 43.4k.) A truncated CLAUDE.md is a silent behavioral-loss bug, so this is correctness, not cosmetics.
>
> **What changed:** CLAUDE.md compacted **43.4k → 39.1k chars (~10%, ~900 char headroom)** with **zero behavioral change** — verbose prose tightened, redundant restatements merged, and duplicated navigational reference (command lists, structure-tree comments that also live in CHEATSHEET/TOOLS) compressed. Every rule, trigger, and instruction is preserved in meaning; verified all 35 section headers intact and each removed line maps to a tighter replacement.
>
> **What to do:** nothing — `/aios:update` brings the compacted CLAUDE.md (Tier-1, overwritten byte-identical to canonical). If your own CLAUDE.md was near the limit too, this is your cue it can be compacted the same way. No migration.

---

## 2026-06-15 — /housekeeping gains two silent-failure guards: dataview path-validity + session-insights cap [from a Fable 5 audit]

`hash: 58c62d6`

> **Two classes of silent rot that only surface when you happen to look.** (1) A dataview `FROM "folder"` clause that points at a renamed folder doesn't error — the table just renders **empty**, so a stale path can sit broken for weeks (caught 2026-06-15: 17 `FROM "04 - export/…"` clauses across 5 export indexes still pointed at the old folder name weeks after it became `03 - export` — the meetings index had been silently empty the whole time). (2) The session-insights buffer has caps (Emerging ≤10, Reinforced ≤5), but nothing *enforced* them as a hard check — an overflowing buffer means gardening is falling behind and signal gets cannibalized, with no signal that it's happening.
>
> **What changed:** `/housekeeping` gains two checks. **Bucket 7** now validates every dataview `FROM` path in `_index.md` against the actual vault tree and proposes the corrected path (or flags it) when the folder is missing — the structural sibling of Bucket 19's reference-integrity layer (dead *command* refs), now for dead *folder* refs. **Bucket 19** adds a hard cap finding (Emerging >10 / Reinforced >5) alongside its existing age-based backlog checks — count-overflow caught regardless of entry age.
>
> **What to do:** nothing — `/aios:update` brings the new `housekeeping.md`. Your next `/aios:housekeeping` will flag any silently-empty dataview index and any over-cap insight buffer. No migration.

---

## 2026-06-15 — Spend capability wisely: spawn model tiers + a recalibration ritual + the arc-session pattern [from a Fable 5 audit]

`hash: 306bfcb`

> **The harness was single-model, and the trust contract was calibrated for a previous generation.** Every spawned session ran on the frontier model — even a file sweep or an ingest, which doesn't need it. And `INTENT.md` framed trust as growing only with *context*, never with *capability* — so when the model jumped a generation, your autonomy levels silently stayed calibrated for the old one. Three coordinated changes, all one insight (match capability to the work, deliberately):
>
> **1. `spawn --tier mechanical|judgment`** (`-Tier` on Windows). Mechanical work routes to the *second-best* model (Sonnet 4.6 today — "aim second-best" auto-tracks the lineup as it evolves); judgment work (or no flag) keeps the frontier default. **Strictly additive** — no flag = byte-identical to before. *Use `--tier mechanical` for ingests, sweeps, transcription; omit it for anything needing real reasoning.*
>
> **2. A capability-recalibration ritual.** `INTENT.md` gains a **Recalibration log** + "trust grows with capability, not just context" framing. Your AI now glances at that log once per session and — if it's running a *newer* model generation than your last entry — gently prompts: *"you're on {model}; your last recalibration was for {older gen} — want to revisit which domains can move toward autonomous?"* You decide; it just surfaces the lag.
>
> **3. The arc-session pattern, named.** `CLAUDE.md` now names **arc sessions** as the long-context default for compounding work (audits, migrations, multi-pass investigations): one continuous 1M-context session that back-edits live beats N bootstrap-heavy small ones. The old "many short sessions" optimum was a small-context workaround. (Mechanical sub-work still fans out to `--tier mechanical` workers.)
>
> **What to do:** `/aios:update` brings the new wrapper + docs and **auto-re-runs the wrapper installer** (so `spawn --tier` is live in new terminals — open a fresh one). **`INTENT.md` is yours and is never overwritten** — so your AI won't auto-add the Recalibration log; on your next `/aios:update` it will *offer* to append the section (and a baseline entry for your current model) to your `INTENT.md`. Accept it once and the ritual is wired. No migration.

---

## 2026-06-15 — /housekeeping now catches dead command/namespace refs in observed context [from a Fable 5 audit]

`hash: adf6aa2`

> **A renamed command rots silently in the files read at every session start.** When the framework renames a command or its plugin namespace (e.g. the `vault-commands:* → aios:*` rename), canonical's *seed* files update — but an operator's *evolved* observed-context copy (especially `vault-routine.md`, read at the top of every session) keeps teaching the old token indefinitely. Nothing surfaced it; you'd only notice when a `/aios:vault-update` you copied from your own cadence map failed to resolve. Caught 2026-06-15 on a vault-routine still listing `vault-commands:today … vault-commands:vault-update` weeks after the rename.
>
> **What changed:** `/housekeeping` Bucket 19 (observed-context lifecycle health) gains a **third detection layer — reference integrity.** It builds the live command set from `plugins/aios/commands/*.md`, scans `context/observed/*` + `declared/*` for dead tokens, and classifies each: **dead namespace** (`vault-commands:*` → propose `aios:*`), **renamed command** (`sovra-sync → company --sync`, `vault-update → update`), or **historical narration** (a record *describing* a past rename — left untouched). It fixes only *active instructions* that still tell a future session to call a dead token; it never rewrites history and never touches the surrounding lesson in `antifragile.md`. All proposals go through housekeeping's normal approve-before-apply.
>
> **What to do:** nothing forced — `/aios:update` brings the new `housekeeping.md`. **If you've been running a while, your next `/aios:housekeeping` will likely surface a 19.x reference-integrity row or two** (renamed commands you copied into your own cadence/preference notes); approve the swaps and your startup files stop teaching dead systems. No migration.

---

## 2026-06-15 — Reinforced session-insights are now bounded to a two-close-day auto-route [from a Fable 5 audit]

`hash: 8a1061b`

> **A Reinforced session-insight could linger forever if it never got a `Route to:` tag.** The lifecycle is *Emerging → Reinforced → routed to a target observed file → removed from buffer*. The previous close-day enforcement routed any Reinforced entry that carried a `Route to:` tag, but an entry **missing** that tag just got a nudge — and could sit untriaged for weeks (the same 11-49 day backlog the routing step was built to kill, re-entering through a side door). That's one of the "ball-dropping" anxieties the cascade-trust work named: an insight you flagged as real, quietly going nowhere.
>
> **What changed:** `/close-day` now enforces a **two-close-day bound** on Reinforced entries. First untriaged close-day: stamp `UNTRIAGED-SINCE` + nudge. Second consecutive close-day: the substance bar is already passed (Reinforced = 2+ sessions of evidence) and the only thing missing is a human-picked target — so close-day **infers the best target file and auto-routes**, surfacing the inference so you can redirect (the snapshot is reversible). Promotion Emerging→Reinforced stays human judgment; *reaching* a target becomes mechanical. The routing now also appears in the **Cascade ledger** as a third sub-table (insight → target file, with provenance) — so observed-context changes are as legible as project-note cascades.
>
> **Why it matters:** the Reinforced→Routed transition stops being aspirational. No Reinforced insight survives two close-days stranded, and every route is shown with its origin — the same trust contract the cascade ledger introduced, now extended to the observed-context layer.
>
> **What to do:** nothing — `/aios:update` brings the new `close-day.md`. Your next close-day surfaces any auto-routed insight (with a flag-to-redirect prompt) in the ledger. No migration.

---

## 2026-06-15 — close-day's cascade is now trustable (provenance stamps + a confirm-first ledger) [from a Fable 5 audit]

`hash: b862bf6`

> **Close-day's compounding cascade ran opaquely.** Insights and tasks flow: session-insight → project note → `_index` snapshot → surfaces in tomorrow's `/today`. It works — but when a task appeared tomorrow, you couldn't see *where it came from* or whether the pipeline *dropped* something. Three failure modes followed: a dropped ball you never notice, a "weird task" you don't recognize, and the worst — *"if I can't trace it, do I have to re-check everything myself?"* That's trust collapsing, which defeats the whole point of the cascade.
>
> **What changed:** `/close-day` gains a **Cascade ledger** + a **provenance rule**. Every item that cascades into a project note or will surface in tomorrow's `/today` now carries an inline origin stamp — `_(from: {source} · {date})_` (a meeting, a dev-report, an audit/`/ingest` finding, a Reinforced session-insight, a carry, a user request). Before the snapshots-refresh makes anything surface, close-day presents ONE consolidated ledger — *everything going into project notes + everything surfacing tomorrow, each with its origin* — for a single confirm. An item with no traceable origin is treated as a bug, not surfaced silently.
>
> **Why it matters:** it kills all three — *dropped ball* (you see the full surfacing set, can spot the gap), *weird task* (every item shows its origin), *re-check-everything* (traceability replaces re-audit). The compounding itself is untouched — insights still route, growth edges still get named — it's just made legible. (Operator-specific overnight delegation stays in your `USER.md`, not canonical.)
>
> **What to do:** nothing — `/aios:update` brings the new `close-day.md`. Your next `/close-day` shows the ledger before anything surfaces; tomorrow's tasks arrive with their origins attached. No migration.

---

## 2026-06-15 — antifragile.md is now bounded (size-gated compaction via /aios:compact) [from a Fable 5 audit]

`hash: 0e5d752`

> **`antifragile.md` grows forever and loads every session.** The "never delete, only supersede" rule (good — evolution is the value) means the file only grows; meanwhile CLAUDE.md tells Claude to scan it at every session start. On a mature vault it can hit ~70k tokens / 70+ entries — most of them old, settled, or already graduated into CLAUDE.md rules — so every session pays a growing tax to reload mostly-resolved history that drowns the genuinely-hot recent lessons.
>
> **What changed:** `/aios:compact` gains **Step 3.5 — a size-gated antifragile bound** (runs every invocation, not month-gated; operates on the live file). When `antifragile.md` exceeds ~50 entries / ~40k tokens, it **snapshots first**, then compacts in **two safety tiers**: it **auto-removes only entries the file itself explicitly marks** (`→ Graduated to CLAUDE.md` / `→ Merged into #N` / `superseded` — the file declares these redundant), and **surfaces unmarked stale-looking candidates for you to confirm** — it never silent-deletes an entry on inference (a wrong cut loses real wisdom, and on a teammate's vault Claude can't see what's load-bearing). The meta-pattern index + active/recent lessons always stay. The CLAUDE.md principle moves from *"never delete"* → *"never delete without a snapshot."* History stays **in the vault** (the snapshot) — never in machine-local memory — so the vault stays self-contained.
>
> **What to do:** nothing forced — `/aios:update` brings the new `compact.md` + CLAUDE.md rule. **If your `antifragile.md` is already large, run `/aios:compact` once** and it'll snapshot + lean it on the spot; otherwise it self-manages from here. No migration.

---

## 2026-06-15 — study-buddy recognizes the mirror-fork (a study session can output a decision, not just notes) [from a Fable 5 audit]

`hash: 3af2fb5`

> **A study session has two valid outcomes — and `study-buddy` now recognizes the fork.** Until now the agent ran one shape: read → brief → explain → discuss → write chapter notes (*absorption*). But sometimes a chapter isn't absorbed — it *triggers* something: a decision, a project, a change in how you'll act. The chapter was the spark, not the subject. The old agent steered back to "finish the brief," and the realization (the higher-value artifact) got lost.
>
> **What changed:** `study-buddy` now names two outcomes — **Absorption** (default → chapter notes) and **Mirror** (the chapter precipitates a personal decision/project → capture THAT as the session's primary output, in your words). On a mirror the reading queue still advances (the chapter is "done"); the deliverable is the realization, not a summary, and the chapter notes link to the decision/project note so the trail stays intact.
>
> **What to do:** nothing — `/aios:update` overwrites `agents/aios/personal/study-buddy.md` for you (Tier-1 infra). Your next study session, the agent recognizes a mirror moment instead of forcing absorption. No config, no migration.

---

## 2026-06-14 — spawn wrapper layout-independence + AIOS Glass promoted to a required setup step

`hash: 8c2ba67`

> **The `spawn` wrapper silently assumed a US keyboard layout.** It created the IDE terminal with `Ctrl+Shift+\`` and *typed* the launcher — both break on non-US layouts (Spanish LA/ES confirmed, others likely): the backtick chord maps to a different physical key (no terminal created) and `keystroke` garbles symbols/spaces (launcher corrupts). The result was the "leak" signature — the active tab gets renamed and the launcher spills into the parent session, no new worker. Surfaced on a LATAM operator's onboarding.
>
> **The fix is layout-independent by construction** (validated end-to-end on US/ABC + Latin American + Spanish-ISO, including the worst case of a non-US layout *with focus in another window*): create the terminal via the Command Palette (`⌘⇧P`, a letter chord) with the command name **pasted** (not typed), deliver the launcher by **paste**, and force the IDE frontmost (`set frontmost to true`) before any keystroke so focus can't leak. The fragile palette-rename step is dropped (the session is already named via `--name`). The operator's clipboard is saved + restored around the spawn. Glass-shell is unaffected (it spawns natively via node-pty).
>
> **What to do.** State→Ask→Act for your Claude session:
> - **Detect:** `/aios:update` pulls the corrected `install-wrappers.sh` (Tier 1, byte-identical) + the new `hooks/claude-identity/TROUBLESHOOTING.md`.
> - **Act (RESTART-CLASS):** the installer is auto-re-run by `/aios:update`; if running manually, `bash ~/aios/hooks/claude-identity/install-wrappers.sh`, then **open a new terminal** to pick up the regenerated wrappers.
> - **Verify:** `grep -c "Terminal: Create New Terminal" ~/.zshrc` ≥ 1 and `grep -c 'control down, shift down' ~/.zshrc` = 0.
>
> **AIOS Glass is now a required part of setup, not a "recommended" extra.** Glass is the front door — the difference between using the AIOS and bouncing off the terminal, especially for non-terminal operators. The onboarding flow was soft-pedaling it ("recommended… skip/later is fine"), so a new operator could miss it entirely (caught on a LATAM onboarding — the operator never got Glass without hands-on help). Now the cold-start interview **installs it by default** (walk-through, no fake skip-gate — same posture as bundles/plugins), and SETUP + START-HERE frame it as core. The walkthrough also now covers **opening** it (the bottom status-bar item — installing isn't opening) + the secondary-sidebar layout.
>
> **What to do (Glass):** nothing for existing operators — you already have Glass; this only changes how *new* operators are onboarded (the cold-start interview runs once at first clone). `/aios:update` pulls the updated SETUP / START-HERE / cold-start-interview (the command file auto-syncs to your plugin cache).

### What changed

- `hooks/claude-identity/install-wrappers.sh` — IDE spawn AppleScript: `Ctrl+Shift+\`` create → Command-Palette-via-paste create; typed launcher → pasted launcher; added `set frontmost to true` focus guard; dropped the palette-rename; save/restore the user clipboard.
- `hooks/claude-identity/TROUBLESHOOTING.md` (new) — Claude-facing runbook for diagnosing spawn leaks (stale wrapper / focus race / layout / Accessibility permission).
- `plugins/aios/commands/cold-start-interview.md` — Step 8.5: Glass install reframed from "announce + offer, skip-fine" to **install-by-default** (walk-through, no fake skip-gate); added open-the-panel + secondary-sidebar steps; persona calibration now tunes *pace*, not *whether*.
- `SETUP.md` + `START-HERE.md` — Glass reframed from "(recommended)" to a core, required part of setup for every operator; both now include the open-the-panel (bottom status-bar) + secondary-sidebar steps.

---

## 2026-06-12 — TOOLS.md agents table catches up to the fleet (31)

`hash: 9d9d0ad`

> **A docs-only fix: the TOOLS.md agents table drifted from the filesystem.** `protocol-steward` (shipped in `agents/aios/strategy/`) was missing from the table, and `brand-monitor` was listed under *communication* while it lives in `agents/aios/sales/` — the canonical registry (`agents/_index.md`) and the sales bundle README both already had it right. The table now matches the 31-agent ground truth the CI counts job enforces.
>
> **Why it matters.** TOOLS.md is the menu — `/today` task-matching reads the registry, but humans (and external collateral) read TOOLS.md. A stale row propagates: this one surfaced when a brochure built from the TOOLS.md table shipped "30 agents" and the operator caught the off-by-one. The registry was never wrong; the menu was.
>
> **What to do.** State→Ask→Act for your Claude session:
> - **Detect:** `/aios:update` pulls the corrected `TOOLS.md` (Tier 1, byte-identical).
> - **Act:** nothing — docs-only, auto-applies on sync. If you've built anything downstream from the TOOLS.md agents table (decks, one-pagers, onboarding docs), re-check its agent count and bundles against `agents/_index.md`.

### What changed

- `TOOLS.md` § Agents — added `protocol-steward` row (governance, open-source strategy, licensing + trademark posture for open protocols; strategy bundle); `brand-monitor` row re-bundled communication → sales.

---

## 2026-06-08 — Spawn serialization fix (stray Terminal window on back-to-back spawns)

`hash: 05cae11`

> **Spawning two workers in quick succession could pop an empty Terminal.app window. The agents landed fine in the IDE; the Terminal was leaked-keystroke debris. Fixed at the source.**
>
> **What changed.** The `spawn` wrapper's IDE path (taken when `CLAUDECODE` is set — i.e. spawning from inside a Claude Code session) drives a new IDE terminal via AppleScript keystrokes: `Ctrl+Shift+\`` to create → `Cmd+Shift+P` → "Terminal: Rename" → run the launcher. It's GUI automation, so it depends on the IDE being frontmost for each keystroke. Two **back-to-back** spawns overlapped: the second `activate`d the IDE while the first's keystrokes were still settling, and the first `Ctrl+Shift+\`` leaked to the desktop → macOS surfaced an empty Terminal.app window. Two fixes in `install-wrappers.sh`: (1) post-activate focus-settle bumped `0.5s → 1.2s`; (2) the spawn lock is now held `~1.5s` after `osascript` returns, so consecutive spawns serialize their *keystroke tails*, not just lock acquisition. Single spawns are unaffected; the fragility only ever showed with rapid multi-spawns.
>
> **Why it matters.** Cosmetic, but it reads as "spawn half-broke" when it didn't — the agents were always running correctly in the IDE. macOS-only path; the Windows `.ps1` never hits the AppleScript branch and is untouched.
>
> **What to do.** State→Ask→Act for your Claude session:
> - **Detect:** `/aios:update` pulls the new `hooks/claude-identity/install-wrappers.sh` into your vault (Tier 1). This updates the *source*, not your live shell.
> - **Act (restart-required — do LAST):** re-run the installer to regenerate the `spawn` block in your shell rc — `bash hooks/claude-identity/install-wrappers.sh` (idempotent: timestamped backup → strip prior block → append → verify → auto-rollback on failure). Then open a fresh terminal (or `source ~/.zshrc`) so the new `spawn` is live. If you never spawn from inside an IDE session, this is optional — your spawns were never affected.

---

## 2026-06-05 — Placement Router · Windows spawn fix · command upgrades (trace/graduate/connect/7plan) · marketplace merge rule · README positioning · session-identity fallback + standalone deliverables · agent search keywords

`hash: 4bf8b78`

> **Five threads today: files get a semantic router, Windows operators get `spawn` back, three commands absorb Internet Vin's best framings, operator plugins survive syncs, and two session-integrity rules land from a live routine test.**
>
> **(1) File Placement Router (CLAUDE.md § IV).** The vault's numbered folders were always semantic zones — but the routing logic lived in each operator's accumulated taste, not in the framework. Six questions, asked before any new file is written: written by a script? → `logs/` (and ONLY that) · raw input you didn't author? → `02 - assets/` · ships to an audience (+ its HTML source)? → `03 - export/` · time-bound narrative? → `01 - calendar/` · compounds on re-read? → `reflections/` / project note / `ideas/` · about who the operator is? → `context/`. Anchored by the **retrieval test**: place by the question you'll ask later — **date-stamped ≠ log**. Plus the **rule of 3** (3+ same-species files → noun-named subfolder) and **sanctioned bespoke rooms** (a cookbook is legitimate — give it an `_index.md`). `/housekeeping` gains **Bucket 21** (placement-drift audit, propose-only).
>
> **(2) Windows spawn-wrapper fix.** npm on Windows installs BOTH `claude.cmd` and an extensionless Unix shim `claude`; `Get-Command -CommandType Application` matched both, `.Source` became a 2-element array, and `& $claudeExe` collapsed it into one bogus path → `spawn`/`zai` dead for every Windows npm operator. Now resolves deterministically (`.cmd` > `.exe` > `.bat`, fallback first-match). Reported root-caused-and-patched via internal review 2026-06-02 — this lands it upstream so syncs stop reverting the local fix.
>
> **(3) Command upgrades from the Internet Vin diff — then deepened from his full prompt pages.** A 27-command diff against [internetvin.com/Obsidian+Commands] found 13 already covered and the value concentrated in framings; a second pass against his full prompt pages imported the rigor the one-line verdicts had compressed away: `/trace` gains the **Compounding view** (answer the topic's question at THREE vault snapshots picked at inflection points; equal-length hard constraint; anachronism guard; "no improvement IS the finding") · `/graduate` gains the **Make lens** (5 ripeness signals — density, originality, narrative, tension, resonance — as search queries; multiple natural forms per candidate; max 3) · `/connect` goes graph-mechanical (2-3 hop neighborhoods, depth asymmetry for sparse domains, intermediary-note focus, Converging/Diverging/Stable trend per bridge, strongest-bridge + missing-links sections) · `/7plan` gains **The bet (durable layer)** (one multi-week bet + review cadence + 3-5 leverage domains, carried verbatim week to week unless deliberately changed). His deeper `/focus` (Kill-Park Ledger, falsifiable thresholds) and `/leverage` (constraint-mapping diagnostic) are parked as potential builds — too big for tweaks.
>
> **(5) README positioning.** The architecture convergence happening publicly (independent builders arriving at filesystem-as-context, plain Markdown, no RAG) is now named in the README as validation, with the differentiation stated on top: *governed (INTENT.md trust contract), multiplayer (personal × team × company), substrate-agnostic — not a deeper single-player engine, but the operating system your whole circle runs.*
>
> **(4) Marketplace manifest is now MERGE, not byte-replace.** `.claude-plugin/marketplace.json` is dual-owned: the framework owns bundled entries, but operators register `plugins/custom/<name>/` (and companies `plugins/<company>/`) in the same file. The old Tier-1 byte-replace silently deregistered every operator plugin on every sync. `/aios:update` now merges: upstream wins on bundled entries, local `custom/`+company entries are preserved.
>
> **(6) Session-identity fallback + standalone deliverables (CLAUDE.md).** A live routine-session test caught two gaps. First: routines, scheduled runs, and bridge sessions are *named by the harness* but never set `$CLAUDE_AGENT_NAME` — the Mandatory First Action misread them as plain CLI, skipping worker behaviors (role greeting, proactive `/close-session`). The identity check now falls back to the session's own transcript (`grep` the `agent-name` record in `~/.claude/projects/*/$CLAUDE_CODE_SESSION_ID.jsonl`) before concluding "plain CLI" — deterministic, zero behavior change for spawn-wrapper and true-CLI sessions. Second: assistant text emitted *between tool calls* in the same turn can be silently dropped on some session surfaces — present in the model's context, never rendered, never persisted to the transcript (a deliverable vanished mid-turn while standalone messages survived). New § VI discipline rule: **deliverables land in a standalone message or a file, never as mid-turn interleaved text** — and "the user didn't see it" gets verified against the on-disk transcript, not context.

> **(7) Agents declare search keywords.** Every bundled agent's frontmatter gains a `keywords:` line — 4–8 intent words an operator might type (content-writer: "social media, posts, linkedin…"). AIOS Glass (0.1.6) folds them into picker search so intent words find the right agent; inert metadata for every other consumer. The company context repos received the same treatment in their own repos. **No action** — agent files auto-apply on sync.

### What changed

- `agents/aios/**` — every bundled agent (31) declares `keywords:` search synonyms in frontmatter (consumed by AIOS Glass search; inert elsewhere).
- `CLAUDE.md` § Live daily-note ledger — multi-part tasks: strike the TITLE when the last sub-item completes (title-struck = done is the contract consumers read; sub-item strikes alone read as partial).
- `CLAUDE.md` — new § IV subsection **"File Placement Router"**; `CHEATSHEET.md` § 3 human version.
- `plugins/aios/commands/housekeeping.md` — new **Bucket 21: File placement drift**.
- `hooks/claude-identity/install-wrappers.ps1` — deterministic claude-executable resolution (`.cmd` > `.exe` > `.bat`).
- `plugins/aios/commands/trace.md` — step 5 + **Compounding view** output section (3 inflection-point snapshots, equal-length constraint, anachronism guard, null-result honesty).
- `plugins/aios/commands/graduate.md` — step 5 **Make lens** (5 detection signals, multi-form recommendations) + **Make-ripe** summary section.
- `plugins/aios/commands/connect.md` — graph-mechanical steps (neighborhood hops, depth asymmetry, intermediaries, bridge trends) + **strongest bridge** / **missing links** output sections.
- `plugins/aios/commands/7plan.md` — **The bet (durable — carries across weeks)** output section (carry-by-default).
- `plugins/aios/commands/update.md` — marketplace.json Tier-1 entry changed to **merge semantics**.
- `README.md` — convergence-validation + governed/multiplayer/substrate-agnostic positioning in "What makes The AIOS different".
- `CLAUDE.md` — **Mandatory First Action** gains the transcript-based identity fallback for harness-named sessions; new § VI subsection **"Deliverables land standalone"**.

### Action required

- **Windows operators:** after this sync auto-runs `install-wrappers.ps1`, open a NEW terminal — `spawn`/`zai` resolve correctly again. (If you hand-patched locally per the 2026-06-02 finding, this upstream version supersedes it cleanly — deterministic extension order instead of first-match.)
- **Everyone else: none — auto-applies.** Optionally run `/aios:housekeeping` after syncing; Bucket 21 will surface existing placement drift as a propose-only packet. Next `/7plan` will derive your first durable bet and mark it "(first bet — calibrate over 2-3 weeks)".

---

## 2026-06-02 — study-buddy gains a reading system: the method, the library pipeline, and infographics

`hash: 95b4aa2`

> **The `study-buddy` agent goes from "walk a chapter" to "run a reading system" — and bootstraps one for you if you don't have it.** Three upgrades, all de-personalized and shipped via the bundled agent + a new template.
>
> **(1) The method — read it to me, unfiltered but engaging.** study-buddy now has explicit reading doctrine: read the chapter *to* you (as if aloud), source-faithful and register-honest — never a sanitized digest. Keep the cool empirical claims and the hot rhetoric distinct as you go, and *name the moment the evidence-quality changes*. The brief is the scaffold; the walk is the value.
>
> **(2) Detect-or-scaffold.** A new Step 0: study-buddy checks for an existing reading protocol (a `reading`/`study` project note, a `USER.md → Growth routines → Reading` pointer, or a `reflections/books/_index`). If found, that note is the source of truth and the agent follows it. If not, it offers to scaffold one from the new `templates/aios/reading-project-template.md` — the method + a WIP-5 library pipeline (focus on 5 books at a time; read all 5, then bring 5 more) + a `{Title} — {Author} ({Year}).pdf` naming convention + the per-book output stack.
>
> **(3) The completion stack now includes infographics + smart replenishment.** On book completion, beyond the non-negotiables synthesis, study-buddy now (a) builds infographic(s) via the `infographic-builder` skill — an *argument* one-pager always, plus a *personal* one if the book has personal-specific value — and (b) when a library pipeline is active, proposes the next 5 books with a **deepen + mutate** rule: ~3 same-vein + ~1 bridge + **≥1 deliberately unrelated "mutation" (hard floor, never zero)** so studying stays expansive.

### What changed

- `agents/aios/personal/study-buddy.md` — new **Step 0 (detect-or-scaffold)** + **the method** doctrine block; Step 4 (explain) now invokes the method explicitly; new completion steps **10 (infographics)** + **11 (deepen + mutate replenishment)**.
- `templates/aios/reading-project-template.md` — **new**: a scaffoldable reading-project note (Current State, Library Pipeline WIP-5, batch-selection heuristic, naming convention, Study Protocol + method, completion stack, Reading Queue).
- `templates/_index.md` — registers `[[reading-project-template]]` under Operational.

### Action required

**None — auto-applies.** The agent + template ship as plain framework files (no installer, no restart). Next time you invoke `study-buddy`, it detects your reading setup or offers to scaffold one. If you already keep a reading/study project note, study-buddy defers to it as the source of truth.

---

## 2026-06-01 — Live daily-note ledger + onboarding portability fixes

`hash: cb20fb2`

> **Two threads today: the daily note becomes a live ledger, and three onboarding papercuts a fresh external user surfaced get fixed.**
>
> **(1) Live daily-note ledger.** Until now the note was written at `/today` and reconciled at `/close-day` — a task finished at 9am still showed `- [ ]` until evening. A new § VI Discipline rule closes the loop in real time: the moment Claude completes/ships/confirms a task that's an unchecked `- [ ]` in *today's* note, it marks it `- [x]` with a one-line result. Honest about partials (a passed meeting ≠ a finished deliverable), composes with the publish-evidence rule (a `✅` on a publish-action still needs a URL or `published-pending`), autonomous (daily-note writes already are per INTENT.md). `/close-day` stays the deterministic backstop.
>
> **(2) `spawn` works on non-zsh login shells.** The spawn launcher hard-coded `#!/bin/zsh` + `source ~/.zshrc`, but `install-wrappers.sh` installs the wrapper functions to `$RC` resolved from `$SHELL` (`~/.bashrc` for a bash user). On any non-zsh login shell the helper landed in `.bashrc` while the launcher sourced `.zshrc` → `_claude_with_respawn: command not found`, and spawn silently failed. The launcher now re-derives shell+rc from `$SHELL`, in lockstep with the installer. Windows parity: `install-wrappers.ps1` now opens the *current* PowerShell edition (Core→pwsh, Desktop→5.1) instead of "pwsh if it exists," so the new window dot-sources the same `$PROFILE` the wrapper was installed into.
>
> **(3) Freshness check no longer false-alarms "unreachable" for HTTPS-clone users.** `/today` + `/close-day` did `git ls-remote {ssh-url}`; a fresh user who cloned via HTTPS with no SSH keys got "unreachable" — scary, and it masked a real BEHIND. The check now falls back SSH→public-HTTPS (the upstream is public), resolving to synced/BEHIND correctly. "unreachable" now means genuinely offline.
>
> **(4) Dead "vault-update" narrative removed.** `vault-update` was the pre-rename name of `/aios:update`; every active reference across commands/docs/hooks is now `aios-update` / `/aios:update`. (CHANGELOG history left intact — those are dated records.)

### What changed

- `CLAUDE.md` — new § VI Discipline subsection **"Live daily-note ledger."**
- `hooks/claude-identity/install-wrappers.sh` — spawn launcher re-derives shell+rc from `$SHELL`.
- `hooks/claude-identity/install-wrappers.ps1` — launcher opens the current PowerShell edition, not "pwsh if present."
- `plugins/aios/commands/today.md` + `close-day.md` — `git ls-remote` SSH→HTTPS fallback in the freshness checks; `vault-update`→`aios-update` labels + section names.
- `plugins/aios/commands/update.md`, `_index.md`, `mcps/setup.sh`, `mcps/_index.md`, `hooks/claude-identity/README.md`, `CHEATSHEET.md` — `vault-update`→`aios-update` / `/aios:update` references; temp clone dir `/tmp/vault-update-check`→`/tmp/aios-update-check`.
- `plugins/aios/commands/update.md` — auto-execution **platform guard**: `install-wrappers.sh` auto-runs on macOS/Linux only, `install-wrappers.ps1` on Windows only (both files still *copy* on every OS — only *execution* is platform-gated, so a Mac session no longer attempts the `.ps1` and vice-versa).

### Action required

1. **Apply the Tier-1 + Tier-2 diffs** (auto during this `/aios:update`): CLAUDE.md (live-ledger subsection), today.md/close-day.md (fallback + rename), and the doc/hook renames.
2. **`install-wrappers.sh` auto-re-runs** (it's a state-producer) — it re-installs the corrected spawn launcher into your `$RC`. Open a new terminal afterward so `spawn` picks it up. (Windows: `install-wrappers.ps1` likewise.)
3. No restart beyond a fresh terminal for the wrapper change.

---

## 2026-05-31 — AIOS Glass: a graphical layer over your AIOS (now on Open VSX)

`hash: 2647749`

> **Your AIOS now has a face.** [AIOS Glass](https://open-vsx.org/extension/the-aios/aios-glass) is an IDE extension — a *glass layer* over the framework you already run from the terminal. It surfaces and triggers your existing AIOS; it reimplements nothing (**glass, not engine**). From one Home panel you run the daily rituals (`/today`, `/close-session`, `/close-day`), launch agents and "go with agents" off your daily note, browse skills/commands, manage spaces/workspaces, watch your context **compound** (recent learnings + outputs + reports), and swap accounts/model/permission-mode — all without typing slash commands. It reads everything live from `~/aios` at runtime, so the vault stays the single source of truth. Optional and additive: the framework works exactly as before without it. Same license as the framework (GPL-2.0-or-later).
>
> **This is a one-time install nudge, not a recurring one** — once you install from Open VSX, Glass **auto-updates itself** on every future release with zero changelog action.

### What is it / what you get

- **Daily Ritual card** — one-click `/today` · `/close-session` · `/close-day`, plus **Go with agents** (spawns the agents your daily note suggests under "Agents can handle," one terminal each; the counter tracks unchecked items).
- **Sessions Running** — live view of your named Claude sessions (from `~/.claude/sessions/`), spawn a new one, reveal/close.
- **Context that compounds** — recent learnings (session-insights), recent outputs (`03 - export/`), reports, plus a close-loop nudge so the discipline that makes the AIOS valuable stays visible.
- **Frequent tasks + Reports** — pre-bundled, context-driven prompts (elevator pitch, "who I am for this audience," what's changed lately, …) and a report launcher (role / weekly / status / custom × period).
- **Config cog** — model, permission mode, terminal mode, account swap, `/goal` · `/fewer-permission-prompts` · `/schedule`, framework-update status.

### Action required (optional — install only if you want the GUI)

1. **Detect the editor + whether Glass is already present.** Run `<editor-cli> --list-extensions` (Antigravity: `~/.antigravity-ide/antigravity-ide/bin/agy-ide`; VSCodium/Cursor/Windsurf: their CLI; stock VS Code: `code`). If `the-aios.aios-glass` is already listed → **skip, nothing to do** (it auto-updates).
2. **If on an Open VSX–backed editor** (Antigravity, VSCodium, Cursor, Windsurf) **and not installed** → ask the operator *"Install AIOS Glass (graphical layer over your AIOS)?"* On yes: `<editor-cli> --install-extension the-aios.aios-glass` (this pulls Foam, the wikilink dependency, automatically), then tell them to **reload the window** (`⌘⇧P` → *Developer: Reload Window*).
3. **If on stock Microsoft VS Code** (uses the MS marketplace, where Glass is **not** published) → inform: install isn't available from the registry; download the `.vsix` from [Releases](https://github.com/The-AIOS/aios-glass/releases) and *Install from VSIX…*, or switch to an Open VSX–backed editor. Point them at [`INSTALL.md`](https://github.com/The-AIOS/aios-glass/blob/main/INSTALL.md).
4. **How to launch** (tell the operator after install) — command palette (`⌘⇧P`) → **AIOS Glass: Open Home**, or click the AIOS mark in the activity bar. Dock it in the **secondary side bar** (drag the view there). If the cards are empty, Glass can't find the vault → set `aiosGlass.frameworkPath` to your AIOS root.

**Restart-required:** no framework restart — but the IDE **window must be reloaded** after install for Glass to activate.

---

## 2026-05-30 — Agents leverage registered skills · aios-builder · primary-session resume · housekeeping skill-reg bucket · changelog backup-exemption · automatic-updates setting

`hash: 034ec7b`

> **Closing the skills loop end to end.** Now that `skills/setup.sh` registers AIOS skills, five follow-ons land: (1) the **bundled agents** — authored before skills were loadable — get light `## Skills` nudges so the right methodology fires (12 wired across engineering / finance-legal / strategy + report-drafter; deck-builder, design-md-author, and self-disciplined agents deliberately **skipped** to avoid diluting their craft); (2) a new **`aios-builder`** agent that scaffolds AND **registers** new custom elements — it runs `skills/setup.sh` for new skills (and drives skill-creation through `skill-creator`'s eval loop), so the "authored but never wired in" gap never recurs; (3) the primary-session wrapper (`buddai` / your name) now supports **`-c`/`--continue`** and **`-r`/`--resume`**, resuming with the session's `--name` intact so a resumed primary is identifiable to tooling instead of anonymous; (4) `/aios:housekeeping` gains **Bucket 20 — skill-registration verification**, the sibling of the plugin-cache bucket: it catches AIOS skills authored but never symlinked into `~/.claude/skills` and auto-registers them (collision-safe via `skills/setup.sh`); (5) `/aios:update` now **exempts `CHANGELOG.md` from backup-on-divergence** — it's append-only canonical history (never a personalization), so a local diff is always stale and gets clean-overwritten instead of producing a noise backup; (6) a new **`## Settings` section in USER.md** with **`Automatic updates: yes`** (default) — `/today` reads it before its BEHIND→auto-fire of `/aios:update`: `yes` keeps auto-pulling, `no` switches to nudge-only (never auto-runs). Operator-owned, toggleable from AIOS Glass's config cog. Skills stay standalone (skills-dir / marketplace) — the `aios:` commands plugin is untouched.

### What changed

- `agents/aios/**` — 12 agents gained a `## Skills` block (prose nudges to registered skills; marketplace skills namespaced `document-skills:*`). New `agents/aios/engineering/aios-builder.md`. `agents/_index.md` + `templates/aios/agent-template.md` — "declare relevant skills" convention; engineering 5→6, total bundled agents 29→30.
- `hooks/claude-identity/install-wrappers.sh` + `install-wrappers.ps1` — `_claude_with_respawn` / `Invoke-ClaudeWithRespawn` gain a `--continue` resume mode; the emitted primary-session function accepts `-c`/`--continue` and `-r [sid]`/`--resume`, both preserving `--name`.
- `plugins/aios/commands/housekeeping.md` — new **Bucket 20: Skill registration verification** (sibling to Bucket 11 plugin-cache); cross-linked from Bucket 11; summary line added; stale bucket-count refs corrected to 20.
- `plugins/aios/commands/update.md` — `CHANGELOG.md` exempted from backup-on-divergence (always clean-overwrite, never backed up). Applied to your vault automatically via the Step 2.5 self-update guard — no manual action.
- `USER.md` (template) + `plugins/aios/commands/today.md` — new `## Settings` → `Automatic updates: yes`; `today.md` gates its BEHIND→auto-fire on it (no → nudge-only). `close-day.md` already only nudges, so it's unchanged.

### Action required

1. **Agents + aios-builder** — applied automatically by `/aios:update` (Tier-1 file sync); nothing to run. Bundled agents now name the skills that drive their methodology, and `spawn aios-builder "create a new …"` scaffolds + registers compliant custom elements under `*/custom/`.
2. **Primary-session resume** — to get `<your-session> -c` (resume, named), **re-run the wrapper installer**: `bash ~/aios/hooks/claude-identity/install-wrappers.sh` (macOS/Linux) or `pwsh ~/aios/hooks/claude-identity/install-wrappers.ps1` (Windows). It regenerates the managed profile blocks idempotently. *(The `.ps1` port mirrors the `.sh` structure but was authored on a machine without `pwsh` to syntax-test — Windows operators, flag anything that misbehaves.)*
3. **Refresh the `aios` plugin cache** so `/aios:housekeeping` runs the new Bucket 20. `/aios:update`'s Tier-1 sync updates the repo file, but the runtime cache is what the slash command actually reads. Run `claude plugin update aios@the-aios` (or, per CLAUDE.md → Personalization, `cp` the updated `housekeeping.md` from `plugins/aios/commands/` into both the marketplace and cache paths, then `diff -q` all three to confirm). Verify: `/aios:housekeeping` should list **20 buckets** and include "Skill registration verify" in its summary.

4. **Add the `Automatic updates` setting to your USER.md** — `USER.md` is operator-personal (denylisted from overwrite), so `/aios:update` adds this **surgically, additive-only** (a sanctioned exception, same shape as the INTENT.md disclaimer): **detect** whether your `USER.md` already has a `## Settings` section with an `Automatic updates:` line. If present → skip. If absent → **insert** a `## Settings` section (after `## Identity`) containing `- **Automatic updates:** yes` (preserving current behavior), then tell the operator: *"Added an Automatic-updates setting to your USER.md (default: yes) — toggle it from Glass's cog or set to `no` to stop `/today` auto-pulling updates."* Never overwrite existing Settings content.

**Restart-required:** yes — **open a fresh shell** after re-running the installer (action 2) so the updated `_claude_with_respawn` / `Invoke-ClaudeWithRespawn` + primary-session function load.

---

## 2026-05-29 — Register bundled skills into ~/.claude/skills (skills/setup.sh)

`hash: f6f26c6`

> **AIOS-authored skills were never actually loadable.** `skills/aios/*` (and `custom/`, company namespaces) are vendored in the repo, but nothing wired them into Claude Code — only the marketplace-installed `anthropic/` + `superpowers/` skills live in `~/.claude/skills` (the auto-loaded skills-dir). So invoking an AIOS skill (e.g. `accessibility-compliance`) returned *"I don't have that skill."* Fix: a new **`skills/setup.sh`** (+ `skills/setup.ps1` for Windows) that **symlinks every AIOS-origin skill into `~/.claude/skills`** — the same skills-dir mechanism the superpowers skills already use — so they auto-load at session start. Skills register **standalone**; this deliberately does NOT bundle them into the `aios` commands plugin (keeps commands and skills cleanly separate). Idempotent: skips `anthropic/`+`superpowers/` (marketplace-provided) and any name already present in `~/.claude/skills`.

### What changed

- `skills/setup.sh` (new) — symlinks `skills/<source>/<skill>/` → `~/.claude/skills/<skill>/` for every source except `anthropic`/`superpowers`; skips already-registered names. Mirrors the `mcps/setup.sh` pattern (idempotent, re-runnable).
- `skills/setup.ps1` (new) — Windows equivalent using **directory junctions** (no admin / Developer Mode required, unlike Windows symlinks).
- `SETUP.md` — added the skill-registration step alongside MCP setup.

### Action required

Run the skill-registration step so the bundled AIOS skills become invocable in your sessions.

1. **Detect:** after this sync your vault has `skills/setup.sh` — proceed.
2. **Run it:** `bash skills/setup.sh` (macOS/Linux) or `pwsh skills/setup.ps1` (Windows). Idempotent — safe to re-run; it skips already-registered names and the marketplace-provided `anthropic`/`superpowers` folders.
3. **Report** which skills it linked.

**Restart-required:** yes — **restart your Claude Code sessions** after running, so the newly-symlinked skills load (the skills-dir is read at session start).

---

## 2026-05-28 — INTENT.md: honest "guidance vs enforcement" disclaimer

`hash: 013bff8`

> **Transparency over the comfortable omission.** INTENT.md is loaded into context every session and shapes the AI's judgment, autonomy, and focus — but loading is *soft* governance: it guides the model, it doesn't *stop* it, and adherence scales with the model you run. The framework never said this out loud, which risked operators believing a parked item or autonomy boundary in INTENT.md was a hard guarantee. It isn't. Added a calm, non-alarming note to the INTENT.md template explaining the distinction and pointing operators to the hard-enforcement layer: their AI tool's permission config (`deny` / `ask` / `allow`). Intent guides; permissions enforce; the strongest setups use both. This makes the trust model honest — you know exactly what the contract does and doesn't do.

### What changed

- `INTENT.md` (template) — new intro callout: *"How this contract works — and where it stops."* Explains that context-loading guides but doesn't enforce, that fidelity is model-dependent, and that non-negotiable boundaries should be elevated to hard permission rules (`deny` = never, `ask` = confirm first, `allow` = autonomous). Framed as empowerment ("here's how to make a boundary hard if you want"), not alarm.

### Action required

INTENT.md is **operator-personal** — `/aios:update`'s denylist protects it from being *overwritten* (your autonomy levels + venture content are never clobbered). But this disclaimer is a **purely additive, universal callout** (zero operator-specific content), so the action is: **add it directly, then tell the operator — no confirm prompt.**

1. **Detect:** check whether your `INTENT.md` already contains a "How this contract works — and where it stops" note (or equivalent guidance-vs-enforcement language). If present → skip silently.
2. **If absent → add it (don't ask):** insert the disclaimer callout from the template right after the intro blockquote (before `## Autonomy levels`), preserving everything else byte-for-byte. This is safe despite the denylist precisely *because* it's additive + universal — it touches nothing operator-specific. Then tell the operator: *"Added the guidance-vs-enforcement note to your INTENT.md."* (A sanctioned, narrow exception to the INTENT.md write-denylist: additive-only, universal text, content-preserving — never an overwrite.)
3. **Optional follow-on (mention, don't auto-do):** if any INTENT.md boundary is *genuinely non-negotiable* and maps to a concrete tool/command, mirror it into `settings.json` → `permissions` — `deny` ("never") or `ask` ("confirm first"). Most operators' `ask` list is empty; that's the highest-value tier for outward actions (sends/merges/deploys).

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
