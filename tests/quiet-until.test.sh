#!/usr/bin/env bash
# tests/quiet-until.test.sh
#
# #341: a deferral ("table it", "later", "not until the 30th") is an instruction about attention.
# An item tagged `quiet-until: YYYY-MM-DD` stays out of sight until its date, is never lost while
# it waits, and comes back once on the date. Asserted across the three commands and CLAUDE.md.
# Usage: bash tests/quiet-until.test.sh [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1
python3 - <<'PY'
import sys
ok = fail = 0
def check(name, cond):
    global ok, fail
    if cond: ok += 1; print("  ok   " + name)
    else: fail += 1; print("  FAIL " + name)
print("quiet-until (#341)")
C = "plugins/aios/commands/"
td = open(C + "today.md", encoding="utf-8").read()
cd = open(C + "close-day.md", encoding="utf-8").read()
cs = open(C + "close-session.md", encoding="utf-8").read()
cm = open("CLAUDE.md", encoding="utf-8").read()
q = td[td.find("**`quiet-until` carries are silent until their date**"):td.find("- **Window-cadence carries are not drift.**")]
check("today has the quiet-until rule", bool(q))
check("before the date it appears nowhere visible, Google Tasks preview included", "appears **nowhere** visible" in q and "Google Tasks preview" in q and "no 📅 line" in q)
check("it is not counted or triaged while quiet", "not counted and never triaged" in q)
check("it is never lost: project to-dos or the hidden quiet block, copied forward", "never dropped" in q and "%% quiet-until" in q and "Copy the previous note's quiet block forward whole" in q)
check("on the date it surfaces once as a normal task", "on or after the date" in q and "surfaces once as a normal task" in q)
check("the drop check counts a quiet carry as placed", "counts a quiet carry as placed" in q)
check("it is distinct from waiting-on-date (remind me)", "`waiting-on-date` means *blocked, remind me*" in q)
check("close-day passes it through silently, out of carries, triage and the Tasks preview",
      "**`quiet-until` carries pass through silently**" in cd and "carry-reason triage and the Google Tasks preview" in cd)
check("close-day never creates a Google Task for it and moves a deferred task's due date",
      "never a `quiet-until` item" in cd and "update its due date to that date" in cd)
check("the carry-reason prompt offers quiet-until", "waiting-on-date / quiet-until {date} / park" in cd and "`quiet-until {date}` / `park`" in td)
check("close-session tags a deferral instead of leaving an open thread", "is not an open thread: tag it `quiet-until: YYYY-MM-DD`" in cs)
check("CLAUDE.md: tag a deferral the turn it is spoken", "Tag a deferral the turn it is spoken" in cm and "quiet-until: YYYY-MM-DD" in cm)
print("%d passed, %d failed" % (ok, fail))
sys.exit(1 if fail else 0)
PY
