#!/usr/bin/env python3
"""Check a project's `## Team` plan, and launch it only after the operator approved it (#274).

The team-composer skill writes the plan into the project note; this script is the part that must
not be left to judgment: every agent exists, every tier is one the ladder knows, exactly one chief
of staff, every task fits one typed line, and nothing is spawned before the operator said yes.

The section it reads (the skill writes it; an operator may edit it):

    ## Team

    **Charter.** Why this team exists, what it never trades away, its source of truth.

    | Role | Session | Agent | Tier | Kind | Owns | Reports to | First task |
    |---|---|---|---|---|---|---|---|
    | chief of staff | bakery-lead | consultant | judgment | standing | the plan | operator | ... |

Usage:
  team-plan.py check  <project-note.md>               exit 0 = valid, 1 = refused (reasons printed)
  team-plan.py launch <project-note.md> --approved    one spawn-inbox request per member, all in one
                                                      tab group named after the project; with no live
                                                      surface, prints one `spawn` line per member instead
`launch` without `--approved` refuses: the flag is the operator's yes, passed by the skill only after
they gave it. Env: AIOS_ROOT (vault, default ~/aios), AIOS_INBOX_DIR, AIOS_SURFACES_DIR.
"""
import glob
import importlib.util
import json
import os
import re
import subprocess
import sys

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("AIOS_ROOT") or os.path.join(os.path.expanduser("~"), "aios")
COLUMNS = ["role", "session", "agent", "tier", "kind", "owns", "reports to", "first task"]
KINDS = {"standing", "crew"}
SESSION = re.compile(r"^[a-z0-9]+(-[a-z0-9]+){0,2}$")   # lowercase kebab, at most three words
MAX_TASK = 1000                                         # bytes a surface types in one line


def _load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    return mod


def known_agents():
    return {fm["name"] for kind, _r, fm in _load("list-agents").classify(ROOT) if kind == "agent"}


def known_tiers():
    try:
        out = subprocess.run([os.path.join(HERE, "resolve-tier"), "--list"], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.TimeoutExpired):
        return set()
    return {line.split()[0] for line in out.splitlines() if line.strip()}


def parse(note):
    """(charter, rows) from the note's `## Team` section; rows are dicts keyed by COLUMNS."""
    text = open(note, encoding="utf-8").read()
    m = re.search(r"^## Team[ \t]*\n(.*?)(?=^## |\Z)", text, re.S | re.M)
    if not m:
        return None, None, []
    body = m.group(1)
    charter = re.search(r"\*\*Charter\.\*\*\s*(.+)", body)
    lines = [l.strip() for l in body.splitlines() if l.strip().startswith("|")]
    if len(lines) < 2:
        return (charter.group(1).strip() if charter else ""), [], []
    cells = lambda l: [c.strip() for c in l.strip("|").split("|")]
    head = [c.lower() for c in cells(lines[0])]
    rows = []
    for l in lines[2:]:
        c = cells(l)
        rows.append({k: (c[head.index(k)] if k in head and head.index(k) < len(c) else "") for k in COLUMNS})
    return (charter.group(1).strip() if charter else ""), rows, head


def task_for(row):
    report = "operator" if row["reports to"].lower() == "operator" else row["reports to"]
    tail = ("When it is done, report back with one spawn-inbox `send` to %s: what you did and what is open." % report
            if report != "operator" else "When it is done, tell the operator what you did and what is open.")
    return "%s %s" % (row["first task"].rstrip(), tail)


def check(note):
    if not os.path.isfile(note):
        return ["no such note: %s" % note]
    charter, rows, head = parse(note)
    if rows is None:
        return ["the note has no `## Team` section"]
    errs = []
    missing = [c for c in COLUMNS if c not in head]
    if missing:
        return ["the Team table lacks column(s): %s" % ", ".join(missing)]
    if not charter:
        errs.append("no **Charter.** line: every member reads it first")
    if len(rows) < 2:
        errs.append("a team needs at least two members (%d found)" % len(rows))
    chiefs = [r for r in rows if r["role"].lower() == "chief of staff"]
    if len(chiefs) != 1:
        errs.append("exactly one row must be the chief of staff (%d found)" % len(chiefs))
    agents, tiers = known_agents(), known_tiers()
    if not tiers:
        errs.append("could not read the tier list from hooks/resolve-tier --list")
    sessions = [r["session"] for r in rows]
    for r in rows:
        who = r["session"] or "(no session)"
        if not SESSION.match(r["session"]):
            errs.append("%s: session names are lowercase kebab, at most three words" % who)
        if sessions.count(r["session"]) > 1:
            errs.append("%s: two members share this session name" % who)
        if r["agent"] not in agents:
            errs.append("%s: no agent named '%s' under agents/" % (who, r["agent"]))
        if tiers and r["tier"] not in tiers:
            errs.append("%s: unknown tier '%s' (known: %s)" % (who, r["tier"], ", ".join(sorted(tiers))))
        if r["kind"].lower() not in KINDS:
            errs.append("%s: kind is standing or crew, not '%s'" % (who, r["kind"]))
        if r["kind"].lower() == "standing" and not r["owns"]:
            errs.append("%s: a standing member owns something (it is that thing's single writer)" % who)
        target = r["reports to"]
        if r in chiefs:
            if target.lower() != "operator":
                errs.append("%s: the chief of staff reports to the operator" % who)
        elif target not in sessions or target == r["session"]:
            errs.append("%s: reports to '%s', which is not another member's session" % (who, target))
        if not r["first task"]:
            errs.append("%s: no first task" % who)
        elif len(task_for(r).encode("utf-8")) > MAX_TASK:
            errs.append("%s: the first task is too long to be typed in one line (keep it under ~%d bytes)" % (who, MAX_TASK - 150))
    # de-duplicate, keep order
    return list(dict.fromkeys(errs))


def surface_alive():
    d = os.environ.get("AIOS_SURFACES_DIR") or os.path.join(os.path.expanduser("~"), ".aios", "surfaces")
    for f in glob.glob(os.path.join(d, "*.json")):
        try:
            pid = int(json.load(open(f)).get("pid"))
            os.kill(pid, 0)
            return True
        except (ValueError, TypeError, OSError, PermissionError):
            continue
    return False


def launch(note):
    errs = check(note)
    if errs:
        return errs, []
    _charter, rows, _h = parse(note)
    group = os.path.splitext(os.path.basename(note))[0]
    if not surface_alive():
        lines = ['spawn --tier %s %s "%s"' % (r["tier"], r["session"], task_for(r).replace('"', '\\"')) for r in rows]
        return [], lines
    inbox = os.environ.get("AIOS_INBOX_DIR") or os.path.join(os.path.expanduser("~"), ".aios", "spawn-inbox")
    os.makedirs(inbox, exist_ok=True)
    written = []
    for r in rows:
        path = os.path.join(inbox, r["session"] + ".json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump({"name": r["session"], "task": task_for(r), "tier": r["tier"], "group": group}, fh, ensure_ascii=False)
        written.append(path)
    return [], written


def main(argv):
    if len(argv) < 2 or argv[0] not in ("check", "launch"):
        print("usage: team-plan.py check|launch <note> [--approved]", file=sys.stderr)
        return 2
    cmd, note = argv[0], argv[1]
    if cmd == "check":
        errs = check(note)
        for e in errs:
            print("refused: " + e)
        if not errs:
            print("ok: the plan is valid")
        return 1 if errs else 0
    if "--approved" not in argv:
        print("refused: launch needs --approved, the operator's yes; nothing was written")
        return 1
    errs, out = launch(note)
    for e in errs:
        print("refused: " + e)
    if errs:
        return 1
    if out and out[0].startswith("spawn "):
        print("No live surface (AIOS App or Glass), so nothing was written. One line per member, to paste in a terminal:")
    else:
        print("Wrote %d spawn-inbox request(s), group '%s':" % (len(out), os.path.splitext(os.path.basename(note))[0]))
    for line in out:
        print("  " + line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
