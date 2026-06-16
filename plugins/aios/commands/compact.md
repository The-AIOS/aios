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
   a. Count entries (`### ` / `## ` headers) + tokens in `vault/00 - notes/context/observed/antifragile.md`. If **≤ ~50 entries / ~40k tokens**, skip — within bounds.
   b. If over: **snapshot first** — `cp` the current file to `00 - notes/logs/observed-snapshots/{current-month}/{today}-antifragile.md`. The snapshot IS the archive — no separate `-archive.md` file; `/trace` reads snapshots + git history.
   c. Then compact the LIVE file, in this order:
      - **Remove** entries whose lesson has **graduated into CLAUDE.md** (a rule now covers it → the lesson lives in CLAUDE.md, loaded every session → the entry is redundant).
      - **Remove** entries that are **resolved/shipped or superseded** (the fix landed, or a later entry replaced it) — preserved in the snapshot + git, reachable via `/trace`.
      - **Keep** the meta-pattern index + every **active, load-bearing, recent** lesson (last ~90 days or still-recurring).
   d. Report: entries removed (graduated vs superseded), entries kept, before/after size. Each removal is safe — the 3.5b snapshot + git preserve the full pre-compaction file.

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

6. **Commit and push**: `cd ~/aios && git add -A && git commit -m "Compact {target-month} logs" && git push`

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
- **Antifragile (Step 3.5) is size-gated, not month-gated** — it runs every invocation and operates on the LIVE `antifragile.md` (the only compaction touching a current file, not a dated log). Always snapshot before compacting it; **"never delete" → "never delete without a snapshot."** Keep the meta-pattern index + active recent lessons; only remove graduated-into-CLAUDE.md or superseded entries.
- If the digest or zip already exists for the target month, warn and skip (don't double-compact)
- Use [[wiki-links]] for all project names, context files, and ventures mentioned.
