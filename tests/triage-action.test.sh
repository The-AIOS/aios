#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The triage Action comments and nothing else (#260)
#
# WHAT IT HOLDS
#   * keywords, routing and the comment behave: a near-duplicate title finds its words,
#     an App install problem filed here suggests aios-app, a framework issue suggests
#     nothing, and no matches + no suggestion means no comment at all
#   * the workflow runs only on "opened", checks out only the base repo, never the PR's
#     code, and asks for comment permissions only
#   * the script makes no call that closes, labels, edits or transfers anything
#   * it starts in dry-run: without TRIAGE_MODE=comment it posts nothing
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
command -v node >/dev/null 2>&1 || { echo "SKIP: node not found" >&2; exit 0; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
S=.github/scripts/triage.js; W=.github/workflows/triage.yml
out=$(node -e '
const t = require("./.github/scripts/triage.js");
const r = [];
r.push(JSON.stringify(t.keywords("aios-commit: the short name on PATH refuses every commit")));
r.push(String(t.suggestRepo("Windows installer: the setup window never finishes installing", "aios")));
r.push(String(t.suggestRepo("/aios:today skips a command when the hook fails", "aios")));
r.push(String(t.suggestRepo("Glass panel: the extension status bar item is missing in VS Code", "aios")));
r.push(JSON.stringify(t.buildComment({ matches: [], suggestion: null })));
const c = t.buildComment({ matches: [{repo:"aios",number:290,title:"x",state:"open"}], suggestion: "aios-app" });
r.push(String(c.includes(t.MARKER) && c.includes("aios#290") && c.includes("The-AIOS/aios-app") && c.includes("never closes")));
console.log(r.join("\n"));')
L(){ printf '%s\n' "$out" | sed -n "${1}p"; }
[ "$(L 1)" = '["aios-commit","short","name","path","refuses","commit"]' ] && ok "a title becomes its search words" || no "keywords" "$(L 1)"
[ "$(L 2)" = "aios-app" ] && ok "an App install problem filed here suggests aios-app" || no "install problem routing" "$(L 2)"
[ "$(L 3)" = "null" ] && ok "a framework issue suggests no transfer" || no "framework issue routing" "$(L 3)"
[ "$(L 4)" = "aios-glass" ] && ok "a panel/extension problem suggests aios-glass" || no "glass routing" "$(L 4)"
[ "$(L 5)" = '""' ] && ok "nothing matched means no comment at all" || no "empty comment" "$(L 5)"
[ "$(L 6)" = "true" ] && ok "the comment carries its marker, the match, the suggestion and the promise" || no "comment content" "$(L 6)"
forbidden=$(grep -nvE '^[[:space:]]*//' "$S" | grep -E "issues\.(update|lock|addLabels|removeLabel|setLabels|removeAllLabels|addAssignees)|pulls\.(update|merge)|transfer|state: *['\"]closed|closeIssue" || true)
[ -z "$forbidden" ] && ok "the script makes no call that closes, labels, edits or transfers" || no "forbidden calls in the script" "$forbidden"
grep -E '^\s+types: \[opened\]' "$W" | wc -l | grep -q 2 && ok "it runs only when an issue or PR is opened" || no "it runs on more than 'opened'"
perm=$(awk '/^permissions:/{f=1;next} f&&/^[a-z]/{exit} f' "$W" | tr -d ' ' | grep -v '^$' | sort | tr '\n' ' ')
[ "$perm" = "contents:read issues:write pull-requests:write " ] && ok "comment permissions only" || no "unexpected permissions" "$perm"
grep -F 'github.event.pull_request.head' "$W" >/dev/null && no "the workflow checks out the PR's code" || ok "it never checks out the PR's code"
grep -F "process.env.TRIAGE_MODE || 'dry-run'" "$S" >/dev/null && ok "it starts in dry-run unless TRIAGE_MODE=comment" || no "dry-run is not the default"
printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
