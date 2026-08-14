#!/usr/bin/env bash
# tests/star-check.test.sh
#
# Guards hooks/aios-star-check — the in-product star ask.
#
# WHY THIS EXISTS
# ---------------
# Three real defects were found by hand while writing the script, and every one of them
# fails in the SILENT direction — the script still exits 0 and still prints a verdict, it is
# just the wrong verdict:
#
#   1. A MISSING TRACKER read as "not declined" instead of "cannot tell", so an operator who
#      had already declined would be asked again. That is the precise nag the three-state
#      design exists to prevent, and it looked like a pass.
#   2. `--star` on a repo whose PUT could not succeed reported `starred=` anyway in the first
#      draft's failure path — a receipt for something that did not happen.
#   3. The key=value output was not shell-quoted, so the `eval "$(aios-star-check)"` snippet
#      documented for its own caller executed the reason sentence as a command.
#
# None of the three would be caught by "does it run". So this suite asserts the VERDICT for
# each input state, and every scenario that can be inverted is also run inverted, so a
# vacuous version of this file fails its own controls.
#
# NETWORK: the API-dependent paths (starred / unstarred) are NOT asserted here — they need an
# authenticated `gh` and would make the suite depend on one account's star state. Everything
# that decides WHETHER to ask is local, and that is what this covers. The write path is
# exercised against a repo that cannot exist, so a PUT can only fail.
#
# Run:  bash tests/star-check.test.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/hooks/aios-star-check"
PASS=0; FAIL=0
TMP=$(mktemp -d "${TMPDIR:-/tmp}/star-check-test.XXXXXX")
cleanup() { chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
check(){ # check <label> <expected-verdict> <actual-output>
  case "$3" in *"verdict='$2'"*) ok "$1" ;; *) bad "$1" "expected verdict='$2', got: $(printf '%s' "$3" | tr '\n' ' ')" ;; esac; }

# check_reason <label> <expected-verdict> <substring the reason MUST contain> <output>
#
# WHY VERDICT ALONE IS NOT ENOUGH, and this is not theoretical — CI caught it.
# `unknown` has FIVE causes, and asserting only the verdict cannot tell them apart. On a
# runner with `gh` installed but unauthenticated, "missing tracker" and "not authenticated"
# both print verdict='unknown'. So the missing-tracker assertion PASSED on CI for entirely
# the wrong reason, and its control then reported itself vacuous — correctly. The `reason`
# field is the only part of the output that identifies WHICH guard fired, so any assertion
# about a specific guard has to read it.
check_reason(){
  case "$4" in
    *"verdict='$2'"*)
      case "$4" in
        *"$3"*) ok "$1" ;;
        *) bad "$1" "verdict='$2' as expected, but a DIFFERENT guard produced it — reason lacks '$3': $(printf '%s' "$4" | tr '\n' ' ')" ;;
      esac ;;
    *) bad "$1" "expected verdict='$2', got: $(printf '%s' "$4" | tr '\n' ' ')" ;;
  esac; }

mk_tracker() { printf 'repo=git@github.com:The-AIOS/aios.git\nhash=abc1234\nsynced=2026-01-01\n' > "$1"; }

echo "── 1. the script is present and executable ──"
[ -f "$SCRIPT" ] && ok "hooks/aios-star-check exists" || bad "hooks/aios-star-check missing"
[ -x "$SCRIPT" ] && ok "carries the exec bit" || bad "not executable — ./hooks/aios-star-check would be Permission denied"
bash -n "$SCRIPT" && ok "parses" || bad "syntax error"

echo "── 2. fail closed: every inconclusive input yields 'unknown' ──"
T="$TMP/t1"; mk_tracker "$T"

out=$(AIOS_TRACKER="$TMP/does-not-exist" bash "$SCRIPT" 2>/dev/null)
check_reason "missing tracker → unknown, from the TRACKER guard (DEFECT 1: was 'starred')" \
  unknown "tracker unreadable" "$out"

touch "$TMP/unreadable"; chmod 000 "$TMP/unreadable"
if [ -r "$TMP/unreadable" ]; then
  ok "unreadable-tracker case skipped (running as root — chmod 000 is not enforced)"
else
  out=$(AIOS_TRACKER="$TMP/unreadable" bash "$SCRIPT" 2>/dev/null)
  check_reason "unreadable tracker → unknown, from the TRACKER guard" unknown "tracker unreadable" "$out"
fi

out=$(AIOS_TRACKER="$T" AIOS_STAR_ASK=never bash "$SCRIPT" 2>/dev/null)
check_reason "AIOS_STAR_ASK=never → unknown, from the AUTOMATION guard" unknown "AIOS_STAR_ASK=never" "$out"

out=$(PATH=/usr/bin:/bin AIOS_TRACKER="$T" bash "$SCRIPT" 2>/dev/null)
check_reason "no gh on PATH → unknown, from the GH guard" unknown "gh not installed" "$out"

echo "── 3. the verdict path ALWAYS exits 0 (the verdict is the output, not the status) ──"
for env_desc in "AIOS_TRACKER=$TMP/does-not-exist" "AIOS_STAR_ASK=never AIOS_TRACKER=$T"; do
  # shellcheck disable=SC2086
  env $env_desc bash "$SCRIPT" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 0 ] && ok "exit 0 with $env_desc" || bad "exit $rc with $env_desc — a non-zero verdict path breaks callers"
done

echo "── 4. decline is three-state, terminal, and never touches hash= ──"
T2="$TMP/t2"; mk_tracker "$T2"
out=$(AIOS_TRACKER="$T2" bash "$SCRIPT" --decline 2>&1)
case "$out" in *recorded*) ok "--decline records" ;; *) bad "--decline did not record" "$out" ;; esac
grep -q '^star-ask=declined' "$T2" && ok "star-ask=declined written" || bad "star-ask= line absent"
grep -q '^hash=abc1234$' "$T2" && ok "hash= untouched (/aios:update owns that field alone)" || bad "hash= was disturbed"
grep -q '^repo=git@github.com:The-AIOS/aios.git$' "$T2" && ok "repo= untouched" || bad "repo= was disturbed"
out=$(AIOS_TRACKER="$T2" bash "$SCRIPT" 2>/dev/null)
check "after a decline → declined, forever" declined "$out"
out=$(AIOS_TRACKER="$T2" bash "$SCRIPT" --decline 2>&1)
case "$out" in *"already recorded"*) ok "--decline is idempotent" ;; *) bad "second --decline was not idempotent" "$out" ;; esac
# The decline must win even when the check could otherwise reach the API.
n_before=$(wc -l < "$T2")
AIOS_TRACKER="$T2" bash "$SCRIPT" >/dev/null 2>&1
[ "$(wc -l < "$T2")" -eq "$n_before" ] && ok "reading a verdict never writes the tracker" || bad "the verdict path mutated the tracker"

echo "── 5. output is eval-safe in bash AND zsh (DEFECT 3) ──"
for sh in bash zsh; do
  command -v "$sh" >/dev/null 2>&1 || { ok "$sh not installed — skipped"; continue; }
  got=$("$sh" -c 'eval "$(AIOS_TRACKER='"$T2"' '"$SCRIPT"' 2>/dev/null)"; printf "%s|%s" "$verdict" "$reason"' 2>&1)
  case "$got" in
    declined\|*) ok "$sh: eval round-trip sets verdict + a multi-word reason cleanly" ;;
    *)           bad "$sh: eval round-trip broken" "$got" ;;
  esac
done
# A reason containing a quote and a shell metacharacter must arrive as DATA.
got=$(bash -c '
  shq() { printf "'"'"'%s'"'"'" "$(printf "%s" "$1" | sed "s/'"'"'/'"'"'\\\\'"'"''"'"'/g")"; }
  eval "reason=$(shq "it'"'"'s; touch '"$TMP"'/PWNED")"; printf "%s" "$reason"')
[ -e "$TMP/PWNED" ] && bad "quoting is injectable — a metacharacter in a value executed" || ok "quoting contains quotes + metacharacters as data"

echo "── 6. --star reports honestly and exits non-zero on any failure (DEFECT 2) ──"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  # A repo that cannot exist: the PUT can only fail, so no outward-facing side effect.
  out=$(bash "$SCRIPT" --star "The-AIOS/zz-not-a-real-repo-$$" 2>/dev/null); rc=$?
  case "$out" in
    *"failed=The-AIOS/zz-not-a-real-repo-$$"*) ok "an impossible PUT is reported as failed, naming the repo" ;;
    *) bad "an impossible PUT was not reported as a failure" "$out" ;;
  esac
  case "$out" in *"summary=0 starred, 1 failed"*) ok "summary counts the failure" ;; *) bad "summary miscounts" "$out" ;; esac
  [ "$rc" -ne 0 ] && ok "exits non-zero so a caller cannot print success over it" || bad "exited 0 on a failed PUT"
else
  ok "gh unauthenticated — --star network assertions skipped (local-only suite)"
fi
out=$(bash "$SCRIPT" --star 2>/dev/null); rc=$?
case "$out" in *"no-repos-given"*) ok "--star with no repos fails loudly" ;; *) bad "--star with no repos was silent" "$out" ;; esac
[ "$rc" -ne 0 ] && ok "…and exits non-zero" || bad "--star with no repos exited 0"

echo "── 7. the repo allowlist never names a repo that must not be asked about ──"
for forbidden in forum site org company-template; do
  if grep -qE "['\"]The-AIOS/$forbidden" "$SCRIPT"; then
    bad "allowlist names The-AIOS/$forbidden"
  else
    ok "never asks about The-AIOS/$forbidden"
  fi
done
grep -q 'CANONICAL_REPO="The-AIOS/aios"' "$SCRIPT" && ok "canonical repo is the always-asked one" || bad "canonical repo constant changed shape"

echo "── 8. CONTROLS — an assertion that cannot fail proves nothing ──"
# Invert defect 1: with the tri-state collapsed back to two, a missing tracker must stop
# reading 'unknown'. If this control does NOT fire, section 2's first assertion is vacuous.
BROKEN="$TMP/broken-star-check"
sed 's/\[ -r "\$CONFIG_TRACKER" \] || return 2/[ -r "$CONFIG_TRACKER" ] || return 1/' "$SCRIPT" > "$BROKEN"
chmod +x "$BROKEN"
if ! grep -q 'return 1$' "$BROKEN"; then
  bad "control could not be constructed — the sed target moved; fix this test"
else
  # Assert on the REASON, not the verdict. With the tri-state collapsed the tracker guard can
  # no longer fire, so the reason must no longer mention it — whatever the next guard decides.
  # Keying on verdict alone made this control environment-dependent: on a runner with an
  # unauthenticated `gh`, the very next guard also returns `unknown`, so the control saw no
  # change and declared the assertion vacuous. It was the CONTROL that was wrong, and it was
  # right to complain.
  out=$(AIOS_TRACKER="$TMP/does-not-exist" bash "$BROKEN" 2>/dev/null)
  case "$out" in
    *"tracker unreadable"*) bad "CONTROL DID NOT FIRE — the tracker guard still fired with the tri-state collapsed, so the assertion is vacuous" ;;
    *)                      ok "control fires: collapsing the tri-state stops the tracker guard from firing (assertion is real)" ;;
  esac
fi
# Invert section 7: a forbidden repo added to a copy must be caught.
printf '\nJUNK="The-AIOS/forum"\n' >> "$BROKEN"
grep -qE "['\"]The-AIOS/forum" "$BROKEN" && ok "control fires: a forbidden repo in the allowlist is detectable" \
  || bad "CONTROL DID NOT FIRE — section 7 cannot see a forbidden repo"

printf '\nRESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
