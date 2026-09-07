---
name: vault-migrations
description: The craft of restructuring a vault without losing a byte — bulk moves, folder dissolutions, renames, file splits/merges across many notes. Use whenever a structure change touches more than a handful of files (dissolving a folder, splitting a monolith note into several, re-homing a species, renaming with many inbound links), or when /aios:housekeeping proposals are approved and need executing. Pairs with templates/aios/vault-grammar.md (what the target structure should be); this skill is HOW to get there verifiably.
---

# Vault Migrations — restructure without loss

A vault migration is a refactor of *meaning-bearing text* with no compiler to catch what you drop. The failure mode is silent: a file left behind in a deleted folder, a table row swallowed by a regex, a wiki-link that stops resolving — none of it errors, all of it surfaces weeks later as "where did X go?" This skill is the discipline that makes structure changes safe enough to do boldly.

## The contract (non-negotiable)

1. **Dry-run first, always.** Every migration is a script (or explicit plan) that runs in report-only mode and prints its full audit — what moves where, what gets rewritten, what the verification found — *before* any write. The write pass runs the identical logic behind a `--write` flag. Never "carefully do it live."
2. **Inventory-verify, don't spot-check.** Prove completeness with counts and set-equality, not by eyeballing:
   - **File accounting:** count files in the source tree before; assert `planned moves == that count` (unmapped files fail loudly); after writing, assert every destination exists and the source is empty.
   - **Key/heading-set equality** when the content carries identities (roadmap keys, section headings): extract the full set before and after; assert equal *as sets* and duplicate-free. A lost identity is the worst loss because everything referencing it dangles.
   - **Line accounting** for in-file restructures: every non-empty source line must appear in the output or be on an explicit, printed dissolve-whitelist. "Probably nothing was dropped" is not a verification.
3. **No silent overwrites.** Before moving, assert no destination already exists. A move that lands on an existing file is byte-for-byte indistinguishable from success.
4. **The graph is part of the inventory.** Wiki-links resolve by basename: check for basename collisions the move would create; leave `aliases:` on every rename; leave a redirect stub at any dissolved basename with heavy inbound traffic (see `templates/aios/vault-grammar.md` § 5).
5. **One commit per verified stage.** Each stage commits only after its verification prints clean — so any stage is individually revertible and the git log reads as the migration's audit trail. Scope the commit to the migration's paths (never `git add -A` in a concurrently-written vault).
6. **Verify deletion last.** Only remove a source folder after the N-of-N accounting passes — and remove *empty directories* (`rmdir`, which fails on leftovers), never `rm -rf` a tree you believe is empty.

## The script shape

```python
# migration.py — dry-run by default, --write to apply
DRY = '--write' not in sys.argv

# 1. build the full move/rewrite plan up front (never decide mid-write)
# 2. assert source accounting: files_before == len(planned_moves)
# 3. assert no destination exists (no silent overwrite)
# 4. print the entire plan (src → dst, one line each)
if DRY: sys.exit(0)
# 5. apply
# 6. verify: every dst exists · key/line sets equal · source empty
# 7. print a VERIFIED line with the numbers — the commit message quotes it
```

Small enough to read in one screen per stage. Many small verified stages beat one omnibus script.

## Field-tested gotchas (each cost a real migration a real bug)

- **Regex-extracted identities need the full grammar.** A key pattern like `AI-\d+` misses segmented keys (`AI-XYZ-\d+`); a definition-row regex must anchor on the row *syntax* (e.g. the ` · ` separator) or annotation lines mentioning a key get counted as second definitions. Always print the extracted set's size and compare against a `grep -c` sanity check.
- **Markdown tables lie to line-based tools.** Escaped pipes (`\|`) split naive `split('|')`; a stray *unescaped* pipe inside a cell adds a phantom column (rejoin overflow cells rather than asserting exact width). Converting table rows to list rows: verify every cell's text survives as a substring of the output.
- **Wrapping pre-formatted text double-applies formatting.** Bolding a cell that already contains bold produces `****` seams. After any wrap-in-formatting pass, grep the output for the seam pattern.
- **Table-escaped wiki-links are the link-cascade blind spot.** A rename cascade that greps `[[old-name]]` misses `[[old-name\|alias]]` inside tables. Grep the *basename*, not the full link syntax.
- **Hidden dot-directories block `rmdir`.** Tool/system droppings (`.claude/`, editor state) live in folders that "should be empty." `rmdir` failing there is the safety net working — inspect, then remove the dropping explicitly, never blanket `rm -rf`.
- **grep skips files it mis-detects as binary.** Emoji-dense or mixed-encoding notes can return "no matches" falsely — sweep with `grep -a` when completeness matters.
- **Frontmatter colons need quoting.** A rewritten frontmatter value containing `: ` (colon-space) breaks YAML parsing downstream — quote it.
- **Concurrent writers exist.** Another session (or the operator in the editor) may touch files mid-migration: re-read immediately before rewriting a shared file, and treat a stale-anchor edit failure as safety, not error.

## After the migration

- Update every `_index.md` whose folder changed; regenerate any derived board/registry.
- Re-run the link check: grep the old basenames vault-wide; anything still pointing at a dissolved name gets the redirect stub or an alias.
- Record the migration where the vault keeps structural history (the folder's `_index.md` or the migration's commit trail) — the *map* of what moved where is itself a retrieval surface.
- Propose the structure change to `/aios:housekeeping`'s checklist if it established a new convention (grammar evolves by decision — update `templates/aios/vault-grammar.md` in the same breath, or the next audit reports your new convention as drift).
