#!/usr/bin/env python3
"""_kill_target.py -- what `spawn-kill <name>` may close, decided once (#417).

`spawn-kill` used to find its target with `pgrep -f "claude .*--remote-control --name $name" | head
-1` and send SIGKILL to that process's group. The pattern was not anchored, so `deploy` also matched
`deploy-eu` and the first match won; it only matched sessions started with `--remote-control`, so a
session the AIOS App started was never found; and when nothing matched it removed the files of a
session that might still be running. This helper replaces the pattern.

THE TARGET is the session whose `name` in the session registry (~/.claude/sessions/*.json, or under
$CLAUDE_CONFIG_DIR) is exactly the name asked for, whose pid is alive and is `claude`. Two such
sessions: refuse and list them. None: say so. A registry that cannot be read: refuse. There is no
fallback to the command line: a pattern on a command line is not an address.

WHAT IS CLOSED is the session's process group, only when the group is provably nothing more than
the session; otherwise only its pid. The rule is The-AIOS/aios-app#239's (`killScope`), plus one case
that rule does not recognise yet:

  * the process at that pid is `claude`;
  * the group is led by the session itself, or by its DIRECT PARENT when that parent is
      - the spawn wrapper's launcher (a non-login shell running `spawn-launch-<name>.sh`), or
      - the wrapper's respawn loop: a shell that is not a session leader, and the session's own
        environment carries CLAUDE_RESPAWN_CAPABLE=1 and CLAUDE_AGENT_NAME=<that name>. This is
        `spawn`'s in-shell path, which AIOS Glass and a person typing `spawn` both take: the loop
        runs in a subshell that leads its own group. Signalling only the pid there lets the loop
        start a new session 60 s later;
  * every member of the group is that leader, the session, or a descendant of the session;
  * the group is not the caller's own, and no other registered session is in it.

READING ANOTHER PROCESS'S ENVIRONMENT is reading where credentials live. Only the two variables above
are looked up; the environment is never printed, logged, returned or quoted in an error, whole or
in part. When it cannot be read on this platform the answer is "pid only", never a guess.

Commands (exit codes in brackets):
  resolve <name>       one line on stdout: `group <pgid> <pid> <start> <leader-start>` or
                       `pid <pid> <start> <why>` [0]; no live session [1]; more than one [2];
                       registry unreadable [3]; a start time unreadable [4]. Messages go to stderr.
  running <pid> <start>  [0] when the same process (same start time) is still running and is not a
                       zombie, [1] otherwise.
  exists <name> <since-epoch-seconds>  [0] when a live session has exactly that name and started at
                       or after that time, [1] otherwise. For spawn's start check.
Read-only: it never signals anything; the caller does.
"""
import glob
import json
import os
import re
import subprocess
import sys
import time

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
SHELLS = {"sh", "zsh", "bash", "dash", "fish", "ksh"}
LAUNCHER = re.compile(r"(^|[/\s])spawn-launch-[^/\s]+\.sh(\s|$)")
LOOP_VARS = ("CLAUDE_RESPAWN_CAPABLE", "CLAUDE_AGENT_NAME")


def registry_dir():
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    return os.path.join(base, "sessions")


def read_registry(d):
    """[(pid, name, startedAt-ms, cwd)] from the *.json files only. Raises OSError when the folder
    cannot be read. A file that does not parse is skipped: it is one session, not the registry."""
    if not os.path.isdir(d):
        raise OSError("no session registry at %s" % d)
    os.listdir(d)   # PermissionError surfaces here, before the glob hides it
    out = []
    for f in sorted(glob.glob(os.path.join(d, "*.json"))):
        try:
            with open(f, encoding="utf-8") as fh:
                rec = json.load(fh)
            pid = int(rec.get("pid") or os.path.basename(f)[:-5])
            if not 0 < pid < 2 ** 31:
                continue
            fn = rec.get("formerNames")
            former = [x if isinstance(x, str) else x["name"] for x in (fn if isinstance(fn, list) else [])
                      if isinstance(x, str) or (isinstance(x, dict) and isinstance(x.get("name"), str))]
            st = rec.get("startedAt")   # epoch ms; anything else is unreadable, and that entry is skipped below
            st = st if isinstance(st, (int, float)) and not isinstance(st, bool) and 0 < st < 1e14 else None
        except (OSError, ValueError, TypeError, AttributeError, OverflowError, RecursionError):
            continue
        name = rec.get("name")
        if isinstance(name, str):
            out.append((pid, name, st, str(rec.get("cwd") or ""), former))
    return out


def comm_name(comm):
    """The program's own name: no directory, no login-shell dash."""
    return comm.strip().split("/")[-1].lstrip("-")


SESSION_COMMS = ("claude", "claude.exe")   # the native binary; npm's package ships it as claude.exe


def parse_ps(text):
    """{pid: (ppid, pgid, comm)} from `ps -axo pid=,ppid=,pgid=,comm=`."""
    rows = {}
    for line in text.splitlines():
        m = re.match(r"^\s*(\d+)\s+(\d+)\s+(\d+)(?:\s+(.*\S))?\s*$", line)
        if m:
            rows[int(m.group(1))] = (int(m.group(2)), int(m.group(3)), m.group(4) or "")
    return rows


def kill_scope(rows, pid, name, own_pgid, other_pids, parent_command, loop_vars, is_session_leader):
    """Pure. ('group', pgid) or ('pid', why).

    name: the session's name, or the set of names it has carried (its registry name and formerNames:
    a session that renamed itself keeps the loop's CLAUDE_AGENT_NAME from when it started).
    rows: parse_ps output. parent_command: the session's parent's full command line, or None.
    loop_vars: {var: value} for LOOP_VARS read from the SESSION's environment, or None when it could
    not be read. is_session_leader(pid) -> True / False / None (unknown)."""
    names = {name} if isinstance(name, str) else set(name)
    me = rows.get(pid)
    if not me:
        return ("pid", "the process is not in the process table")
    ppid, g, comm = me
    if comm_name(comm) not in SESSION_COMMS:
        return ("pid", "the process at that pid is '%s', not a session" % comm_name(comm))
    if g <= 1:
        return ("pid", "the process group could not be read")
    if g == own_pgid:
        return ("pid", "the session is in the caller's own process group")
    if g != pid:
        parent = rows.get(ppid)
        if g != ppid or not parent:
            return ("pid", "the group is led by %d, which is neither the session nor its direct parent" % g)
        if comm_name(parent[2]) not in SHELLS:
            return ("pid", "the group is led by the session's parent, '%s', which is not a shell" % comm_name(parent[2]))
        launcher = not parent[2].strip().startswith("-") and bool(parent_command) and bool(LAUNCHER.search(parent_command))
        loop = (loop_vars is not None and loop_vars.get("CLAUDE_RESPAWN_CAPABLE") == "1"
                and loop_vars.get("CLAUDE_AGENT_NAME") in names and is_session_leader(ppid) is False)
        if not (launcher or loop):
            return ("pid", "the group is led by a shell that is neither the spawn wrapper's launcher nor its respawn loop")

    def descends(p):
        for _ in range(64):
            if p == pid:
                return True
            r = rows.get(p)
            if not r or r[0] == p:
                return False
            p = r[0]
        return False
    strangers = [p for p, r in rows.items() if r[1] == g and p != g and not descends(p)]
    if strangers:
        return ("pid", "the group holds %d process(es) that are not the session's (e.g. %d '%s')"
                % (len(strangers), strangers[0], comm_name(rows[strangers[0]][2])))
    if any(rows.get(o, (0, -1, ""))[1] == g for o in other_pids if o != pid):
        return ("pid", "another live session is in the same process group")
    return ("group", g)


# ---- the machine ------------------------------------------------------------------------------
def _ps(*args):
    # LC_ALL=C: `lstart` is printed in the locale's words, and it is parsed below.
    r = subprocess.run(["ps", *args], capture_output=True, text=True, timeout=5, env={**os.environ, "LC_ALL": "C"})
    return r.stdout if r.returncode == 0 else ""


def pid_alive(pid):
    sys.path.insert(0, HERE)
    from _fs import pid_alive as alive   # the side-effect-free probe (never os.kill(pid, 0) on Windows)
    return alive(pid)


def start_time(pid):
    return " ".join(_ps("-o", "lstart=", "-p", str(pid)).split())


def start_epoch(pid):
    try:
        return time.mktime(time.strptime(start_time(pid), "%a %b %d %H:%M:%S %Y"))
    except (ValueError, OverflowError):
        return None


def is_zombie(pid):
    return _ps("-o", "stat=", "-p", str(pid)).strip().startswith("Z")


def session_leader(pid):
    try:
        return os.getsid(pid) == pid
    except (OSError, AttributeError):
        return None


def loop_vars_of(pid):
    """{var: value} for LOOP_VARS only, from the process's environment, or None when it cannot be read.
    Nothing else is kept, and nothing read here is ever printed."""
    found = {}
    try:
        if sys.platform.startswith("linux"):
            with open("/proc/%d/environ" % pid, "rb") as fh:
                for item in fh.read().split(b"\0"):
                    k, sep, v = item.partition(b"=")
                    if sep and k.decode("ascii", "replace") in LOOP_VARS:
                        found[k.decode()] = v.decode("utf-8", "replace")
            return found
        if sys.platform == "darwin":
            # `ps -E` prints the command line followed by the environment. Take the command line on
            # its own, drop it from the front, and read KEY=VALUE tokens from what follows only, so an
            # argument that merely looks like an assignment is never taken for the environment.
            cmd = _ps("-ww", "-o", "command=", "-p", str(pid)).rstrip("\n")
            full = _ps("-ww", "-E", "-o", "command=", "-p", str(pid)).rstrip("\n")
            if not cmd or not full.startswith(cmd):
                return None
            for tok in full[len(cmd):].split():
                k, sep, v = tok.partition("=")
                if sep and k in LOOP_VARS and k not in found:
                    found[k] = v
            return found
    except Exception:   # unreadable here: the caller treats it as "pid only"
        return None
    return None


def live_named(name, reg, rows):
    """[(pid, startedAt, cwd, former)] of registered sessions with exactly that name that are running.
    An entry can outlive its session and its pid be handed to another `claude` that never registered
    (a headless run): a process that started after the entry was written is not that session. An entry
    or a process whose start cannot be read is not provably that session either."""
    out = []
    for pid, n, st, cwd, former in reg:
        if n != name or not pid_alive(pid) or pid not in rows or comm_name(rows[pid][2]) not in SESSION_COMMS:
            continue
        began = start_epoch(pid)
        if began is None or st is None or began > st / 1000.0 + 5:
            continue
        out.append((pid, st, cwd, former))
    return out


def cmd_resolve(name):
    try:
        reg = read_registry(registry_dir())
    except OSError as e:
        print("[spawn-kill] cannot read the session registry (%s); nothing was done." % e.__class__.__name__, file=sys.stderr)
        return 3
    rows = parse_ps(_ps("-ww", "-axo", "pid=,ppid=,pgid=,comm="))
    hits = live_named(name, reg, rows)
    if not hits:
        print("[spawn-kill] no live session named '%s'; nothing was done." % name, file=sys.stderr)
        return 1
    if len(hits) > 1:
        print("[spawn-kill] %d live sessions are named '%s'; refusing to choose. Close the right one from its own terminal:" % (len(hits), name), file=sys.stderr)
        for pid, _st, cwd, _f in hits:
            print("  pid %d  started %s  in %s" % (pid, start_time(pid) or "?", cwd or "?"), file=sys.stderr)
        return 2
    pid, _st, _cwd, former = hits[0]
    ppid = rows[pid][0]
    others = [r[0] for r in reg if r[0] != pid and pid_alive(r[0])]
    try:
        own = os.getpgid(0)
    except OSError:
        own = -1
    scope = kill_scope(rows, pid, {name, *former}, own, others, _ps("-ww", "-o", "command=", "-p", str(ppid)).strip() or None,
                       loop_vars_of(pid), session_leader)
    # The start times are how the caller knows, before each signal, that the pid still names the same
    # process. Without them nothing is signalled.
    st = start_time(pid).replace(" ", "_")
    lead = start_time(scope[1]).replace(" ", "_") if scope[0] == "group" else "-"
    if not st or not lead:
        print("[spawn-kill] cannot read the start time of '%s' (PID %d); nothing was done." % (name, pid), file=sys.stderr)
        return 4
    if scope[0] == "group":
        print("group %d %d %s %s" % (scope[1], pid, st, lead))
    else:
        print("pid %d %s %s" % (pid, st, scope[1]))
    return 0


def cmd_running(pid, st):
    return 0 if pid_alive(pid) and not is_zombie(pid) and start_time(pid).replace(" ", "_") == st else 1


def cmd_exists(name, since):
    try:
        reg = read_registry(registry_dir())
    except OSError:
        return 1
    rows = parse_ps(_ps("-ww", "-axo", "pid=,ppid=,pgid=,comm="))
    return 0 if any(st >= since * 1000 for _p, st, _c, _f in live_named(name, reg, rows)) else 1


def main(argv):
    try:
        if len(argv) == 2 and argv[0] == "resolve":
            return cmd_resolve(argv[1])
        if len(argv) == 3 and argv[0] == "running":
            return cmd_running(int(argv[1]), argv[2])
        if len(argv) == 3 and argv[0] == "exists":
            return cmd_exists(argv[1], float(argv[2]))
    except ValueError:
        pass
    print(__doc__.split("Commands")[1].split("Read-only")[0].rstrip(), file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
