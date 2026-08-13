#!/usr/bin/env bash
# Regression suite for two bugs in /aios:update found by RUNNING the command
# (2026-08-13) rather than hand-executing its steps. Both were silent: the sync still
# landed, so nothing failed — only the account of it was wrong.
#
#   1. Step 1.5's changelog scan assumed ONE hash per entry. Same-day accumulation made
#      entries cite many (`hash: a · b · c`), and taking the first returned "synced" for
#      an entry whose later subsections were new — so the operator was never shown them
#      and their `Action required` never ran.
#
#   2. Step 2 built its layer pathspec as a SPACE-JOINED STRING and passed it unquoted.
#      THE SESSION SHELL IS ZSH, WHICH DOES NOT WORD-SPLIT, so the whole list reached
#      git as one pathspec matching nothing: every layer change invisible to Step 2.
#
# TEST 3 IS THE ONE THAT MATTERS FOR BUG 2, AND IT MUST RUN UNDER ZSH.
# Under bash the buggy form WORKS (bash word-splits), so a bash-only test passes on
# broken code — that is precisely why this survived weeks of green CI.

set -u
PASS=0; FAIL=0; SKIP=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
sk(){ SKIP=$((SKIP+1)); printf '  skip %s\n' "$1"; }
have(){ [ "$1" = "$2" ] && ok "$3" || { no "$3"; printf '       expected %s, got %s\n' "$2" "$1"; }; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="$ROOT/plugins/aios/commands/update.md"
[ -f "$SPEC" ] || { echo "cannot find update.md"; exit 1; }

printf '/aios:update — changelog scan + layer pathspec\n'

# ═══════════════════════════════════════════════════════════════════
# BUG 1 — multi-hash changelog entries
# ═══════════════════════════════════════════════════════════════════
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1
git init -q .; git config user.email t@t; git config user.name t; git config commit.gpgsign false
for i in 1 2 3 4 5; do echo "c$i" > f; git add f; git commit -qm "commit $i"; done
H1=$(git rev-parse --short=7 HEAD~4); H2=$(git rev-parse --short=7 HEAD~3)
H3=$(git rev-parse --short=7 HEAD~2); H5=$(git rev-parse --short=7 HEAD)
STORED=$(git rev-parse HEAD~2)          # operator synced up to the 3rd commit

# The rule under test: an entry is NEW if ANY cited hash is not an ancestor of STORED.
entry_state(){ # $@ = hashes
  local any_new=0 all_ok=1 h
  for h in "$@"; do
    if git merge-base --is-ancestor "$h" "$STORED" >/dev/null 2>&1; then :
    else any_new=1; all_ok=0; fi
  done
  [ "$any_new" -eq 1 ] && echo NEW || echo SYNCED
}
# The OLD rule: look at the first hash only.
entry_state_v1(){ git merge-base --is-ancestor "$1" "$STORED" >/dev/null 2>&1 && echo SYNCED || echo NEW; }

have "$(entry_state "$H1" "$H2" "$H3")"      "SYNCED" "1. entry whose every hash is an ancestor → SYNCED"
have "$(entry_state "$H1" "$H2" "$H3" "$H5")" "NEW"   "2. entry with 3 synced + 1 new hash → NEW (the reported bug)"
have "$(entry_state_v1 "$H1")"                "SYNCED" "3. OLD rule returns SYNCED for that same entry (i.e. it hid it)"
have "$(entry_state "$H5")"                   "NEW"    "4. single new hash → NEW (single-hash case still works)"
have "$(entry_state "$H1")"                   "SYNCED" "5. single old hash → SYNCED"
# An unreachable hash must never SATISFY the synced test.
have "$(entry_state "$H1" "deadbeef")"        "NEW"    "6. unreachable hash counts as NOT synced, never as synced"

# ═══════════════════════════════════════════════════════════════════
# BUG 2 — the layer pathspec. Static assertion first (runs everywhere).
# ═══════════════════════════════════════════════════════════════════
grep -q '"${LAYERS\[@\]}"' "$SPEC" \
  && ok "7. spec passes the layer list as a QUOTED ARRAY expansion" \
  || no "7. spec must use \"\${LAYERS[@]}\" — a bare \$LAYERS matches nothing under zsh"
grep -qE '^\s*\$LAYERS\b' "$SPEC" \
  && no "8. spec still contains a bare unquoted \$LAYERS pathspec" \
  || ok "8. no bare unquoted \$LAYERS pathspec remains"
grep -q 'LAYERS=()' "$SPEC" \
  && ok "9. LAYERS is declared as an array, not a string" \
  || no "9. LAYERS must be declared as an array"

# ═══════════════════════════════════════════════════════════════════
# BUG 2 — dynamic proof, UNDER ZSH. Skipped (loudly) if zsh is absent,
# because under bash the buggy form works and the test would be vacuous.
# ═══════════════════════════════════════════════════════════════════
mkdir -p agents hooks plugins/aios/commands
echo a > agents/x.md; echo b > hooks/y.py; echo c > plugins/aios/commands/z.md
git add -A; git commit -qm "layers"
BASE=$(git rev-parse HEAD)
echo changed > plugins/aios/commands/z.md; git add -A; git commit -qm "change a layer file"

if command -v zsh >/dev/null 2>&1; then
  STR=$(zsh -c '
    LAYERS=""
    for d in agents hooks plugins; do LAYERS="$LAYERS $d/"; done
    git diff --name-only '"$BASE"'..HEAD -- $LAYERS 2>/dev/null | grep -c . ' 2>/dev/null)
  ARR=$(zsh -c '
    LAYERS=()
    for d in agents hooks plugins; do LAYERS+=("$d/"); done
    git diff --name-only '"$BASE"'..HEAD -- "${LAYERS[@]}" 2>/dev/null | grep -c . ' 2>/dev/null)
  have "${ARR:-0}" "1" "10. under zsh: QUOTED ARRAY finds the changed layer file"
  have "${STR:-x}" "0" "11. under zsh: unquoted string finds NOTHING (the bug, reproduced)"
else
  sk "10-11. zsh not available — the dynamic proof cannot run here"
  printf '       NOTE: under bash the buggy form WORKS, so a bash-only run of this\n'
  printf '       suite cannot prove bug 2. macOS runners have zsh; the static\n'
  printf '       assertions (7-9) are the portable guard.\n'
fi

printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
