#!/usr/bin/env python3
"""transcript-secret-scan.py — find API keys and tokens you pasted into Claude Code sessions.

WHY. A token pasted into a chat stays in that session's transcript under ~/.claude/projects/, and transcripts can be
kept for years (see hooks/transcript-inventory.py). The commit scanner (hooks/git/secret-scan.sh) never sees them. This
looks, with the SAME pattern list (read from that file, so there is one list to maintain), and tells you where, not what.
The fix for a hit is to ROTATE the token. This tool never edits or redacts a transcript.

WHAT IT REPORTS. Per distinct value: the kind of secret, the date of the transcript entry, the transcript file and line,
and the value masked to its last 4 characters. The value itself is never printed, logged or stored. The same token pasted
in several places is one value (grouped by a short fingerprint, shown as its id).

USAGE
  transcript-secret-scan.py scan            read only what was added since the last run; write the report
  transcript-secret-scan.py report          print the report path and the counts (needs a completed scan)
  transcript-secret-scan.py ack ID [ID...]  mark values as rotated or dead: they stop counting
  --root DIR         transcripts folder (default: $CLAUDE_CONFIG_DIR/projects, else ~/.claude/projects)
  --state-dir DIR    where state and the report live (default: $AIOS_TRANSCRIPT_SCAN_DIR, else ~/.aios/transcript-scan)
  --notify "CMD"     after a scan, if there are open values you have not been told about, run CMD once with one extra
                     argument: a one-line summary (no values). At most once per 20 hours. Use it to message yourself.

The first run reads every transcript (it can take minutes on a large history) and reports a backlog. Later runs read only
new bytes. Each machine scans its own transcripts; nothing is copied elsewhere. Run it on a schedule (cron, launchd, Task
Scheduler); one run per night is plenty.

Exit 0 = scanned, whatever was found · 1 = scanned but some folder or file could not be read (the report says
INCOMPLETE) or the notify command failed · 2 = nothing was scanned (bad folder, unreadable state, no patterns).
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCANNER = os.path.join(HERE, "git", "secret-scan.sh")
NOTIFY_EVERY = 20 * 3600
SCAN_VERSION = "1"      # bump when the matching rules change: every transcript is then read again
# The report names transcript files, which can hold non-ASCII; a cp1252 console would otherwise stop the run.
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")


def default_root():
    return os.path.join(os.path.expanduser(os.environ.get("CLAUDE_CONFIG_DIR", "~/.claude")), "projects")


def default_state():
    return os.path.expanduser(os.environ.get("AIOS_TRANSCRIPT_SCAN_DIR", "~/.aios/transcript-scan"))


# ---------------------------------------------------------------------------------------------------- patterns
def load_patterns(path=SCANNER):
    """[(regex, kind)] from the PATTERNS=( ... ) array of secret-scan.sh. The kind is the entry's trailing comment."""
    out, inside = [], False
    try:
        with open(path, encoding="utf-8") as f:
            for ln in f:
                if re.match(r"^\s*PATTERNS=\(", ln):
                    inside = True
                    continue
                if inside and ln.strip().startswith(")"):
                    break
                m = re.match(r"^\s*'([^']+)'\s*(?:#\s*(.*))?$", ln) if inside else None
                if m:
                    out.append((m.group(1), (m.group(2) or "secret").strip()[:40]))
    except OSError:
        pass
    if not out:
        raise RuntimeError("could not read the secret patterns from %s: nothing was scanned" % path)
    return out


def compile_patterns(pats):
    return [(re.compile(p), kind) for p, kind in pats]


# ---------------------------------------------------------------------------------------------------- files
class Store:
    def __init__(self, home):
        self.home = home

    def p(self, name):
        return os.path.join(self.home, name)

    def load(self, name, default):
        """The saved file, `default` only when it does not exist yet. A corrupt file is an error, never "nothing found"."""
        try:
            with open(self.p(name), encoding="utf-8") as f:
                return json.load(f)
        except FileNotFoundError:
            return default
        except (OSError, ValueError) as e:
            raise RuntimeError("%s is unreadable (%s): fix or remove it, then run a full rescan" % (self.p(name), e.__class__.__name__))

    def save(self, name, obj):
        os.makedirs(self.home, mode=0o700, exist_ok=True)
        tmp = "%s.%d.tmp" % (self.p(name), os.getpid())
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(obj, f)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, self.p(name))


class Locked:
    """One scan, ack or notify at a time on this machine; the whole load -> scan -> save transaction holds it."""

    def __init__(self, home):
        self.path = os.path.join(home, "lock")
        os.makedirs(home, mode=0o700, exist_ok=True)

    def __enter__(self):
        self.fh = open(self.path, "a")
        try:
            import fcntl
            fcntl.flock(self.fh, fcntl.LOCK_EX)
        except ImportError:                                # Windows
            import msvcrt
            self.fh.seek(0)
            msvcrt.locking(self.fh.fileno(), msvcrt.LK_LOCK, 1)
        return self

    def __exit__(self, *a):
        self.fh.close()


def head_of(path):
    """Fingerprint of the first 4 KB: a transcript only grows at its end, so a changed start means a different file."""
    try:
        with open(path, "rb") as f:
            return hashlib.sha256(f.read(4096)).hexdigest()[:16]
    except OSError:
        return ""


B64 = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/_-")
RUN = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
MAX_RUN = 200            # a real key is shorter than this; a base64 blob or an attachment id is not


def standalone(line, m):
    """A pasted key stands alone. A match inside a longer base64 run (an image blob, an attachment id) is not one.
    The match is extended to the whole run of key characters (some patterns stop short of a key's end); the character
    before it and the one after the run must not be base64 characters, and the run must not be long. A key right after
    a JSON-escaped newline, tab or return, or after `//` (https://TOKEN@host), starts on its own. The only context veto is the text IMMEDIATELY
    before the match naming an attachment id or an image payload field, never ordinary words nearby."""
    if m.group(0).startswith("-----BEGIN"):         # a key header is not base64 text (a diff line starts `+-----BEGIN`)
        return True
    a, b = m.start(), m.end()
    while b < len(line) and line[b] in RUN:
        b += 1
    escaped_break = line[max(0, a - 2):a] in ("\\n", "\\t", "\\r", "//")   # a new line, or the start of a URL authority
    if a > 0 and line[a - 1] in "+-" and re.search(r"(\\[nrt]|[\"' ]|^)$", line[:a - 1]):
        escaped_break = True                       # a diff addition or removal line: `+TOKEN` / `-TOKEN` at the start of a line
    if (a > 0 and line[a - 1] in B64 and not escaped_break) or (b < len(line) and line[b] in "+/") or b - a > MAX_RUN:
        return False
    return True


def day_of(line):
    try:
        t = json.loads(line).get("timestamp")
        return t[:10] if isinstance(t, str) and re.match(r"^\d{4}-\d{2}-\d{2}", t) else ""
    except (ValueError, AttributeError):
        return ""


def scan_file(path, st, pats):
    """New hits since the recorded offset -> (hits, new offset, line count). A hit = (kind, line, fingerprint, last4, day)."""
    size = os.path.getsize(path)
    off, lines = st.get("off", 0), st.get("lines", 0)
    head = head_of(path)
    if size < off or (off and st.get("head") != head):      # truncated, or the start changed: it was rewritten
        off, lines = 0, 0
    hits = []
    with open(path, "rb") as f:
        f.seek(off)
        pos = off
        for raw in f:
            if not raw.endswith(b"\n") and pos + len(raw) >= size:
                break                                      # a half-written last line: read it next time
            pos += len(raw)
            lines += 1
            line = raw.decode("utf-8", "ignore")
            for rx, kind in pats:
                for m in rx.finditer(line):
                    if not standalone(line, m):
                        continue
                    v = m.group(0)
                    body = line[m.start(): m.end() + 240] if v.startswith("-----BEGIN") else v   # a key header is shared by every key
                    hits.append((kind, lines, hashlib.sha256(body.encode()).hexdigest()[:8], v[-4:], day_of(line)))
    return hits, pos, lines


def scan(root, store, pats):
    if not os.path.isdir(root):
        raise RuntimeError("transcripts folder %s does not exist: nothing was scanned" % root)
    state = store.load("state.json", {})
    digest = hashlib.sha256((SCAN_VERSION + json.dumps([p for p, _k in pats])).encode()).hexdigest()[:16]
    hits = store.load("hits.json", {})
    if state and (not os.path.exists(store.p("hits.json")) or state.get("_patterns") != digest):
        state, hits = {}, {}             # older pattern list or scan rules: read everything again and rebuild every hit
    state["_patterns"] = digest
    rx = compile_patterns(pats)
    new = seen = 0
    errors = []
    for dp, _dn, fns in os.walk(root, onerror=lambda e: errors.append(str(getattr(e, "filename", e)))):
        for fn in fns:
            if not fn.endswith(".jsonl"):
                continue
            p = os.path.join(dp, fn)
            try:
                if not os.access(p, os.R_OK):
                    raise OSError("not readable")
                st, mt = state.get(p, {}), os.path.getmtime(p)
                if st.get("mtime") == mt and st.get("off") == os.path.getsize(p):
                    continue
                got, off, lines = scan_file(p, st, rx)
            except OSError:
                errors.append(p)
                continue
            seen += 1
            state[p] = {"off": off, "lines": lines, "mtime": mt, "head": head_of(p)}
            rel = os.path.relpath(p, root)
            for kind, ln, fp, last4, day in got:
                k = "%s|%d|%s" % (rel, ln, fp)
                if k not in hits:
                    hits[k] = {"kind": kind, "day": day, "last4": last4}
                    new += 1
    store.save("hits.json", hits)            # hits first: a crash can then only re-read bytes, never lose a hit
    store.save("state.json", state)
    store.save("errors.json", errors[:200])
    store.save("last-scan.json", {"at": time.time(), "root": root, "errors": len(errors)})
    return {"files": seen, "new_hits": new, "total_hits": len(hits), "errors": len(errors)}


# ---------------------------------------------------------------------------------------------------- report
def summarise(store):
    hits = store.load("hits.json", {})
    acked = set(store.load("acked.json", []))
    values = {}
    for k, h in hits.items():
        rel, ln, fp = k.rsplit("|", 2)
        v = values.setdefault(fp, {"kind": h["kind"], "last4": h["last4"], "where": [], "days": []})
        v["where"].append((rel, int(ln)))
        if h.get("day"):
            v["days"].append(h["day"])
    live = {fp: v for fp, v in values.items() if fp not in acked}
    return hits, values, live, acked


def write_report(store):
    if store.load("last-scan.json", None) is None:
        raise RuntimeError("no scan has completed yet: nothing was examined (run `scan` first)")
    hits, _values, live, acked = summarise(store)
    errs = store.load("errors.json", [])
    by = {}
    for v in live.values():
        by[v["kind"]] = by.get(v["kind"], 0) + 1
    lines = ["# Secret-shaped values in Claude Code transcripts", "",
             ("**INCOMPLETE: %d folder(s) or file(s) could not be read; a clean count here is not a clean bill.**" % len(errs))
             if errs else "Coverage: every transcript file was readable.", "",
             "Written %s. Values are masked to their last 4 characters and never stored. The fix is to rotate the token; "
             "`ack ID` marks one as rotated or dead." % time.strftime("%Y-%m-%d %H:%M"), "",
             "**%d distinct value(s) open, %d hit(s) in total, %d acknowledged.**" % (len(live), len(hits), len(acked)), ""]
    for kind, n in sorted(by.items(), key=lambda x: -x[1]):
        lines.append("- %s: %d" % (kind, n))
    lines += ["", "| id | kind | first seen | places | value | first place (file:line) |", "|---|---|---|---|---|---|"]
    for fp, v in sorted(live.items(), key=lambda x: min(x[1]["days"] or ["9999"])):
        w = sorted(v["where"])
        lines.append("| %s | %s | %s | %d | ...%s | %s:%d |" % (fp, v["kind"], min(v["days"]) if v["days"] else "?",
                                                                len(w), v["last4"], w[0][0], w[0][1]))
    os.makedirs(store.home, mode=0o700, exist_ok=True)
    path = store.p("report.md")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return path, live


def notify(store, live, path, cmd, run=subprocess.run):
    """Run the operator's command once with a one-line summary, when an open value has not been announced yet."""
    meta = store.load("notified.json", {"at": 0, "ids": []})
    fresh = sorted(set(live) - set(meta.get("ids", [])))
    if not cmd or not fresh or time.time() - meta.get("at", 0) < NOTIFY_EVERY:
        return "none"
    msg = "%d secret-shaped value(s) in Claude Code transcripts (%d new); rotate the live ones. Report: %s" % (
        len(live), len(fresh), path)
    r = run(shlex.split(cmd) + [msg], capture_output=True, text=True, timeout=60)
    if r.returncode == 0:
        store.save("notified.json", {"at": time.time(), "ids": sorted(set(meta.get("ids", [])) | set(live))})
        return "sent"
    print("transcript-secret-scan: the notify command FAILED (exit %d): %s" % (r.returncode, (r.stderr or "").strip()[:150]),
          file=sys.stderr)
    return "failed"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("cmd", choices=["scan", "report", "ack"])
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--root")
    ap.add_argument("--state-dir")
    ap.add_argument("--notify")
    a = ap.parse_args(argv)
    store = Store(os.path.expanduser(a.state_dir) if a.state_dir else default_state())
    try:
        with Locked(store.home):
            if a.cmd == "ack":
                acked = set(store.load("acked.json", []))
                acked |= {i for i in a.ids if re.fullmatch(r"[0-9a-f]{8}", i)}
                store.save("acked.json", sorted(acked))
                print("acknowledged: %d" % len(acked))
                return 0
            if a.cmd == "scan":
                r = scan(os.path.expanduser(a.root) if a.root else default_root(), store, load_patterns())
                path, live = write_report(store)
                print("scanned %d changed file(s); %d new hit(s); %d distinct value(s) open; %d read error(s); report %s" % (
                    r["files"], r["new_hits"], len(live), r["errors"], path))
                told = notify(store, live, path, a.notify)
                return 1 if (r["errors"] or told == "failed") else 0
            path, live = write_report(store)
            print("%d distinct value(s) open; report %s" % (len(live), path))
            return 0
    except RuntimeError as e:
        print("transcript-secret-scan: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
