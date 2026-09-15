#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# CLAUDE.md budget — a ratchet, so condensation is not repaid by the next feature
#
# CLAUDE.md loads into EVERY session, so its size is a tax on all of them. Issue #93
# measured it and the framework has condensed it twice, section by section, each time
# with a pre-registered behavioural rubric. Both passes were real work and correct.
#
# Both were also erased within a week, which is why this file exists:
#
#   § Spawning Sessions, condensed by #98 on 2026-09-07:  14,777 B -> 12,392 B  (-16%)
#   the same section seven days later:                              15,924 B  (+28%)
#
# It ended up LARGER than before it was ever condensed. Across the whole file, the week
# after that pass ran 72,725 B -> 96,204 B (+32%) — the pass removed 2,405 bytes and the
# next seven days added 23,479. No commit did anything wrong; each added a real rule with
# a real reason. Nothing ever showed the running total, so nobody was deciding.
#
# THE POINT IS NOT TO BLOCK GROWTH. It is to make growth a decision. A PR that needs more
# room has three honest moves: condense something else, relocate the prose to the doc that
# owns it, or raise CEILING here in the same PR and let a reviewer see the trade. What the
# ratchet forbids is the fourth: adding silently, forever, in increments nobody totals.
#
# Reviewing a raise: it is not a rubber stamp and not a veto. Ask what a session now gets
# for the bytes, and whether the same rule could live in the doc that owns it — CLAUDE.md
# is the behavioural contract, not the place a justification goes to be safe.
#
# Written for bash 3.2. No dependencies.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# The ratchet. Raise it DELIBERATELY, in the PR that needs the room, never to get green.
CEILING=94500

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

[ -f CLAUDE.md ] || { echo "  FAIL CLAUDE.md not found"; exit 1; }

BYTES=$(wc -c < CLAUDE.md | tr -d ' ')
# Same token proxy /aios:compact uses, so the two surfaces speak one language.
TOKENS=$(( BYTES * 10 / 37 ))
HEADROOM=$(( CEILING - BYTES ))

printf '  CLAUDE.md: %s bytes (~%s tokens) · ceiling %s · headroom %s\n' \
  "$BYTES" "$TOKENS" "$CEILING" "$HEADROOM"

if [ "$BYTES" -le "$CEILING" ]; then
  ok "CLAUDE.md is within its per-session budget"
else
  no "CLAUDE.md is $(( BYTES - CEILING )) bytes over its budget ($BYTES > $CEILING)" \
     "Every session pays this. Condense a section (pin its literals first, then run the rubric — see #93/#98), relocate the prose to the doc that owns it, or raise CEILING in tests/claude-md-budget.test.sh in THIS PR so the trade is reviewed. The largest sections are listed below."
  # Name where the weight is, so the author is not left hunting.
  awk '
    /^#{2,3} /{ if (n != "") printf "       %7d  %s\n", b, n; n=$0; sub(/^#+ /,"",n); b=0 }
    { b += length($0) + 1 }
    END { if (n != "") printf "       %7d  %s\n", b, n }
  ' CLAUDE.md | sort -rn | head -5
fi

# A ceiling far above the file stops being a ratchet without ever failing, so the drift
# that matters is slack, not size. This never fails the build — it is the early warning
# the size number alone does not give.
if [ "$HEADROOM" -gt 8000 ]; then
  printf '  note  %s bytes of unused headroom — after a condensation, lower CEILING to lock the gain in.\n' "$HEADROOM"
fi

printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
