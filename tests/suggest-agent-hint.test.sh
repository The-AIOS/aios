#!/usr/bin/env bash
# Hook G, hooks/agents/suggest-agent-hint.py (#317): names one agent for a prompt that clearly fits it, and
# stays silent for small talk, slash commands, ties, and the hat already worn. Never blocks.
# Runs against the real agents index, so a keyword edit that breaks a fixture fails here.
# Usage: bash tests/suggest-agent-hint.test.sh [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
H="$ROOT/hooks/agents/suggest-agent-hint.py"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
no(){ fail=$((fail+1)); echo "  FAIL $1"; }
echo "suggest-agent-hint"
T=$(mktemp -d "${TMPDIR:-/tmp}/sah.XXXXXX")
hint(){ # prompt [transcript] [cwd] -> agent name or "-"
  python3 -c 'import json,sys;print(json.dumps({"prompt":sys.argv[1],"transcript_path":sys.argv[2],"cwd":sys.argv[3]}))' "$1" "${2:-/nonexistent}" "${3:-$ROOT}" \
    | AIOS_ROOT="$ROOT" python3 "$H" | python3 -c 'import sys,re;t=sys.stdin.read();m=re.search(r"`([a-z0-9-]+)` agent",t);print(m.group(1) if m else "-")'
}
expect(){ got=$(hint "$1" "${3:-/nonexistent}"); [ "$got" = "$2" ] && ok "\"$1\" → $2" || no "\"$1\" → expected $2, got $got"; }

expect "help me check October's invoices before Friday" invoice-tracker
expect "help me with this quarter's bookkeeping and taxes please" accountant
expect "review this NDA and the liability clause" lawyer
expect "can you build me a pitch deck for investors" deck-builder
expect "write a blog post about our launch" content-writer
expect "hello" -
expect "hello there my friend how are you" -
expect "what time is it in Madrid right now" -
expect "rename this file to something better please" -
expect "/aios:today plan my day and my invoices" -

printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Wearing agent: invoice-tracker."}]}}' > "$T/t.jsonl"
expect "help me check October's invoices before Friday" - "$T/t.jsonl"
got=$(hint "help me with this quarter's bookkeeping and taxes please" /nonexistent "$T"); [ "$got" = - ] && ok "outside the vault: silent (a client repo gets no hats)" || no "fired outside the vault: $got"

out=$(printf 'not json' | AIOS_ROOT="$ROOT" python3 "$H"; echo "rc=$?")
[ "$out" = "rc=0" ] && ok "bad input: silent, exit 0 (never blocks a prompt)" || no "bad input: $out"
out=$(printf '{"prompt":"help me check my invoices this week"}' | AIOS_ROOT="$T/none" python3 "$H"; echo "rc=$?")
[ "$out" = "rc=0" ] && ok "no agents index: silent, exit 0" || no "no index: $out"
out=$(printf '{"prompt":"help me check October invoices please"}' | AIOS_ROOT="$ROOT" python3 "$H")
printf '%s' "$out" | python3 -c 'import json,sys;d=json.load(sys.stdin)["hookSpecificOutput"];assert d["hookEventName"]=="UserPromptSubmit" and "suggest-agent" in d["additionalContext"]' 2>/dev/null \
  && ok "output is UserPromptSubmit additionalContext pointing at suggest-agent" || no "bad output shape: $out"
rm -rf "$T"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
