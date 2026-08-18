#!/usr/bin/env bash
# tests/secret-scan.test.sh
#
# Guards hooks/git/secret-scan.sh — the commit-time credential block.
#
# WHAT THIS IS PROTECTING
# -----------------------
# secret-scan.sh is the last thing between a credential and the remote, and it is called
# from two places: the pre-commit hook (porcelain commits) and aios-commit's self-scan
# (plumbing commits bypass hooks entirely, so the scanner must be invoked directly). A
# pattern silently missing from the list is invisible in normal use — the scanner exits 0,
# the commit succeeds, and nothing anywhere reports that a class of secret is unguarded.
# There is no failure state to observe: a scanner that catches nothing and a repository
# with no secrets produce identical output.
#
# So the coverage has to be asserted, one case per credential class. Each assertion below
# corresponds to exactly one entry in PATTERNS, and adding a pattern without adding its
# case here re-opens the same silent gap.
#
# FAKE CREDENTIALS ARE BUILT AT RUNTIME, NEVER WRITTEN LITERALLY.
# A literal secret-shaped string in this file would make the file itself unstageable by
# the very scanner it tests — the guard would block its own guard. Every probe below is
# assembled from fragments that individually match nothing.
#
# Run:  bash tests/secret-scan.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="$ROOT/hooks/git/secret-scan.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/secret-scan-test.XXXXXX"); trap 'rm -rf "$TMP"' EXIT

A=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA        # 40 filler chars
H=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa        # 40 hex filler
DASH=$(printf -- -)

# blocks <name> <probe-string>  — the scanner must exit non-zero on a file containing it
blocks(){
  printf 'harmless line\n%s\nanother line\n' "$2" > "$TMP/probe.txt"
  "$SCAN" "$TMP/probe.txt" >/dev/null 2>&1
  [ $? -ne 0 ] && ok "$1" || no "$1" "scanner exited 0 — this credential class is UNGUARDED"
}

echo "── 1. every PATTERNS entry has a live assertion ──"
blocks "Anthropic API key"        "key = sk${DASH}ant${DASH}api03${DASH}$A"
blocks "AWS access key id"        "id  = AKIA$(printf %s AAAAAAAAAAAAAAAA)"
blocks "private key header"       "$(printf -- '-----BEGIN RSA PRIVATE')$(printf -- ' KEY-----')"
blocks "GitHub PAT (classic)"     "tok = ghp$(printf %s _)$(printf %s AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA)"
blocks "GitHub PAT (fine)"        "tok = github_pat_${A}${A}"
blocks "Slack token"              "tok = xoxb${DASH}${A}"
blocks "Google API key"           "key = AIza${A}"
blocks "GitLab PAT"               "tok = glpat${DASH}${A}"
blocks "Google OAuth secret"      "sec = GOCSPX${DASH}${A}"
blocks "launchd plist 40-hex tok" "<string>${H}</string>"

echo "── 2. clean input is not blocked (no false positive) ──"
printf 'ordinary prose about tokens, keys and secrets\nGOCSPX is a prefix\n' > "$TMP/clean.txt"
"$SCAN" "$TMP/clean.txt" >/dev/null 2>&1
[ $? -eq 0 ] && ok "benign file passes" || no "benign file blocked" "false positive"

echo "── 3. no-input is not an error ──"
"$SCAN" "$TMP/does-not-exist.txt" >/dev/null 2>&1
[ $? -eq 0 ] && ok "absent path exits 0" || no "absent path exits non-zero"

echo "── 4. a blocked run names the offending line ──"
printf 'a\nsec = GOCSPX%s%s\nb\n' "$DASH" "$A" > "$TMP/loud.txt"
out=$("$SCAN" "$TMP/loud.txt" 2>&1 >/dev/null)
printf '%s' "$out" | grep -q "GOCSPX" && ok "error output quotes the match" || no "error output does not show what matched"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
