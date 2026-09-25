#!/usr/bin/env bash
# tests/housekeeping-checks-that-cannot-fail.test.sh
#
# Three checks in /aios:housekeeping had a single reachable answer:
#   1. Bucket 18 compared a 7-char vendored hash with the 40-char sha the API returns by
#      string equality — every source "behind", always.
#   2. Bucket 22's duplicate-frontmatter scan ran through `python3` (nothing on Windows,
#      silence reads as clean) and printed nothing on an empty glob.
#   3. Bucket 13 skipped "already graduated" patterns by a phrase that is not a substring
#      of the mark it writes — so nothing was ever skipped.
#
# Run:  bash tests/housekeeping-checks-that-cannot-fail.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="$ROOT/plugins/aios/commands/housekeeping.md"
PASS=0; FAIL=0; SKIP=0
ok(){ PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
sk(){ SKIP=$((SKIP+1)); printf '  skip  %s\n' "$1"; }
have(){ [ "$1" = "$2" ] && ok "$3" || no "$3" "got [$1], wanted [$2]"; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/hkc.XXXXXX"); trap 'rm -rf "$TMP"' EXIT

printf '/aios:housekeeping — three checks that could not fail\n'

# ---------------------------------------------------------------------------
# 1. upstream freshness: prefix compare, in the exact shape the spec prescribes
# ---------------------------------------------------------------------------
# The compare is EXTRACTED from the spec (the one backticked `case … esac` in Bucket 18) and
# eval'd, so the test runs what the command prescribes — not a copy that could drift from it.
CASE=$(grep -oE 'case "\$upstream" in "\$local"\*\) [a-z_]+=current ;; \*\) [a-z_]+=behind ;; esac' "$SPEC" | head -1)
[ -n "$CASE" ] && ok "1-. the prefix compare is extracted from the spec: [$CASE]" || no "1-. could not extract the prefix compare from Bucket 18"
VAR=$(printf '%s' "$CASE" | sed -E 's/.*\) ([a-z_]+)=current.*/\1/')
status_of(){ local local="$1" upstream="$2"; eval "$CASE"; eval "printf '%s' \"\$$VAR\""; }
FULL="1f20bef0c0ffee1234567890abcdef1234567890"
have "$(status_of 1f20bef "$FULL")" "current" "1a. 7-char vendored hash that prefixes the upstream sha → current"
have "$(status_of 1f20bee "$FULL")" "behind"  "1b. a different 7-char hash → behind (fails if the spec's behind branch is mutated)"
have "$(status_of "$FULL" "$FULL")" "current" "1c. a full 40-char hash still compares equal"
old=$([ "1f20bef" = "$FULL" ] && echo current || echo behind)
have "$old" "behind" "1d. string equality on that same pair says behind (the defect, reproduced)"
[ "$VAR" = status ] && no "1e. the spec assigns \`status\`, read-only in zsh" || ok "1e. the spec's variable (\`$VAR\`) is not a zsh read-only name"
if command -v zsh >/dev/null 2>&1; then
  Z=$(zsh -c 'local=1f20bef; upstream="'"$FULL"'"; '"$CASE"'; printf "%s" "$'"$VAR"'"' 2>&1)
  have "$Z" "current" "1z. the same case runs under zsh (the session shell) and answers current"
else
  sk "1z. zsh unavailable — cannot prove the compare runs in the session shell"
fi
grep -q 'If equal → mark `current`' "$SPEC" && no "1f. spec: the equality wording is still there" || ok "1f. spec: the equality wording is gone"

# ---------------------------------------------------------------------------
# 2. duplicate-frontmatter scan: uv, and a count that makes an empty glob visible
# ---------------------------------------------------------------------------
have "$(grep -c "^python3 - <<'PY'" "$SPEC")" "0" "2a. spec: no inline python3 heredoc left"
grep -q "uv run - <<'PY'" "$SPEC" && ok "2b. spec: the scan runs through uv" || no "2b. spec: the scan does not run through uv"
SCRIPT=$(awk "/uv run - <<'PY'/{f=1;next} f&&/^PY\$/{exit} f" "$SPEC")
[ -n "$SCRIPT" ] && ok "2c. scan script extracted from the spec" || no "2c. could not extract the scan script"
printf '%s\n' "$SCRIPT" | grep -q 'print("checked %d file(s)" % len(files))' && ok "2d. the script always ends with a count" || no "2d. the script can still end silently"
if command -v uv >/dev/null 2>&1; then
  mkdir -p "$TMP/home/aios/vault/00 - notes/context/observed"
  printf -- '---\nupdated: 1\nupdated: 2\n---\nx\n' > "$TMP/home/aios/vault/00 - notes/context/observed/dupe.md"
  # HOME for POSIX Python; USERPROFILE for a native Windows Python, whose expanduser("~")
  # ignores HOME — without it, on Git Bash the scan would read the operator's real vault.
  FH="$TMP/home"; case "$OSTYPE" in msys*|cygwin*) FH=$(cygpath -w "$TMP/home" 2>/dev/null || printf '%s' "$TMP/home") ;; esac
  out=$(HOME="$TMP/home" USERPROFILE="$FH" UV_CACHE_DIR="${TMPDIR:-/tmp}/uv-cache" uv run - <<<"$SCRIPT" 2>/dev/null | tr -d '\r')   # CRLF-safe: a native Windows Python writes CRLF
  printf '%s' "$out" | grep -qE 'DUPLICATE KEY: observed[/\\]dupe.md -> updated' && ok "2e. run through uv: a duplicate key is reported" || no "2e. run through uv: duplicate key NOT reported" "$out"
  printf '%s' "$out" | grep -q 'checked 1 file(s)' && ok "2f. …and the count line names how many files were read" || no "2f. count line missing" "$out"
  rm -f "$TMP/home/aios/vault/00 - notes/context/observed/dupe.md"
  out=$(HOME="$TMP/home" USERPROFILE="$FH" UV_CACHE_DIR="${TMPDIR:-/tmp}/uv-cache" uv run - <<<"$SCRIPT" 2>/dev/null | tr -d '\r')
  have "$out" "checked 0 file(s)" "2g. an empty folder says so instead of printing nothing"
else
  sk "2e-2g. uv not installed here — runtime half of the scan check cannot run"
fi

# ---------------------------------------------------------------------------
# 3. graduation: the skip phrase must be a substring of the mark that is written
# ---------------------------------------------------------------------------
# WRITTEN comes from the instruction that WRITES the mark (the blockquoted line under step 3),
# never from prose that merely quotes it — otherwise the check compares the skip phrase with
# its own explanation and passes whatever the writing step says.
WRITTEN=$(grep -E '^ *> \*\*→ Graduated to USER.md' "$SPEC" | sed -E 's/^ *> \*\*(.*)\*\* *$/\1/' | head -1)
[ -n "$WRITTEN" ] && ok "3a. the written graduation mark is read from the writing step: [$WRITTEN]" || no "3a. could not find the blockquoted line that writes the mark"
SKIPPHRASE=$(grep -oE 'already carries a `[^`]*` flag' "$SPEC" | sed -E 's/already carries a `([^`]*)` flag/\1/' | head -1)
[ -n "$SKIPPHRASE" ] && ok "3b. the skip phrase is stated in the spec: [$SKIPPHRASE]" || no "3b. could not find the skip phrase"
case "$WRITTEN" in *"$SKIPPHRASE"*) ok "3c. the skip phrase IS a substring of the written mark" ;; *) no "3c. the skip phrase is not a substring of the written mark" ;; esac
case "$WRITTEN" in *"→ Graduated to USER.md on YYYY-MM-DD"*) no "3d. the old phrase would have matched (test is vacuous)" ;; *) ok "3d. the old skip phrase does NOT match the written mark (the defect, reproduced)" ;; esac

printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
