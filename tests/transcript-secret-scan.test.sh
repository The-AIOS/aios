#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# A token pasted into a Claude Code session must be findable, and never reprinted
#
# hooks/transcript-secret-scan.py looks for secret-shaped values in session
# transcripts using hooks/git/secret-scan.sh's own pattern list. What this pins:
#
#   1. It FINDS a pasted key and a pasted cloud key, and reports kind, date,
#      file:line and the last 4 characters.
#   2. The value NEVER appears in any file the tool writes, nor in its output.
#      (A scanner that copies secrets into a report is a second leak.)
#   3. A second run reads nothing; a later append is found without re-reading;
#      a half-written last line waits instead of being lost.
#   4. A missing folder is exit 2, never a clean "0 found" (CONTROL: the same
#      command on a real folder exits 0). A report before any scan fails.
#   5. Two private keys with the same header are two values.
#   6. `ack` stops a value counting; --notify runs once and again only for a
#      value it has not announced.
# Keys are built at run time so this file is not itself a finding.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PYBIN=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PYBIN="$_cand"; break; fi
done
if [ -z "$PYBIN" ]; then echo "SKIP: no working Python found" >&2; exit 0; fi
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
S=hooks/transcript-secret-scan.py
R="$T/projects/p1"; ST="$T/state"; mkdir -p "$R"
KEY="sk-ant-$(printf 'Ab1Cd2Ef%.0s' 1 2 3 4)"          # 32 chars after the prefix
AWS="AKIA$(printf 'ABCDEFGH12345678')"
HDR="-----BEGIN RSA PRIVATE KEY-----"
run(){ $PYBIN "$S" "$@" --root "$T/projects" --state-dir "$ST"; }
entry(){ printf '{"type":"user","timestamp":"2026-10-20T10:00:00Z","text":"%s"}\n' "$1"; }

echo "── it finds a pasted key and says where, not what ──"
{ entry "hello"; entry "my key is $KEY"; entry "and $AWS"; entry "bye"; } > "$R/s1.jsonl"
out=$(run scan 2>&1); rc=$?
[ "$rc" = "0" ] && ok "scan exits 0" || no "scan exit $rc" "$out"
echo "$out" | grep -q "2 new hit" && ok "2 hits counted" || no "hit count" "$out"
rep="$ST/report.md"
grep -q "Anthropic API key" "$rep" && ok "kind reported" || no "kind missing" "$(cat "$rep")"
grep -q "2026-10-20" "$rep" && ok "date of the entry reported" || no "date missing"
grep -q "s1.jsonl:2" "$rep" && ok "file:line reported" || no "file:line missing" "$(cat "$rep")"
grep -q "\.\.\.${KEY: -4}" "$rep" && ok "value masked to its last 4" || no "mask missing"

echo "── the value is never written or printed ──"
leak=0
for f in "$ST"/*; do grep -q "$KEY" "$f" 2>/dev/null && leak=1; grep -q "$AWS" "$f" 2>/dev/null && leak=1; done
echo "$out" | grep -q "$KEY" && leak=1
[ "$leak" = "0" ] && ok "no secret in the state files or the output" || no "a secret value leaked"
[ "$(ls -ld "$rep" | cut -c1-10)" = "-rw-------" ] && ok "report is private (600)" || no "report permissions"

echo "── incremental, and a half line waits ──"
out=$(run scan 2>&1); echo "$out" | grep -q "scanned 0 changed" && ok "second run reads nothing" || no "second run" "$out"
entry "later $AWS" >> "$R/s1.jsonl"
out=$(run scan 2>&1); echo "$out" | grep -q "2 distinct value" && ok "the same value again is one value (a second place)" || no "dedupe" "$out"
printf '{"type":"user","text":"half %s' "$KEY" >> "$R/s2.jsonl"
out=$(run scan 2>&1); echo "$out" | grep -q "0 new hit" && ok "a half-written line is not read yet" || no "half line read" "$out"
printf '"}\n' >> "$R/s2.jsonl"
out=$(run scan 2>&1); echo "$out" | grep -q "scanned 1 changed" && ok "finished line is read next run" || no "finished line" "$out"

echo "── a missing folder is never a clean result ──"
$PYBIN "$S" scan --root "$T/nope" --state-dir "$T/state2" >/dev/null 2>&1; rc=$?
[ "$rc" = "2" ] && ok "missing folder → exit 2" || no "missing folder exit $rc"
$PYBIN "$S" scan --root "$T/projects" --state-dir "$T/state3" --notify "" >/dev/null 2>&1; rc=$?
[ "$rc" = "0" ] && ok "CONTROL: a real folder → exit 0" || no "control exit $rc"
$PYBIN "$S" report --state-dir "$T/state4" >/dev/null 2>&1; rc=$?
[ "$rc" = "2" ] && ok "report before any scan → exit 2" || no "report before scan exit $rc"

echo "── two private keys with one header are two values ──"
{ entry "$HDR\\\\nAAAA1111\\\\n"; entry "$HDR\\\\nBBBB2222\\\\n"; } > "$R/s3.jsonl"
out=$(run scan 2>&1)
n=$(grep -c "private key" "$rep" || true)
[ "$n" -ge 2 ] && ok "two key rows" || no "private keys merged" "$(cat "$rep")"

echo "── false positives: base64 and attachments; the newer Gemini shape ──"
GK="AIza$(printf 'B1c2D3e4%.0s' 1 2 3 4)XyZ"          # 35 characters after the prefix, as real Google keys have
GEM="AQ.$(printf 'Ab8RN6Kx%.0s' 1 2 3 4 5)"
{ entry "blob $(printf 'QUJD%.0s' 1 2 3 4 5 6 7 8 9 10)$GK$(printf 'REVG%.0s' 1 2 3 4 5 6 7 8 9 10)"
  entry "attachment_id: \\\"Xy$GK\\\""
  entry "attachment_id: Xy$GK"; } > "$R/s4.jsonl"
before=$(grep -c "^| " "$rep" || true)
run scan >/dev/null 2>&1
after=$(grep -c "^| " "$rep" || true)
[ "$before" = "$after" ] && ok "base64 run / attachment id are not keys" || no "false positive" "$(cat "$rep")"
GK2="AIza$(printf 'Z1x2C3v4%.0s' 1 2 3 4)bnc"
entry "my key is $GK ok" > "$R/s5.jsonl"; entry "GOOGLE_API_KEY=$GEM" >> "$R/s5.jsonl"
entry "attachment failed, my API key is $GK2" >> "$R/s5.jsonl"       # no word nearby hides a standalone key
printf '{"type":"user","text":"line one\\n%s\\nlast"}\n' "AIza$(printf 'M1n2B3v4%.0s' 1 2 3 4)xyz" >> "$R/s5.jsonl"   # key right after a newline
run scan >/dev/null 2>&1
grep -q "\.\.\.${GK: -4}" "$rep" && ok "a standalone Google key is still found" || no "standalone key lost"
grep -q "\.\.\.${GEM: -4}" "$rep" && ok "the newer Gemini shape (AQ.) is found" || no "AQ. key missed"
grep -q "\.\.\.${GK2: -4}" "$rep" && ok "a nearby word 'attachment' does not hide a key" || no "key hidden by a nearby word"
grep -q "\.\.\.4xyz" "$rep" && ok "a key right after an escaped newline is found" || no "key after newline missed"
GH="ghp_$(printf 'Q1w2E3r4%.0s' 1 2 3 4)T5y6"
entry "git clone https://$GH@example.com/org/repo.git" > "$R/s6.jsonl"; run scan >/dev/null 2>&1
grep -q "\.\.\.T5y6" "$rep" && ok "a token inside an authenticated URL is found" || no "URL token missed"

entry "diff:\\n+$HDR\\n+b3BlbnNzaC1rZXk" > "$R/s7.jsonl"; before=$(grep -c "private key" "$rep" || true); run scan >/dev/null 2>&1
after=$(grep -c "private key" "$rep" || true)
[ "$after" -gt "$before" ] && ok "a private key shown in a diff line is found" || no "diff-line key header missed"

DK="ghp_$(printf 'L1k2J3h4%.0s' 1 2 3 4)G5f6"
entry "+$DK" > "$R/s8.jsonl"; run scan >/dev/null 2>&1
grep -q "\.\.\.G5f6" "$rep" && ok "a token on a diff addition line is found" || no "diff-line token missed"
RK="ghp_$(printf 'P1o2I3u4%.0s' 1 2 3 4)Y5t6"
entry "-$RK" > "$R/s9.jsonl"; run scan >/dev/null 2>&1
grep -q "\.\.\.Y5t6" "$rep" && ok "a token on a diff removal line is found" || no "removal-line token missed"

echo "── ack and notify ──"
id=$(grep "Anthropic API key" "$rep" | head -1 | cut -d'|' -f2 | tr -d ' ')
run ack "$id" >/dev/null 2>&1; run scan >/dev/null 2>&1
grep -q "| $id |" "$rep" && no "acked value still listed" || ok "acked value stops counting"
printf '#!/bin/sh\necho "$1" >> "%s/notified.log"\n' "$T" > "$T/n.sh"; chmod +x "$T/n.sh"
run scan --notify "$T/n.sh" >/dev/null 2>&1
run scan --notify "$T/n.sh" >/dev/null 2>&1
[ "$(wc -l < "$T/notified.log" | tr -d ' ')" = "1" ] && ok "notify ran once" || no "notify count" "$(cat "$T/notified.log" 2>/dev/null)"
grep -q "$AWS" "$T/notified.log" && no "notify carried a value" || ok "notify message has no value"

echo
echo "transcript-secret-scan: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
