#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# A pin bump reaches an install that already exists
#
# WHY
# Every Python MCP in mcps/setup.sh was guarded by `[ ! -d .venv ]`, so it
# installed once and never again: a machine set up months ago kept those
# versions whatever requirements.txt said. notebooklm-py was found frozen at
# 0.3.4 while 0.8.2 shipped. Installs now stamp a hash of requirements.txt and
# reinstall when it changes.
#
# It also covers the NotebookLM helper scripts: notebooklm-py 0.8 moved its
# session under ~/.notebooklm/profiles/<name>/, and the helpers must follow.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  ✗ %s\n      %s\n' "$1" "${2:-}"; }
PY=""; for _c in python3 python "py -3"; do if $_c -c 'import sys' >/dev/null 2>&1; then PY="$_c"; break; fi; done
[ -n "$PY" ] || { echo "SKIP: no working Python" >&2; exit 0; }
S="${SETUP_SH:-mcps/setup.sh}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

echo "-- 1. no Python MCP is guarded by install-once any more --"
left=$(grep -cE '\[ ! -d "\$SCRIPT_DIR/[a-z-]+/\.venv" \]' "$S")
[ "$left" -eq 0 ] && ok "no '[ ! -d …/.venv ]' guard left" || no "$left install-once guard(s) left" "a pin bump never reaches those installs"
nreq=$(ls mcps/*/requirements.txt | wc -l | tr -d ' ')
nguard=$(grep -cE 'needs_install "\$SCRIPT_DIR/[a-z-]+"' "$S")
[ "$nguard" -eq "$nreq" ] && ok "all $nreq MCPs with a requirements.txt use needs_install" || no "needs_install on $nguard of $nreq MCPs" ""

echo "-- 2. needs_install answers each state correctly --"
sed -n '/^req_sha()/,/^stamp_install()/p' "$S" > "$T/fns.sh"
if ! grep -c '^needs_install()' "$T/fns.sh" >/dev/null; then
  no "setup.sh defines no needs_install()" "nothing below can run"
else
  D="$T/mcp"; mkdir -p "$D"; printf 'pkg==1.0\n' > "$D/requirements.txt"
  run(){ ( PY="$PY"; . "$T/fns.sh"; needs_install "$D" ) && echo install || echo skip; }
  [ "$(run)" = install ] && ok "no venv → install" || no "no venv did not install" ""
  mkdir -p "$D/.venv"
  [ "$(run)" = install ] && ok "venv with no stamp (every existing machine) → reinstall once" || no "unstamped venv skipped" "existing installs would stay frozen"
  ( cd "$D" && PY="$PY" && . "$T/fns.sh" && stamp_install )
  [ "$(run)" = skip ] && ok "stamp matches → skip" || no "matching stamp reinstalled" "every setup run would reinstall"
  printf 'pkg==1.0\r\n' > "$D/requirements.txt"
  [ "$(run)" = skip ] && ok "same pins with CRLF line endings → skip" || no "CRLF read as a change" "Windows checkouts would reinstall every run"
  printf 'pkg==2.0\n' > "$D/requirements.txt"
  [ "$(run)" = install ] && ok "pin bumped → reinstall" || no "a pin bump was skipped" "the bug this test exists for"
  r=$( ( PY=""; . "$T/fns.sh"; needs_install "$D" ) && echo install || echo skip )
  [ "$r" = skip ] && ok "no Python + existing venv → left alone" || no "no Python still asked to rebuild" ""
fi

echo "-- 3. the NotebookLM helpers follow notebooklm-py's profile folder --"
H="$T/home"; for f in manual_login.py save_storage.py; do
  src="mcps/notebooklm-mcp/$f"
  probe(){ HOME="$H" $PY - "$src" <<'PYX'
import sys, types
src = open(sys.argv[1], encoding="utf-8").read()
src = src[:src.index("PROFILE, STORAGE = _notebooklm_dirs()")]
ns = {}; exec(src.replace("from playwright", "#"), ns)
print(ns["_notebooklm_dirs"]()[1])
PYX
  }
  rm -rf "$H"; mkdir -p "$H/.notebooklm"
  case "$(probe)" in "$H/.notebooklm/storage_state.json") ok "$f: fresh install → old root (0.8 migrates it)";; *) no "$f: fresh install resolved to $(probe)" "";; esac
  mkdir -p "$H/.notebooklm/profiles/work"; printf '{"default_profile": "work"}' > "$H/.notebooklm/config.json"
  case "$(probe)" in "$H/.notebooklm/profiles/work/storage_state.json") ok "$f: migrated install → profiles/<default_profile>/";; *) no "$f: migrated install resolved to $(probe)" "0.8 would never read what it writes";; esac
done

printf '\n  %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
