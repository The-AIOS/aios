#!/usr/bin/env python3
"""install-settings.py — wire the universal hooks into ~/.claude/settings.json, in plain language.

WHY. Setup used to have the session edit ~/.claude/settings.json with its file-edit tool, so a new
operator was asked to approve a wall of JSON they could not read, at the moment they trust the
system least. The hooks are the same; what changes is the approval. This merges them for you,
keeps every key you already have, shows in one line per hook what each one does for you, and asks
for one yes (a command, not a JSON diff).

WHAT IT WIRES (SETUP §10 is the reference; tests/install-settings.test.sh keeps the two in step):
  A  the clock            -- every message carries the real date and time
  B  the status line      -- context and quota display; feeds the quota autopilot's cache
  C  the venture guard    -- only once a company is mounted (a ventures/*/.{v}-sync marker exists)
  D  provenance           -- labels text you did not write (email, chat, docs, web, inbox prompts)
  E  the floor at start   -- a compact context floor delivered to every new session
  F  the model-switch log -- one line whenever a session's model changes under it
  R  transcript retention -- keep session transcripts for 10 years instead of Claude Code's 30 days
     (set only when the file has no cleanupPeriodDays; an operator's own value is never changed)

USAGE
  install-settings.py              show what would change (default: changes nothing)
  install-settings.py --apply      back up settings.json, merge, write, read back and verify

Merge rules: a hook already present (matched by its script, however it is spelled) is left alone;
an existing statusLine is never replaced (the summary says so, because hook B feeds the quota cache);
every other key in the file is kept byte for byte in meaning. A symlinked settings.json stays a
link: the file it points to is backed up and updated. Exit 0 ok · 1 the file is not valid JSON, or is
JSON of a shape this cannot merge into (e.g. "statusLine": null, a hooks event that is not a list),
or could not be written -- nothing written, no backup left · 2 the write could not be verified (the
backup is named).
"""
import argparse
import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("AIOS_ROOT") or os.path.dirname(HERE)
PROVENANCE_MATCHER = ("mcp__forum__.*|mcp__google-workspace__.*|mcp__claude_ai_.*|mcp__slack__.*|"
                      "mcp__atlassian__.*|mcp__claude-in-chrome__.*|mcp__notebooklm.*|WebFetch|WebSearch")


def windows_python():
    if os.environ.get("AIOS_WIN_PYTHON"):  # tests, or an operator who knows better than the probe
        return os.environ["AIOS_WIN_PYTHON"]
    for cand in (["python3"], ["python"], ["py", "-3"]):
        try:
            if subprocess.run(cand + ["-c", ""], capture_output=True, timeout=20).returncode == 0:
                return " ".join(cand)
        except (OSError, subprocess.TimeoutExpired):
            continue
    return "python"


# A hook command that names a missing file must be a no-op, never a block. Claude Code reads exit 2
# from a hook as BLOCK, and `python3 missing.py` exits 2 ("can't open file") -- so when ~/aios moves,
# is renamed, or a release renames a hook, every prompt and every tool call is refused, including in
# the session that could repair it. `[ ! -f FILE ] || CMD` exits 0 when FILE is missing and CMD's own
# code when it is present, so a hook that means to block still can. Hook commands run through a POSIX
# shell on every platform (Git Bash on Windows), so one form serves both.
SCRIPT = re.compile(r'("[^"]*?hooks/[^"]+?\.(?:py|sh|ps1)"|[^\s"\']*hooks/[^\s"\']+?\.(?:py|sh|ps1))')
GUARDED = re.compile(r"^\s*\[\s+!\s+-f\s")


def guard(cmd):
    """`[ ! -f <script> ] || <cmd>`, using the script path exactly as the command spells it."""
    if GUARDED.match(cmd):
        return cmd
    m = SCRIPT.search(cmd)
    return "[ ! -f %s ] || %s" % (m.group(1), cmd) if m else cmd


def plan(platform, root, venture_guard):
    """[(key, event, matcher, command, timeout, what it does)] in SETUP §10's exact command forms."""
    if platform == "windows":
        py = windows_python()
        r = root.replace("\\", "/")
        h = lambda s: '%s "%s/hooks/%s"' % (py, r, s)
        clock = 'powershell -NoProfile -ExecutionPolicy Bypass -File "%s/hooks/inject-datetime.ps1"' % r
        rows = [
            ("A", "UserPromptSubmit", None, clock, None),
            ("D", "UserPromptSubmit", None, h("provenance.py") + " --prompt", 10),
            ("D", "PreToolUse", "Write|Edit", h("bus_log.py") + " --hook", 10),
            ("D", "PostToolUse", PROVENANCE_MATCHER, h("provenance.py") + " --tool", 10),
            ("E", "SessionStart", None, h("floor-at-start.py"), 60),
            ("F", "PostModelSwitch", None, h("model-switch-log.py"), 10),
        ]
        if venture_guard:
            rows.append(("C", "PreToolUse", "Edit|Write|MultiEdit|NotebookEdit", h("guard-venture-mount.py"), 10))
        # One program per render (#292): context-monitor.py also writes the rate-limit cache.
        status = '%s "%s/hooks/claude-identity/context-monitor.py"' % (py, r)
    else:
        rows = [
            ("A", "UserPromptSubmit", None, "bash ~/aios/hooks/inject-datetime.sh", None),
            ("D", "UserPromptSubmit", None, "python3 ~/aios/hooks/provenance.py --prompt", 10),
            ("D", "PreToolUse", "Write|Edit", "python3 ~/aios/hooks/bus_log.py --hook", 10),
            ("D", "PostToolUse", PROVENANCE_MATCHER, "python3 ~/aios/hooks/provenance.py --tool", 10),
            ("E", "SessionStart", None, "python3 ~/aios/hooks/floor-at-start.py", 60),
            ("F", "PostModelSwitch", None, "python3 ~/aios/hooks/model-switch-log.py", 10),
        ]
        if venture_guard:
            rows.append(("C", "PreToolUse", "Edit|Write|MultiEdit|NotebookEdit",
                         "python3 ~/aios/hooks/guard-venture-mount.py", 10))
        status = "python3 $HOME/aios/hooks/claude-identity/context-monitor.py"
    rows = [(k, ev, mt, guard(cmd), to) for k, ev, mt, cmd, to in rows]
    return rows, guard(status)


WHAT = {
    "A": "the clock: every message you send carries the real date and time",
    "B": "the status line: context and quota at the bottom of the terminal; feeds the quota autopilot",
    "C": "the venture guard: stops edits to a company folder that is a synced copy",
    "D": "provenance: marks text you did not write (email, chat, docs, the web, inbox prompts)",
    "E": "the floor at start: each new session starts with your trust contract and recent learnings",
    "F": "the model-switch log: records when a session is moved to another model",
    "R": ("transcript retention: keep your session transcripts for 10 years. Claude Code deletes "
          "them after 30 days by default, silently, at every session start, so a long-running "
          "session you want to reopen or learn from is gone a month later"),
}
RETENTION_DAYS = 3650


def old_status_forms(root):
    """The exact status lines AIOS wrote before #292, for this machine's root and the interpreters
    the installer itself would have written. Exact strings, not a pattern: a line the operator
    changed in any way (another interpreter, a fork's path) is theirs and is never replaced, and a
    root with spaces in it still matches."""
    r = root.replace("\\", "/")
    pys = {"python3", "python", "py -3"}
    if os.environ.get("AIOS_WIN_PYTHON"):
        pys.add(os.environ["AIOS_WIN_PYTHON"])
    forms = {"bash -c 'tee >($HOME/aios/hooks/claude-identity/claude-identity.sh cache > /dev/null) | "
             "python3 $HOME/aios/hooks/claude-identity/context-monitor.py'"}
    for py in pys:
        forms.add("bash -c 'tee >(\"%s/hooks/claude-identity/claude-identity.sh\" cache > /dev/null) | "
                  "%s \"%s/hooks/claude-identity/context-monitor.py\"'" % (r, py, r))
    return forms


def signature(cmd):
    """What identifies a hook regardless of how its interpreter or path is spelled."""
    for key in ("inject-datetime", "floor-at-start.py", "model-switch-log.py", "guard-venture-mount.py",
                "bus_log.py", "provenance.py"):
        if key in cmd:
            if key == "provenance.py":
                return key + (" --prompt" if "--prompt" in cmd else " --tool" if "--tool" in cmd else "")
            return key
    return cmd


def present(settings, event, cmd):
    want = signature(cmd)
    for group in (settings.get("hooks") or {}).get(event, []) or []:
        for hk in group.get("hooks", []) or []:
            if signature(str(hk.get("command", ""))) == want:
                return True
    return False


def shape_problem(settings, events):
    """Plain words for the first part of the file this cannot merge into, or None. Checked before
    anything is written, so a surprise shape exits 1 with no backup and no partial write."""
    if not isinstance(settings, dict):
        return "a top-level %s where an object ({...}) is expected" % type(settings).__name__
    if "statusLine" in settings and not isinstance(settings["statusLine"], dict):
        return '"statusLine" set to %s where an object is expected' % json.dumps(settings["statusLine"])
    if "hooks" not in settings:
        return None
    hooks = settings["hooks"]
    if not isinstance(hooks, dict):
        return '"hooks" set to %s where an object is expected' % json.dumps(hooks)
    for ev in events:
        if ev not in hooks:
            continue
        if not isinstance(hooks[ev], list):
            return '"hooks" -> "%s" set to %s where a list is expected' % (ev, json.dumps(hooks[ev]))
        for group in hooks[ev]:
            if not isinstance(group, dict) or not isinstance(group.get("hooks", []), list) \
                    or not all(isinstance(hk, dict) for hk in group.get("hooks", [])):
                return '"hooks" -> "%s" holding an entry that is not {"hooks": [{...}]}' % ev
    return None


def main():
    ap = argparse.ArgumentParser(prog="install-settings.py")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--platform", choices=["windows", "posix"])
    ap.add_argument("--settings")
    a = ap.parse_args()
    platform = a.platform or ("windows" if sys.platform == "win32" else "posix")
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    # Absolute before anything else (a relative --settings used to fail after the backup existed),
    # and the link resolved: writing over a symlink would replace it with a plain file.
    path = os.path.abspath(os.path.expanduser(a.settings or os.path.join(cfg, "settings.json")))
    real = os.path.realpath(path)
    venture_guard = bool(glob.glob(os.path.join(ROOT, "vault", "00 - notes", "context", "ventures", "*", ".*-sync")))

    if os.path.exists(real):
        try:
            with open(real, encoding="utf-8") as f:
                raw = f.read()
            settings = json.loads(raw) if raw.strip() else {}
        except ValueError as e:
            print("settings.json is not valid JSON (%s). Nothing was changed; fix or move it first: %s" % (e, path))
            return 1
        except OSError as e:
            print("settings.json could not be read (%s). Nothing was changed: %s" % (e.strerror or e, path))
            return 1
    else:
        settings = {}

    rows, status = plan(platform, ROOT, venture_guard)
    problem = shape_problem(settings, {ev for _, ev, _, _, _ in rows})
    if problem:
        print("settings.json has %s, which this helper cannot merge into. Nothing was changed; fix that "
              "part by hand (SETUP §10 shows the shape) or move the file aside: %s" % (problem, path))
        return 1
    adds, keeps = [], []
    for key, event, matcher, cmd, timeout in rows:
        (keeps if present(settings, event, cmd) else adds).append((key, event, matcher, cmd, timeout))
    # Existing AIOS hooks registered before the guard (a bare `python3 .../hooks/X.py`): wrapped in
    # place, keeping the operator's own interpreter and path, so an update fixes installs it did not write.
    # Every hook AIOS can register, the venture guard included, even when this vault does not plan it.
    wanted = {signature(cmd): key for key, _, _, cmd, _ in plan(platform, ROOT, True)[0]}
    upgrades = []
    for event, groups in (settings.get("hooks") or {}).items():
        for group in groups or []:
            for hk in group.get("hooks", []) or []:
                cmd = str(hk.get("command", ""))
                if signature(cmd) in wanted and not GUARDED.match(cmd) and guard(cmd) != cmd:
                    upgrades.append((wanted[signature(cmd)], hk))
    status_add = "statusLine" not in settings
    status_note = None
    status_upgrade = False
    if not status_add:
        cur = str(settings["statusLine"].get("command", "")).strip()
        flat = cur.replace('"', "")
        # The form AIOS itself wrote before #292: bash + tee + claude-identity.sh cache + context-monitor.py,
        # two programs per render. Only those exact strings are ours to replace; anything else is the operator's.
        if cur in old_status_forms(ROOT):
            status_upgrade = True
        elif "claude-identity.sh cache" not in flat and "context-monitor.py" not in flat:
            status_note = ("you already have your own status line, so it is left as it is -- the usage cache the "
                           "App, Glass and the quota autopilot read is not fed until it also runs "
                           "hooks/claude-identity/context-monitor.py (SETUP §10)")

    # R: only when the key is absent. A value the operator chose, even a short one, is theirs.
    retention_add = "cleanupPeriodDays" not in settings
    retention_note = None
    if not retention_add:
        try:
            days = int(settings["cleanupPeriodDays"])
        except (TypeError, ValueError):
            days = None
        if days is not None and days < RETENTION_DAYS:
            retention_note = ("transcripts are kept %d days (your setting, left as it is); "
                              "/aios:housekeeping can archive throwaway runs instead of letting age delete everything" % days)

    print("Claude Code settings: %s" % path)
    shown = set()
    for key, *_ in adds:
        if key not in shown:
            print("  + add   %s  %s" % (key, WHAT[key])); shown.add(key)
    if status_add:
        print("  + add   B  %s" % WHAT["B"])
    for key, *_ in keeps:
        if key not in shown:
            print("  = keep  %s  already set up" % key); shown.add(key)
    if status_upgrade:
        print("  ~ update B  the status line becomes one program instead of two, so typing does not lag on Windows")
    elif not status_add and not status_note:
        print("  = keep  B  already set up")
    if status_note:
        print("  ! note  B  " + status_note)
    for key in sorted({k for k, _ in upgrades}):
        print("  ~ guard %s  a missing hook file is skipped instead of blocking every prompt" % key)
    if not venture_guard:
        print("  - later C  the venture guard is added when you mount a company (/aios:company --mount)")
    if retention_add:
        print("  + set   R  %s" % WHAT["R"])
    elif retention_note:
        print("  ! note  R  " + retention_note)
    else:
        print("  = keep  R  already set up")
    print("  Everything else in the file is kept.")

    if not adds and not status_add and not status_upgrade and not upgrades and not retention_add:
        print("Nothing to change.")
        return 0
    if not a.apply:
        print("Nothing written yet. To make these changes: %s --apply" % os.path.basename(sys.argv[0]))
        return 0

    hooks = settings.setdefault("hooks", {})
    for key, event, matcher, cmd, timeout in adds:
        entry = {"type": "command", "command": cmd}
        if timeout:
            entry["timeout"] = timeout
        group = {"hooks": [entry]}
        if matcher:
            group = {"matcher": matcher, "hooks": [entry]}
        hooks.setdefault(event, []).append(group)
    if status_add:
        settings["statusLine"] = {"type": "command", "command": status}
    elif status_upgrade:
        settings["statusLine"]["command"] = status
    for _, hk in upgrades:
        hk["command"] = guard(str(hk["command"]))
    if retention_add:
        settings["cleanupPeriodDays"] = RETENTION_DAYS

    backup = None
    tmp = real + ".aios-tmp"
    try:
        os.makedirs(os.path.dirname(real), exist_ok=True)
        if os.path.exists(real):
            backup = real + ".bak-aios-" + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
            shutil.copy2(real, backup)
        # Keep the file's permissions: settings.json can hold tokens and is often 0600. A temp file is
        # created with the default umask (typically 0644), so without this the replace would loosen it.
        mode = (os.stat(real).st_mode & 0o777) if os.path.exists(real) else 0o600
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(settings, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.chmod(tmp, mode)
        os.replace(tmp, real)
    except OSError as e:
        for leftover in (tmp, backup):
            if leftover and os.path.exists(leftover):
                os.remove(leftover)
        print("settings.json could not be written (%s). Nothing was changed: %s" % (e.strerror or e, path))
        return 1
    try:
        with open(real, encoding="utf-8") as f:
            back = json.load(f)
        ok = (all(present(back, ev, cmd) for _, ev, _, cmd, _ in rows) and "statusLine" in back
              and "cleanupPeriodDays" in back)
    except (OSError, ValueError):
        ok = False
    if not ok:
        print("Written, but the read-back did not show every hook. Your previous file is at: %s" % (backup or "(none)"))
        return 2
    print("Done. " + (("Your previous file is saved as %s. " % backup) if backup else "")
          + "A new Claude session picks these up (hooks load at session start).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
