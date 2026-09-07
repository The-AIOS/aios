#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# resolve-tier must agree with the spawn wrapper, rung for rung — and the
# installer must normalize every hook .gitattributes claims to protect.
#
# WHY BOTH LIVE HERE. They are the same defect wearing two faces: a fact that
# exists in one file and is needed in another, with nothing checking that the
# copies agree. The rung→model table lived only inside the wrapper function, so
# a surface launching `claude` directly lost tiering silently (measured
# 2026-09-07: "tier":"fast" produced `claude --name <n>` with no --model, and
# the worker ran frontier). The eol/exec normalization named two paths while
# .gitattributes declared three globs, so aios-snapshot and aios-star-check
# stayed CRLF-exposed on Windows — the one platform the code exists for.
#
# The parity half is deliberately compared against
# hooks/claude-identity/install-wrappers.sh, NOT against the operator's rc file:
# the installer is the repo-side source of that function, so this runs in CI
# where no rc file exists. Writing the expectations out by hand instead would
# make this suite a third copy of the very table it exists to police — the
# assertion is *agreement between the two shipped copies*, never a literal
# restatement of what they should say.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
R=hooks/resolve-tier
W=hooks/claude-identity/install-wrappers.sh
[ -x "$R" ] || { echo "::error::$R missing or not executable"; exit 1; }
[ -f "$W" ] || { echo "::error::$W missing"; exit 1; }

echo "-- 1. resolve-tier agrees with the wrapper, rung for rung --"
# Pull the wrapper's table out of the installer: lines like
#   frontier)    spawn_model='claude-fable-5-1' ;;
WT=$(grep -oE "^[[:space:]]*[a-z]+\)[[:space:]]*spawn_model='[^']*'" "$W" \
     | sed -E "s/^[[:space:]]*([a-z]+)\)[[:space:]]*spawn_model='([^']*)'.*/\1 \2/")
[ -n "$WT" ] || no "could not extract the wrapper's table from $W" "the grep shape changed — fix this test, do not delete it"
n=0
while read -r rung model; do
  [ -n "$rung" ] || continue
  n=$((n+1))
  got=$("$R" "$rung" 2>/dev/null); rc=$?
  if [ "$rc" != "0" ]; then no "resolve-tier rejects '$rung', which the wrapper accepts (exit $rc)" "a rung the wrapper honours must resolve here too"
  elif [ "$got" = "$model" ]; then ok "$rung → $model (both agree)"
  else no "$rung: wrapper says '$model', resolve-tier says '$got'" "one table, two copies, and they have drifted — the whole point of this file"
  fi
done <<< "$WT"
[ "$n" -ge 4 ] && ok "compared $n rungs (the ladder has at least 4)" || no "only $n rungs compared" "the extraction is matching too little to be a real check"

echo "-- 2. judgment resolves EMPTY at exit 0, and that is a real answer --"
got=$("$R" judgment 2>/dev/null); rc=$?
[ "$rc" = "0" ] && [ -z "$got" ] && ok "judgment → empty, exit 0 (inherit the default)" \
  || no "judgment returned '$got' exit $rc" "it must mean 'pass no --model', which is empty-and-zero — not an error"

echo "-- 3. an unknown rung FAILS loudly, never silently defaults --"
got=$("$R" definitely-not-a-rung 2>/dev/null); rc=$?
[ "$rc" != "0" ] && ok "unknown rung → exit $rc" || no "unknown rung exited 0 with '$got'" "a typo must not resolve to the frontier default — that is the silent-drop bug this replaces"
err=$("$R" definitely-not-a-rung 2>&1 >/dev/null)
case "$err" in *frontier*|*rungs*) ok "the error names the valid rungs" ;; *) no "the error does not list the rungs" ;; esac

echo "-- 4. every rung .gitattributes/CLAUDE.md advertise is resolvable --"
# CLAUDE.md advertises --tier frontier|judgment|scale|fast. All four must work.
for rung in frontier judgment scale fast; do
  "$R" "$rung" >/dev/null 2>&1 && ok "advertised rung '$rung' resolves" || no "advertised rung '$rung' does not resolve" "CLAUDE.md names it, so it must work"
done

echo "-- 5. install-git-hooks normalizes every hook .gitattributes protects --"
# .gitattributes is Tier-0 and never reaches an operator, so the installer is the only
# surface that can deliver the guarantee. Whatever the one declares, the other must cover.
#
# The patterns are EXTRACTED FROM THE INSTALLER, never restated here. An earlier version of
# this check carried its own `git/*|aios-*|*.sh` case list, so reverting the installer to a
# narrow name list left it green — it was testing the test's belief about the installer
# rather than the installer. That is the defect class this whole suite exists for, found by
# mutating it.
GLOBS=$(grep -oE '^for _h in .*; do' hooks/install-git-hooks.sh \
        | sed -E 's/^for _h in //; s/; do$//' \
        | tr ' ' '\n' | sed -E 's/"//g; s|\$HOOKS_DIR|hooks|g' | grep -v '^$')
[ -n "$GLOBS" ] && ok "extracted the installer's own normalization globs" \
  || no "could not extract globs from install-git-hooks.sh" "the loop shape changed — fix this extraction, never hardcode the patterns"

GA=$(grep -oE '^hooks/[A-Za-z0-9_*./-]+' .gitattributes 2>/dev/null | sort -u)
[ -n "$GA" ] || no ".gitattributes declares no hooks/ paths" "expected eol rules for hooks/"
miss=0; checked=0
for pat in $GA; do
  for f in $pat; do
    [ -f "$f" ] || continue
    case "$f" in *.md|*.ps1) continue ;; esac
    checked=$((checked+1)); hit=0
    for g in $GLOBS; do
      # shellcheck disable=SC2254
      case "$f" in $g) hit=1; break ;; esac
    done
    [ "$hit" = "1" ] || { miss=$((miss+1)); printf '     UNCOVERED %s\n' "$f"; }
  done
done
[ "$checked" -ge 4 ] && ok "checked $checked protected hook file(s)" || no "only $checked file(s) checked" "the .gitattributes extraction is matching too little to be a real check"
[ "$miss" = "0" ] && ok "every .gitattributes-protected hook is inside the installer's globs" \
  || no "$miss protected hook(s) outside the installer's normalization" "widen the globs in install-git-hooks.sh/.ps1 — .gitattributes cannot reach an operator"

echo "-- 6. the two installers cover the same three sets (no platform left behind) --"
# Each side is matched with ITS OWN idiom, on code lines only. Two earlier versions of this
# check were wrong in opposite directions and both are instructive: matching raw file text
# let a comment mentioning aios- satisfy it (a guard firing on its own prose), and then
# matching one shared literal across both files reported a false gap, because PowerShell
# writes `Join-Path $HooksDir 'git'` where bash writes `$HOOKS_DIR/git/`. A cross-language
# substring compare measures textual similarity, not coverage.
strip_sh(){  sed -E 's/#.*//'  hooks/install-git-hooks.sh; }
strip_ps(){  sed -E 's/#.*//'  hooks/install-git-hooks.ps1; }
chk(){ # label · bash regex · powershell regex
  a=$(strip_sh | grep -cE "$2"); b=$(strip_ps | grep -cE "$3")
  if [ "${a:-0}" -gt 0 ] && [ "${b:-0}" -gt 0 ]; then ok "both installers cover $1"
  else no "$1 — bash=$a powershell=$b" "Windows is the platform this exists for; the .ps1 may not lag the .sh"; fi
}
chk "the git/ hook dir"   'HOOKS_DIR/git/'         "Join-Path \\\$HooksDir 'git'"
chk "the aios-* hooks"    'HOOKS_DIR"?/aios-\*'   "Join-Path \\\$HooksDir 'aios-\*'"
chk "the *.sh hooks"      'HOOKS_DIR"?/\*\.sh'   "Join-Path \\\$HooksDir '\*\.sh'"

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
