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
they gave it. Env: AIOS_ROOT (vault, default: the root this file lives in), AIOS_INBOX_DIR, AIOS_SURFACES_DIR.
"""
import glob
import hashlib
import importlib.util
import json
import os
import re
import shlex
import unicodedata
import sys

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("AIOS_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))  # hooks/agents/ -> root
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


def untagged_files():
    """{name: path} for files under agents/ that would be agents but for the `agent` tag (#418)."""
    out = {}
    for kind, rel, fm in _load("list-agents").classify(ROOT):
        if kind == "unclear":
            for key in (fm.get("name"), os.path.basename(rel)[:-3]):   # a plan may use either
                if key:
                    out.setdefault(key, rel)
    return out


def known_tiers():
    # Read from resolve-tier's own RUNGS line, never by running it: on Windows a bare `bash` can be
    # WSL's launcher, which cannot read a Windows path, and Git Bash is often not on PATH.
    try:
        text = open(os.path.join(os.path.dirname(HERE), "pipeline", "resolve-tier"), encoding="utf-8").read()
    except OSError:
        return set()
    m = re.search(r'^RUNGS="([^"]+)"', text, re.M)
    return set(m.group(1).split()) if m else set()


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


NOTE_REF = ""   # set by main(): the project note, as the session will find it


def task_for(row):
    report = "operator" if row["reports to"].lower() == "operator" else row["reports to"]
    head = "Wear the `%s` agent (/aios:agent %s)." % (row["agent"], row["agent"])
    if NOTE_REF:
        head += " Read the Charter in the ## Team section of %s first." % NOTE_REF
    # The request file is named after the SENDER: crews reporting to one lead named it after the
    # lead, so two reports in the same second overwrote each other and one was lost unseen.
    tail = ("When it is done, report back with one spawn-inbox `send` to %s, written as "
            "~/.aios/spawn-inbox/%s-report.json (never a file named after %s): what you did and what is open."
            % (report, row["session"], report)
            if report != "operator" else "When it is done, tell the operator what you did and what is open.")
    return "%s %s %s" % (head, row["first task"].rstrip(), tail)


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
    elif any(unicodedata.category(ch) in ("Cc", "Cf", "Zl", "Zp") for ch in charter):
        errs.append("the charter holds an invisible or control character, so what is shown would not be what members read")
    if len(rows) < 2:
        errs.append("a team needs at least two members (%d found)" % len(rows))
    chiefs = [r for r in rows if r["role"].lower() == "chief of staff"]
    if len(chiefs) != 1:
        errs.append("exactly one row must be the chief of staff (%d found)" % len(chiefs))
    agents, tiers = known_agents(), known_tiers()
    untagged_by_name = None
    if not tiers:
        errs.append("could not read the tier list from hooks/pipeline/resolve-tier --list")
    sessions = [r["session"] for r in rows]
    for r in rows:
        who = r["session"] or "(no session)"
        if not SESSION.match(r["session"]):
            errs.append("%s: session names are lowercase kebab, at most three words" % who)
        if sessions.count(r["session"]) > 1:
            errs.append("%s: two members share this session name" % who)
        if r["agent"] not in agents:
            if untagged_by_name is None:
                untagged_by_name = untagged_files()
            untagged = untagged_by_name.get(r["agent"])
            errs.append("%s: no agent named '%s' under agents/" % (who, r["agent"])
                        + (" (%s has no `agent` tag: add `agent` to its `tags`)" % untagged if untagged else ""))
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
        elif any(unicodedata.category(ch) in ("Cc", "Cf", "Zl", "Zp") for ch in task_for(r)):
            errs.append("%s: the task holds an invisible or control character, so what is shown would not be what is sent" % who)
        elif len(task_for(r).encode("utf-8")) > MAX_TASK:
            errs.append("%s: the first task is too long to be typed in one line (keep it under ~%d bytes)" % (who, MAX_TASK - 150))
    # de-duplicate, keep order
    return list(dict.fromkeys(errs))


def surface_alive():
    d = os.environ.get("AIOS_SURFACES_DIR") or os.path.join(os.path.expanduser("~"), ".aios", "surfaces")
    # The one liveness check the framework allows: it never ends the process it checks (Windows).
    sys.path.insert(0, os.path.join(os.path.dirname(HERE), "claude-identity"))
    from _fs import pid_alive
    for f in glob.glob(os.path.join(d, "*.json")):
        try:
            if pid_alive(int(json.load(open(f, encoding="utf-8")).get("pid"))):
                return True
        except (ValueError, TypeError, OSError, AttributeError):
            continue
    return False


def plan_hash(charter, rows):
    """What the operator approved: the charter every member reads first, and every member's session,
    agent, tier and the exact task it will be sent. Shown by `check`, required by `launch`, computed
    from the same parsed rows that are then sent, so a note edited after the yes is refused."""
    blob = "\n".join(["charter|" + (charter or "")] +
                     ["%s|%s|%s|%s" % (r["session"], r["agent"], r["tier"], task_for(r)) for r in rows or []])
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:12]


def ps_quote(s):
    """A PowerShell single-quoted string. PowerShell treats the curly quotes as quote characters too,
    so every one of them is doubled, or a task could close the string and run the rest."""
    for q in ("'", "\u2018", "\u2019", "\u201a", "\u201b"):
        s = s.replace(q, q + q)
    return "'%s'" % s


def fingerprint(data):
    """Log the request in the bus log BEFORE it exists, as Hook D's Write hook does for a session's own
    writes, so the prompt the surface types into the new session is marked as delivered by the inbox,
    never as typed by the operator. A team launch must not be the one path that skips it."""
    sys.path.insert(0, os.path.join(os.path.dirname(HERE), "context"))
    import bus_log
    bus_log.record(data, "team-plan")


def write_request(path, data):
    """Never overwrite a pending request, never follow a planted link, never expose a half-written file
    to a surface watching the folder: write a private temp with O_EXCL, then rename into place."""
    if os.path.lexists(path):
        raise FileExistsError(path)
    fingerprint(data)
    tmp = "%s.%d.tmp" % (path, os.getpid())
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False)
    try:
        os.link(tmp, path)        # fails if the path appeared meanwhile: never replaces a request
    finally:
        os.unlink(tmp)


def launch(note, approved):
    errs = check(note)
    if errs:
        return errs, []
    charter, rows, _h = parse(note)          # parsed once: these rows are hashed AND sent
    now = plan_hash(charter, rows)
    if approved != now:
        return ["the plan changed after it was approved, or the approval names another plan "
                "(approved %s, plan is now %s): show it again and ask again" % (approved or "nothing", now)], []
    group = os.path.splitext(os.path.basename(note))[0]
    if not surface_alive():
        # These lines are pasted into a terminal, so a task holding `$(...)`, backticks or quotes must
        # stay one literal argument, never run: POSIX quoting here, PowerShell quoting on Windows.
        q = ps_quote if os.name == "nt" else shlex.quote
        flag = "-Tier" if os.name == "nt" else "--tier"     # the PowerShell spawn function's parameter
        lines = ["spawn %s %s %s %s" % (flag, q(r["tier"]), q(r["session"]), q(task_for(r))) for r in rows]
        return [], lines
    inbox = os.environ.get("AIOS_INBOX_DIR") or os.path.join(os.path.expanduser("~"), ".aios", "spawn-inbox")
    os.makedirs(inbox, exist_ok=True)
    written = []
    taken = [r["session"] for r in rows if os.path.lexists(os.path.join(inbox, r["session"] + ".json"))]
    if taken:
        return ["a request for %s is already waiting in the inbox; nothing was written" % ", ".join(taken)], []
    for r in rows:
        path = os.path.join(inbox, r["session"] + ".json")
        try:
            write_request(path, {"name": r["session"], "task": task_for(r), "tier": r["tier"], "group": group})
        except FileExistsError:
            return ["a request for %s appeared in the inbox while launching; written before it: %s"
                    % (r["session"], ", ".join(os.path.basename(w) for w in written) or "none")], []
        written.append(path)
    return [], written


def main(argv):
    if len(argv) < 2 or argv[0] not in ("check", "launch"):
        print("usage: team-plan.py check <note> | launch <note> --approved <plan-hash>", file=sys.stderr)
        return 2
    cmd, note = argv[0], argv[1]
    global NOTE_REF
    NOTE_REF = os.path.realpath(note)           # the real path: valid wherever the vault lives
    if cmd == "check":
        errs = check(note)
        for e in errs:
            print("refused: " + e)
        if not errs:
            charter, rows, _h = parse(note)
            h = plan_hash(charter, rows)
            print("ok: the plan is valid. Show the operator the charter and each member's task exactly as sent:")
            print("  Charter: %s" % charter)
            for r in rows:
                print("  %s (%s, %s): %s" % (r["session"], r["agent"], r["tier"], task_for(r)))
            print("plan: %s   (launch with --approved %s only after the operator's yes to exactly this)" % (h, h))
        return 1 if errs else 0
    if "--approved" not in argv or argv.index("--approved") + 1 >= len(argv):
        print("refused: launch needs --approved <plan-hash>, the operator's yes to the plan `check` showed; nothing was written")
        return 1
    errs, out = launch(note, argv[argv.index("--approved") + 1])
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
