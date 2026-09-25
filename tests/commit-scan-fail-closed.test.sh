#!/usr/bin/env bash
# tests/commit-scan-fail-closed.test.sh
#
# Four ways a commit went through with a check that never ran, each reproduced against the
# previous code (fetched with `git show` from the commit this branch starts at) and then
# refused by the current one:
#   1. aios-commit scanned the files but not the commit MESSAGE — a token in `-m` went in.
#   2. `[ -x "$SCAN" ] &&` in aios-commit and pre-commit: a missing scanner = an unscanned pass.
#   3. `grep -I` in secret-scan.sh skipped a file with a NUL byte, token and all.
#   4. `aios-commit --vault` sent the sweep's git errors to /dev/null; a failed sweep printed
#      "no vault changes to commit", exit 0.
#
# The fake token is assembled at runtime from a split prefix, so no secret-shaped literal lives
# in this file (it would trip push protection and the scan itself).
#
# Run:  bash tests/commit-scan-fail-closed.test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/csfc.XXXXXX"); trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
TOKEN="gh""p_$(printf 'A%.0s' $(seq 1 36))"

# a hooks/ tree to run: "new" = this checkout; "old" = the same files before this change
mkhooks(){ # $1 dest  $2 source ("new" or a git ref)
  mkdir -p "$1/git"
  for f in aios-commit git/secret-scan.sh git/pre-commit; do
    if [ "$2" = new ]; then cp "$ROOT/hooks/$f" "$1/$f"; else git -C "$ROOT" show "$2:hooks/$f" > "$1/$f"; fi
    chmod +x "$1/$f"
  done
}
# The "old" hooks are pinned to the last commit before this change — never a moving ref like
# main: once this change is merged, main's hooks ARE the new ones, and asserting that they still
# show the defects would fail a correct tree. If the pinned commit is not in this checkout, or its
# hooks turn out identical to the current ones, the old-side reproductions are skipped (said, not
# silent) and the NEW-side checks still gate.
BASE=${BASE_REF:-3d135ded112bf7b77156b61bb29e6233ff7c7285}
mkhooks "$TMP/new" new
HAVE_OLD=0
if git -C "$ROOT" cat-file -e "$BASE:hooks/aios-commit" 2>/dev/null; then
  mkhooks "$TMP/old" "$BASE"
  cmp -s "$TMP/old/aios-commit" "$TMP/new/aios-commit" || HAVE_OLD=1
fi
newrepo(){ local d="$1"; rm -rf "$d"; mkdir -p "$d"; git -C "$d" init -q; git -C "$d" config user.email t@t.io; git -C "$d" config user.name t
           git -C "$d" config core.hooksPath /dev/null; echo x > "$d/f"; git -C "$d" add f; git -C "$d" commit -qm init; }
commits(){ git -C "$1" rev-list --count HEAD; }

printf 'commits and the scanner fail closed\n'

# ---------------------------------------------------------------------------------------------
# 1. the message is scanned
# ---------------------------------------------------------------------------------------------
for v in old new; do
  [ "$v" = old ] && [ "$HAVE_OLD" = 0 ] && continue
  R="$TMP/r1-$v"; newrepo "$R"; echo y > "$R/f"
  ( cd "$R" && "$TMP/$v/aios-commit" --no-push -m "fix: rotate $TOKEN" -- f >/dev/null 2>&1 ); n=$(commits "$R")
  if [ "$v" = old ]; then [ "$n" = 2 ] && ok "1o. OLD: a token in the message was committed (the defect, reproduced)" || no "1o. old code unexpectedly refused"
  else [ "$n" = 1 ] && ok "1n. NEW: a token in the message is refused" || no "1n. token in the message was committed"; fi
done
R="$TMP/r1c"; newrepo "$R"; echo y > "$R/f"
( cd "$R" && "$TMP/new/aios-commit" --no-push -m "fix: ordinary message" -- f >/dev/null 2>&1 ); [ "$(commits "$R")" = 2 ] && ok "1c. an ordinary message still commits" || no "1c. a clean commit was refused"

# ---------------------------------------------------------------------------------------------
# 2. a missing scanner refuses (aios-commit and pre-commit); a scanner without +x still runs
# ---------------------------------------------------------------------------------------------
for v in old new; do
  [ "$v" = old ] && [ "$HAVE_OLD" = 0 ] && continue
  H="$TMP/h2-$v"; rm -rf "$H"; cp -R "$TMP/$v" "$H"; rm -f "$H/git/secret-scan.sh"
  R="$TMP/r2-$v"; newrepo "$R"; printf '%s\n' "$TOKEN" > "$R/f"
  ( cd "$R" && "$H/aios-commit" --no-push -m "x" -- f >/dev/null 2>&1 ); n=$(commits "$R")
  if [ "$v" = old ]; then [ "$n" = 2 ] && ok "2o. OLD: no scanner → a token was committed unscanned (the defect, reproduced)" || no "2o. old code unexpectedly refused"
  else [ "$n" = 1 ] && ok "2n. NEW: no scanner → refused" || no "2n. committed with no scanner"; fi
  ( cd "$R" && AIOS_HUMAN=1 bash "$H/git/pre-commit" >/dev/null 2>&1 ); rc=$?
  if [ "$v" = old ]; then [ "$rc" = 0 ] && ok "2po. OLD pre-commit: no scanner → exit 0 (the defect, reproduced)" || no "2po. old pre-commit unexpectedly refused"
  else [ "$rc" != 0 ] && ok "2pn. NEW pre-commit: no scanner → refused" || no "2pn. pre-commit passed with no scanner"; fi
done
H="$TMP/h2x"; rm -rf "$H"; cp -R "$TMP/new" "$H"; chmod -x "$H/git/secret-scan.sh"
R="$TMP/r2x"; newrepo "$R"; printf '%s\n' "$TOKEN" > "$R/f"
( cd "$R" && "$H/aios-commit" --no-push -m "x" -- f >/dev/null 2>&1 ); [ "$(commits "$R")" = 1 ] && ok "2x. a scanner that lost +x still scans (and blocks the token)" || no "2x. scanner without +x was skipped"
# the same for the pre-commit hook (a human commit with AIOS_HUMAN=1): scanner present, no +x
R="$TMP/r2px"; newrepo "$R"; printf '%s\n' "$TOKEN" > "$R/g"; git -C "$R" add g
out=$(cd "$R" && AIOS_HUMAN=1 bash "$H/git/pre-commit" 2>&1); rc=$?
{ [ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'BLOCKED'; } && ok "2px. pre-commit with a scanner that lost +x still scans (and blocks a staged token)" || no "2px. pre-commit skipped a non-executable scanner" "rc=$rc out=$out"
R="$TMP/r2py"; newrepo "$R"; echo clean > "$R/g"; git -C "$R" add g
( cd "$R" && AIOS_HUMAN=1 bash "$H/git/pre-commit" >/dev/null 2>&1 ); [ $? = 0 ] && ok "2py. …and lets a clean staged file through" || no "2py. pre-commit refused a clean staged file"
R="$TMP/r2y"; newrepo "$R"; echo clean > "$R/f"
( cd "$R" && "$H/aios-commit" --no-push -m "x" -- f >/dev/null 2>&1 ); [ "$(commits "$R")" = 2 ] && ok "2y. …and lets a clean commit through" || no "2y. clean commit refused with a non-executable scanner"

# ---------------------------------------------------------------------------------------------
# 3. a NUL byte does not hide a token
# ---------------------------------------------------------------------------------------------
F="$TMP/nul.bin"; printf 'x\0y\n%s\n' "$TOKEN" > "$F"
bash "$TMP/new/git/secret-scan.sh" "$F" >/dev/null 2>&1; [ $? = 1 ] && ok "3n. NEW: a token next to a NUL byte is blocked" || no "3n. the NUL-byte file passed"
if [ "$HAVE_OLD" = 1 ]; then bash "$TMP/old/git/secret-scan.sh" "$F" >/dev/null 2>&1; [ $? = 0 ] && ok "3o. OLD: grep -I passed it (the defect, reproduced)" || no "3o. old scanner unexpectedly blocked"; fi
printf 'x\0y\nnothing here\n' > "$TMP/nul-clean.bin"
bash "$TMP/new/git/secret-scan.sh" "$TMP/nul-clean.bin" >/dev/null 2>&1; [ $? = 0 ] && ok "3c. a binary file without a token still passes" || no "3c. clean binary blocked"

# ---------------------------------------------------------------------------------------------
# 4. a --vault sweep that cannot read the repo refuses instead of reporting "no changes"
# ---------------------------------------------------------------------------------------------
# A git shim on PATH delegates every call to the real git, except the ONE sweep call named by
# $FAIL_ON, which fails with 128. No permissions trick: it works as root and on Windows, and it
# fails each sweep call on its own, so each sentinel is proven separately.
REAL_GIT=$(command -v git)
SHIM="$TMP/shim"; mkdir -p "$SHIM"
cat > "$SHIM/git" <<SHIMEOF
#!/usr/bin/env bash
case "\${FAIL_ON:-} \$*" in
  "diff "*"diff --name-only HEAD -- vault/"*)                  echo "fatal: simulated diff failure" >&2; exit 128 ;;
  "ls "*"ls-files --others --exclude-standard -- vault/"*)      echo "fatal: simulated ls-files failure" >&2; exit 128 ;;
esac
exec "$REAL_GIT" "\$@"
SHIMEOF
chmod +x "$SHIM/git"
mkvault(){ newrepo "$1"; mkdir -p "$1/vault"; echo n > "$1/vault/n.md"; git -C "$1" add vault; git -C "$1" commit -qm v; }
for which in diff ls; do
  R="$TMP/r4-$which"; mkvault "$R"
  [ "$which" = diff ] && echo m >> "$R/vault/n.md" || echo new > "$R/vault/new.md"
  out=$(cd "$R" && FAIL_ON=$which PATH="$SHIM:$PATH" "$TMP/new/aios-commit" --vault --no-push -m "x" 2>&1); rc=$?
  { [ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'could not read the repo' && [ "$(commits "$R")" = 2 ]; } \
    && ok "4$which. NEW: the sweep's $which call fails → refused, named, nothing committed" || no "4$which. NEW: failed $which call misread" "rc=$rc out=$out"
  if [ "$HAVE_OLD" = 1 ]; then
    out=$(cd "$R" && FAIL_ON=$which PATH="$SHIM:$PATH" "$TMP/old/aios-commit" --vault --no-push -m "x" 2>&1); rc=$?
    if [ "$which" = diff ]; then
      # old: the failed diff yields no paths; the status cross-check then blames a desynced index
      # ("do not differ from HEAD") — exit 0, nothing committed, and no word that git failed
      { [ "$rc" = 0 ] && [ "$(commits "$R")" = 2 ] && ! printf '%s' "$out" | grep -qi 'fail'; } \
        && ok "4${which}o. OLD: a failed diff exited 0 with nothing committed and no mention of the failure (the defect, reproduced)" || no "4${which}o. old code did not show the defect" "rc=$rc out=$out"
    else
      { [ "$rc" = 0 ] && [ "$(commits "$R")" = 2 ] && ! printf '%s' "$out" | grep -qi 'fail'; } \
        && ok "4${which}o. OLD: a failed ls-files exited 0, left the new file out, and never mentioned the failure (the defect, reproduced)" || no "4${which}o. old code did not show the defect" "rc=$rc out=$out"
    fi
  fi
done
R="$TMP/r4ok"; mkvault "$R"; echo m >> "$R/vault/n.md"
out=$(cd "$R" && PATH="$SHIM:$PATH" "$TMP/new/aios-commit" --vault --no-push -m "x" 2>&1); [ "$(commits "$R")" = 3 ] && ok "4c. with nothing failing, the sweep commits as before (shim in place)" || no "4c. the sweep did not commit" "$out"

# a repo with no commits yet: `git diff HEAD` has no HEAD, so the sweep must read the staged paths
E=$(mktemp -d "${TMPDIR:-/tmp}/csfc-empty.XXXXXX"); git -C "$E" init -q; mkdir -p "$E/vault"; echo hi > "$E/vault/a.md"
( cd "$E" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false "$ROOT/hooks/aios-commit" --vault --no-push -m first >/dev/null 2>&1 )
[ "$(git -C "$E" rev-list --count HEAD 2>/dev/null)" = 1 ] && ok "--vault makes the first commit in a repo with no commits yet" || no "--vault refused the first commit of an empty repo" "the sweep read a failed 'git diff HEAD' as a failed measurement"
rm -rf "$E"
[ "$HAVE_OLD" = 1 ] || printf '  skip  old-code reproductions: the pinned pre-change commit is not in this checkout, or its hooks equal the current ones (set BASE_REF to run them)\n'
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
