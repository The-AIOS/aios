#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# install-git-hooks.sh must leave every hook in hooks/git RUNNABLE — executable
# and free of the CRLF line endings a Windows checkout introduces.
#
# What this measures, and why it is the requirement rather than a cousin of it:
# the assertion is that the hook EXECUTES after install, not merely that no \r
# byte remains. Those come apart — an LF file with no exec bit does not run
# either, and normalizing through `mv` produces exactly that. So every case
# below ends by invoking the hook the way git does.
#
# The control comes first and plants the defect: a CRLF hook must FAIL before
# the installer touches it. If that control ever passes, this platform stopped
# caring about \r and the whole guard is pointless — the test says so loudly
# rather than reporting a pass it did not earn.
#
# Every run relocates HOME: the installer symlinks aios-commit into
# $HOME/.local/bin, and a test has no business writing to the real one.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

SRC="$PWD"
[ -f "$SRC/hooks/install-git-hooks.sh" ] || { echo "::error::hooks/install-git-hooks.sh missing"; exit 1; }
[ -f "$SRC/hooks/git/pre-push" ]         || { echo "::error::hooks/git/pre-push missing"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# A scratch repo carrying its own copy of hooks/, so the installer's chmod and
# rewrite land on the fixture and never on the working tree of this repo.
mkrepo(){
  r="$T/repo.$1"; rm -rf "$r"; mkdir -p "$r"
  git init -q "$r" 2>/dev/null
  cp -R "$SRC/hooks" "$r/hooks"
  echo "$r"
}
# Run the installer against a scratch repo with an isolated HOME.
install_into(){ HOME="$T/home.$$" bash "$1/hooks/install-git-hooks.sh" "$1" 2>&1; }
# Invoke a pre-push hook the way git does: (remote-name, url) + a ref line on stdin.
runhook(){ printf 'refs/heads/main a refs/heads/main b\n' | "$1" origin git@github.com:someone/x.git >/dev/null 2>&1; echo $?; }
has_cr(){ LC_ALL=C grep -q $'\r' "$1" 2>/dev/null; }

echo "── CONTROL: a CRLF hook must be broken BEFORE the installer runs ──"
R=$(mkrepo control)
sed $'s/$/\r/' "$SRC/hooks/git/pre-push" > "$R/hooks/git/pre-push"; chmod +x "$R/hooks/git/pre-push"
rc=$(runhook "$R/hooks/git/pre-push")
if [ "$rc" != "0" ]; then
  ok "CRLF pre-push fails to run (exit $rc) — the defect is real and reproducible"
else
  no "a CRLF hook ran fine on this platform" \
     "the control did not reproduce, so nothing below can prove the fix works — do NOT read the passes as evidence"
fi

echo "── the installer makes that same hook runnable ──"
R=$(mkrepo fix)
sed $'s/$/\r/' "$SRC/hooks/git/pre-push"   > "$R/hooks/git/pre-push"
sed $'s/$/\r/' "$SRC/hooks/git/pre-commit" > "$R/hooks/git/pre-commit"
chmod -x "$R/hooks/git/pre-push"                       # the exec bit a hardcoded chmod list missed
out=$(install_into "$R")
has_cr "$R/hooks/git/pre-push"   || ok "pre-push CRLF stripped"   ; has_cr "$R/hooks/git/pre-push"   && no "pre-push still carries CR"
has_cr "$R/hooks/git/pre-commit" || ok "pre-commit CRLF stripped" ; has_cr "$R/hooks/git/pre-commit" && no "pre-commit still carries CR" "the chmod/normalize loop must be derived from hooks/git, not a named list"
[ -x "$R/hooks/git/pre-push" ] && ok "pre-push is executable after install" || no "pre-push not executable" "the chmod list named pre-commit and secret-scan.sh only, so a new hook shipped without an exec bit"
rc=$(runhook "$R/hooks/git/pre-push")
[ "$rc" = "0" ] && ok "pre-push RUNS after install (exit 0, inert with no owner list)" || no "pre-push still does not run (exit $rc)" "this is the assertion that matters — a CR-free hook with no exec bit fails here too"
case "$out" in *"normalized CRLF -> LF: pre-push"*) ok "installer reports what it normalized" ;; *) no "normalization was silent" "an operator whose checkout was mangled should learn that it was" ;; esac

echo "── idempotent: a second run finds nothing to do ──"
out=$(install_into "$R")
case "$out" in *normalized*) no "second run normalized again" "it must detect CR and skip, not rewrite every time" ;; *) ok "second run reports no normalization" ;; esac
rc=$(runhook "$R/hooks/git/pre-push"); [ "$rc" = "0" ] && ok "hook still runs after the second install" || no "second install broke the hook (exit $rc)"

echo "── a clean LF checkout is left byte-identical ──"
R=$(mkrepo clean)
before=$(shasum -a 256 < "$R/hooks/git/pre-push" | cut -d' ' -f1)
install_into "$R" >/dev/null
after=$(shasum -a 256 < "$R/hooks/git/pre-push" | cut -d' ' -f1)
[ "$before" = "$after" ] && ok "LF hook untouched (no gratuitous rewrite)" || no "an already-clean hook was rewritten"

echo "── only line-terminating CR is stripped ──"
R=$(mkrepo lonecr)
printf '#!/usr/bin/env bash\nprintf "a\\rb"\nexit 0\r\n' > "$R/hooks/git/pre-push"
install_into "$R" >/dev/null
if LC_ALL=C grep -q 'a\\rb' "$R/hooks/git/pre-push" 2>/dev/null; then
  ok "a CR written inside a string survives (escape sequence untouched)"
else
  no "the in-string CR escape was mangled" "strip \\r only at end-of-line; a blanket tr -d would corrupt payloads"
fi
LC_ALL=C grep -q $'\r$' "$R/hooks/git/pre-push" 2>/dev/null && no "trailing CR survived" || ok "trailing CR removed"

echo "── docs in hooks/git are not made executable ──"
R=$(mkrepo docs)
printf '# notes\n' > "$R/hooks/git/README.md"
install_into "$R" >/dev/null
[ -x "$R/hooks/git/README.md" ] && no "README.md was chmod +x" "the loop must skip .md — a doc is not a hook" || ok ".md skipped by the chmod loop"

echo
echo "── $PASS passed, $FAIL failed ──"
[ "$FAIL" -eq 0 ]
