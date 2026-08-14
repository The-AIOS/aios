#!/usr/bin/env bash
# tests/workflow-expressions.test.sh
#
# Asserts every doubled-brace expression in .github/workflows/*.yml names a real GitHub
# Actions context or function.
#
# WHY THIS CANNOT BE A CI CHECK, WHICH IS THE ENTIRE POINT
# -------------------------------------------------------
# GitHub Actions evaluates doubled-brace expressions as a layer ABOVE YAML, substituting them
# into the raw `run:` string before any shell sees it. An expression whose contents are not a
# valid context therefore makes the WORKFLOW FILE INVALID — and an invalid workflow does not
# fail a job, it fails to produce any jobs at all:
#
#     conclusion: failure   ·   job count: 0   ·   check-runs: 0   ·   combined state: pending
#
# So the usual guard is unavailable by construction. A check inside the workflow cannot catch a
# defect that stops the workflow from running, and `gh pr checks` reports "no checks reported"
# — which a polling loop can easily read as "nothing pending, therefore settled", while the PR
# itself shows mergeStateStatus CLEAN because GitHub sees no required checks. Green-looking, and
# nothing ran. That is the failure this file exists to make impossible before a push.
#
# It happened while writing a Python heredoc into a `run:` block: an f-string containing
# `${{{name}}}` put a literal doubled brace in the file. `yaml.safe_load` passed, and the
# extracted step was executed verbatim and printed OK — both blind, because the collision is
# with the expression layer, not with YAML or with the shell.
#
# Run:  bash tests/workflow-expressions.test.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

# The contexts and functions Actions actually provides. Anything else in an expression is a
# typo or an accident, and both are fatal to the whole file.
VALID='github|env|vars|job|jobs|steps|runner|secrets|strategy|matrix|needs|inputs'
VALID="$VALID"'|always|success|failure|cancelled|hashFiles|format|join|toJSON|fromJSON|contains|startsWith|endsWith'

scan() { # scan <file> — prints one line per invalid expression
  python3 - "$1" "$VALID" <<'PY'
import re, sys
path, valid = sys.argv[1], sys.argv[2].split('|')
src = open(path, encoding='utf-8', errors='replace').read()
for n, line in enumerate(src.split('\n'), 1):
    for m in re.finditer(r'\$\{\{(.*?)(\}\}|$)', line):
        body = m.group(1).strip()
        if not body:
            print(f"{path}:{n}: empty expression"); continue
        head = re.split(r'[.\[\s(!=<>&|]', body.lstrip('!( '), maxsplit=1)[0]
        if head and head not in valid:
            print(f"{path}:{n}: '{head}' is not a GitHub Actions context or function -> {body[:48]}")
        if m.group(2) != '}}':
            print(f"{path}:{n}: unterminated expression -> {body[:48]}")
PY
}

echo "── 1. every workflow's expressions resolve to a real context ──"
shopt -s nullglob 2>/dev/null || true
found=0
for wf in "$REPO"/.github/workflows/*.yml "$REPO"/.github/workflows/*.yaml; do
  [ -f "$wf" ] || continue
  found=$((found+1))
  out=$(scan "$wf")
  if [ -n "$out" ]; then
    bad "$(basename "$wf") has invalid expression(s)" "$(printf '%s' "$out" | sed 's|.*/||')"
  else
    n=$(grep -c '\${{' "$wf" 2>/dev/null || echo 0)
    ok "$(basename "$wf") — $n expression(s), all valid contexts"
  fi
done
[ "$found" -gt 0 ] && ok "found $found workflow file(s) to check" \
  || bad "no workflow files found — this suite would pass vacuously"

echo "── 2. the workflows are still valid YAML ──"
for wf in "$REPO"/.github/workflows/*.yml; do
  [ -f "$wf" ] || continue
  if python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$wf" 2>/dev/null; then
    ok "$(basename "$wf") parses as YAML"
  else
    bad "$(basename "$wf") is not valid YAML"
  fi
done

echo "── 3. CONTROLS — the scanner must fire on the real defects ──"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/wf-expr.XXXXXX"); trap 'rm -rf "$TMP"' EXIT

# (a) The exact shape that broke the build: a Python f-string emitting a doubled brace.
{ printf 'name: t\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run: |\n'
  printf '          echo "use ${{{name}}}: instead"\n'; } > "$TMP/fstring.yml"
[ -n "$(scan "$TMP/fstring.yml")" ] && ok "control (a): catches the f-string doubled brace" \
  || bad "control (a) DID NOT FIRE — section 1 cannot see the defect that caused this file to exist"

# (b) A doubled brace inside a shell COMMENT is equally fatal — Actions substitutes into the
#     raw string before any shell exists to treat it as a comment.
{ printf 'name: t\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run: |\n'
  printf '          # explaining ${{ badctx }} in a comment\n'; } > "$TMP/comment.yml"
[ -n "$(scan "$TMP/comment.yml")" ] && ok "control (b): catches one inside a comment" \
  || bad "control (b) DID NOT FIRE — a comment is not a safe place to write one"

# (c) An unterminated expression.
{ printf 'name: t\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ${{ github.sha\n'; } > "$TMP/unterm.yml"
[ -n "$(scan "$TMP/unterm.yml")" ] && ok "control (c): catches an unterminated expression" \
  || bad "control (c) DID NOT FIRE"

# (d) And it must NOT flag the real thing — no false positives on genuine contexts.
{ printf 'name: t\njobs:\n  a:\n    runs-on: ${{ matrix.os }}\n    if: github.event.repository.fork != true\n    steps:\n'
  printf '      - run: echo ${{ github.event.pull_request.head.sha }} ${{ hashFiles("**/x") }} ${{ !cancelled() }}\n'
  printf '        env:\n          X: ${{ secrets.TOKEN }}\n          Y: ${{ needs.build.outputs.v }}\n'; } > "$TMP/legit.yml"
o=$(scan "$TMP/legit.yml")
[ -z "$o" ] && ok "control (d): no false positives on real contexts, functions or negation" \
  || bad "control (d): FALSE POSITIVE on valid expressions" "$o"

printf '\nRESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
