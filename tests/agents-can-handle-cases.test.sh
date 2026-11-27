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
#   - the reading both surfaces had before (kept in the reference as parse_old) fails the cases,
#     on both defects (the control);
#   - the template lines of today.md and CLAUDE.md are listed in the file VERBATIM, each one is
#     filled in by at least one case, and every case that names a template still has that
#     line's shape, so a template edit cannot leave the file behind;
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
PIN="7d7f8d7dd5bd307cbb850dfa717260bfc511ea43931a66aadaf0e23bd53148d9"

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

echo "-- 2. the control: the reading the surfaces had before fails --"
out=$($PYBIN "$R" --old "$F" 2>&1); rc=$?
[ $rc -ne 0 ] && ok "the cases catch it: $(printf '%s' "$out" | tail -1)" \
  || no "the cases pass under the old reading" "they would not have caught either defect"
printf '%s' "$out" | grep -qF 'MISS a project wikilink before the agent' \
  && ok "a project note dispatched as the agent is caught" || no "the project-wikilink case passes under the old reading"
printf '%s' "$out" | grep -qF 'MISS the template line, with its canonical task checked in another section' \
  && ok "a template line that outlives its checked task is caught" || no "the checked-twin case passes under the old reading"

echo "-- 3. the templates are in the file, and the file follows the templates --"
# The checker goes to a file: bash 3.2 cannot parse every quoted heredoc inside $( ).
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/templates.py" <<'PY'
import json, re, sys
fx, today, claude = sys.argv[1:4]
doc = json.load(open(fx, encoding="utf-8"))
cases, listed = doc["cases"], doc["templates"]
# CLAUDE.md quotes each form inside a code span: take it up to the backtick that closes the span,
# so text added after the `)_` is part of what is compared.
LINE = re.compile(r"- \U0001F916 \{task\} _\(\u2192 (?:agent: [^`]*|command: `[^`]*`[^`]*)(?=`)")
bad = 0
def say(good, msg):
    global bad
    print(("ok   " if good else "FAIL ") + msg)
    bad += 0 if good else 1
def shape(t):
    """A template line as a pattern: every {placeholder} and every [[name]] is a slot."""
    rx = re.sub(r"\\\[\\\[.*?\\\]\\\]", r"\\[\\[.+\\]\\]", re.escape(t))
    return "^" + re.sub(r"\\\{[^}]*\\\}", ".+", rx) + "$"
broken = [c.get("case") for c in cases if not {"case", "note", "expect"} <= set(c)
          or c["expect"].get("count") != len(c["expect"].get("suggestions", [None]))]
say(not broken, "every case has case, note, expect, and a count equal to its suggestions" + (": %s" % broken if broken else ""))
# Undecided, so the cases must not take a side: no note line may carry a strike without the done mark.
bare = [c["case"] for c in cases for l in c["note"] if re.search(r"~~[^~]+~~", l) and "\u2705" not in l]
say(bool(doc.get("undecided")) and not bare, "no case rules on a strike with no done mark (undecided)" + (": %s" % bare if bare else ""))
names = [c["case"] for c in cases]
say(len(names) == len(set(names)), "case names are unique")
for src, path in (("plugins/aios/commands/today.md", today), ("CLAUDE.md", claude)):
    text = open(path, encoding="utf-8").read()
    if path == today:
        # the template block: from the section HEADING (the name also occurs in prose) to its rules
        text = text.split("\n## Agents can handle\n", 1)[1].split("**Generation rules", 1)[0]
        # whole lines there: anything after the closing `)_` would be read as part of the route
        found = sorted(set(l for l in text.split("\n") if l.startswith("- \U0001F916 {task}")))
    else:
        found = sorted(set(LINE.findall(text)))
    say(len(found) == 2, "%s states both forms (%d found)" % (src, len(found)))
    say(found == sorted(listed.get(src, [])), "the cases file lists %s's template lines verbatim" % src)
ours = listed["plugins/aios/commands/today.md"]
say(sorted(shape(t) for t in ours) == sorted(shape(t) for t in listed["CLAUDE.md"]),
    "today.md and CLAUDE.md teach the same two shapes")
for t in ours:
    held = [c for c in cases if c.get("template") == t]
    say(bool(held), "%d cases fill in: %s" % (len(held), t))
for c in cases:
    if "template" not in c:
        continue
    t = c["template"]
    say(t in ours and any(re.match(shape(t), l) for l in c["note"]), "has its template's shape: %s" % c["case"])
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
