#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Repair the CI failures that have exactly ONE correct answer.
#
#   bash scripts/autofix.sh            # fix them
#   bash scripts/autofix.sh --check    # say what would change, change nothing (exit 1 if any)
#   bash scripts/autofix.sh --covers   # the CI step names this repairs
#
# WHY THIS EXISTS. Some checks fail on a fact the repo can compute for itself: a
# doc says "30 skills" and the folder holds 31. There is nothing to decide — the
# folder is right, the sentence is stale — yet the failure still costs a red run,
# an email, and a round trip for whoever sent the change. Those are the ones
# worth automating; everything else in this workflow is a judgment call and must
# stay one.
#
# WHAT IT WILL NEVER DO. It does not touch a failing test, a guard, or anything
# whose fix could be wrong. A fixer that guesses turns a red check into a green
# lie, which is the one outcome worse than the email.
#
# The repairs are DERIVED from the same ground truth the check uses (count the
# folders), never from a stored number — a fixer holding its own copy of the
# answer is a second source of the drift it exists to remove.
# ─────────────────────────────────────────────────────────────────────────────
set -u

ROOT="${AIOS_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MODE="${1:-apply}"
CHANGED=""

# The CI steps whose failure this script can repair. The explainer reads this to
# decide whether to offer the fix, so the list lives here, next to the repairs.
if [ "$MODE" = "--covers" ]; then
  printf '%s\n' "Doc count claims match bundled ground truth"
  exit 0
fi

# Replace the number in a single anchored pattern. Reports whether it changed.
# sed -E with a temp file: `sed -i` differs between GNU and BSD, and this runs on
# both a contributor's Mac and an ubuntu runner.
fix_num() { # file  extended-regex-with-one-capture-around-the-number  new-value  label
  local file="$ROOT/$1" re="$2" val="$3" label="$4" tmp
  [ -f "$file" ] || return 0
  tmp="$(mktemp)"
  # `#` as the delimiter, never `|`: these patterns match markdown TABLE rows, and a pipe
  # inside a `|`-delimited sed expression is read as an escaped delimiter — the regex then
  # sees a bare alternation and rewrites the wrong half of the line. It looked like a
  # correct fixer reporting endless work to do on a repo that was already right.
  sed -E "s#${re}#\1${val}\2#" "$file" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  if cmp -s "$file" "$tmp"; then rm -f "$tmp"; return 0; fi
  CHANGED="$CHANGED$1 — $label
"
  if [ "$MODE" = "--check" ]; then rm -f "$tmp"; else mv "$tmp" "$file"; fi
}

# ── ground truth: count the folders, exactly as the check does ───────────────
cd "$ROOT" || exit 1
CMD=$(ls plugins/aios/commands/*.md 2>/dev/null | grep -v _index | wc -l | tr -d ' ')
AGENTS=$(find agents/aios -name '*.md' ! -name '_index.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
S_AIOS=$(ls -d skills/aios/*/ 2>/dev/null | wc -l | tr -d ' ')
S_ANTH=$(ls -d skills/anthropic/*/ 2>/dev/null | wc -l | tr -d ' ')
S_SUP=$(ls -d skills/superpowers/*/ 2>/dev/null | wc -l | tr -d ' ')
S_TOTAL=$((S_AIOS + S_ANTH + S_SUP))

# ── the repairs ──────────────────────────────────────────────────────────────
fix_num TOOLS.md          '(AIOS-built[^0-9]*)[0-9]+( skills)'        "$S_AIOS"  "AIOS-built skills count"
fix_num TOOLS.md          '(anthropics/skills[^0-9]*)[0-9]+( skills)' "$S_ANTH"  "vendored anthropic skills count"
fix_num TOOLS.md          '(obra/superpowers[^0-9]*)[0-9]+( skills)'  "$S_SUP"   "vendored superpowers skills count"
fix_num TOOLS.md          '(Total bundled: )[0-9]+()'                 "$S_TOTAL" "total bundled skills"
fix_num README.md         '(\*\*)[0-9]+( commands)'                   "$CMD"     "command count"
fix_num agents/_index.md  '(Total bundled agents: )[0-9]+()'          "$AGENTS"  "total bundled agents"

# The registry's per-bundle table: one row per agents/aios/<bundle>/, its Count column last.
for d in agents/aios/*/; do
  b="$(basename "$d")"
  n=$(find "$d" -name '*.md' ! -name '_index.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
  fix_num agents/_index.md "(\*\*\`aios/${b}/\`\*\*.*\| )[0-9]+( \|)" "$n" "$b row count"
done

# ── report ───────────────────────────────────────────────────────────────────
if [ -z "$CHANGED" ]; then
  echo "autofix: nothing to repair — every count claim already matches the folders"
  exit 0
fi

if [ "$MODE" = "--check" ]; then
  echo "autofix: these would be repaired by 'bash scripts/autofix.sh':"
  printf '%s' "$CHANGED" | sed 's/^/  /'
  exit 1
fi

echo "autofix: repaired"
printf '%s' "$CHANGED" | sed 's/^/  /'
exit 0
