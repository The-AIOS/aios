#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The documented "did the registration land?" check must read BOTH scopes
#
# `claude mcp add` writes ~/.claude.json and prints success even when a
# sandboxed call wrote nothing, so /aios:mcps-setup tells sessions to verify by
# reading the file back. The first version of that read-back looked only at the
# top-level `mcpServers` -- and `claude mcp add` DEFAULTS to local (per-directory)
# scope, so a normal registration lands under projects["<cwd>"].mcpServers.
#
# Measured on a live vault: the connector was running, all nine services
# present, and the documented check printed False. A session acting on that
# would re-register something that already worked -- and the repo's own docs
# warn that two registrations drift independently, which is how one grew Gmail
# and the other did not. So the wrong check does not merely fail to confirm; it
# actively pushes toward the failure it was meant to detect.
#
# This suite EXTRACTS the snippet from the command file and runs it against
# fixtures. It does not restate the logic: a guard that reimplements what it
# checks is only testing its own copy, and would have passed against the
# broken original.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

DOC="plugins/aios/commands/mcps-setup.md"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[ -f "$DOC" ] || { printf '  FAIL  %s missing\n' "$DOC"; exit 1; }

echo "── 1. the snippet is extractable from the doc ──"
# Pull the python heredoc body that follows the read-back instruction.
python3 - "$DOC" "$TMP/snippet.py" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
# the fenced bash block containing a `python3 - <<'PY'` heredoc
m = re.search(r"```bash\n\s*python3 - <<'PY'[^\n]*\n(.*?)\n\s*PY\n\s*```", text, re.S)
if not m:
    sys.exit("could not find the read-back snippet in the doc")
body = "\n".join(l[5:] if l.startswith("     ") else l for l in m.group(1).split("\n"))
open(sys.argv[2], "w").write(body)
PY
if [ -s "$TMP/snippet.py" ]; then
  ok "extracted $(grep -c . "$TMP/snippet.py") lines of the documented check"
else
  no "could not extract the snippet — this suite cannot test what is shipped"
  printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"; exit 1
fi

# Run the extracted snippet against a fixture HOME.
runsnip(){ HOME="$1" python3 "$TMP/snippet.py" "${2:-google-workspace}" 2>&1; }

mkfix(){ # $1 = dir · stdin = the .claude.json content
  mkdir -p "$1"; cat > "$1/.claude.json"
}

echo "── 2. a PROJECT-scoped registration is found (the default scope) ──"
mkfix "$TMP/proj" <<'J'
{"mcpServers":{"railway":{}},
 "projects":{"/Users/someone/aios":{"mcpServers":{"google-workspace":{"args":["--permissions","drive:full"]}}}}}
J
OUT="$(runsnip "$TMP/proj")"
if printf '%s' "$OUT" | grep -q 'NOT REGISTERED'; then
  no "project-scoped registration reported as NOT REGISTERED" \
     "this is the live-vault defect: the connector works and the check says it does not
        got: $OUT"
elif printf '%s' "$OUT" | grep -q '/Users/someone/aios'; then
  ok "found it, and named the project it belongs to"
else
  no "unexpected output for a project-scoped registration" "$OUT"
fi

echo "── 3. a USER-scoped registration is still found ──"
mkfix "$TMP/user" <<'J'
{"mcpServers":{"google-workspace":{"args":["--permissions","drive:full"]}},"projects":{}}
J
OUT="$(runsnip "$TMP/user")"
printf '%s' "$OUT" | grep -q 'user' \
  && ok "user scope reported" || no "user-scoped registration missed" "$OUT"

echo "── 4. genuinely absent reads as absent ──"
mkfix "$TMP/none" <<'J'
{"mcpServers":{"railway":{}},"projects":{"/Users/someone/aios":{"mcpServers":{"slack":{}}}}}
J
OUT="$(runsnip "$TMP/none")"
printf '%s' "$OUT" | grep -q 'NOT REGISTERED' \
  && ok "absent → NOT REGISTERED (the check can still say no)" \
  || no "an absent server was reported as present — the check cannot fail" "$OUT"

echo "── 5. BOTH scopes at once is surfaced, not hidden ──"
# Two registrations drift independently; the docs already record one growing
# Gmail while the other did not. Reporting only the first hides that.
mkfix "$TMP/both" <<'J'
{"mcpServers":{"google-workspace":{}},
 "projects":{"/Users/someone/aios":{"mcpServers":{"google-workspace":{}}}}}
J
OUT="$(runsnip "$TMP/both")"
{ printf '%s' "$OUT" | grep -q 'user' && printf '%s' "$OUT" | grep -q '/Users/someone/aios'; } \
  && ok "both registrations named in one answer" \
  || no "a duplicate registration was not fully reported" "$OUT
        two registrations drift independently; the operator must be told there are two"

echo "── 6. CONTROL — the ORIGINAL broken check must fail this suite ──"
# Without this, a future simplification back to top-level-only would pass
# whatever the suite happens to assert. Replay the exact shipped one-liner.
cat > "$TMP/broken.py" <<'PY'
import json, os, sys
print('google-workspace' in json.load(open(os.path.expanduser('~/.claude.json'))).get('mcpServers', {}))
PY
OUT="$(HOME="$TMP/proj" python3 "$TMP/broken.py" 2>&1)"
if [ "$OUT" = "False" ]; then
  ok "control: the original check answers False on a working project-scoped install"
else
  no "control: the original broken check did NOT reproduce" \
     "got '$OUT' — if this stops being wrong, re-derive why this suite exists"
fi

echo "── 7. the doc states WHY both scopes matter ──"
# A correct snippet with no explanation gets "simplified" back by the next reader.
grep -qiE 'defaults to \*?local\*?|per-directory' "$DOC" \
  && ok "the doc names local/per-directory as the default scope" \
  || no "the doc does not say why the top level is the wrong place to look" \
        "without the reason, the next reader shortens it back"
grep -qiE 'NOT REGISTERED on a perfectly working|reports .*on a perfectly working install' "$DOC" \
  && ok "the doc records the observed failure" \
  || no "the doc does not record that this was measured on a live install"

printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
