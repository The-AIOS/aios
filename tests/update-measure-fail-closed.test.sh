#!/usr/bin/env bash
# tests/update-measure-fail-closed.test.sh
#
# Guards four places where /aios:update turned a FAILED measurement into a
# confident verdict — each one silent, each one ending in an overwrite, a
# dropped ignore rule, or a "0 drift" that examined nothing.
#
#   1. h_file / h_git returned rc=0 with an EMPTY hash when `shasum` was
#      missing (the status of a pipeline is its last command, `cut`). Empty
#      LOCAL == empty BASE == "identical" == overwrite silently, no backup.
#   2. The legacy .gitignore migration re-ordered the operator's rules
#      (`sort -u` + `comm`), so a `!exception` line sorted ABOVE the pattern
#      it excepts and stopped working — git reads the last matching rule.
#   3. `{ cat canonical; awk operator; } > new && mv` took awk's exit status,
#      so an unreadable canonical .gitignore installed a file holding only the
#      operator's lines.
#   4. `diff -rq vault/x clone/x 2>/dev/null` with vault/x MISSING prints to
#      stderr only (exit 2) — dropped by the redirect and by the trailing
#      `|| true` — so a bundled folder absent from the vault read as clean.
#
# Each test runs the shape the spec now prescribes AND the shape it replaced,
# so a case that cannot fail is caught as such.
#
# Run:  bash tests/update-measure-fail-closed.test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="$ROOT/plugins/aios/commands/update.md"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
have(){ [ "$1" = "$2" ] && ok "$3" || no "$3" "got [$1], wanted [$2]"; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ufc.XXXXXX"); trap 'rm -rf "$TMP"' EXIT

printf '/aios:update — failed measurements fail CLOSED\n'

# ---------------------------------------------------------------------------
# 1. hash helpers, transcribed from § Backup-on-divergence.
# ---------------------------------------------------------------------------
CLONE="$TMP/clone"; git init -q "$CLONE"; ( cd "$CLONE" && printf 'a\r\nb\n' > f && git add f && git -c user.email=t@t -c user.name=t commit -q -m i )

h_file_old(){ [ -f "$1" ] || return 1; tr -d '\r' < "$1" | shasum -a 256 | cut -d' ' -f1; }
# The helpers under test are EXTRACTED FROM THE SPEC, not transcribed — so a regression in
# update.md itself fails here. Each is a `name(){ … }` block whose last line ends in `}`.
# `h_file` is defined twice in the spec (backup compare, self-update compare); both copies are
# extracted and eval'd in order, so the LAST one is what runs — a stale second copy fails 1c/1e.
extract(){ awk -v n="$1" '$0 ~ "^"n"\\(\\)\\{" {f=1} f{print} f && /\}$/ {f=0}' "$SPEC"; }
HF=$(extract h_file); HG=$(extract h_git)
[ -n "$HF" ] && [ -n "$HG" ] && ok "1a'. h_file and h_git extracted from the spec" || no "1a'. could not extract the hash helpers from the spec" "anchors moved"
eval "$HF"; eval "$HG"
a=$(h_file "$CLONE/f"); b=$(h_git "HEAD:f")
have "$a" "$b" "1a. spec helpers: file and object hash equal (CRLF-normalized), shasum present"
# simulate a machine without shasum: a function that fails like a missing command
shasum(){ echo "shasum: command not found" >&2; return 127; }
# the session shell that runs the spec has NO pipefail — reproduce the defect under that shell
r_old=$( set +o pipefail; h_file_old "$CLONE/f" 2>/dev/null; echo ":rc=$?" )
have "$r_old" ":rc=0"    "1b. OLD h_file: shasum missing → rc 0 and an empty hash (the defect, reproduced)"
r_new=$( set +o pipefail; h_file "$CLONE/f" 2>/dev/null; echo ":rc=$?" )
have "$r_new" ":rc=1"    "1c. spec h_file: shasum missing → non-zero, no hash to compare"
r_git=$( set +o pipefail; h_git "HEAD:f" 2>/dev/null; echo ":rc=$?" )
have "$r_git" ":rc=1"    "1d. spec h_git: shasum missing → non-zero"
unset -f shasum
# a shasum that is PRESENT but emits nothing (rc 0) — only the empty-hash refusal catches this
shasum(){ :; }
r_e=$( set +o pipefail; h_file "$CLONE/f" 2>/dev/null; echo ":rc=$?" )
have "$r_e" ":rc=1"      "1e. spec h_file: shasum present but silent → refused (the empty-hash check is load-bearing)"
r_g=$( set +o pipefail; h_git "HEAD:f" 2>/dev/null; echo ":rc=$?" )
have "$r_g" ":rc=1"      "1f. spec h_git: shasum present but silent → refused"
# mutation: the same helpers with the empty-hash refusal removed must ACCEPT that state,
# proving 1e/1f discriminate rather than pass by accident
eval "$(printf '%s\n' "$HF" | sed 's/ \&\& \[ -n "\$h" \]//; s/^h_file/h_file_mut/')"
r_m=$( set +o pipefail; h_file_mut "$CLONE/f" 2>/dev/null | tr -d '\n'; echo ":rc=${PIPESTATUS[0]}" )
have "$r_m" ":rc=0"      "1g. mutant without the empty-hash check accepts a silent shasum: empty hash, rc 0 (so 1e cannot be vacuous)"
unset -f shasum

# ---------------------------------------------------------------------------
# 2. legacy .gitignore carry keeps the operator's rule ORDER.
# ---------------------------------------------------------------------------
printf 'node_modules/\n' > "$TMP/base"
printf 'node_modules/\nprivate/*\n!private/public.txt\n' > "$TMP/local"
old=$(comm -13 <(sort -u "$TMP/base") <(sort -u "$TMP/local") | grep -vE '^[[:space:]]*(#|$)' | tr '\n' '|')
new=$(grep -vxF -f "$TMP/base" "$TMP/local" | grep -vE '^[[:space:]]*(#|$)' | tr '\n' '|')
have "$old" "!private/public.txt|private/*|" "2a. OLD carry (sort/comm) puts the exception ABOVE its pattern (the defect, reproduced)"
have "$new" "private/*|!private/public.txt|" "2b. NEW carry (grep -vxF -f base) keeps the operator's order"
# and git agrees that order is what decides
R="$TMP/repo"; git init -q "$R"; mkdir -p "$R/private"; echo p > "$R/private/public.txt"; echo s > "$R/private/secret.txt"
printf '%s\n' "private/*" "!private/public.txt" > "$R/.gitignore"
# `git check-ignore` exits 0 for a path matched by a NEGATED pattern too, so ask the other way
# round: which untracked files are NOT ignored.
have "$(git -C "$R" ls-files -o --exclude-standard | tr '\n' '|')" ".gitignore|private/public.txt|" "2c. in git, original order: public.txt survives, secret.txt is ignored (the exception holds)"
printf '%s\n' "!private/public.txt" "private/*" > "$R/.gitignore"
have "$(git -C "$R" ls-files -o --exclude-standard | tr '\n' '|')" ".gitignore|" "2d. in git, sorted order: public.txt is ignored too — the exception is dead"
# an empty base (nothing to subtract) carries everything, in order
: > "$TMP/empty"
have "$(grep -vxF -f "$TMP/empty" "$TMP/local" | tr '\n' '|')" "node_modules/|private/*|!private/public.txt|" "2e. empty base → every line carried, in order"

# ---------------------------------------------------------------------------
# 3. an unreadable canonical .gitignore must REFUSE, not install a partial file.
# ---------------------------------------------------------------------------
SENT='AIOS-OPERATOR-IGNORES'
printf '# framework\n*.log\n# %s\nprivate/\n' "$SENT" > "$TMP/gi"
merge_old(){ { cat "$1"; awk -v s="$SENT" 'f{print} $0 ~ s {f=1}' "$2"; } > "$2.new" 2>/dev/null && mv "$2.new" "$2"; }
merge_new(){ [ -r "$1" ] || { echo "FATAL: canonical .gitignore unreadable at $1" >&2; return 1; }
             { cat "$1" && awk -v s="$SENT" 'f{print} $0 ~ s {f=1}' "$2"; } > "$2.new" && mv "$2.new" "$2"; }
cp "$TMP/gi" "$TMP/gi.old"; merge_old "$TMP/NOPE/.gitignore" "$TMP/gi.old"
have "$(tr '\n' '|' < "$TMP/gi.old")" "private/|" "3a. OLD merge with canonical unreadable installs ONLY the operator's lines (the defect, reproduced)"
cp "$TMP/gi" "$TMP/gi.new"; merge_new "$TMP/NOPE/.gitignore" "$TMP/gi.new" 2>/dev/null; rc=$?
have "$rc:$(md5 -q "$TMP/gi.new" 2>/dev/null || md5sum < "$TMP/gi.new" | cut -d' ' -f1)" "1:$(md5 -q "$TMP/gi" 2>/dev/null || md5sum < "$TMP/gi" | cut -d' ' -f1)" "3b. NEW merge refuses and leaves the file untouched"
printf 'canon1\ncanon2\n' > "$TMP/canon"; cp "$TMP/gi" "$TMP/gi.ok"; merge_new "$TMP/canon" "$TMP/gi.ok"
have "$(tr '\n' '|' < "$TMP/gi.ok")" "canon1|canon2|private/|" "3c. NEW merge with a readable canonical works as before"
# the precheck passes on a DIRECTORY (readable) but `cat` fails on it — only the && chain stops the mv
mkdir -p "$TMP/canondir"
cp "$TMP/gi" "$TMP/gi.late"; merge_old "$TMP/canondir" "$TMP/gi.late"
have "$(tr '\n' '|' < "$TMP/gi.late")" "private/|" "3d. OLD chain: precheck-passing but un-cat-able canonical still installs a partial file (the defect)"
cp "$TMP/gi" "$TMP/gi.late2"; merge_new "$TMP/canondir" "$TMP/gi.late2" 2>/dev/null; rc=$?
have "$rc:$(tr '\n' '|' < "$TMP/gi.late2")" "1:$(tr '\n' '|' < "$TMP/gi")" "3e. NEW chain: cat fails after the precheck → mv never runs, file intact"

# ---------------------------------------------------------------------------
# 4. a bundled folder MISSING from the vault must surface as drift.
# ---------------------------------------------------------------------------
V="$TMP/vault"; C="$TMP/clone2"; mkdir -p "$V" "$C/agents" "$C/hooks" "$V/hooks"; echo x > "$C/agents/a.md"; echo y > "$C/hooks/h"; echo y > "$V/hooks/h"
RDIRS=(agents hooks)
old=$( { for p in "${RDIRS[@]}"; do diff -rq "$V/$p" "$C/$p" 2>/dev/null; done; } | grep -c . )
new=$( { for p in "${RDIRS[@]}"; do
           if [ ! -d "$V/$p" ]; then echo "Only in $C: $p"; else diff -rq "$V/$p" "$C/$p" 2>/dev/null; fi
         done; } | grep -c . )
have "$old" "0" "4a. OLD reconcile: vault/agents missing → 0 lines = 'clean' (the defect, reproduced)"
have "$new" "1" "4b. NEW reconcile: vault/agents missing → one 'Only in <clone>: agents' line"

# ---------------------------------------------------------------------------
# 5. the spec carries the new shapes (anchors, so a rewrite that drops them fails here).
# ---------------------------------------------------------------------------
have "$(grep -c 'command -v shasum >/dev/null 2>&1 || return 1' "$SPEC"):$(grep -c '&& \[ -n "\$h" \] || return 1' "$SPEC")" "3:3" "5a. spec: all three hash helpers (two h_file, one h_git) probe for shasum AND refuse an empty hash"
grep -q 'grep -vxF -f' "$SPEC"      && ok "5b. spec: .gitignore carry is order-preserving" || no "5b. spec: .gitignore carry lost the order-preserving form"
grep -q 'canonical .gitignore unreadable' "$SPEC" && ok "5c. spec: merge refuses on an unreadable canonical" || no "5c. spec: merge no longer refuses on an unreadable canonical"
grep -q 'cat "\$CLONE/.gitignore" && awk' "$SPEC" && ok "5c'. spec: cat is chained with && into the merge group" || no "5c'. spec: the merge group lost the && after cat"
grep -q 'Only in \$CLONE: \$p"; else diff -rq' "$SPEC" && ok "5d. spec: reconcile reports a missing layer dir" || no "5d. spec: reconcile no longer reports a missing layer dir"
q=$(grep -c 'cp "\$HOME"/aios/plugins/aios/commands' "$SPEC"); u=$(grep -c 'cp \$HOME/aios/plugins/aios/commands' "$SPEC")
have "$q:$u" "4:0" "5e. spec: all four plugin-sync copies quote \$HOME and none is left unquoted"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
