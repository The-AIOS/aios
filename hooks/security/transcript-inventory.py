#!/usr/bin/env python3
"""transcript-inventory.py — what your Claude Code session transcripts are, and which are throwaways.

WHY. Claude Code keeps every session as a transcript under ~/.claude/projects/, and deletes the ones
older than `cleanupPeriodDays` (default 30) at every session start, silently. Raising that keeps the
sessions worth keeping (a long named session you reopen with resume, an arc you learn from), but it
also keeps every headless probe and every test run, which pile up. This sorts them, so the operator
can archive the throwaways on purpose instead of letting age delete everything.

CLASSES (from each transcript's own records, never its file name):
  named      the session has a name (an `agent-name` record): spawned workers, primaries, resumes
  headless   `claude -p` or the SDK (entrypoint sdk-cli / sdk-py): routines, probes, test harnesses
  temp-run   started in a temp folder (/tmp, /var/folders, $TMPDIR): test and dry runs
  unnamed    an interactive session with no name

A THROWAWAY CANDIDATE is a headless or temp-run transcript older than --older-than days (default 14),
and never a named one. Named and unnamed interactive sessions are only counted, never proposed.

USAGE
  transcript-inventory.py                      the inventory and the candidates (changes nothing)
  transcript-inventory.py --json
  transcript-inventory.py --archive [--to DIR] archive the candidates into DIR/transcripts-<date>.tar.gz,
                                               verify every one is in it, THEN delete them. Only run
                                               this after the operator said yes to the list.
$CLAUDE_CONFIG_DIR overrides ~/.claude. Default archive folder: ~/claude-archive. Exit 0 ok · 1 the
archive could not be written or verified (nothing deleted).
"""
import argparse
import datetime as dt
import json
import os
import re
import sys
import tarfile
import tempfile
import time

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

TEMP_CWD = re.compile(r"^(/tmp/|/private/tmp/|/var/folders/|/private/var/folders/)")


def config_dir():
    return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")


def classify(path, max_lines=400):
    """-> (class, name). Reads only the first records; a transcript states its shape early."""
    name, entry, cwd = "", "", ""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for i, line in enumerate(fh):
                if i >= max_lines:
                    break
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(rec, dict):
                    continue
                if rec.get("type") == "agent-name" and rec.get("agentName"):
                    name = rec["agentName"]
                entry = entry or rec.get("entrypoint") or ""
                cwd = cwd or rec.get("cwd") or ""
    except OSError:
        return "unreadable", ""
    tmp = os.path.realpath(tempfile.gettempdir())
    if name:
        return "named", name
    if entry in ("sdk-cli", "sdk-py"):
        return "headless", ""
    if cwd and (TEMP_CWD.match(cwd) or os.path.realpath(cwd).startswith(tmp + os.sep)):
        return "temp-run", ""
    return "unnamed", ""


def inventory(older_than_days):
    base = os.path.join(config_dir(), "projects")
    now = time.time()
    rows = []
    if os.path.isdir(base):
        for proj in sorted(os.listdir(base)):
            d = os.path.join(base, proj)
            if not os.path.isdir(d):
                continue
            for f in sorted(os.listdir(d)):
                if not f.endswith(".jsonl"):
                    continue
                p = os.path.join(d, f)
                try:
                    st = os.stat(p)
                except OSError:
                    continue
                cls, name = classify(p)
                age = (now - st.st_mtime) / 86400
                rows.append({"path": p, "class": cls, "name": name, "bytes": st.st_size,
                             "age_days": round(age, 1),
                             "candidate": cls in ("headless", "temp-run") and age > older_than_days})
    return rows


def retention():
    try:
        with open(os.path.join(config_dir(), "settings.json"), encoding="utf-8") as fh:
            v = json.load(fh).get("cleanupPeriodDays")
        return int(v) if v is not None else None
    except (OSError, ValueError, TypeError):
        return None


def mb(n):
    return "%.1f MB" % (n / 1048576)


def archive(cands, to):
    """Archive, verify by name AND size, then delete. Returns (archive_path, deleted, kept)."""
    # Transcripts are whole sessions: private. The folder is 0700 and refused if it is a symlink or
    # not ours; the archive is created exclusively at 0600, never with the default umask.
    os.makedirs(to, mode=0o700, exist_ok=True)
    st = os.lstat(to)
    import stat
    if not stat.S_ISDIR(st.st_mode) or (hasattr(os, "getuid") and st.st_uid != os.getuid()):
        raise OSError("%s is not a folder owned by you" % to)
    if hasattr(os, "getuid") and stat.S_IMODE(st.st_mode) & 0o077:
        os.chmod(to, 0o700)
    out = os.path.join(to, "transcripts-%s.tar.gz" % dt.datetime.now().strftime("%Y-%m-%d-%H%M%S"))
    root = config_dir()
    fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_BINARY", 0), 0o600)
    with os.fdopen(fd, "wb") as fh, tarfile.open(fileobj=fh, mode="w:gz") as tar:
        for r in cands:
            tar.add(r["path"], arcname=os.path.relpath(r["path"], root))
    with tarfile.open(out, "r:gz") as tar:
        stored = {m.name: m.size for m in tar.getmembers()}
    deleted, kept = [], []
    for r in cands:
        rel = os.path.relpath(r["path"], root)
        if stored.get(rel) == os.path.getsize(r["path"]):
            os.remove(r["path"]); deleted.append(rel)
        else:
            kept.append(rel)                     # not verifiably archived: never deleted
    return out, deleted, kept


def main(argv):
    ap = argparse.ArgumentParser(prog="transcript-inventory.py")
    ap.add_argument("--older-than", type=int, default=14)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--archive", action="store_true")
    ap.add_argument("--to", default=os.path.join(os.path.expanduser("~"), "claude-archive"))
    a = ap.parse_args(argv)
    rows = inventory(a.older_than)
    cands = [r for r in rows if r["candidate"]]
    if a.archive:
        if not cands:
            print("transcript-inventory: no throwaway candidates; nothing archived or deleted.")
            return 0
        try:
            out, deleted, kept = archive(cands, os.path.expanduser(a.to))
        except (OSError, tarfile.TarError) as e:
            print("transcript-inventory: the archive could not be written or verified (%s). Nothing deleted." % e)
            return 1
        print("transcript-inventory: archived %d transcript(s) to %s, then deleted them." % (len(deleted), out))
        if kept:
            print("  kept %d that could not be verified in the archive: %s" % (len(kept), ", ".join(kept[:5])))
        return 0
    if a.json:
        print(json.dumps({"retention_days": retention(), "transcripts": rows}, indent=2))
        return 0
    days = retention()
    print("Transcripts in %s (kept %s):" % (os.path.join(config_dir(), "projects"),
          "%d days" % days if days else "30 days, Claude Code's default"))
    for cls in ("named", "unnamed", "headless", "temp-run", "unreadable"):
        sel = [r for r in rows if r["class"] == cls]
        if sel:
            print("  %-10s %5d  %s" % (cls, len(sel), mb(sum(r["bytes"] for r in sel))))
    if rows:
        print("  oldest     %d days" % max(r["age_days"] for r in rows))
    if cands:
        print("Throwaway candidates (headless or temp-folder runs older than %d days): %d, %s."
              % (a.older_than, len(cands), mb(sum(r["bytes"] for r in cands))))
        print("  Archive and delete them only after the operator says yes:  transcript-inventory.py --archive")
    else:
        print("No throwaway candidates.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
