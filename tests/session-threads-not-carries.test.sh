#!/usr/bin/env bash
# tests/session-threads-not-carries.test.sh
#
# #337: what a session leaves open must not come back next morning as a task the operator never set.
# Three commands form the chain, and each link is asserted:
#   1. /close-session writes open threads as plain bullets tagged by kind, never `- [ ]` checkboxes;
#   2. /close-day triages every session thread (carry, route, drop) before writing carries, asks once
#      for doubtful ones, and never carries a doubtful one when nobody is there to answer;
#   3. /today does not carry from `## Session —` blocks once the note has a Close of Day, in the
#      extraction and in the drop check alike.
# Usage: bash tests/session-threads-not-carries.test.sh [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1
python3 - <<'PY'
import re, sys
ok = fail = 0
def check(name, cond):
    global ok, fail
    if cond: ok += 1; print("  ok   " + name)
    else: fail += 1; print("  FAIL " + name)
print("session threads are not carries (#337)")
C = "plugins/aios/commands/"
cs = open(C + "close-session.md", encoding="utf-8").read()
cd = open(C + "close-day.md", encoding="utf-8").read()
td = open(C + "today.md", encoding="utf-8").read()

# 1. close-session's template
m = re.search(r"\*\*Open threads:\*\*\n(- .*)\n", cs)
line = m.group(1) if m else ""
check("close-session has an Open threads line in its block template", bool(m))
check("the template line is a plain bullet, not a checkbox", line.startswith("- ") and not line.startswith("- [ ]"))
check("each thread is tagged task, follow-up or note", "_(task | follow-up | note)_" in line)

# 2. close-day's triage
tri = cd.find("## Session threads triage")
done = cd.find("## Done-outside-a-session check")
carries = cd.find("## Carry-reason triage prompt")
check("close-day has a session threads triage step", tri != -1)
check("it runs before any carry is checked or counted", tri != -1 and tri < done < carries)
body = cd[tri:done] if tri != -1 and done != -1 else ""
check("each thread is carried, routed or dropped", all(w in body for w in ("**carry**", "**route**", "**drop**")))
check("doubtful threads are asked about once, together", "ask once" in body and "doubtful" in body)
check("with nobody to answer, a doubtful thread is never carried", "--auto" in body and "never carried" in body)
check("handled threads are marked in their block", "→ carried" in body and "→ dropped" in body)

# 3. today's carry sources
check("today excludes session blocks once the note has a Close of Day",
      "Exclude every `## Session —` block once the note has a `## Close of Day`" in td)
check("the drop check uses the same sources as the extraction",
      "from the same sources as the extraction" in td and "`## Session —` blocks are not checked" in td)
check("without a Close of Day, session threads are shown once, never carried with a count",
      "candidates shown once" in td and "never carries with a count" in td)
print("%d passed, %d failed" % (ok, fail))
sys.exit(1 if fail else 0)
PY
