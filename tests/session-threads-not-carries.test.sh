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
check("with nobody to answer, a doubtful thread is neither carried nor routed", "nobody to answer" in body and "never carried and never routed" in body and "`undecided`" in body)
check("routing writes a line, never a message to another session", "a line, never a message" in body and "never sends, spawns or resumes" in body)
check("routed project to-dos go through the cascade ledger", "Into project notes" in body)
check("a second close-day skips decided threads but decides undecided ones again", "already decided as carried, routed or dropped" in body and "an `undecided` thread is decided again" in body)
check("routing never writes an Agents-can-handle line (it is rebuilt daily, never carried)", "Agents can handle` line" not in body and "the to-do names the agent" in body)
check("a Session threads line never copies a checkbox", "without its bullet or checkbox" in cd)
check("no Decide line for a thread already open or done elsewhere", "unless an open line or a done twin with the same identity is already in the note" in td)
check("the drop check covers plain-bullet threads, not only checkboxes", "every Open-threads bullet of the previous note's `## Session —` blocks, checkbox or plain" in td)
check("undecided does not count as decided in today", "decided there as carried, routed or dropped is skipped" in td)
check("decisions are recorded in the Close of Day, session blocks stay untouched",
      "### Session threads" in body and "Session blocks stay untouched" in body)
tpl = cd.find("### Session threads\n")
check("the Close of Day template has the Session threads list before Carries forward",
      tpl != -1 and tpl < cd.find("### Carries forward\n- [ ] {Items"))

# 3. today's carry sources
check("today carries only what close-day decided from session blocks",
      "Session blocks: carry only what was decided" in td and "a thread decided there as carried, routed or dropped is skipped" in td)
check("an undecided or never-triaged thread becomes one decision line, never a lost task",
      "`- [ ] Decide: {thread}" in td and "a session that closed after close-day ran" in td and "a note from before this change" in td)
check("the drop check counts a session thread as placed only when decided or on a Decide line",
      "counts as placed when `### Session threads` decided it carried, routed or dropped, or when it appears in today's note as a `Decide:` line" in td)
check("close-session's comprehension carry is a task thread, not a checkbox carry",
      "`**Open threads:**` carry" not in cs and "open-threads carry" not in cs and "thread tagged `task`" in cs)
print("%d passed, %d failed" % (ok, fail))
sys.exit(1 if fail else 0)
PY
