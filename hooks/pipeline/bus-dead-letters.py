#!/usr/bin/env python3
"""Report spawn-inbox dead letters — requests the command bus could NOT deliver.

WHY THIS IS A SCRIPT AND NOT A SHELL ONE-LINER
----------------------------------------------
Scanning a directory for `*.undelivered` in shell has two idioms and each one
breaks in a different shell, in opposite directions:

  for x in $(ls dir/*.undelivered)   # relies on word-splitting an unquoted var.
                                     # bash splits on newlines; ZSH DOES NOT — it
                                     # hands you every path joined into one string,
                                     # so N files are read as 1 bogus filename and a
                                     # `|| echo "(unparseable)"` swallows the error.
  for x in dir/*.undelivered         # relies on an unmatched glob being harmless.
                                     # bash passes the literal pattern through (an
                                     # `-e` guard catches it); ZSH treats it as a
                                     # HARD ERROR and aborts before any guard runs —
                                     # and "no dead letters" is the common case.

Both failures are silent-looking: the first prints one plausible line per run while
telling you nothing, which is a false negative inside the feature built to end
silent failure. Python globs without word-splitting and returns an empty list
instead of erroring, so behaviour is identical on any shell and any OS.

Keeping it in a file (rather than inline `python3 -c "…"`) also means permission
matching sees a short, stable command prefix, and /today · /close-day ·
/housekeeping can share ONE implementation instead of drifting into three.

TWO FAILURE SHAPES, NOT ONE (the second added 2026-09-07)
---------------------------------------------------------
A request can fail to reach a session in two distinguishable ways, and only one of
them used to be reported:

  <name>.json.undelivered  a surface CLAIMED it, tried, and gave up. Retirement is
                           not delivery: the work did not happen and nobody was told.
  <name>.json              NOBODY EVER CLAIMED IT. On pickup a surface renames the
                           file to `<name>.json.holding`, so a plain `.json` still
                           sitting there after minutes means no fulfiller took it —
                           the operator quit the App, closed the IDE, or never had a
                           surface. It is never dead-lettered (retirement needs a
                           surface to perform it), so nothing surfaced it at all.

Measured 2026-09-07: a request addressed to a surface whose pid had been dead three
weeks sat unclaimed and completely invisible, while an identical one addressed to the
live surface was picked up in ~1s. The `.holding` rename is what makes this safe to
report — a legitimate wait (up to HOLD_STALE_MS, 45 min) is a `.holding` file and is
never flagged here, so this cannot become the check that always fires.

A THIRD SHAPE: TAKEN AND NEVER PUBLISHED
----------------------------------------
A surface that claims through the shared claim (The-AIOS/aios-app#229) no longer renames
a request straight to `.holding`. It takes it under a name of its own,

  <name>.json.claiming-<surface>-<pid>

stamps it there, and only then publishes it as `<name>.json.holding`. Three calls in a
row, so the name exists for an instant. But it is neither `*.json` nor `*.holding` nor
`*.undelivered`: if the process dies between those calls, nothing above reads the file,
and the request is gone without a dead letter. A running surface that knows the name
puts it back on its next recovery pass (at start and every 5 minutes), once the pid in
the name is gone. When no such surface is running, this report is the only thing that
says so.

THIS SCRIPT ONLY REPORTS. It never renames a claim back into the queue: a claimer that
is merely paused publishes the hold when it resumes, and a request put back meanwhile
would be fulfilled twice. Putting it back is the surfaces' job, and they do it only for
a pid that is gone.

CONTRACT (relied on by the commands that call it)
-------------------------------------------------
  * nothing wrong        -> print exactly `bus-dead-letters: none`
  * each dead letter     -> one line with to / action / reason / at
  * each unclaimed req   -> one `bus-unclaimed:` line with to / action / age
  * each abandoned claim -> one `bus-claim-abandoned:` line that STARTS with
                            `file=<file> restore-as=<request>.json` (or with
                            `file=(unusual-name)` when the name is not plain), then
                            age / to / action, and ENDS in
                            `claimer=<surface>:<pid> (<state>)`, where state is
                            `gone`, `still running` or `not checked`
  * if that check itself fails -> one `bus-claim-abandoned: (this check failed: …)`
                            line, with no claimer; the other two reports still print
  * anything printed from a request (a field, its file name, the error from reading
    it) stays on one line: control characters and line breaks become a space, so a
    request cannot forge a report line
  * unreadable file      -> still reported BY NAME, with the reason why
  * exit code            -> always 0; finding nothing is not a failure

A fresh request is NOT an anomaly: only files older than UNCLAIMED_AFTER_S are
reported, so the normal ~1s window between writing a request and its pickup never
shows up. See CLAUDE.md § Spawning Sessions.

Usage:  python3 hooks/pipeline/bus-dead-letters.py [inbox-dir]
"""

import glob
import json
import math
import os
import re
import sys
import time

# Text read from files (vault headings, request payloads, names) carries "→", "—" and
# accents. On a Windows console stdout/stderr default to cp1252, so print() raises
# UnicodeEncodeError on the first one and the tool emits nothing. Force UTF-8 on both.
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        try:
            _stream.reconfigure(encoding="utf-8", errors="replace")
        except (ValueError, OSError):
            pass  # a wrapped or redirected stream that cannot be reconfigured

DEFAULT_INBOX = "~/.aios/spawn-inbox"

# Grace period before an unclaimed request is worth mentioning. Pickup is ~1s in
# practice; 5 min is far outside that and far inside RETIRE_TTL_MS (10 min), so a
# stuck request is raised BEFORE the protocol would retire it rather than after.
UNCLAIMED_AFTER_S = 300


# A claim is three filesystem calls, so one that has lasted minutes is not in progress.
# The grace is longer than the 5 min on which a running surface restores an abandoned
# claim by itself: past it, either no surface that knows the name is running, or the pid
# in the name is still alive (a paused claimer, or a pid reused after a crash), and in
# both cases nobody else is going to say anything.
CLAIMING_AFTER_S = 600

# <request>.json.claiming-<surface>-<pid>. The surfaces match `app|glass`; any lowercase
# surface name is accepted here so a third surface is not silently left out. ASCII digits
# only and matched whole (fullmatch), as the surfaces do: a name they would never restore
# must not be reported as one they will.
CLAIMING_NAME = re.compile(r"(.+\.json)\.claiming-([a-z0-9]+)-([0-9]+)")


# A file name the commands may put in a shell command as it stands: no space, no quote,
# no shell metacharacter, nothing `_clean` would have altered.
PLAIN_NAME = re.compile(r"[A-Za-z0-9._-]+")


def _clean(value):
    """One line per field. A request's `name` and `action`, its FILE NAME, and the text of
    an error raised while reading it are all chosen by whoever wrote the request; printed
    raw, a line break in any of them would forge a second report line, and the commands
    act on what a line says."""
    return re.sub(r"[\x00-\x1f\x7f-\x9f\u2028\u2029]+", " ", str(value)).strip() or "?"


def _now():
    """The clock. AIOS_BUS_NOW (epoch seconds) replaces it for the tests of the claim
    report only: a test can backdate a file's mtime, and nothing can backdate its ctime."""
    try:
        now = float(os.environ["AIOS_BUS_NOW"])
    except (KeyError, ValueError):
        return time.time()
    # A value that is not a plain positive number is ignored, never obeyed: NaN would
    # compare false against the grace and report every claim with an unprintable age.
    return now if math.isfinite(now) and now > 0 else time.time()


def _pid_state(pid):
    """'gone', 'still running' or 'not checked', with no side effect on the process.

    Through the one liveness check the framework allows (claude-identity/_fs.py). The
    usual signal-0 probe is never sent from here: on Windows it is not a probe, it
    terminates the process.

    'still running' means a process with that pid exists as far as that check can tell.
    It may be the claimer, paused, or an unrelated process that got the pid later. The
    check errs towards 'still running' (a pid that exists and is not ours counts), which
    is the safe side: the commands put a request back only for a claimer that is gone.
    A pid of 0 or 1 is never a surface, and the surfaces read it as gone too.
    """
    try:
        n = int(pid)
    except ValueError:
        return "not checked"
    if n <= 1:
        return "gone"
    try:
        here = os.path.dirname(os.path.abspath(__file__))
        ident = os.path.join(os.path.dirname(here), "claude-identity")
        if ident not in sys.path:
            sys.path.insert(0, ident)
        from _fs import pid_alive
    except Exception:
        return "not checked"
    try:
        return "still running" if pid_alive(n) else "gone"
    except Exception:
        return "not checked"


def _taken_age(path):
    """Seconds since the file got its current name.

    A rename keeps the mtime of the request it came from, so a request that waited an
    hour would look like an hour-old claim the instant it is taken. The rename moves
    ctime, so the later of the two is when the claim began (or when it was stamped).
    On Windows ctime is the creation time and does not move; the age is then the
    request's, which can only over-report a claim caught in its one instant.
    """
    try:
        st = os.stat(path)
        return _now() - max(st.st_mtime, st.st_ctime)
    except OSError:
        return None


def abandoned_claims(inbox):
    """Requests a surface took and never published as a hold, older than the claim grace.

    The commands turn a line into a shell command, so the parts they act on are the
    script's own and sit where text from the request cannot reach them:

      bus-claim-abandoned: file=<F> restore-as=<R> age=<A> to=… action=… claimer=<S>:<P> (<state>)

    * `file=` and `restore-as=` come FIRST and hold no space: the file's name, and the
      request name it goes back to (computed here, so nobody splits a name by eye). They
      are printed only for a name made of letters, digits, dot, dash and underscore.
      Any other name prints `file=(unusual-name)` and no `restore-as=`: such a name
      would need quoting, or was altered when printed, and the commands then offer
      nothing but a look at the directory.
    * the line ENDS in the claimer and its state, whether or not the file could be read.
    * `to=` and `action=` are text from the request and sit in the middle.
    """
    out = []
    for path in sorted(glob.glob(os.path.join(inbox, "*.json.claiming-*"))):
        name = os.path.basename(path)
        m = CLAIMING_NAME.fullmatch(name)
        if not m:
            continue
        secs = _taken_age(path)
        if secs is None or not secs >= CLAIMING_AFTER_S:
            continue
        if PLAIN_NAME.fullmatch(name):
            head = "file=%s restore-as=%s age=%s" % (name, m.group(1), _fmt_age(secs))
        else:
            head = "file=(unusual-name) age=%s" % _fmt_age(secs)
        tail = "claimer=%s:%s (%s)" % (m.group(2), m.group(3), _pid_state(m.group(3)))
        try:
            with open(path, encoding="utf-8") as fh:
                doc = json.load(fh)
            if not isinstance(doc, dict):
                raise ValueError("top level is %s, expected object" % type(doc).__name__)
            out.append(
                "bus-claim-abandoned: %s to=%s action=%s %s"
                % (head, _clean(doc.get("name", "?")), _clean(doc.get("action", "spawn")), tail)
            )
        except Exception as exc:
            out.append("bus-claim-abandoned: %s (unreadable: %s) %s" % (head, _clean(exc), tail))
    return out


def _age(path):
    try:
        return time.time() - os.path.getmtime(path)
    except OSError:
        return None


def _fmt_age(secs):
    if secs is None:
        return "?"
    m = int(secs // 60)
    return "%dm" % m if m < 60 else "%dh%dm" % (m // 60, m % 60)


def unclaimed(inbox):
    """Plain *.json files nobody renamed to .holding, older than the grace period."""
    out = []
    for path in sorted(glob.glob(os.path.join(inbox, "*.json"))):
        secs = _age(path)
        if secs is None or secs < UNCLAIMED_AFTER_S:
            continue
        name = os.path.basename(path)
        try:
            with open(path, encoding="utf-8") as fh:
                doc = json.load(fh)
            doc = doc if isinstance(doc, dict) else {}
            # A hand-written `_claim` is not a real claim (the rename is), but if one
            # is present the file is at least mid-protocol — say so rather than guess.
            out.append(
                "bus-unclaimed: to=%s action=%s age=%s%s"
                % (
                    _clean(doc.get("name", "?")),
                    _clean(doc.get("action", "spawn")),
                    _fmt_age(secs),
                    " (carries _claim but was never renamed)" if doc.get("_claim") else "",
                )
            )
        except Exception as exc:
            out.append("bus-unclaimed: %s (unreadable: %s)" % (_clean(name), _clean(exc)))
    return out


def main(argv):
    inbox = os.path.expanduser(argv[1] if len(argv) > 1 else DEFAULT_INBOX)
    files = sorted(glob.glob(os.path.join(inbox, "*.undelivered")))
    stuck = unclaimed(inbox)
    try:
        taken = abandoned_claims(inbox)
    except Exception as exc:
        # The newest report must never cost the two older ones: say it failed and go on.
        taken = ["bus-claim-abandoned: (this check failed: %s)" % _clean(exc)]

    if not files and not stuck and not taken:
        print("bus-dead-letters: none")
        return 0

    for line in stuck + taken:
        print(line)

    for path in files:
        name = os.path.basename(path)
        try:
            with open(path, encoding="utf-8") as fh:
                doc = json.load(fh)
            if not isinstance(doc, dict):
                raise ValueError("top level is %s, expected object" % type(doc).__name__)
            und = doc.get("_undelivered") or {}
            print(
                "bus-dead-letter: to=%s action=%s reason=%s at=%s"
                % (
                    _clean(doc.get("name", "?")),
                    _clean(doc.get("action", "spawn")),
                    _clean(und.get("reason", "unrecorded")),
                    _clean(und.get("at", "?")),
                )
            )
        except Exception as exc:
            # Report it, never skip it — an unreadable dead letter is still a task
            # owed, and carrying the reason is what makes the cause visible in one
            # run instead of needing a debugger.
            print("bus-dead-letter: %s (unreadable: %s)" % (_clean(name), _clean(exc)))

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
