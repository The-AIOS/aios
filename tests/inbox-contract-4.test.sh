#!/usr/bin/env bash
# tests/inbox-contract-4.test.sh
#
# Contract 4 has two implementations outside this repo (the App and Glass) and one inside it (the
# spawn wrappers). The conformance fixture is what all of them run against, so it must parse, and
# the advisor rung table must say the same thing in the spec, the fixture and both wrappers. (A rung
# resolved through resolve-tier answers `judgment` with an empty string -- naming no advisor at all --
# which is how the first draft of the fixture went wrong.)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D="$ROOT/skills/aios/orchestration-ladder"
PYBIN="${PYBIN:-python3}"
PASS=0; FAIL=0
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
no(){ echo "  ✗ $1"; [ -n "${2:-}" ] && echo "      $2"; FAIL=$((FAIL+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# The checker goes to a file: bash 3.2 cannot parse a quoted heredoc inside $( ).
cat > "$T/check.py" <<'PY'
import json, re, sys
fx, spec, sh, ps = sys.argv[1:5]
d = json.load(open(fx, encoding="utf-8")); cases = d["cases"] if isinstance(d, dict) else d
bad = [c.get("case") for c in cases if not {"case", "request", "expect"} <= set(c)]
print("SHAPE", "ok" if not bad else "missing keys in: %s" % bad)
table = dict(re.findall(r"\|\s*`(frontier|judgment|scale|fast)`\s*\|\s*`([^`]+)`\s*\|", open(spec, encoding="utf-8").read()))
print("TABLE", "ok" if len(table) == 4 and all(table.values()) else "spec rung table incomplete: %s" % table)
shs = open(sh, encoding="utf-8").read(); pss = open(ps, encoding="utf-8").read()
m_sh = dict(re.findall(r"\b(frontier|judgment|scale|fast)\)\s+spawn_advisor='([^']+)'", shs))
m_ps = dict(re.findall(r"'(frontier|judgment|scale|fast)'\s*\{\s*'([^']+)'\s*\}", pss.split("$spawnAdvisor = switch")[1].split("}\n    }")[0] if "$spawnAdvisor = switch" in pss else ""))
print("SH", "ok" if m_sh == table else "sh %s != spec %s" % (m_sh, table))
print("PS", "ok" if m_ps == table else "ps1 %s != spec %s" % (m_ps, table))
rung = [c for c in cases if c["request"].get("advisor") in table]
wrong = [c["case"] for c in rung if c["expect"].get("advisor_model") != table[c["request"]["advisor"]]]
print("FIXTURE", "ok" if rung and not wrong else "rung cases disagree with the table: %s" % (wrong or "none present"))
PY
out=$($PYBIN "$T/check.py" "$D/inbox-contract-4.conformance.json" "$D/inbox-contract-4.md" "$ROOT/hooks/claude-identity/install-wrappers.sh" "$ROOT/hooks/claude-identity/install-wrappers.ps1")
while IFS= read -r line; do
  k="${line%% *}"; v="${line#* }"
  [ "$v" = ok ] && ok "$k agrees" || no "$k" "$v"
done <<< "$out"
echo "── queue fixture: every case passes a reference implementation of the amendment ──"
cat > "$T/queue.py" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1], encoding="utf-8")); CEIL = 24 * 3600 * 1000; STAMP = 2 * 60 * 1000
def decide(c):
    t = c["target"]
    if t is None or c["heldMs"] > CEIL: return "undeliverable"
    return "hold" if t.get("status") == "busy" else "deliver"
def queue(c):
    me = c["me"]; same = [h for h in c["held"] if h["target"] == me["target"]]
    newer = lambda a, b: a["queuedAt"] > b["queuedAt"]
    for h in same:
        if me.get("from") and h.get("from") == me["from"] and newer(h, me): return {"do": "superseded", "by": h["key"]}
    live = [h for h in same if not (h.get("from") and any(o.get("from") == h["from"] and newer(o, h) for o in same + [me]))]
    ahead = sorted([h for h in live if h["queuedAt"] < me["queuedAt"]], key=lambda h: h["queuedAt"])
    return {"do": "wait", "behind": ahead[0]["key"]} if ahead else {"do": "go"}
def stamp(c):
    text, w, frm = c["text"], c["waitedMs"], c.get("from")
    if w < STAMP or re.match(r"^\s*/", text): return text
    m = round(w / 60000); age = "%d h" % round(m / 60) if m >= 120 else "%d min" % m
    return "[queued %s ago%s] %s" % (age, " by " + frm if frm else "", text)
bad = []
for c in d["cases"]:
    got = decide(c["decideSend"]) if "decideSend" in c else queue(c["queue"]) if "queue" in c else stamp(c["stamp"])
    if got != c["expect"]: bad.append("%s: got %r" % (c["case"], got))
print("QUEUE", "ok" if not bad and len(d["cases"]) >= 13 else "; ".join(bad) or "too few cases")
PY
line=$($PYBIN "$T/queue.py" "$D/inbox-queue.conformance.json"); v="${line#* }"
[ "$v" = ok ] && ok "all queue cases pass the reference" || no "queue fixture" "$v"
grep -F '## Amendment — a send waits' "$D/inbox-contract-4.md" >/dev/null && ok "the contract text carries the queue amendment" || no "contract does not carry the queue amendment"

echo "── RESULT: $PASS passed, $FAIL failed ──"
[ "$FAIL" = 0 ] && [ "$PASS" -ge 7 ]
