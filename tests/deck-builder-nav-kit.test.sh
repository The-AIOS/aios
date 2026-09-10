#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The presenter keys the deck-builder ADVERTISES must be the keys it BINDS.
#
# WHY. The agent tells operators, in prose, which keys a generated deck answers
# to. Those bindings live far away in the toolkit code blocks. Nothing connected
# the two, so the prose and the implementation could drift in either direction:
# a promised key that does nothing (the operator presses it on stage), or a
# working key nobody is told about.
#
# The cost was already paid once, in the other direction: a roadmap row was
# written claiming five kit items were missing from the agent. All five were
# bound. The row was written from a deck build without re-reading the agent, and
# the only way to know was to grep the dispatch by hand -- which is exactly the
# check that should not be manual.
#
# Extraction, never restatement: the advertised set is read from the kit line
# the operator reads, and the bound set from the code the deck actually ships.
# A guard that hardcoded either list would go green while the doc drifted.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
A=agents/aios/communication/deck-builder.md
[ -f "$A" ] || { echo "::error::$A missing"; exit 1; }

echo "-- 1. the advertised kit and the bound keys agree --"
python3 - "$A" <<'PY'
import re, sys
src = open(sys.argv[1]).read()

# ADVERTISED: the operator-facing kit line. Single-letter/?-bolded tokens on it.
m = re.search(r'^.*full nav kit is keyboard-driven.*$', src, re.M)
if not m:
    print("  FAIL could not find the advertised kit line"); sys.exit(1)
advertised = set(re.findall(r'\*\*([A-Za-z?])\*\*', m.group(0)))

# BOUND: every single-character key the toolkit dispatches on, either shape.
bound = set(re.findall(r"""k\s*===\s*'([A-Za-z?])'""", src)) | \
        set(re.findall(r"""e\.key\s*===\s*'([A-Za-z?])'""", src))
bound = {k.upper() if k.isalpha() else k for k in bound}
adv   = {k.upper() if k.isalpha() else k for k in advertised}

print(f"  advertised: {' '.join(sorted(adv))}")
print(f"  bound:      {' '.join(sorted(bound))}")
promised_unbound = sorted(adv - bound)
bound_unadvertised = sorted(bound - adv)
rc = 0
if promised_unbound:
    print(f"  FAIL advertised but NOT bound: {' '.join(promised_unbound)}")
    print("     an operator presses it on stage and nothing happens"); rc = 1
else:
    print("  ok   every advertised key is bound")
if bound_unadvertised:
    print(f"  FAIL bound but NOT advertised: {' '.join(bound_unadvertised)}")
    print("     a working capability nobody is told about is a capability nobody uses"); rc = 1
else:
    print("  ok   every bound key is advertised")
sys.exit(rc)
PY
[ $? -eq 0 ] && ok "advertised ↔ bound parity holds" || no "the kit prose and the dispatch disagree" "extracted from both sides, so one of them drifted"

echo "-- 2. the runtime click-nav toggle exists and is reachable --"
grep -qE "k==='c'\|\|k==='C'" "$A" && ok "C is bound" || no "C is not bound" "click-nav would stay build-time only"
grep -qF 'function clickNav()' "$A" && ok "one resolver both the click handler and C read" \
  || no "no single clickNav() resolver" "two readers of the same setting drift into disagreeing"
# the click path must go THROUGH the resolver, or the toggle silently does nothing
grep -qF 'var CN = clickNav();' "$A" && ok "the click handler resolves per click (so C takes effect live)" \
  || no "the click handler does not call clickNav()" "C would flip a variable nothing reads — a toggle that appears to work and does not"

echo "-- 3. a click meant for something interactive never navigates --"
guard=$(grep -oE "closest\('button,input[^']*'\)" "$A" | head -1)
[ -n "$guard" ] && ok "interactive guard present: ${guard:0:58}…" \
  || no "clicks are only guarded against links" "a form control, embedded player or iframe demo would advance the slide the first time anyone used it"
for el in button input iframe; do
  printf '%s' "$guard" | grep -qF "$el" && ok "guards $el" || no "does not guard $el"
done

echo "-- 4. the frontmatter says the setting is a build-time DEFAULT --"
grep -qiE 'BUILD-TIME default only: C toggles' "$A" && ok "frontmatter points at the runtime toggle" \
  || no "frontmatter reads as the final word" "an operator would not know C exists"

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
