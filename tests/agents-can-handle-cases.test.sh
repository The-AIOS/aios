#!/usr/bin/env bash
# tests/agents-can-handle-cases.test.sh
#
# The daily note's `## Agents can handle` section has one writer (`/today`) and, outside this
# repo, two readers (the App and Glass). The readers agreed with each other and disagreed with
# the writer: the template line `/today` is told to write never matched its own canonical task
# checked in another section, and a project wikilink in the task text was dispatched as the agent.
# No test tied the three together, so each side was green on its own.
#
# tests/fixtures/agents-can-handle.cases.json is that tie: input lines and what a reader must
# bind from them. This suite checks the file against this repo's half:
#   - the reference reading (tests/fixtures/agents-can-handle-ref.py) passes every case;
#   - the cases can tell the old rule from the new one (the control);
#   - the template lines in today.md and CLAUDE.md are in the file VERBATIM, and every filled-in
#     case still has the shape of a template line, so a template edit cannot leave the file behind;
#   - the file's hash is pinned. The App carries a byte-identical copy pinned to the same hash
#     (Glass will too): a change here must move those copies. The pin is a stopgap until the
#     cases file ships in the surfaces' shared package.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PYBIN=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PYBIN="$_cand"; break; fi
done
if [ -z "$PYBIN" ]; then
  echo "SKIP: no working Python found (tried python3, python, py -3)" >&2
  exit 0
fi
export PYTHONIOENCODING=utf-8 PYTHONUTF8=1

# Moves ONLY together with the copies: aios-app src/test/fixtures/agents-can-handle.cases.json
# and its pin in src/test/agentCases.test.ts.
PIN="eac737fe9d01bc1f696afa496dc4e049e704cc506a51c71f1590d44e7d6fe343"

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
F=tests/fixtures/agents-can-handle.cases.json
R=tests/fixtures/agents-can-handle-ref.py
T=plugins/aios/commands/today.md
C=CLAUDE.md
for f in "$F" "$R" "$T" "$C"; do [ -f "$f" ] || { echo "::error::$f missing"; exit 1; }; done

echo "-- 1. the reference reading passes every case --"
out=$($PYBIN "$R" "$F" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "$(printf '%s' "$out" | tail -1)" || no "the reference misses cases" "$out"

echo "-- 2. the control: the old rule (first wikilink on the line is the agent) fails --"
out=$($PYBIN "$R" --first-wikilink "$F" 2>&1); rc=$?
[ $rc -ne 0 ] && ok "the cases catch it: $(printf '%s' "$out" | tail -1)" \
  || no "the cases pass under the old rule" "they would not have caught a project note dispatched as an agent"
printf '%s' "$out" | grep -qF 'MISS a project wikilink before the agent' \
  && ok "and name the project-wikilink case" || no "the project-wikilink case did not fail under the old rule"

echo "-- 3. the templates are in the file, and the file follows the templates --"
# The checker goes to a file: bash 3.2 cannot parse every quoted heredoc inside $( ).
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/templates.py" <<'PY'
import json, re, sys
fx, today, claude = sys.argv[1:4]
cases = json.load(open(fx, encoding="utf-8"))["cases"]
LINE = re.compile(r"- \U0001F916 \{task\} _\(→ (?:agent|command): .*?\)_")
bad = 0
def say(good, msg):
    global bad
    print(("ok   " if good else "FAIL ") + msg)
    bad += 0 if good else 1
shape = [c.get("case") for c in cases if not {"case", "note", "expect"} <= set(c)
         or c["expect"].get("count") != len(c["expect"].get("suggestions", [None]))]
say(not shape, "every case has case, note, expect, and a count equal to its suggestions" + (": %s" % shape if shape else ""))
names = [c["case"] for c in cases]
say(len(names) == len(set(names)), "case names are unique")
tpl_today = None
for src, path in (("plugins/aios/commands/today.md", today), ("CLAUDE.md", claude)):
    text = open(path, encoding="utf-8").read()
    if path == today:
        text = text.split("## Agents can handle", 1)[1].split("**Generation rules", 1)[0]
    found = sorted(set(LINE.findall(text)))
    if path == today:
        tpl_today = found
    say(len(found) == 2, "%s states both forms (%d found)" % (src, len(found)))
    for line in found:
        held = [c for c in cases if c.get("source") == src and line in c["note"]]
        say(bool(held), "%s line is a case, verbatim: %s" % (src, line))
filled = [c for c in cases if "template" in c]
say(len(filled) >= 2, "%d cases are a template line filled in" % len(filled))
for c in filled:
    t = c["template"]
    known = t in (tpl_today or [])
    rx = re.compile("^" + re.sub(r"\\\{[^}]*\\\}|agent\\-name", ".+", re.escape(t)) + "$")
    fits = any(rx.match(l) for l in c["note"])
    say(known and fits, "follows the today.md template: %s" % c["case"])
sys.exit(1 if bad else 0)
PY
out=$($PYBIN "$TMP/templates.py" "$F" "$T" "$C" 2>&1); rc=$?
while IFS= read -r line; do
  case "$line" in
    "ok   "*) ok "${line#ok   }" ;;
    *) no "${line#FAIL }" "a template changed without the cases file, or the reverse" ;;
  esac
done <<< "$out"
[ $rc -eq 0 ] || [ "$FAIL" -gt 0 ] || no "the template check did not run" "$out"

echo "-- 4. the file is the one the surfaces copied --"
got=$($PYBIN -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read().replace(b"\r\n",b"\n")).hexdigest())' "$F")
[ "$got" = "$PIN" ] && ok "sha256 matches the pin" \
  || no "the cases file changed (sha256 $got)" "update PIN here, then copy the file to aios-app src/test/fixtures/ and move the pin in its src/test/agentCases.test.ts in the same change"

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
