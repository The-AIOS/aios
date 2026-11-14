#!/usr/bin/env bash
# Third-party text inside a framework folder keeps its credit (#310). Every LICENSE-AUDIT.md
# Skills row that names one folder under skills/aios/ with an outside origin must have that
# origin linked in the folder's own SKILL.md, so the credit cannot be dropped silently.
# Usage: bash tests/third-party-credits.test.sh [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1
python3 - <<'PY'
import os, re, sys
ok = fail = 0
def check(name, cond):
    global ok, fail
    if cond: ok += 1; print("  ok   " + name)
    else: fail += 1; print("  FAIL " + name)
print("third-party-credits")
audit = open("LICENSE-AUDIT.md", encoding="utf-8").read()
rows = re.findall(r"^\| `(skills/aios/[^`]+?)/?` \| \[([^\]]+)\]\((https://[^)]+)\)", audit, re.M)
check("LICENSE-AUDIT lists at least one third-party folder under skills/aios/", len(rows) > 0)
for folder, repo, url in rows:
    skill = os.path.join(folder, "SKILL.md")
    text = open(skill, encoding="utf-8").read() if os.path.isfile(skill) else ""
    check("%s exists" % skill, bool(text))
    check("%s links its origin %s" % (skill, url), url in text)
    check("%s names its license" % skill, re.search(r"\bMIT\b|Apache|BSD|ISC|GPL", text) is not None)
print("%d passed, %d failed" % (ok, fail))
sys.exit(1 if fail else 0)
PY
