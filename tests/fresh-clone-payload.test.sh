#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# What a fresh clone delivers: no doc tells an operator to run a script they lack (#267, part a)
#
# WHY THIS EXISTS
# Every other gate asks whether the repo agrees with itself. This one asks what a new
# operator receives. SETUP.md slims a clone (no tests/), and /aios:update never copies
# tests/ or .github/ into a vault, yet shipped docs have told operators to run things
# there. Real incident, found when this gate was written: mcps/slack-mcp/UPSTREAM.md, a
# file every operator receives, told them to run `bash tests/vendored-pins.test.sh`.
#
# THE RULE (add a rule only from a real incident, and name it here):
#   1. In every shipped *.md, a command (`bash|sh|python3|python|uv run …`) that runs a
#      repo path must name a file the slimmed clone contains. A block meant for
#      maintainers in a canonical checkout says so on the line before its fence:
#      <!-- maintainers: run in a canonical checkout -->
# Not scanned: tests/, .github/ and vault/ (they are not operator docs), CHANGELOG.md
# (history) and CONTRIBUTING.md (read by contributors, who work in a canonical clone).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYBIN=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PYBIN="$_cand"; break; fi
done
[ -n "$PYBIN" ] || { echo "SKIP: no working Python found" >&2; exit 0; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n%s\n' "$1" "${2:-}"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/scan.py" <<'PY'
import os, re, subprocess, sys
root = sys.argv[1]
files = [f for f in subprocess.run(["git", "-C", root, "ls-files", "-z", "*.md"],
         capture_output=True, text=True).stdout.split("\0") if f]
files = [f for f in files if not f.startswith(("tests/", ".github/", "vault/"))
         and f not in ("CHANGELOG.md", "CONTRIBUTING.md")]
cmd = re.compile(r"(?:bash|sh|python3|python|uv run(?: --[a-z-]+(?: \S+)?)*)\s+(?:\"?\$HOME/aios/|~/aios/|\./)?"
                 r"((?:hooks|tests|\.github|mcps|skills|agents|plugins|templates)/[A-Za-z0-9_./-]+)")
MARK = "<!-- maintainers: run in a canonical checkout -->"
bad = []
for f in files:
    path = os.path.join(root, f)
    if not os.path.isfile(path):
        continue
    lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    in_fence, marked, prev = False, False, ""
    for i, line in enumerate(lines, 1):
        if line.lstrip().startswith("```"):
            if not in_fence:
                in_fence, marked = True, MARK in prev
            else:
                in_fence, marked = False, False
            prev = line
            continue
        if line.strip():
            prev = line
        if in_fence and marked:
            continue
        for m in cmd.finditer(line):
            p = m.group(1).rstrip(".,)`'\"")
            if any(c in p for c in "{}<>*"):
                continue
            if not os.path.exists(os.path.join(root, p)):
                bad.append(f"     {f}:{i}  runs {p}, which a fresh clone does not contain")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
slim(){ git clone -q "$1" "$2" 2>/dev/null && git -C "$2" sparse-checkout set --no-cone '/*' '!/tests/' 2>/dev/null; }

slim "$ROOT" "$T/clone" || { no "could not make a fresh clone of the repo under test"; exit 1; }
[ ! -e "$T/clone/tests" ] && ok "the clone is slimmed the way SETUP.md slims it (no tests/)" || no "tests/ is still in the clone"
out=$($PYBIN "$T/scan.py" "$T/clone"); rc=$?
[ $rc -eq 0 ] && ok "no shipped doc runs a script a fresh clone lacks" || no "shipped docs run scripts a fresh clone does not have:" "$out"

# Controls, on a copy: a planted instruction fails the gate; the maintainer marker allows it.
git clone -q "$ROOT" "$T/ctl" 2>/dev/null
printf '\nRun `bash tests/planted.test.sh` to check your setup.\n' >> "$T/ctl/README.md"
git -C "$T/ctl" -c user.name=t -c user.email=t@t commit -qam planted
slim "$T/ctl" "$T/ctl-clone"; out=$($PYBIN "$T/scan.py" "$T/ctl-clone"); rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -F 'README.md' >/dev/null && ok "CONTROL: a planted 'bash tests/…' in README fails, naming the file and line" || no "CONTROL: the planted instruction passed"
python3 - "$T/ctl/README.md" <<'PY2'
import sys;p=sys.argv[1];s=open(p).read().replace("\nRun `bash tests/planted.test.sh` to check your setup.\n","\n<!-- maintainers: run in a canonical checkout -->\n```bash\nbash tests/planted.test.sh\n```\n")
open(p,"w").write(s)
PY2
git -C "$T/ctl" -c user.name=t -c user.email=t@t commit -qam marked
rm -rf "$T/ctl-clone"; slim "$T/ctl" "$T/ctl-clone"; $PYBIN "$T/scan.py" "$T/ctl-clone" >/dev/null; rc=$?
[ $rc -eq 0 ] && ok "CONTROL: the same block marked for maintainers passes" || no "CONTROL: the maintainer marker is not honoured"
printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
