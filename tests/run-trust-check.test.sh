#!/usr/bin/env bash
# hooks/install/run-trust-check.py (#323): says once when ~/.aios/run is untrusted, is silent when it is
# trusted or absent, honours CLAUDE_CONFIG_DIR and AIOS_RUN_DIR, and never writes ~/.claude.json.
# Usage: bash tests/run-trust-check.test.sh [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
H="$ROOT/hooks/install/run-trust-check.py"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
no(){ fail=$((fail+1)); echo "  FAIL $1"; }
echo "run-trust-check"
T=$(mktemp -d "${TMPDIR:-/tmp}/rtc.XXXXXX")
run(){ env -u CLAUDE_CONFIG_DIR -u AIOS_RUN_DIR HOME="$1" python3 "$H" 2>&1; }

mkdir -p "$T/a"; out=$(run "$T/a"); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "no run folder yet: silent" || no "no run folder: rc=$rc out=$out"

mkdir -p "$T/b/.aios/run"; out=$(run "$T/b")
printf '%s' "$out" | grep -q 'choose Yes' && ok "no ~/.claude.json: says how to trust, once" || no "no ~/.claude.json: $out"

mkdir -p "$T/c/.aios/run"; printf '{"projects":{"%s":{"hasTrustDialogAccepted":false}}}' "$T/c/.aios/run" > "$T/c/.claude.json"
before=$(shasum "$T/c/.claude.json"); out=$(run "$T/c")
printf '%s' "$out" | grep -q 'cd ~/.aios/run && claude' && ok "untrusted: prints the command" || no "untrusted: $out"
[ "$(shasum "$T/c/.claude.json")" = "$before" ] && ok "never writes ~/.claude.json" || no "~/.claude.json was changed"

mkdir -p "$T/d/.aios/run"; printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}' "$T/d/.aios/run" > "$T/d/.claude.json"
out=$(run "$T/d"); [ -z "$out" ] && ok "trusted: silent" || no "trusted but still printed: $out"

mkdir -p "$T/e/.aios/run" "$T/e/cfg"; printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}' "$T/e/.aios/run" > "$T/e/cfg/.claude.json"
out=$(env -u AIOS_RUN_DIR HOME="$T/e" CLAUDE_CONFIG_DIR="$T/e/cfg" python3 "$H" 2>&1)
[ -z "$out" ] && ok "reads .claude.json inside a relocated CLAUDE_CONFIG_DIR" || no "CLAUDE_CONFIG_DIR ignored: $out"

mkdir -p "$T/f/run2"; printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}' "$T/f/run2" > "$T/f/.claude.json"
out=$(env -u CLAUDE_CONFIG_DIR HOME="$T/f" AIOS_RUN_DIR="$T/f/run2" python3 "$H" 2>&1)
[ -z "$out" ] && ok "honours AIOS_RUN_DIR, as the wrappers do" || no "AIOS_RUN_DIR ignored: $out"

mkdir -p "$T/g/.aios/run"; echo 'not json' > "$T/g/.claude.json"; out=$(run "$T/g"); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'choose Yes' && ok "an unreadable ~/.claude.json reads as untrusted, never as a crash" || no "bad json: rc=$rc $out"

rm -rf "$T"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
