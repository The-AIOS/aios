#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The `## Agents can handle` mirror must stay BINDABLE.
#
# WHY THIS EXISTS. The mirror is parsed by both surfaces into a dispatch picker,
# and the failure runs two ways with only one of them loud. An over-count is
# self-announcing (a phantom button appears). An UNDER-count is silent: a bullet
# with no bindable target is skipped, the badge reads low or zero while the note
# visibly lists the tasks, and nothing anywhere reports it -- no error, no
# phantom, no missing UI. Measured on a live vault with the surfaces' own
# parser: 0 of 3 bullets bound one day, 1 of 3 the next, 1 of 4 the next, with
# the section header claiming 3 throughout.
#
# The measured cause was NOT prose routing. It was `spawn ingest` and `ingest`
# written in backticks WITHOUT the slash -- tokens that look like command
# references, so nothing about them reads as wrong. CLAUDE.md made this easy in
# two ways that this suite now guards: it claimed a bare `/token` binds (it does
# not -- the backticks are mandatory), and it documented only the AGENT form
# while `/today`'s own rules list ingest as delegatable, leaving a writer with an
# ingest task no template to copy.
#
# SCOPE. Canonical cannot import the surfaces' TypeScript, so BINDS_* below is
# the binding contract as canonical DECLARES it, mirroring
# `aios-glass/src/tasks/agentParse.ts` and `aios-app/src/main/aios.ts`. The
# surfaces are the implementation. If they ever disagree with this contract that
# is a surface bug -- file it per CONTRIBUTING.md § the symptom router (a
# documented form with no effect -> suspect the surface that executes it).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
C=CLAUDE.md; T=plugins/aios/commands/today.md; D=plugins/aios/commands/close-day.md
for f in "$C" "$T" "$D"; do [ -f "$f" ] || { echo "::error::$f missing"; exit 1; }; done

echo "-- 1. the binding contract discriminates (the control) --"
# A line binds iff it is a list item AND carries [[wikilink]] or a BACKTICKED /command.
python3 - <<'PY'
import re, sys
WIKI = re.compile(r'\[\[([^\]|]+?)(?:\|[^\]]+)?\]\]')
CMD  = re.compile(r'`(/[a-z][\w:-]*)`', re.I)
LIST = re.compile(r'^\s*[-*]\s')
def binds(line):
    return bool(LIST.match(line)) and bool(WIKI.search(line) or CMD.search(line))
cases = [
    (True,  '- 🤖 Task _(→ agent: [[deck-builder]])_',            'agent form'),
    (True,  '- 🤖 Ingest _(→ command: `/aios:ingest`)_',          'command form (backticked, slashed)'),
    (False, '- 🤖 Ingest _(→ command: /aios:ingest)_',            'bare /command -- NO backticks'),
    (False, '- 🤖 Ingest _(→ visible `spawn ingest`)_',           'backticked `spawn ingest` -- no slash'),
    (False, '- 🤖 Ingest _(→ `ingest` session, idle)_',           'backticked `ingest` -- no slash'),
    (False, '- 🤖 Reports backfill _(→ me at close-day)_',        'prose routing'),
    (False, 'Say "go with agents" or run `/ghost` here.',         'prose footer mentioning a /command'),
]
bad = 0
for want, line, label in cases:
    got = binds(line)
    print(f"  {'ok  ' if got == want else 'FAIL'} {'binds' if got else 'skips'}: {label}")
    if got != want: bad += 1
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] && ok "contract binds both sanctioned forms and skips all five near-misses" \
  || no "the binding contract does not discriminate" "if it cannot skip \`spawn ingest\` it cannot catch the real bug"

echo "-- 2. CLAUDE.md documents BOTH forms, and no longer claims a bare /token binds --"
grep -qF '_(→ agent: [[name]])_' "$C" && ok "agent form documented" || no "agent form missing"
grep -qF '_(→ command: `/aios:{name}`)_' "$C" && ok "command form documented" \
  || no "no command form in CLAUDE.md" "the most common dispatchable (ingest) is command-routed; a writer with no template improvises and improvisation does not bind"
grep -qE 'a `/token` becomes a command to run' "$C" \
  && no "still claims a bare \`/token\` binds" "it does not -- the backticks are mandatory in both parsers; this is a documented form with no effect" \
  || ok "the false bare-\`/token\` claim is gone"
grep -qiE 'backticked' "$C" && ok "names the backticks as load-bearing" || no "backticks not called out"

echo "-- 3. the under-count direction is stated where the rule lives --"
grep -qiE 'runs BOTH ways|both directions' "$C" && ok "CLAUDE.md states the failure runs both ways" \
  || no "only the phantom direction is justified" "a writer reasoning from a one-directional reason applies the rule in half"
grep -qF 'spawn ingest' "$C" && ok "names the measured cause (\`spawn ingest\`)" \
  || no "the specific substitution is not named" "it caused most of the misses and looks correct"

echo "-- 4. the writer (/today) offers both forms in its TEMPLATE, not just its prose --"
tpl=$(awk '/^## Agents can handle/{f=1} f&&/^\*\*Generation rules/{exit} f&&/^- 🤖 \{task\}/{c++} END{print c+0}' "$T")
[ "${tpl:-0}" -ge 2 ] && ok "$tpl template lines (agent + command)" \
  || no "only ${tpl:-0} template line(s)" "a writer copies the template; one form means the other gets improvised"
grep -qF '/aios:ingest' "$T" && ok "/today names the ingest routing explicitly" || no "ingest routing not named in /today"

echo "-- 5. the backstop (/close-day) checks the SILENT direction too --"
# SCOPED to the reconcile section, and keyed to the operator-facing report line -- a
# file-wide grep for "bindable" passed on a mutation that gutted the check, because the
# word occurs elsewhere. A guard satisfied by a weaker signal than the one it names is
# not measuring the thing it claims to measure.
sec=$(awk '/^### Agents-can-handle reconciliation/{f=1;next} f&&/^#{2,3} /{exit} f' "$D")
printf '%s' "$sec" | grep -qiE 'surfaces cannot see them|no dispatch target' \
  && ok "close-day's reconcile section reports the under-count to the operator" \
  || no "close-day only handles the over-count" "the silent direction needs a check that runs unprompted"
printf '%s' "$sec" | grep -qF 'spawn ingest' \
  && ok "the backstop names the near-miss it must catch" \
  || no "the backstop is abstract" "'bindable' without the failing form is not actionable at 22:00"

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
