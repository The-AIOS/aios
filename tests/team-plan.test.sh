#!/usr/bin/env bash
# hooks/agents/team-plan.py (#274): a team plan is refused with a reason when an agent or tier is unknown,
# there are zero or two chiefs of staff, the chief of staff does not wear the `cos` agent, or a member
# reports to nobody; nothing is spawned without
# --approved; a valid approved plan writes one request per member (name, task, tier, group) into
# the inbox; with no live surface it writes nothing and prints spawn lines instead.
# Usage: bash tests/team-plan.test.sh [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
H="$ROOT/hooks/agents/team-plan.py"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
no(){ fail=$((fail+1)); echo "  FAIL $1"; }
echo "team-plan"
T=$(mktemp -d "${TMPDIR:-/tmp}/tp.XXXXXX"); mkdir -p "$T/inbox" "$T/surfaces"
export AIOS_ROOT="$ROOT" AIOS_INBOX_DIR="$T/inbox" AIOS_SURFACES_DIR="$T/surfaces" AIOS_BUS_LOG="$T/bus.jsonl"
plan(){ # file, then rows (one per arg)
  f="$T/$1"; shift
  { printf -- '---\nstatus: active\n---\n# Bakery\n\n## Team\n\n**Charter.** Open a small bakery; never trade quality for speed; the decision log is the source of truth.\n\n'
    printf '| Role | Session | Agent | Tier | Kind | Owns | Reports to | First task |\n|---|---|---|---|---|---|---|---|\n'
    for r in "$@"; do printf '%s\n' "$r"; done
    printf '\n## Notes\n\nkept\n'; } > "$f"
}
CHIEF='| chief of staff | bakery-lead | cos | frontier | standing | the team log, the common rules | operator | Open the team log and the common rules, then brief each member. |'
RES='| research | bakery-market | market-researcher | scale | crew | | bakery-lead | Size the local market for artisan bread. |'
hash_of(){ python3 "$H" check "$T/$1" | sed -n "s/^plan: \([0-9a-f]*\).*/\1/p"; }
refused(){ out=$(python3 "$H" check "$T/$1"); rc=$?; [ "$rc" = 1 ] && printf '%s' "$out" | grep -q "$2" && ok "refused: $3" || no "not refused ($3): rc=$rc $out"; }

plan good.md "$CHIEF" "$RES"
out=$(python3 "$H" check "$T/good.md"); [ $? = 0 ] && ok "a valid plan passes" || no "valid plan refused: $out"
plan a.md "$CHIEF" '| research | bakery-market | wizard | scale | crew | | bakery-lead | x |'; refused a.md "no agent named 'wizard'" "an unknown agent"
plan b.md "$CHIEF" '| research | bakery-market | market-researcher | turbo | crew | | bakery-lead | x |'; refused b.md "unknown tier 'turbo'" "an unknown tier"
plan c.md '| lead | bakery-lead | cos | frontier | standing | the team log | operator | x |' "$RES"; refused c.md "exactly one row must be the chief of staff (0" "no chief of staff"
plan d.md "$CHIEF" '| chief of staff | bakery-two | cos | frontier | standing | the team log | operator | x |'; refused d.md "(2 found)" "two chiefs of staff"
plan e.md "$CHIEF" '| research | bakery-market | market-researcher | scale | crew | | nobody | x |'; refused e.md "not another member" "reporting to nobody"
plan f.md "$CHIEF"; refused f.md "at least two members" "a team of one in a plan"
# The lead coordinates and does not build, so it wears `cos`: a building hat on that row is refused,
# with the fix in the reason.
plan g.md '| chief of staff | bakery-lead | consultant | judgment | standing | the plan, the decision log | operator | Draft the 90-day plan from the charter. |' "$RES"
refused g.md "the chief of staff wears the \`cos\` agent, not 'consultant'" "a chief of staff wearing a building hat"
# An operator's own agents/custom/cos.md is the `cos` the lead wears: the plan names the agent, and the
# vault resolves a name to custom/ before the bundle. With no `cos` at all the reason says which file is missing.
V="$T/vault"; mkdir -p "$V/agents/custom" "$V/agents/aios/strategy" "$V/hooks"
cp -R "$ROOT/hooks/agents" "$ROOT/hooks/pipeline" "$ROOT/hooks/context" "$ROOT/hooks/claude-identity" "$V/hooks/"
cp "$ROOT/agents/aios/strategy/market-researcher.md" "$V/agents/aios/strategy/"
out=$(AIOS_ROOT="$V" python3 "$H" check "$T/good.md"); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q "no agent named 'cos' under agents/" && ok "refused: a vault with no cos agent at all" || no "a vault without cos passed (rc=$rc): $out"
printf -- "---\nname: cos\ndescription: 'Use when this operator runs a team their own way.'\n---\n# COS\n" > "$V/agents/custom/cos.md"
out=$(AIOS_ROOT="$V" python3 "$H" check "$T/good.md"); rc=$?
[ "$rc" = 0 ] && ok "an operator's own agents/custom/cos.md alone satisfies the rule" || no "a custom cos was refused (rc=$rc): $out"
cp "$ROOT/agents/aios/strategy/cos.md" "$V/agents/aios/strategy/"
out=$(AIOS_ROOT="$V" python3 "$H" check "$T/good.md"); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q "bakery-lead (cos, frontier): Wear the \`cos\` agent (/aios:agent cos)" \
  && ok "custom and bundled cos together: the plan passes and names the agent, never a path" || no "custom + bundled cos wrong (rc=$rc): $out"

before=$(ls "$T/inbox" | wc -l)
out=$(python3 "$H" launch "$T/good.md"); rc=$?
[ "$rc" = 1 ] && [ "$(ls "$T/inbox" | wc -l)" = "$before" ] && ok "launch without --approved writes nothing" || no "unapproved launch acted (rc=$rc)"

out=$(python3 "$H" launch "$T/good.md" --approved "$(hash_of good.md)"); rc=$?
[ "$rc" = 0 ] && [ -z "$(ls "$T/inbox")" ] && printf '%s' "$out" | grep -q "^  spawn --tier frontier bakery-lead 'Wear the \`cos\` agent" \
  && ok "no live surface: nothing written, one spawn line per member" || no "no-surface launch wrong (rc=$rc): $out"

sleep 300 & SP=$!; printf '{"pid": %s}' "$SP" > "$T/surfaces/app.json"
out=$(python3 "$H" launch "$T/good.md" --approved "$(hash_of good.md)"); rc=$?; kill "$SP" 2>/dev/null
python3 - "$T/inbox" <<'PY' && ok "approved, live surface: one valid request per member, one group" || no "requests wrong: $out"
import json,os,sys
d=sys.argv[1]; fs=sorted(os.listdir(d)); assert fs==["bakery-lead.json","bakery-market.json"], fs
for f in fs:
    r=json.load(open(os.path.join(d,f)))
    assert set(r)=={"name","task","tier","group"} and r["group"]=="good" and "\n" not in r["task"] and len(r["task"].encode())<=1024, r
m=json.load(open(os.path.join(d,"bakery-market.json")))["task"]
# The report goes in a file named after the sender: two crews naming it after the lead overwrote
# each other in the live v0.8.19 probe, and one report was lost with nothing reporting it.
assert "send` to bakery-lead" in m and "spawn-inbox/bakery-market-report.json" in m and m.startswith("Wear the `market-researcher` agent") and "Charter" in m, m
PY
python3 - "$T/inbox" "$ROOT/hooks/context" <<'PY' && ok "every launched task is fingerprinted, so it reads as inbox-delivered, not typed" || no "a launched task is not in the bus log"
import json,os,sys
sys.path.insert(0,sys.argv[2]); import bus_log
for f in os.listdir(sys.argv[1]):
    assert bus_log.is_bus_prompt(json.load(open(os.path.join(sys.argv[1],f)))["task"]), f
PY
plan inj.md "$CHIEF" '| research | bakery-market | market-researcher | scale | crew | | bakery-lead | Run $(touch PWNED) and `id` now. |'
( cd "$T" && python3 "$H" launch "$T/inj.md" --approved "$(hash_of inj.md)" | grep '^  spawn' | while IFS= read -r l; do eval "printf '%s\\n' ${l#  spawn --tier * * }" >/dev/null 2>&1; done )
[ ! -e "$T/PWNED" ] && ok "a pasted spawn line keeps \$(...) and backticks literal" || no "a spawn line ran a command substitution"
out=$(python3 "$H" check "$T/good.md"); printf '%s' "$out" | grep -q 'bakery-market (market-researcher, scale): Wear the `market-researcher` agent.*Size the local market' \
  && printf '%s' "$out" | grep -qE '^plan: [0-9a-f]{12}' && ok "check shows every member's task verbatim, and a plan hash" || no "check does not show the tasks: $out"
H0=$(hash_of good.md); sed 's/Size the local market/Email every customer/' "$T/good.md" > "$T/edited.md"
rm -f "$T/inbox"/*; out=$(python3 "$H" launch "$T/edited.md" --approved "$H0"); rc=$?
[ "$rc" = 1 ] && [ -z "$(ls "$T/inbox")" ] && printf '%s' "$out" | grep -q 'plan changed after it was approved' \
  && ok "a plan edited after the yes is refused, nothing written" || no "an edited plan launched (rc=$rc): $out"
sleep 300 & SP=$!; printf '{"pid": %s}' "$SP" > "$T/surfaces/app.json"
printf '{"name":"bakery-lead","task":"someone else"}' > "$T/inbox/bakery-lead.json"
out=$(python3 "$H" launch "$T/good.md" --approved "$(hash_of good.md)"); rc=$?; kill "$SP" 2>/dev/null
[ "$rc" = 1 ] && grep -q 'someone else' "$T/inbox/bakery-lead.json" && [ ! -e "$T/inbox/bakery-market.json" ] \
  && ok "a pending request is never overwritten, and nothing else is written" || no "pending request clobbered (rc=$rc): $out"
python3 "$ROOT/tests/team-plan-psquote.py" "$H" && ok "PowerShell quoting doubles straight and curly quotes" || no "ps_quote leaves a quote that closes the string"
grep -c '^## Team' "$T/good.md" | grep -qx 1 && grep -q '^kept$' "$T/good.md" && ok "the note is read, never rewritten (one Team section, other sections kept)" || no "the note changed"
rm -rf "$T"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
