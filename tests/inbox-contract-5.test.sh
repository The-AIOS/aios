#!/usr/bin/env bash
# tests/inbox-contract-5.test.sh
#
# Contract 5 adds the `open` verb: a session asks a surface to show a file in its own viewer. The
# decision is security-sensitive (any session can ask, and a session may have read someone else's
# text), and it has to come out the same in the App and in Glass. So it is written once, as an
# ordered list of checks in inbox-contract-5.md, and once more as a fixture both surfaces run.
#
# This suite holds the two together: every case in the fixture passes a reference implementation
# of the spec's checks (tests/fixtures/inbox-contract-5-ref.py), the spec and the fixture name the same refusal codes, and the numbers the
# spec states are the ones the fixture uses. A control proves the reference can fail.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D="$ROOT/skills/aios/orchestration-ladder"
PYBIN="${PYBIN:-python3}"
PASS=0; FAIL=0
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
no(){ echo "  ✗ $1"; [ -n "${2:-}" ] && echo "      $2"; FAIL=$((FAIL+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

REF="$ROOT/tests/fixtures/inbox-contract-5-ref.py"

F="$D/inbox-contract-5.conformance.json"; S="$D/inbox-contract-5.md"
[ -f "$F" ] && [ -f "$S" ] && [ -f "$REF" ] || { no "the contract 5 spec or its fixture is missing"; echo "── RESULT: $PASS passed, $FAIL failed ──"; exit 1; }

echo "── every case passes the reference implementation of the spec ──"
out=$($PYBIN "$REF" "$F" 2>&1)
case "$(printf '%s\n' "$out" | grep '^CASES')" in "CASES ok "*) ok "$(printf '%s\n' "$out" | grep '^CASES' | sed 's/CASES ok //') cases agree with the reference" ;; *) no "fixture and reference disagree" "$(printf '%s\n' "$out" | head -8)" ;; esac
n=$(printf '%s\n' "$out" | grep '^OPENS' | cut -d' ' -f2)
[ "${n:-0}" -ge 15 ] && ok "$n cases open a file (the fixture is not all refusals)" || no "only '${n:-0}' cases open a file"

echo "── the spec and the fixture name the same refusals ──"
FIX=$(printf '%s\n' "$out" | grep '^WHYS' | cut -d' ' -f2 | tr ',' '\n' | sort -u)
SPEC=$(grep -oE '\[`[a-z-]+`\]' "$S" | tr -d '[]`' | sort -u)
[ -n "$SPEC" ] && [ "$FIX" = "$SPEC" ] && ok "same $(printf '%s\n' "$SPEC" | grep -c .) codes: $(printf '%s ' $SPEC)" \
  || no "codes differ" "only in the spec: $(comm -23 <(printf '%s\n' "$SPEC") <(printf '%s\n' "$FIX") | tr '\n' ' ') · only in the fixture: $(comm -13 <(printf '%s\n' "$SPEC") <(printf '%s\n' "$FIX") | tr '\n' ' ')"

echo "── the numbers the spec states are the ones the fixture uses ──"
k(){ $PYBIN -c "import json,sys; print(json.load(open(sys.argv[1]))['constants'][sys.argv[2]])" "$F" "$1"; }
[ "$(k max_age_ms)" = "60000" ] && grep -q 'more than \*\*60 seconds\*\* ago' "$S" && ok "60 seconds, in both" || no "the age bound differs between the spec and the fixture"
[ "$(k rate_max)" = "5" ] && [ "$(k flood_max)" = "20" ] && [ "$(k rate_window_ms)" = "60000" ] \
  && grep -q '\*\*20\*\* or more' "$S" && grep -q '\*\*5\*\* or more' "$S" && ok "5 a session and 20 in all, a minute, in both" || no "the rates differ between the spec and the fixture"
[ "$(k max_line)" = "10000000" ] && grep -q '1 to 10,000,000' "$S" && ok "the line bound, in both" || no "the line bound differs"
[ "$(k max_name)" = "64" ] && grep -q 'longer than 64' "$S" && ok "the name bound, in both" || no "the name bound differs"

echo "── the spec says it is in force, and the declared contract agrees ──"
# The spec and the declaration move together: an "in force" spec beside a declaration of 4 would tell a
# session to send a verb the docs say no surface takes, and the reverse would hide a verb that works.
IN=0; grep -q 'Status: in force' "$S" && IN=1
DECL5=0; grep -qE '"current" *: *5' "$D/inbox-contract.json" 2>/dev/null && DECL5=1
[ "$IN" = 1 ] && [ "$DECL5" = 1 ] && ok "the spec is in force and inbox-contract.json declares 5" \
  || no "the spec's status and the declared contract disagree (spec in force: $IN, declared 5: $DECL5)" \
        "they change in one commit, after both surfaces stamp contract 5"

echo "── CONTROL — a wrong expectation is caught ──"
$PYBIN - "$F" "$T/bad.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for c in d["cases"]:
    if c["case"] == "a file with a second hard link":
        c["expect"] = {"do": "open", "path": "/home/op/aios/vault/meeting.md", "mode": "auto"}
json.dump(d, open(sys.argv[2], "w"))
PY
case "$($PYBIN "$REF" "$T/bad.json" | grep '^CASES')" in "CASES ok "*) no "control: a fixture that opens a hard-linked file still passed" ;; *) ok "control: a fixture that opens a hard-linked file is caught" ;; esac

echo "── RESULT: $PASS passed, $FAIL failed ──"
[ "$FAIL" = 0 ] && [ "$PASS" -ge 9 ]
