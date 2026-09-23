#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The setup path must not stop the operator more than once, and must not hand
# Windows a command that does not exist there.
#
# WHY THIS EXISTS. A real Windows install through the AIOS App stopped twice for
# things only the operator could do — GitHub login mid-step-2, then `/add-dir
# ~/.claude` at step 8, after work had already been done around the block. On the
# way it cloned into a sibling `~/aios-src` it then could not read (the App starts
# the session inside an empty `~/aios`), and it rewired two of the three hooks by
# trial, because SETUP.md named `pwsh` (never installed by the Windows
# prerequisites) and `python3` (the Microsoft Store placeholder).
#
# Each assertion below is paired with a mutation that must make it FAIL, so the
# guard cannot pass by measuring nothing.
#
# Canonical-only (Tier 0). Run:  bash tests/setup-operator-gates.test.sh
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
PY=python3; command -v python3 >/dev/null 2>&1 && python3 -c '' 2>/dev/null || PY=python
TMP="${TMPDIR:-/tmp}/aios-setup-gates.$$"; mkdir -p "$TMP"; trap 'rm -rf "$TMP"' EXIT

# ── checks, each a function of a SETUP.md path so the mutations can reuse them ──
# The Claude-facing block is an HTML <details>, not a blockquote (see cold-start-interview.test.sh 4b).
block(){ awk '/<summary>.*Reading this as Claude/,/<\/details>/' "$1"; }
# Everything before the numbered clone step.
# No early `exit` in these awks and no `grep -q` downstream: under `set -o pipefail` a reader
# that stops early SIGPIPEs its writer, the pipeline reports 141, and the check fails on Linux
# while passing on Windows (which does not deliver SIGPIPE the same way). Read to the end.
before_clone(){ block "$1" | awk '/^2\. Clone/{d=1} !d{print}'; }
step2(){ block "$1" | awk '/^2\. Clone/{f=1;print;next} f&&/^[0-9]+\. /{f=0;d=1} f&&!d{print}'; }
has(){ grep -F -- "$1" >/dev/null; }

gates_up_front(){ before_clone "$1" | has 'gh auth status' && before_clone "$1" | has '/add-dir'; }
clone_in_place(){ step2 "$1" | has 'git clone https://github.com/The-AIOS/aios.git .'; }
no_pwsh(){ ! grep -qE 'pwsh (-File|skills/)' "$1"; }
# No GitHub must not stop setup: step 2 names the fallback, and the fallback drops
# the framework origin so a vault commit can never target the public repo.
github_optional(){ step2 "$1" | has 'No GitHub → continue' && step2 "$1" | has 'remote remove origin'; }
# ...and the warning is re-derived from the remote every morning, not left to a marker.
backup_probe(){ grep -qF 'remote get-url origin' "$1" && grep -qF 'backup: none' "$1" && grep -qF 'Backup warning rendering' "$1"; }
win_block_runs(){
  "$PY" - "$1" <<'PY'
import io, json, sys
s = io.open(sys.argv[1], encoding='utf-8').read()
marker = 'On Windows — the same three hooks'
if marker not in s: sys.exit(1)
body = s.split(marker, 1)[1].split('```json', 1)[1].split('```', 1)[0]
cfg = json.loads(body)
cmds = [h['command'] for ev in cfg['hooks'].values() for g in ev for h in g['hooks']] + [cfg['statusLine']['command']]
bad = [c for c in cmds if 'python3' in c or 'pwsh ' in c]
sys.exit(1 if bad or len(cmds) != 3 else 0)
PY
}

echo "-- 1. the live file --"
[ "$(block SETUP.md | grep -cE '^[0-9]+\. ')" -ge 8 ] \
  && ok "Claude-facing block located" \
  || no "cannot locate the Claude-facing block" "every check below would pass by measuring nothing"
gates_up_front SETUP.md \
  && ok "GitHub login and /add-dir are asked for BEFORE the clone step" \
  || no "operator-only gates are not batched before step 2" "each one found later is a second, unexpected stop"
clone_in_place SETUP.md \
  && ok "step 2 clones INTO an empty ~/aios, not beside it" \
  || no "step 2 has no clone-in-place instruction" "the App starts the session inside ~/aios; a sibling clone is unreadable"
github_optional SETUP.md \
  && ok "no GitHub → setup continues, with the framework origin removed" \
  || no "step 2 has no no-GitHub fallback" "a failed login must warn, not block"
backup_probe plugins/aios/commands/today.md \
  && ok "/today re-derives the not-backed-up warning from the remote" \
  || no "/today has no backup probe" "a vault left local-only by setup would be silent forever"
for f in SETUP.md plugins/aios/commands/cold-start-interview.md; do
  no_pwsh "$f" && ok "$f invokes no pwsh" \
    || no "$f still invokes pwsh" "the Windows prerequisites never install PowerShell 7"
done
win_block_runs SETUP.md \
  && ok "the Windows hooks block is valid JSON, 3 commands, no pwsh/python3" \
  || no "the Windows hooks block is missing, invalid, or names pwsh/python3" "SETUP §10 → On Windows"

echo "-- 2. each check fails on the defect it guards --"
M="$TMP/SETUP.md"
sed '/gh auth status/d' SETUP.md > "$M"
gates_up_front "$M" && no "gate check passed with the gh probe removed" "it is not measuring anything" || ok "gate check fires without the up-front probe"
sed 's#git clone https://github.com/The-AIOS/aios.git \.#git clone https://github.com/The-AIOS/aios.git ~/aios-src#' SETUP.md > "$M"
clone_in_place "$M" && no "clone check passed with a sibling clone" "" || ok "clone check fires on a sibling clone"
sed 's#(Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File skills/setup.ps1`)#(Windows: `pwsh skills/setup.ps1`)#' SETUP.md > "$M"
no_pwsh "$M" && no "pwsh check passed with pwsh reintroduced" "" || ok "pwsh check fires when pwsh is reintroduced"
sed 's#| python \$HOME/aios/hooks/claude-identity/context-monitor.py#| python3 $HOME/aios/hooks/claude-identity/context-monitor.py#' SETUP.md > "$M"
win_block_runs "$M" && no "Windows block check passed with python3 reintroduced" "" || ok "Windows block check fires on python3"

sed '/remote remove origin/d' SETUP.md > "$M"
github_optional "$M" && no "GitHub fallback check passed with the fallback removed" "" || ok "GitHub fallback check fires without the fallback"
sed '/remote get-url origin/d' plugins/aios/commands/today.md > "$TMP/today.md"
backup_probe "$TMP/today.md" && no "backup probe check passed with the probe removed" "" || ok "backup probe check fires without the probe"

echo; echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
