#!/usr/bin/env bash
# hooks/list-agents.py (#314): the one rule for what is an agent. Fixture vault: an agent, a
# document under reference/, one marked agent: false, an unclear file, README/_index skipped,
# JSON shape. Then the bundled tree: every file there is an agent or a document, none unclear.
# Usage: bash tests/list-agents.test.sh [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
H="$ROOT/hooks/list-agents.py"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
no(){ fail=$((fail+1)); echo "  FAIL $1"; }
echo "list-agents"
T=$(mktemp -d "${TMPDIR:-/tmp}/la.XXXXXX"); A="$T/agents/acme"
mkdir -p "$A/reference"
printf -- '---\nname: acme-lawyer\ndescription: Reviews Acme contracts\n---\nbody\n' > "$A/acme-lawyer.md"
printf -- '---\nname: code-of-commerce\ndescription: The law text\n---\n' > "$A/reference/code-of-commerce.md"
printf -- '---\nagent: false\ntitle: Glossary\n---\n' > "$A/glossary.md"
printf 'no frontmatter, an example\n' > "$A/example-case.md"
printf '# Acme agents\n' > "$A/README.md"; printf '# index\n' > "$T/agents/_index.md"
out=$(AIOS_ROOT="$T" python3 "$H")
[ "$(printf '%s\n' "$out" | grep -c .)" = 1 ] && printf '%s' "$out" | grep -q '^acme-lawyer	agents/acme/acme-lawyer.md$' \
  && ok "only the file with name + description is an agent" || no "agent list wrong: $out"
out=$(AIOS_ROOT="$T" python3 "$H" --unclear); rc=$?
[ "$rc" = 1 ] && [ "$out" = "agents/acme/example-case.md" ] && ok "--unclear names only the file that is neither, and exits 1" || no "--unclear wrong (rc=$rc): $out"
AIOS_ROOT="$T" python3 "$H" --json | python3 -c 'import json,sys;d=json.load(sys.stdin);assert d==[{"name":"acme-lawyer","description":"Reviews Acme contracts","path":"agents/acme/acme-lawyer.md"}]' 2>/dev/null \
  && ok "--json gives name, description and path for surfaces" || no "--json shape wrong"
mkdir -p "$T/real"; mv "$T/agents" "$T/real/"; ln -s "$T/real" "$T/link"
[ "$(AIOS_ROOT="$T/link" python3 "$H" | grep -c .)" = 1 ] && ok "a symlinked vault root is followed" || no "a symlinked root found nothing"
out=$(AIOS_ROOT="$ROOT" python3 "$H" --unclear); rc=$?
[ "$rc" = 0 ] && ok "the bundled agents/ tree has no unclear files" || no "bundled tree has unclear files: $out"
[ "$(AIOS_ROOT="$ROOT" python3 "$H" | grep -c .)" -ge 40 ] && ok "every bundled agent is listed" || no "bundled agents missing from the list"
rm -rf "$T"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
