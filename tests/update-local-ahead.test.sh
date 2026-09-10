#!/usr/bin/env bash
# tests/update-local-ahead.test.sh
#
# Guards the local-AHEAD branch of /aios:update's three-way compare.
#
# WHAT IT PROTECTS
# ----------------
# `update.md` computed BASE (canonical at the stored hash) and LOCAL, and decided from those two
# alone. Two genuinely different situations produce `LOCAL != BASE`:
#
#   · canonical also moved  → real divergence  → back up, take canonical
#   · canonical did NOT move → the local copy is AHEAD → taking canonical is a DOWNGRADE
#
# The second was indistinguishable from the first, so the command overwrote a newer local file with
# an older canonical one, reported success, and left the operator to re-apply the same improvement
# on every sync forever. The backup preserved the bytes; it did not prevent the downgrade.
#
# It happened here: `plugins/aios/commands/graduate.md` was improved in a vault on 2026-08-15 and
# the next sync overwrote it, reported as a "personalization". Under the branch this suite guards it
# would have been classified AHEAD and kept.
#
# The fix asks one more question — *did canonical actually change this file?* — from data the
# command already had. This suite asserts the classifier, not the prose.
#
# Run:  bash tests/update-local-ahead.test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="$ROOT/plugins/aios/commands/update.md"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ahead.XXXXXX"); trap 'rm -rf "$TMP"' EXIT

# The classifier, in the exact shape the spec prescribes.
classify(){ # classify <base> <local> <upstream>   → IDENTICAL | STALE | AHEAD | DIVERGED | INCONCLUSIVE
  local B="$1" O="$2" T="$3"
  [ -z "$B" ] && { echo INCONCLUSIVE; return; }
  [ "$O" = "$T" ] && { echo IDENTICAL; return; }
  [ "$O" = "$B" ] && { echo STALE; return; }
  [ "$T" = "$B" ] && { echo AHEAD; return; }
  echo DIVERGED
}

echo "── 1. the four classes ──"
[ "$(classify v1 v1 v1)" = IDENTICAL ]   && ok "base=local=upstream → IDENTICAL (skip)"        || no "IDENTICAL misclassified"
[ "$(classify v1 v1 v2)" = STALE ]       && ok "local==base, upstream moved → STALE (overwrite, no backup)" || no "STALE misclassified"
[ "$(classify v1 v2 v1)" = AHEAD ]       && ok "local moved, upstream did NOT → AHEAD (KEEP LOCAL)" || no "AHEAD misclassified — this is the downgrade"
[ "$(classify v1 v2 v3)" = DIVERGED ]    && ok "both moved → DIVERGED (backup, take canonical)"  || no "DIVERGED misclassified"
[ "$(classify '' v2 v3)" = INCONCLUSIVE ] && ok "baseline unreachable → INCONCLUSIVE (conservative)" || no "INCONCLUSIVE misclassified"

echo "── 2. the real incident, replayed ──"
# graduate.md: operator added a section; canonical had not touched the file since the last sync.
mkdir -p "$TMP/w"
printf 'A\nB\n'        > "$TMP/w/base"       # canonical @ stored hash
printf 'A\nB\nNEW\n'   > "$TMP/w/local"      # vault: operator added a section
cp "$TMP/w/base"         "$TMP/w/upstream"   # canonical HEAD: unchanged
h(){ shasum -a256 "$1" | cut -d' ' -f1; }
cls=$(classify "$(h "$TMP/w/base")" "$(h "$TMP/w/local")" "$(h "$TMP/w/upstream")")
[ "$cls" = AHEAD ] && ok "graduate.md replay → AHEAD (would have been kept)" || no "replay classified $cls, not AHEAD"
# And the pre-fix logic (base-vs-local only) on the same inputs:
prefix=$([ "$(h "$TMP/w/local")" = "$(h "$TMP/w/base")" ] && echo STALE || echo "OVERWRITE-WITH-BACKUP")
[ "$prefix" = "OVERWRITE-WITH-BACKUP" ] \
  && ok "CONTROL: two-way logic calls the same case OVERWRITE — the downgrade, reproduced" \
  || no "CONTROL DID NOT FIRE — the two-way logic did not downgrade, so the fix guards nothing"

echo "── 3. AHEAD may only ever PREVENT a write ──"
# Whatever else changes, no input may make AHEAD produce an overwrite: assert it is the only
# class that keeps local, and that it never coincides with upstream having moved.
bad=0
for T in v1 v2; do for O in v1 v2; do for B in v1 v2; do
  c=$(classify "$B" "$O" "$T")
  if [ "$c" = AHEAD ] && [ "$T" != "$B" ]; then bad=1; fi
done; done; done
[ "$bad" -eq 0 ] && ok "AHEAD is never returned when canonical moved (cannot mask an upstream change)" \
  || no "AHEAD returned while upstream had moved — it would hide a real canonical change"

echo "── 4. the spec still carries the branch (a classifier nobody executes is prose) ──"
grep -q 'UP=$(h_file' "$SPEC" && ok "spec computes the upstream hash" || no "spec no longer computes UP"
grep -q 'is \*\*AHEAD\*\*' "$SPEC" && ok "spec names the AHEAD outcome" || no "spec lost the AHEAD branch"
grep -q 'never DOWNGRADE' "$SPEC" && ok "the auto-apply rule states the downgrade limit" || no "auto-apply rule no longer qualifies itself"
grep -q 'Known limit' "$SPEC" && ok "the DIVERGED limit is stated, not implied" || no "the known limit was dropped"


# ── the BOTH-MOVED branch must report loudly, not as a plain success ─────────
# Reported by an operator, 2026-09-09: three of their own hunks left CLAUDE.md
# on a live sync and the run reported success. The merge they proposed was
# declined on architecture (CLAUDE.md is Tier-1; its value is being the same
# file for every operator). The SILENCE was not declined -- a rule removed from
# the file every session loads does not surface as a missing file or a broken
# command, it surfaces as agents behaving differently weeks later with nothing
# to trace back to. And the backup is not a remedy: this spec argues in its own
# words that "backups are never auto-restored".
BM=$(awk '/upstream != baseline.*both sides moved/{f=1} f&&/^2\.7\./{exit} f' "$SPEC")
[ -n "$BM" ] && ok "both-moved branch extracted" || no "could not extract the both-moved branch" "anchors moved"
printf '%s' "$BM" | grep -qiE 'never be reported as a plain success|SAY SO' \
  && ok "the branch forbids a silent success report" \
  || no "a replaced file can still be reported as success" "the operator learns weeks later, from behaviour"
printf '%s' "$BM" | grep -qF 'backup path' \
  && ok "the report names the backup path" || no "the backup path is not required in the report"
# the three legitimate homes, so the report ROUTES instead of only informing
for home in 'Command personalizations' 'INTENT.md' 'working_style.md'; do
  printf '%s' "$BM" | grep -qF "$home" && ok "routes to: $home" \
    || no "does not route to $home" "a loud replace that teaches nothing is only a louder loss"
done
printf '%s' "$BM" | grep -qiE 'same file for every operator' \
  && ok "states WHY, so the operator does not read it as a bug" \
  || no "no reason given for the replace" "without it the operator reasonably assumes a defect"
printf '%s' "$BM" | grep -qiE 'PR to canonical' \
  && ok "offers the universal-rule route (PR), not just the personal ones" \
  || no "does not mention upstreaming" "a good rule stuck in one vault is a loss too"

printf '\nRESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
