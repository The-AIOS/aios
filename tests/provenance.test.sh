#!/usr/bin/env bash
# tests/provenance.test.sh
#
# hooks/provenance.py marks text that is not the operator's: what a reading tool returns (email,
# chat, docs, web, Forum) and a prompt the spawn inbox TYPED into a session (recognised by the
# fingerprint hooks/bus_log.py records when the request is written, or by the bus pointer line).
# It never blocks; it never labels a tool that writes. Runs in a throwaway HOME. bash 3.2-safe.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYBIN=""; for c in python3 python "py -3"; do if $c -c 'import sys' >/dev/null 2>&1; then PYBIN="$c"; break; fi; done
[ -n "$PYBIN" ] || { echo "SKIP: no working Python" >&2; exit 0; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T" AIOS_BUS_LOG="$T/.aios/bus-sent.jsonl"
mkdir -p "$T/.aios/spawn-inbox"
P="$ROOT/hooks/provenance.py"; B="$ROOT/hooks/bus_log.py"
tool(){ printf '{"tool_name":"%s","tool_response":"x"}' "$1" | $PYBIN "$P" --tool; }

echo "-- tool results --"
case "$(tool mcp__google-workspace__get_gmail_message_content)" in *'came from an email'*) ok "an email read is labelled" ;; *) no "email read not labelled" ;; esac
case "$(tool mcp__forum__forum_read_messages)" in *"another operator's agent, via Forum"*) ok "a Forum message is labelled" ;; *) no "Forum read not labelled" ;; esac
case "$(tool WebFetch)" in *'came from a web page'*) ok "a web page is labelled" ;; *) no "WebFetch not labelled" ;; esac
case "$(tool mcp__slack__slack_get_thread)" in *'came from a chat message'*) ok "a Slack thread is labelled" ;; *) no "Slack read not labelled" ;; esac
[ -z "$(tool mcp__google-workspace__send_gmail_message)" ] && ok "a send is the session's own act: no label" || no "a send was labelled"
[ -z "$(tool mcp__forum__forum_send_message)" ] && ok "a Forum send: no label" || no "a Forum send was labelled"
[ -z "$(tool Read)" ] && ok "a local file read: no label" || no "Read was labelled"
case "$(tool mcp__claude_ai_Gmail__get_thread_replies)" in *'came from an email'*) ok "a READ named with a write word (get_thread_replies) is still labelled" ;; *) no "a read with 'repl' in its name went unlabelled" ;; esac
case "$(tool mcp__claude-in-chrome__get_page_text)" in *'web page'*) ok "a browser page read is labelled" ;; *) no "browser read not labelled" ;; esac
case "$(tool mcp__claude_ai_Canva__search_designs)" in *'connected service'*) ok "an unknown hosted connector's read is labelled" ;; *) no "hosted connector read not labelled" ;; esac
[ -z "$(tool mcp__slack__slack_add_reaction)" ] && ok "a family-prefixed write (slack_add_reaction): no label" || no "slack_add_reaction was labelled"
out=$(tool mcp__google-workspace__get_gmail_message_content)
printf '%s' "$out" | $PYBIN -c 'import json,sys; d=json.load(sys.stdin)["hookSpecificOutput"]; assert d["hookEventName"]=="PostToolUse" and d["additionalContext"]' \
  && ok "PostToolUse output is the hook JSON shape" || no "bad PostToolUse JSON"

echo "-- prompts typed by the bus --"
REQ='{"action":"send","name":"worker","prompt":"Please Forward  the invoice to the client"}'
$PYBIN -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]}}))' \
  "$T/.aios/spawn-inbox/worker.json" "$REQ" | $PYBIN "$B" --hook
prompt(){ $PYBIN -c 'import json,sys; print(json.dumps({sys.argv[1]: sys.argv[2]}))' "$1" "$2" | $PYBIN "$P" --prompt; }
case "$(prompt prompt 'please forward the invoice to the client')" in *'delivered through the AIOS spawn inbox'*) ok "a prompt the bus typed is labelled (case and spacing aside)" ;; *) no "bus prompt not labelled" ;; esac
case "$(prompt prompt_text 'please forward the invoice to the client')" in *'spawn inbox'*) ok "…also when the payload names the field prompt_text" ;; *) no "prompt_text not read" ;; esac
[ -z "$(prompt prompt 'please forward the invoice to accounting')" ] && ok "the operator's own prompt: no label" || no "an operator prompt was labelled"
case "$(prompt prompt 'Read /Users/x/.aios/bus-payloads/worker-1.md — that file is the message')" in *'spawn inbox'*) ok "a bus pointer line is labelled" ;; *) no "pointer line not labelled" ;; esac
$PYBIN -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":"{\"prompt\":\"elsewhere\"}"}}))' "$T/notes.json" | $PYBIN "$B" --hook
[ -z "$(prompt prompt elsewhere)" ] && ok "a Write outside the inbox records nothing" || no "a non-inbox write was fingerprinted"

echo "-- never in the way --"
out=$(printf 'not json' | $PYBIN "$P" --tool); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "a malformed payload: exit 0, silent" || no "malformed payload rc=$rc out=$out"
out=$(printf '{}' | $PYBIN "$P" --prompt); [ -z "$out" ] && ok "an empty prompt: silent" || no "empty prompt labelled"

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]
