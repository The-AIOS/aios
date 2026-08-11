---
tags:
  - aios
  - command
  - monthly
description: Compact previous month's logs — digest + zip snapshots and role logs
allowed-tools: mcp__obsidian__*, Bash(cd ~/aios && git:*), Bash(zip:*), Bash(rm:*), Bash(ls:*), Bash(mkdir:*), Read
argument-hint: "[YYYY-MM] (optional — defaults to previous month)"
---

# /compact — Monthly Log Compaction

You are compacting the previous month's log files to keep the vault clean over time.

## When to use

First of the month to digest + archive the previous month's snapshots and role logs. Frees up working memory while preserving the historical layer.


## How it works

Individual snapshot and role-log files accumulate daily. This command:
1. Creates a **human-readable digest** (`.md`) summarizing the month's changes
2. **Zips** the individual files into an archive
3. **Removes** the individual files, keeping only the digest + zip

## Steps

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /compact` for any user overrides. Apply them to the steps below.

1. **Determine target month**: If an argument is provided (e.g. `2026-02`), use that. Otherwise, default to the previous month.
2. **Check eligibility**: Only compact months that are at least 1 month old. Never compact the current month or previous month (they're the rolling window for `/trace` and `/drift`).
3. **Compact observed snapshots**:
   a. List all files in `00 - notes/logs/observed-snapshots/{target-month}/`
   b. If no files exist, skip this section
   c. Read each snapshot file — extract the key changes (what was updated, what patterns emerged, what shifted)
   d. Write `00 - notes/logs/observed-snapshots/{target-month}/{target-month}-observed-digest.md` with:
      ```
      ---
      tags:
        - log
        - digest
        - observed
      created: "{today}"
      period: "{target-month}"
      type: monthly-digest
      ---
      # Observed Context Digest — {target-month}

      > Compacted from {N} snapshot files on {today}.

      ## Summary of changes

      {For each observed file that had snapshots this month, summarize the arc:}

      ### profile.md
      - {Key changes this month}

      ### patterns.md
      - {New patterns identified, patterns refined}

      ### growth.md
      - {Growth moments, avoidance patterns noted}

      {etc. for each file that had changes}

      ## Timeline
      {Chronological list of snapshot dates and what changed}
      - {YYYY-MM-DD}: {which files were snapshotted, brief note}
      ```
   e. Zip all individual snapshot files (NOT the digest): `cd vault/00\ -\ notes/logs/observed-snapshots/{target-month} && zip {target-month}-snapshots.zip *.md -x '*-digest.md' && rm` the individual files (keep digest + zip)

3.5. **Bound `antifragile.md` (size-gated — this check runs EVERY invocation, independent of the target month).**
   `antifragile.md` is the one observed file that grows unbounded (the "never delete, supersede" rule) AND is read at *every* session start — so it gets a standing size bound. Unlike the log compaction above, this operates on the **live current file** and is gated by **size, not age**.
   a. Measure `vault/00 - notes/context/observed/antifragile.md` — **tokens are the real cost; entry count is only a proxy for it.** If **≤ ~45k tokens** (≈1,000 lines) **AND ≤ ~120 entries**, skip — within bounds. (Quick read: `wc -c` ÷ 3.7 ≈ tokens; `grep -c '^### [0-9]'` = entries.)
   b. If over: **snapshot first** — `cp` the current file to `00 - notes/logs/observed-snapshots/{current-month}/{today}-antifragile.md`. The snapshot IS the archive — no separate `-archive.md` file; `/trace` reads snapshots + git history.
   c. Then compact the LIVE file in **three tiers** — never silent-delete on inference:
      - **TIER 0 — RELOCATE, and try this BEFORE condensing (added 2026-08-11):** a long argument living inside the meta-pattern index costs its full weight on every single read, while the same prose in its own numbered entry costs nothing until something points at it. Moving one such block out and leaving a two-line pointer measured **~1,570 tokens reclaimed in a single edit** — against **12.6% for condensing 24 of 50 entries**, because mature entries are dense rather than padded. Relocation is the lever that pays; condensation is largely spent after its first pass. ⚠️ **If the relocated block contains a live open decision, the pointer must carry that decision verbatim** — otherwise you have moved a decision into a file nobody opens, which is worse than the tokens you saved. _(Measured and reported by Luigi Matrone / ALI, 2026-08-08, from a real compaction pass.)_
      - **TIER 1 — AUTO-tombstone (safe, mechanical):** entries **explicitly marked** graduated/merged/superseded (carrying `→ Graduated to CLAUDE.md`, `→ Merged into #N`, or `superseded by #N`). The file itself declares these redundant. **Tombstone, don't delete** — collapse the body but keep the number, title, marker and Category tag, so the meta-pattern index and every external `#N` reference still resolve. **Entry numbers are identity — never renumber.**
      - **TIER 2 — CONDENSE (the primary lever):** rewrite verbose entries into tight **what-broke / why / fix** triplets (~6-9 lines). Preserve verbatim: every entry number, all exact commands, flags, paths, hashes, and cross-references (`#N`, `[[wikilinks]]`, meta-pattern letters). This is where the tokens actually are — once entries are already terse, removal frees almost nothing. Condensing is an editorial pass, not a deletion, so the wisdom survives at a fraction of the cost.
      - **TIER 3 — SURFACE for confirmation (judgment — never auto):** entries that *look* stale (resolved/shipped, old, low-recurrence) but carry **no explicit marker**. List them with the reason and **ask the operator to confirm** before removing each. NEVER auto-delete an unmarked entry on inference — a wrong cut loses real wisdom, and on a teammate's vault Claude can't see what's still load-bearing for them.
      - **Keep** the meta-pattern index in full, every **active/recent** lesson (last ~90 days or still-recurring), and any entry the operator didn't confirm.
      - **Before writing, verify:** entry-number set unchanged, meta-pattern index intact, no dangling `#N`, and a grep for the load-bearing commands/hashes still hits. Cheap, and it's what makes the pass reversible-in-practice as well as in-git.
   d. Report: entries tombstoned (with their marker), entries condensed, entries surfaced-for-confirmation (+ operator's decision), entries kept, before/after size in BOTH tokens and entries. Every change is reversible — the 3.5b snapshot + git preserve the full pre-compaction file.

4. **Compact role logs**:
   a. List all files in `00 - notes/logs/role-logs/{target-month}/`
   b. If no files exist, skip this section
   c. Read each role log — group activities by pillar
   d. Write `00 - notes/logs/role-logs/{target-month}/{target-month}-role-digest.md` with:
      ```
      ---
      tags:
        - log
        - digest
        - role
      created: "{today}"
      period: "{target-month}"
      type: monthly-digest
      ---
      # Role Activity Digest — {target-month}

      > Compacted from {N} role log files on {today}.

      ## By pillar

      ### {Pillar 1}
      - {Summarized contributions this month}

      ### {Pillar 2}
      - {Summarized contributions this month}

      {etc.}

      ## Other work
      - {Non-pillar activities worth noting}
      ```
   e. Zip individual role log files: `zip {target-month}-role-logs.zip *.md -x '*-digest.md'` then remove the originals

5. **Report**: Show what was compacted:
   - Observed snapshots: {N} files → digest + zip
   - Role logs: {N} files → digest + zip
   - Space saved estimate

6. **Commit and push**: `cd ~/aios && ~/aios/hooks/aios-commit --vault -m "Compact {target-month} logs"`

## End state

After compaction, an older month folder looks like:
```
logs/observed-snapshots/2026-01/
├── 2026-01-observed-digest.md    ← readable summary
└── 2026-01-snapshots.zip         ← raw files preserved

logs/role-logs/2026-01/
├── 2026-01-role-digest.md
└── 2026-01-role-logs.zip
```

## Output

- Compacted month digest at `vault/00 - notes/logs/digest-{YYYY-MM}.md` summarizing the month's activity
- Original snapshots zipped to `vault/04 - backups/archive-{YYYY-MM}.zip`
- Cleared `observed-snapshots/{YYYY-MM}/` + `role-logs/{YYYY-MM}/` (only after successful zip + digest write)
- Close-session: "Compacted {month}: {N} snapshots archived, {N} role logs digested, working memory freed."

## Rules

- **Never compact current or previous month** — those files are the rolling window for `/trace` and `/drift`
- **Always create the digest BEFORE zipping** — the digest is the human-readable record
- **Always zip BEFORE deleting** — never delete without archiving
- **Digest quality matters** — don't just list files. Summarize the arc: what changed, what patterns emerged, what growth happened
- **If a month has < 3 files**, skip compaction — not worth it yet
- **Antifragile (Step 3.5) is size-gated, not month-gated** — it runs every invocation and operates on the LIVE `antifragile.md` (the only compaction touching a current file, not a dated log). Always snapshot before compacting it; **"never delete" → "never delete without a snapshot."** Keep the meta-pattern index + active recent lessons. **Tombstone only entries the file explicitly marks** (graduated/merged/superseded), **condense verbose entries** to reclaim the tokens, and **surface unmarked stale candidates for the operator to confirm** — never auto-delete on inference (a wrong cut loses real wisdom, and Claude can't see what's load-bearing on a teammate's vault).
- **Entry numbers are identity — never renumber.** They're cited from USER.md, other commands, project notes and daily notes; removal leaves a gap (correct), renumbering silently breaks every external pointer.
- If the digest or zip already exists for the target month, warn and skip (don't double-compact)
- Use [[wiki-links]] for all project names, context files, and ventures mentioned.
