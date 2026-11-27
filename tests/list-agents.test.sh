#!/usr/bin/env bash
# hooks/agents/list-agents.py: the one rule for what is an agent (#314, #418). An agent is a .md file
# under agents/ whose frontmatter tags include `agent`. The cases live in
# tests/fixtures/agent-rule.cases.json so the AIOS App and Glass can run the same ones against their
# own reader. Then the command line, the bundled tree, and the team plan that depends on the rule.
# Usage: bash tests/list-agents.test.sh [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
H="$ROOT/hooks/agents/list-agents.py"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
no(){ fail=$((fail+1)); echo "  FAIL $1"; }
echo "list-agents"
T=$(mktemp -d "${TMPDIR:-/tmp}/la.XXXXXX"); trap 'rm -rf "$T"' EXIT

# 1. Every shared case, through the command line a surface or a hook would use.
out=$(python3 - "$ROOT" "$T" <<'PY'
import json, os, subprocess, sys
root, tmp = sys.argv[1], sys.argv[2]
hook = os.path.join(root, "hooks", "agents", "list-agents.py")
doc = json.load(open(os.path.join(root, "tests", "fixtures", "agent-rule.cases.json"), encoding="utf-8"))
bad = 0
def run(vault, *args):
    r = subprocess.run([sys.executable, hook, *args], capture_output=True, text=True, encoding="utf-8", env={**os.environ, "AIOS_ROOT": vault})
    return r.returncode, r.stdout
for i, c in enumerate(doc["cases"]):
    vault = os.path.join(tmp, "case%d" % i)
    for rel, lines in c["files"].items():
        p = os.path.join(vault, rel); os.makedirs(os.path.dirname(p), exist_ok=True)
        nl = c.get("newline", "\n")
        with open(p, "w", encoding="utf-8", newline="") as fh:
            fh.write(nl.join(lines) + nl)
    for link, target in c.get("links", {}).items():
        p = os.path.join(vault, link); os.makedirs(os.path.dirname(p), exist_ok=True)
        os.symlink(os.path.join(vault, target), p)
    _rc, js = run(vault, "--json")
    try:
        got = sorted(json.loads(js), key=lambda a: a["path"])
    except ValueError:
        got = None
    want = c["expect"]["agents"]
    agents_ok = got is not None and len(got) == len(want) and all(all(g.get(k) == v for k, v in w.items()) for g, w in zip(got, want))
    rc, js = run(vault, "--unclear", "--json")
    try:
        unclear = sorted(({"path": u["path"], "why": u["why"]} for u in json.loads(js)), key=lambda u: u["path"])
    except (ValueError, KeyError, TypeError):
        unclear = None
    unclear_ok = unclear == c["expect"]["unclear"] and rc == (1 if c["expect"]["unclear"] else 0)
    if agents_ok and unclear_ok:
        print("  ok   case: %s" % c["case"])
    else:
        bad += 1
        print("  FAIL case: %s\n       agents %s\n       unclear %s" % (c["case"], got, unclear))
print("CASES %d %d" % (len(doc["cases"]) - bad, bad))
PY
)
printf '%s\n' "$out" | grep -v '^CASES '
set -- $(printf '%s\n' "$out" | grep '^CASES ' | cut -d' ' -f2-)
pass=$((pass+${1:-0})); fail=$((fail+${2:-1}))

# 2. The command line: the plain list, and a lint that tells the operator what to do.
A="$T/cli/agents/custom"; mkdir -p "$A"
printf -- '---\nname: tagged\ndescription: Listed\ntags: [agent]\n---\n' > "$A/tagged.md"
printf -- '---\nname: handmade\ndescription: Written by hand, no tag\n---\n' > "$A/handmade.md"
out=$(AIOS_ROOT="$T/cli" python3 "$H")
[ "$out" = "tagged	agents/custom/tagged.md" ] && ok "the plain list is name, tab, path, for tagged files only" || no "plain list wrong: $out"
out=$(AIOS_ROOT="$T/cli" python3 "$H" --unclear); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^agents/custom/handmade.md	' && printf '%s' "$out" | grep -qF 'add `agent` to `tags`' \
  && ok "--unclear names the untagged file, says to add \`agent\` to \`tags\`, and exits 1" || no "--unclear wrong (rc=$rc): $out"
mkdir -p "$T/real"; mv "$T/cli/agents" "$T/real/"; ln -s "$T/real" "$T/link"
[ "$(AIOS_ROOT="$T/link" python3 "$H" | grep -c .)" = 1 ] && ok "a symlinked vault root is followed" || no "a symlinked root found nothing"

# 3. What depends on the rule: a team plan naming an untagged file is refused, by name.
mkdir -p "$T/tp/hooks/agents" "$T/tp/agents/custom"; cp "$ROOT/hooks/agents/list-agents.py" "$ROOT/hooks/agents/team-plan.py" "$T/tp/hooks/agents/"
cp "$T/real/agents/custom/"*.md "$T/tp/agents/custom/"
names=$(cd "$T/tp" && python3 -c 'import importlib.util,sys
s=importlib.util.spec_from_file_location("tp","hooks/agents/team-plan.py"); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(",".join(sorted(m.known_agents())))' 2>&1)
[ "$names" = "tagged" ] && ok "team-plan.py knows the tagged agent and not the untagged file" || no "team-plan.py's known agents: $names"
mkdir -p "$T/tp/hooks/pipeline"; cp "$ROOT/hooks/pipeline/resolve-tier" "$T/tp/hooks/pipeline/"
{ printf -- '---\nstatus: active\n---\n# P\n\n## Team\n\n**Charter.** x\n\n| Role | Session | Agent | Tier | Kind | Owns | Reports to | First task |\n|---|---|---|---|---|---|---|---|\n'
  printf '| chief of staff | p-lead | handmade | judgment | standing | | operator | x |\n'; } > "$T/tp/plan.md"
out=$(python3 "$T/tp/hooks/agents/team-plan.py" check "$T/tp/plan.md"); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -qF "no agent named 'handmade' under agents/ (agents/custom/handmade.md has no \`agent\` tag: add \`agent\` to its \`tags\`)" \
  && ok "a plan naming the untagged file is refused, and told which file needs the tag" || no "team-plan refusal wrong (rc=$rc): $out"

# 4. The bundled tree follows the rule.
out=$(AIOS_ROOT="$ROOT" python3 "$H" --unclear); rc=$?
[ "$rc" = 0 ] && ok "the bundled agents/ tree has nothing unclear" || no "bundled tree has unclear files: $out"
n=$(AIOS_ROOT="$ROOT" python3 "$H" | grep -c .)
disk=$(find "$ROOT/agents/aios" -name '*.md' ! -name '_*' ! -name 'README.md' | wc -l | tr -d ' ')
[ "$n" -ge "$disk" ] && [ "$disk" -ge 1 ] && ok "every bundled agent file carries the tag and is listed ($disk)" || no "bundled: $n listed, $disk agent files on disk"
grep -q '^  - agent$' "$ROOT/templates/aios/agent-template.md" && ok "the agent template carries the tag" || no "the agent template has no agent tag"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
