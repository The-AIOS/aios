#!/usr/bin/env bash
# tests/hooks-gitattributes.test.sh
#
# hooks/.gitattributes must, ON ITS OWN (an operator vault never gets canonical's root
# .gitattributes), give every script under hooks/ an LF checkout and every .ps1 CRLF. Checked in a
# scratch repo holding only hooks/, with a control: the same repo without the file leaves the eol
# unspecified, so a pass is the file's doing.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
no(){ echo "  ✗ $1"; [ -n "${2:-}" ] && echo "      $2"; FAIL=$((FAIL+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
git -C "$T" init -q
(cd "$ROOT" && git ls-files hooks) > "$T/list"
while IFS= read -r f; do mkdir -p "$T/$(dirname "$f")"; cp "$ROOT/$f" "$T/$f"; done < "$T/list"
cp "$ROOT/hooks/.gitattributes" "$T/hooks/.gitattributes" || { echo "  ✗ hooks/.gitattributes missing"; exit 1; }
attr(){ git -C "$T" check-attr eol -- "$1" | sed 's/.*eol: //'; }

echo "── control: without hooks/.gitattributes the eol is unspecified ──"
mv "$T/hooks/.gitattributes" "$T/ga.off"
[ "$(attr hooks/vault/aios-commit)" = "unspecified" ] && ok "control holds (no root file in this repo)" || no "control: eol already set without the file"
mv "$T/ga.off" "$T/hooks/.gitattributes"

echo "── with it, every executable and script is LF, every .ps1 CRLF ──"
bad=""
while IFS= read -r f; do
  case "$f" in hooks/.gitattributes) continue ;; esac
  want=lf; case "$f" in *.ps1) want=crlf ;; esac
  got="$(attr "$f")"; [ "$got" = "$want" ] || bad="$bad $f($got)"
done < "$T/list"
[ -z "$bad" ] && ok "all $(grep -vc '^hooks/.gitattributes$' "$T/list") tracked files under hooks/ resolve correctly" || no "wrong eol:" "$bad"
[ "$(attr hooks/git/pre-commit)" = lf ] && ok "git/pre-commit is LF (the secret scan runs through sh)" || no "pre-commit not LF"

echo "── it cannot reach a note ──"
mkdir -p "$T/vault"; printf 'x\r\n' > "$T/vault/note.md"
[ "$(attr vault/note.md)" = "unspecified" ] && ok "a vault note is untouched by it" || no "the hooks rule leaks outside hooks/"

echo "── RESULT: $PASS passed, $FAIL failed ──"
[ "$FAIL" = 0 ]
