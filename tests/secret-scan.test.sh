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
blocks "GitHub OAuth token (gho_)" "tok = gho$(printf %s _)$(printf %s AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA)"
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

echo "── 5. a DIRECTORY argument is scanned recursively (aios-commit stages whole trees) ──"
mkdir -p "$TMP/tree/deeper"
printf 'clean\n' > "$TMP/tree/ok.txt"
printf 'sec = GOCSPX%s%s\n' "$DASH" "$A" > "$TMP/tree/deeper/leak.txt"
out=$("$SCAN" "$TMP/tree" 2>&1 >/dev/null); rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "BLOCKED" && printf '%s' "$out" | grep -q "deeper/leak.txt" && ok "secret inside a directory argument is caught and named" || no "directory argument passed" "a whole subtree entered the commit unscanned (exit=$rc)"
mkdir -p "$TMP/cleantree" && printf 'nothing here\n' > "$TMP/cleantree/a.txt"
"$SCAN" "$TMP/cleantree" >/dev/null 2>&1
[ $? -eq 0 ] && ok "clean directory argument passes" || no "clean directory blocked" "false positive on a directory"

echo "── 6. directory edge cases: leading dash, newline in a filename, symlinks, ignored files ──"
# A blocked run and a FAILED enumeration both exit 1, so "non-zero" alone would let the
# dash case pass for the wrong reason (name read as an option → fail-closed → 1). Require
# the detection diagnostic naming the file, and require a clean '-cleandash' to pass.
mkdir -p "$TMP/edge/-dashdir"
printf 'sec = GOCSPX%s%s\n' "$DASH" "$A" > "$TMP/edge/-dashdir/leak.txt"
out=$( cd "$TMP/edge" && "$SCAN" -dashdir 2>&1 >/dev/null ); rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "BLOCKED" && printf '%s' "$out" | grep -q "leak.txt" \
  && ok "directory whose name starts with '-' is scanned (diagnostic names the file)" \
  || no "'-dashdir' not detected as a leak" "exit=$rc; first line: $(printf '%s' "$out" | head -1)"
mkdir -p "$TMP/edge/-cleandash" && printf 'clean\n' > "$TMP/edge/-cleandash/ok.txt"
( cd "$TMP/edge" && "$SCAN" -cleandash >/dev/null 2>&1 ); [ $? -eq 0 ] && ok "clean directory whose name starts with '-' passes" || no "clean '-cleandash' blocked" "enumeration failed closed on the name"
mkdir -p "$TMP/nl" && printf 'sec = GOCSPX%s%s\n' "$DASH" "$A" > "$TMP/nl/leak
.txt"
out=$("$SCAN" "$TMP/nl" 2>&1 >/dev/null); rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "BLOCKED" && ok "filename containing a newline is still scanned" || no "newline filename passed" "the path split in two and both halves were dropped (exit=$rc)"
# git commits a symlink as its link TEXT (mode 120000), so a token in a link target lands in the repo.
# Every positive case requires BLOCKED plus the link's name: an enumeration error also exits 1.
mkdir -p "$TMP/sym" && ln -s "GOCSPX${DASH}${A}" "$TMP/sym/leaklink"
out=$("$SCAN" "$TMP/sym" 2>&1 >/dev/null); rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "BLOCKED" && printf '%s' "$out" | grep -q "symlink .*leaklink" && ok "a symlink under a directory whose target text is a secret is caught and named" || no "symlink target passed" "git stores the link text verbatim (exit=$rc)"
out=$("$SCAN" "$TMP/sym/leaklink" 2>&1 >/dev/null); rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "BLOCKED" && printf '%s' "$out" | grep -q "symlink .*leaklink" && ok "a symlink passed as a direct ARGUMENT is scanned by its link text" || no "direct symlink argument passed" "exit=$rc"
mkdir -p "$TMP/edge2" && ln -s "GOCSPX${DASH}${A}" "$TMP/edge2/-link"
out=$( cd "$TMP/edge2" && "$SCAN" -link 2>&1 >/dev/null ); rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "BLOCKED" && printf '%s' "$out" | grep -q "symlink .*-link" && ok "a symlink whose name starts with '-' is read (readlink not handed an option)" || no "'-link' passed" "readlink read the name as an option and the failure was swallowed (exit=$rc)"
mkdir -p "$TMP/sym2/real" && printf 'clean\n' > "$TMP/sym2/real/a.txt" && ln -s real "$TMP/sym2/linkdir"
"$SCAN" "$TMP/sym2" >/dev/null 2>&1; [ $? -eq 0 ] && ok "a benign symlink to a directory does not block" || no "benign symlink blocked" "false positive on link text"
printf 'sec = GOCSPX%s%s\n' "$DASH" "$A" > "$TMP/sym2/real/secret.txt"
"$SCAN" "$TMP/sym2/linkdir" >/dev/null 2>&1; [ $? -eq 0 ] && ok "a symlink-to-directory ARGUMENT scans its link text, not the tree behind it" || no "symlink-to-dir argument scanned the target tree" "git would commit only the link text"
# Line N of the links file must be link N: a target with a newline before the token, with a
# later benign link, must still be attributed to the right link (and not shift the mapping).
mkdir -p "$TMP/sym3" && ln -s "$(printf 'x\nGOCSPX%s%s' "$DASH" "$A")" "$TMP/sym3/nlink" && ln -s clean "$TMP/sym3/zlast"
out=$("$SCAN" "$TMP/sym3" 2>&1 >/dev/null); rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "BLOCKED" && printf '%s' "$out" | grep -q "symlink .*nlink" && ! printf '%s' "$out" | grep -q "unbound" && ok "a link target containing a newline is caught and attributed to the right link" || no "newline in link target" "mapping shifted or unbound variable (exit=$rc)"
# Only the link TARGET is git content: a checkout that itself lives under a token-shaped
# directory must not turn every benign link into a hit.
mkdir -p "$TMP/GOCSPX${DASH}${A}/repo/real" && ln -s real "$TMP/GOCSPX${DASH}${A}/repo/linkdir"
"$SCAN" "$TMP/GOCSPX${DASH}${A}/repo" >/dev/null 2>&1; [ $? -eq 0 ] && ok "a benign link under a token-shaped path is not a false positive (link path is not scanned)" || no "link path scanned" "the link's own absolute path tripped the pattern"
if command -v git >/dev/null 2>&1; then
  R="$TMP/repo"; mkdir -p "$R/dir" && git -C "$R" init -q . && printf '.env\n' > "$R/.gitignore"
  printf 'sec = GOCSPX%s%s\n' "$DASH" "$A" > "$R/dir/.env"        # ignored: never enters a commit
  printf 'clean\n' > "$R/dir/ok.txt"
  ( cd "$R" && "$SCAN" dir >/dev/null 2>&1 ); [ $? -eq 0 ] && ok "an ignored file under the directory does not block" || no "ignored .env blocked the commit" "git would never add it"
  printf 'sec = GOCSPX%s%s\n' "$DASH" "$A" > "$R/dir/tracked.txt"
  out=$( cd "$R" && "$SCAN" dir 2>&1 >/dev/null ); rc=$?
  [ $rc -ne 0 ] && printf '%s' "$out" | grep -q "BLOCKED" && printf '%s' "$out" | grep -q "dir/tracked.txt" && ok "an untracked, non-ignored file under the directory is caught and named" || no "untracked leak passed" "git add --all would stage it (exit=$rc)"
else
  echo "  skip  git not on PATH — repo-scoped enumeration not exercised"
fi

# --- size cap: files over the cap are scanned as text, NAMED, and a text token still blocks ----
C=$(mktemp -d "${TMPDIR:-/tmp}/ss-cap.XXXXXX")
printf 'plain text with ghp_%s inside\n' "$(printf 'a%.0s' $(seq 36))" > "$C/text.md"
printf 'nothing here\n' > "$C/clean.md"
out=$(AIOS_SECRET_SCAN_CAP_MB=0 bash "$SCAN" "$C/text.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -c 'scanned as text only' >/dev/null && ok "over the cap: a text token still blocks, and the file is named as text-only" || no "over-cap scan did not block or did not name the file" "rc=$rc $out"
out=$(AIOS_SECRET_SCAN_CAP_MB=0 bash "$SCAN" "$C/clean.md" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "over the cap: a clean file passes" || no "over-cap clean file refused" "rc=$rc $out"
# many hits must read as BLOCKED, never as a failed scan: once grep's output overflowed the pipe
# buffer, `| head -3` exited, grep died of SIGPIPE (141) under pipefail, and a real hit was reported
# as "FAILED to scan" (measured with ~1.3 MB of matching lines)
L="ghp_$(printf 'b%.0s' $(seq 36)) $(printf 'x%.0s' $(seq 400))"
for i in $(seq 1 3000); do printf '%s\n' "$L"; done > "$C/many.md"
out=$(bash "$SCAN" "$C/many.md" 2>&1); rc=$?
printf '%s' "$out" | grep -c 'BLOCKED' >/dev/null && ! printf '%s' "$out" | grep -c 'FAILED to scan' >/dev/null && ok "~1.3 MB of hits → BLOCKED, not 'FAILED to scan' (grep SIGPIPE)" || no "many hits misreported" "$out"
rm -rf "$C"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
