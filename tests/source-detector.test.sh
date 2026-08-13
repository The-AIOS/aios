#!/usr/bin/env bash
# Regression suite for the USER.md source detector (hooks/pipeline-executor.py).
#
# History, because it explains the shape of these tests:
#   · Original bug — a whole-document substring test (`if "Slack" in content`). The better
#     an operator documented a source they did NOT use, the more certain the parser became
#     that it was live.
#   · 2026-08-11 fix — line-scoped scan with negation markers. Correct, but incomplete.
#   · The gap this file locks — the scan walked EVERY line, and the template the framework
#     ships into USER.md names the sources in its own explanatory blockquotes. Those lines
#     carry no negation marker, so the first one won and the operator's explicit
#     "Slack — no se usa" never decided. The framework's documentation outvoted the operator.
#
# TEST 1 IS THE CANARY: a USER.md containing ONLY the shipped template must enable NOTHING.
# It fails against the pre-fix code, which is what makes the rest of this suite meaningful.

set -u
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
have(){ [ "$1" = "$2" ] && ok "$3" || { no "$3"; printf '       expected %s, got %s\n' "$2" "$1"; }; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXEC="$ROOT/hooks/pipeline-executor.py"
[ -f "$EXEC" ] || { echo "cannot find hooks/pipeline-executor.py"; exit 1; }

printf 'USER.md source detector\n'

# Load the two functions straight out of the executor, so the test exercises the SHIPPED
# code rather than a copy that can drift away from it.
probe(){ # $1 = USER.md content, $2 = keyword  →  prints ON | off
python3 - "$EXEC" "$1" "$2" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
ns = {}
exec(re.search(r'_NEGATION_MARKERS = \((?:.|\n)*?\)\n', src).group(0), ns)
import re as _re
ns['re'] = _re
m = re.search(r'def _is_operator_line(?:.|\n)*?\n    return True\n', src)
if m: exec(m.group(0), ns)
else: ns['_is_operator_line'] = lambda line: True     # pre-fix code has no such guard
m2 = re.search(r'def _operator_lines(?:.|\n)*?\n            yield line\n', src)
if m2: exec(m2.group(0), ns)
else: ns['_operator_lines'] = lambda c: (l for l in c.split("\n") if ns['_is_operator_line'](l))
exec(re.search(r'def _mentions_enabled(?:.|\n)*?\n    return False\n', src).group(0), ns)
print("ON" if ns['_mentions_enabled'](sys.argv[2], sys.argv[3]) else "off")
PY
}

# ---------------------------------------------------------------------------
# TEST 1 — THE CANARY. Template-only USER.md enables nothing.
# ---------------------------------------------------------------------------
TEMPLATE='## Command personalizations

### /today

> Where Claude pulls data for daily plans. With none configured it still works — no calendar, tasks, or Slack.

**Timezone:** `America/Mexico_City`
> Your timezone. Used by the pipeline executor for calendar queries and Slack recaps.
'
for kw in Slack calendar tasks; do
  have "$(probe "$TEMPLATE" "$kw")" "off" "1. canary: template-only USER.md leaves '$kw' off"
done

# ---------------------------------------------------------------------------
# TEST 2 — an operator line still turns a source ON.
# ---------------------------------------------------------------------------
ON_DOC="$TEMPLATE
- Slack — DM digest every morning
"
have "$(probe "$ON_DOC" "Slack")" "ON" "2. an operator's own line still enables the source"

# ---------------------------------------------------------------------------
# TEST 3 — the reported bug: an explicit negation must WIN over template prose.
# ---------------------------------------------------------------------------
OFF_DOC="$TEMPLATE
- Slack — no se usa (decisión del operador)
"
have "$(probe "$OFF_DOC" "Slack")" "off" "3. operator's negation beats the template's prose (the reported bug)"

# ---------------------------------------------------------------------------
# TEST 4 — English negation, same outcome (USER.md is bilingual by design).
# ---------------------------------------------------------------------------
EN_DOC="$TEMPLATE
- Slack — not used, on purpose
"
have "$(probe "$EN_DOC" "Slack")" "off" "4. English negation also wins"

# ---------------------------------------------------------------------------
# TEST 5 — headings and HTML comments do not vote either.
# ---------------------------------------------------------------------------
HEAD_DOC='### Slack recap settings
<!-- Slack digest wiring lives here -->
'
have "$(probe "$HEAD_DOC" "Slack")" "off" "5. a heading or HTML comment naming a source does not enable it"

# ---------------------------------------------------------------------------
# TEST 6 — the *EXAMPLE ONLY* convention does not vote.
# ---------------------------------------------------------------------------
EX_DOC='*EXAMPLE ONLY — Slack digest at 9am*
'
have "$(probe "$EX_DOC" "Slack")" "off" "6. a fully-italic / EXAMPLE ONLY line does not enable it"

# ---------------------------------------------------------------------------
# TEST 7 — mixed: one negated operator line and one enabling operator line → ON.
#          (An operator who lists it as used anywhere wins; we must not over-correct.)
# ---------------------------------------------------------------------------
MIX_DOC="- Slack — no se usa
- Slack — actually re-enabled for the ops channel
"
have "$(probe "$MIX_DOC" "Slack")" "ON" "7. a later enabling operator line still counts (no over-correction)"

# ---------------------------------------------------------------------------
# TEST 8 — the shipped USER.md in this repo must enable nothing on its own.
#          This is the canary aimed at the real artifact, not a fixture.
# ---------------------------------------------------------------------------
if [ -f "$ROOT/USER.md" ]; then
  REAL="$(cat "$ROOT/USER.md")"
  for kw in Slack calendar; do
    have "$(probe "$REAL" "$kw")" "off" "8. canonical's own USER.md leaves '$kw' off"
  done
else
  ok "8. skipped — no USER.md at repo root"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
