#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# AIOS_CLOSE_SESSION_NO_PUSH must reach EVERY push /close-session makes
#
# Contributed 2026-08-29 (PR #59) to stop an automated wrapper's own end-of-run
# push racing the one inside /close-session. The problem is real and unattended:
# aios-commit releases its lock BEFORE pushing (deliberately — a slow network call
# must not make peers wait), so two pushes race; and a rejected push does NOT
# self-heal, it prints "the remote has diverged. Pull/rebase, then push" and stops.
# Correct for a human at a terminal, useless inside a cron.
#
# The contribution covered ONE of three push sites. That is worse than covering
# none: the wrapper's author sets the variable, believes the race is handled, and
# still hits it at the next site — with a symptom that now looks unrelated to the
# thing they configured. This suite exists so the count cannot drift again.
#
# The failure mode it guards is ADDITIVE: someone adds a fourth push site later,
# with no reason to know the flag exists. Nothing in review would catch that. A
# count assertion does.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
F=plugins/aios/commands/close-session.md

echo "── every push site is guarded ──"
# A push site = an invocation of a helper that pushes. Count them, then count the
# guards, and require the two to agree. Counting BOTH sides is the point: asserting
# only "there are 3 guards" would pass while a 4th unguarded site was added.
# Exclude the `allowed-tools:` frontmatter line: it DECLARES the helpers as permitted
# tools, it does not invoke them. Counting it made this assertion report 4 sites for 3
# guards and fail on a file that was already correct — a guard that cannot tell a
# declaration from a call fires on every honest edit, and then gets muted.
SITES=$(grep -E '~/aios/hooks/aios-(commit|note-append)' "$F" | grep -cv '^allowed-tools:')
GUARDS=$(grep -c 'AIOS_CLOSE_SESSION_NO_PUSH:-' "$F")
printf '     push-helper invocations: %s · flag guards: %s\n' "$SITES" "$GUARDS"
if [ "$SITES" -eq "$GUARDS" ]; then
  ok "every push-helper invocation carries the opt-out ($GUARDS/$SITES)"
else
  no "push sites and guards disagree ($GUARDS guards for $SITES sites)" \
     "an unguarded site means a wrapper that set the flag still races there — and the symptom will look unrelated to what they configured"
fi

echo "── the three known sites specifically ──"
grep -qE 'aios-note-append' "$F" && grep -A6 'aios-note-append' "$F" | grep -q 'AIOS_CLOSE_SESSION_NO_PUSH' \
  && ok "site 1: step 5 aios-note-append (Mode A note block)" \
  || no "site 1 unguarded" "the block commit pushes"
grep -A3 'aios-commit -m "session: {date} {topic}"' "$F" | grep -q 'AIOS_CLOSE_SESSION_NO_PUSH' \
  && ok "site 2: step 10 aios-commit (Mode A observed context)" \
  || no "site 2 unguarded" "this is the one the original contribution missed"
grep -q 'own scoped work via .*AIOS_CLOSE_SESSION_NO_PUSH' "$F" \
  && ok "site 3: Mode B report commit" \
  || no "site 3 unguarded" "an automated wrapper is MORE likely to be in Mode B than Mode A"

echo "── the flag lives in the framework's namespace ──"
# CLAUDE_* is Claude Code's own namespace (CLAUDE_CODE_SESSION_ID, CLAUDE_CONFIG_DIR).
# Framework-owned switches are AIOS_* (AIOS_UPDATE_REINVOKED, AIOS_STAR_ASK, AIOS_HUMAN).
# Renamed while nothing depended on it yet — an env var is a contract the moment it ships.
grep -q 'CLAUDE_CLOSE_SESSION_NO_PUSH' "$F" \
  && no "the flag is still in the CLAUDE_* namespace" "framework switches are AIOS_*" \
  || ok "the flag is AIOS_-prefixed, not CLAUDE_-prefixed"

echo "── the default is unchanged behaviour ──"
# Unset must add NO argument at all — not an empty string, which would reach the
# helper as a stray empty pathspec.
for sh in bash zsh sh; do
  command -v "$sh" >/dev/null 2>&1 || continue
  n=$("$sh" -c 'set -- x $([ "${AIOS_CLOSE_SESSION_NO_PUSH:-}" = "1" ] && echo --no-push); echo $#')
  y=$("$sh" -c 'AIOS_CLOSE_SESSION_NO_PUSH=1; set -- x $([ "${AIOS_CLOSE_SESSION_NO_PUSH:-}" = "1" ] && echo --no-push); echo $#')
  if [ "$n" = "1" ] && [ "$y" = "2" ]; then
    ok "$sh: unset adds nothing, =1 adds exactly --no-push"
  else
    no "$sh: expansion is wrong (unset=$n args, set=$y args)" "an empty unquoted expansion would become a stray empty pathspec"
  fi
done

echo "── the helpers actually accept the flag ──"
grep -q -- '--no-push' hooks/aios-note-append \
  && ok "aios-note-append accepts --no-push" \
  || no "aios-note-append does not accept --no-push" "the guard would pass an unknown flag"
grep -q -- '--no-push' hooks/aios-commit \
  && ok "aios-commit accepts --no-push" \
  || no "aios-commit does not accept --no-push"

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
