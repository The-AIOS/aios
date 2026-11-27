#!/usr/bin/env python3
"""The name a session answers to, read from its transcript: the one reader the Python hooks share.

A transcript carries `{"type":"agent-name","agentName":"…","sessionId":"…"}` records. The harness
writes one at the start and repeats it as the session goes, and a session that renames itself adds
a record with the new name. So the name a session answers to NOW is its LAST record, read over the
whole file: the first record is the name it was born with, and the end of a long transcript may
hold no record at all (measured: none in the last 4 MB of a 30 MB one).

That is the rule both surfaces resolve `resume` by (`core/resumeTarget`, `latestAgentName`). Three
hooks had each written their own reader and two disagreed with it, so a renamed session was known
by different names depending on who asked. They import this instead.

A record is a LINE that begins `{"type":"agent-name"`, compact, as the harness writes it (measured
on one machine: 36,731 of 36,731 records). Anchoring to the start of the line is what keeps a tool
result that QUOTES a record from being read as one, and it is the same test `hooks/context/whoami`
makes with grep. `whoami` stays in bash because it is the first command of every session and must
not wait for an interpreter; `tests/session-name.test.sh` runs the same transcripts through both
and fails when they answer differently.

    session_name.py <transcript.jsonl>      print the name, or nothing

Not used by `hooks/security/transcript-inventory.py` on purpose: that one only asks whether a
transcript is named at all, and reads the first records alone to stay cheap over thousands of files.
"""
import glob
import os
import re
import sys

RECORD_PREFIX = b'{"type":"agent-name"'
_NAME = re.compile(rb'"agentName":"([^"]+)"')
_SAFE_ID = re.compile(r"^[A-Za-z0-9-]+$")


def name_in_record(line):
    """The name in one transcript line when that line is an agent-name record, else ''.

    Takes bytes or str. A record with an empty name is no record."""
    if isinstance(line, str):
        line = line.encode("utf-8", "replace")
    if not line.startswith(RECORD_PREFIX):
        return ""
    found = _NAME.findall(line)
    return found[-1].decode("utf-8", "replace") if found else ""


def last_agent_name(path):
    """The last name recorded in the transcript at `path`; '' when it has none or cannot be read."""
    name = ""
    try:
        with open(path, "rb") as fh:
            for line in fh:
                if line.startswith(RECORD_PREFIX):
                    name = name_in_record(line) or name
    except OSError:
        return ""
    return name


def config_dir():
    return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")


def transcripts_of(session_id, base=None):
    """Every transcript file of a session id. An id that is not letters, digits and hyphens finds
    nothing: it goes into a glob, and it is a file name, not something anyone typed."""
    if not isinstance(session_id, str) or not _SAFE_ID.match(session_id):
        return []
    root = os.path.join(base or config_dir(), "projects")
    return sorted(glob.glob(os.path.join(root, "*", session_id + ".jsonl")))


def session_name(session_id, base=None):
    """The name the session with this id answers to, from its transcript; '' when unknown."""
    for path in transcripts_of(session_id, base):
        name = last_agent_name(path)
        if name:
            return name
    return ""


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.stderr.write("usage: session_name.py <transcript.jsonl>\n")
        sys.exit(2)
    out = last_agent_name(sys.argv[1])
    if out:
        sys.stdout.buffer.write(out.encode("utf-8") + b"\n")
