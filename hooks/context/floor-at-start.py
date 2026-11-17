#!/usr/bin/env python3
"""floor-at-start.py — SessionStart hook: the context floor is DELIVERED, not chosen.

WHY. CLAUDE.md tells every session to run the context floor first. Measured across one vault's
transcripts (2026-10-03 -> 10-11), that instruction alone did not deliver it: 5 of 16 named
sessions never ran it, most of the rest piped or redirected the output and worked from the
1.5 KB map as if it were the floor, and only a few read the floor file to its end. A rule each
session must remember to follow is the weakest kind; the harness can do it instead.

WHAT. At session start (and after /clear or a compaction, when the context is gone) this hook
writes the full floor file exactly as `context-floor.py` does, and hands the session a COMPACT
floor as additionalContext, in this order, so that what matters survives any trimming:

    1. the instruction to read the full floor file (absolute path) to its END OF FLOOR line
    2. INTENT.md's boundary sections -- autonomy, decisions, communication, escalation --
       chosen by HEADING WORDS, never by a fixed layout (operators write INTENT their own way)
    3. the titles of the newest entries of every observed file
    4. the section list of the full floor file, if room is left

THE CEILING. Claude Code shows a SessionStart hook's additionalContext whole only up to about
10,000 characters; above that it saves the text to a file and shows the model a ~2 KB preview,
which on a heavy vault was the first lines of INTENT and no pointer to the floor at all. So
every mode stays under CEILING_CHARS (characters, not bytes), each part trimmed to fit with an
explicit "(truncated; full text in <path>)" marker. The pointer comes first and is never cut.

WHO. The floor exists so every session starts with the right information, so the default is
delivery -- but only to sessions whose working directory is INSIDE the vault (stdin `cwd`,
else the process cwd, compared as resolved real paths; case-insensitive on Windows). The hook
is registered at user level, so without that check every Claude session in every repo would
receive this vault's private INTENT and learnings. Outside: nothing.
  - every INTERACTIVE session (CLAUDE_CODE_ENTRYPOINT=cli) -> the compact floor
  - ROUTINES (CLAUDE_CODE_ENTRYPOINT=sdk-*: headless `claude -p` and the SDKs) -> the pointer
    to INTENT.md plus as much of its boundary sections as fits: they commit and send with
    nobody watching, so the trust contract is the one thing they must carry
  - a vault the floor refuses (a fresh one, exit 2) -> the same INTENT delivery, not silence
  - AIOS_FLOOR_AT_START=0 opts any session out; =1 gives any (in-vault) session the compact floor
  - source "resume": nothing -- the resumed transcript already holds what was delivered

Exit 0 always and print nothing on any failure: a context hook must never stop a session from
starting. Wired per SETUP §10 Hook E. Guarded by tests/floor-at-start.test.sh.
"""
import json
import os
import re
import subprocess
import sys

for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        try:
            _stream.reconfigure(encoding="utf-8", errors="replace")
        except (ValueError, OSError):
            pass

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("AIOS_ROOT") or os.path.dirname(os.path.dirname(HERE))  # hooks/context/ -> root
FLOOR = os.path.join(HERE, "context-floor.py")
# Claude Code previews (does not inline) SessionStart context past ~10,000 characters.
CEILING_CHARS = 9000

# Heading words that mark the parts of INTENT.md governing what a session may DO. Several
# languages, matched case-insensitively anywhere in a heading. No match -> INTENT from the top.
BOUNDARY_WORDS = re.compile(
    r"autonom|boundar|decision|decide|communicat|escalat|andon|permission|approv|"
    r"never|must not|not doing|forbid|red line|"
    r"l[ií]mite|decis|comunica|escala|nunca|permis|aprob|aprova|prohib|proib|"
    r"grenz|entscheid|kommunik|eskal|verbot",
    re.IGNORECASE)
HEADING = re.compile(r"^(#{1,6})\s+(.*\S)\s*$")


def norm(path):
    try:
        p = os.path.realpath(os.path.abspath(path))
    except (OSError, ValueError):
        return ""
    return os.path.normcase(p)  # lowercases on Windows, identity elsewhere


def inside_root(cwd, root):
    r, c = norm(root), norm(cwd)
    if not r or not c:
        return False
    try:
        return os.path.commonpath([r, c]) == r
    except ValueError:  # different drives on Windows
        return False


def mode(data, env):
    """'compact', 'intent' or None -- what this session receives."""
    flag = env.get("AIOS_FLOOR_AT_START", "")
    if flag == "0":
        return None
    if flag == "1":
        return "compact"
    if (data.get("source") or "") == "resume":
        return None
    if (env.get("CLAUDE_CODE_ENTRYPOINT") or "").startswith("sdk"):
        return "intent"
    return "compact"


def intent_path(root):
    return os.path.join(root, "INTENT.md")


def intent_raw(root):
    try:
        return open(intent_path(root), encoding="utf-8").read().strip()
    except OSError:
        return None


def boundary_sections(text):
    """[(heading line, section text)] for headings whose words mark a boundary, in order."""
    lines = text.splitlines()
    heads, fence = [], False
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("```"):
            fence = not fence
            continue
        m = None if fence else HEADING.match(ln)
        if m:
            heads.append((i, len(m.group(1)), m.group(2)))
    out, skip_to = [], -1
    for k, (i, lvl, title) in enumerate(heads):
        if i < skip_to or lvl < 2 or not BOUNDARY_WORDS.search(title):
            continue
        end = len(lines)
        for j, l2, _ in heads[k + 1:]:
            if l2 <= lvl:
                end = j
                break
        out.append("\n".join(lines[i:end]).strip())
        skip_to = end
    return out or [text]


def trim(text, cap, path):
    """text cut at a line boundary to fit cap characters, with a marker naming the full text."""
    if len(text) <= cap:
        return text
    marker = "(truncated; full text in %s)" % path
    room = cap - len(marker) - 1
    if room <= 0:
        return marker if len(marker) <= cap else ""
    cut = text[:room]
    nl = cut.rfind("\n")
    if nl > room // 2:
        cut = cut[:nl]
    return cut.rstrip() + "\n" + marker


def fair_trim(parts, budget, path):
    """Trim each part to share the budget fairly (short parts give their slack to long ones)."""
    sep = 2
    budget -= sep * max(0, len(parts) - 1)
    caps = [0] * len(parts)
    todo = list(range(len(parts)))
    left = max(0, budget)
    while todo:
        share = left // len(todo)
        fits = [i for i in todo if len(parts[i]) <= share]
        if not fits:
            for i in todo:
                caps[i] = share
            break
        for i in fits:
            caps[i] = len(parts[i])
            left -= caps[i]
            todo.remove(i)
    kept = [trim(p, c, path) for p, c in zip(parts, caps)]
    return "\n\n".join(k for k in kept if k)


def intent_block(root, budget):
    raw = intent_raw(root)
    if raw is None:
        return "(no INTENT.md in this vault -- assume nothing is pre-authorised)"[:budget]
    return fair_trim(boundary_sections(raw), budget, intent_path(root))


def assemble(head, blocks):
    """head is never cut; blocks = [(label, body_fn(budget))] filled in order while room lasts."""
    text = head
    for label, fill in blocks:
        room = CEILING_CHARS - len(text) - len(label) - 4
        if room < 200:
            break
        body = fill(room)
        if body:
            text += "\n\n" + label + "\n" + body
    return text[:CEILING_CHARS]


def intent_only(root, why):
    p = intent_path(root)
    head = ("%s\nBEFORE ACTING: read %s in full -- the trust contract: what you may do without "
            "asking. Below are its boundary sections, trimmed to fit the session-start limit."
            % (why, p))
    return assemble(head, [("== INTENT.md -- boundary sections ==",
                            lambda b: intent_block(root, b))])


def titles_of(root):
    import importlib.util
    spec = importlib.util.spec_from_file_location("context_floor", FLOOR)
    cf = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cf)
    base = os.path.join(root, "vault", "00 - notes", "context")
    titles = []
    for fn, lines in cf.folder(base, "observed") or []:
        if cf.is_restated(lines):
            continue
        es, is_lib, _ = cf.recent_slice(lines, cf.DEFAULT_RECENT)
        if is_lib:
            continue
        for block in cf.newest(es, cf.DEFAULT_RECENT):
            titles.append("  %s: %s" % (fn, block[0].lstrip("#").strip()))
    return titles


def compact(root, session_id):
    env = dict(os.environ)
    if session_id:
        env["CLAUDE_CODE_SESSION_ID"] = session_id
    try:
        run = subprocess.run([sys.executable, FLOOR, root], capture_output=True, text=True,
                             encoding="utf-8", errors="replace", timeout=60, env=env)
        ok = run.returncode == 0 and run.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        ok = False
    m = re.search(r"NEXT: Read (.+?) in parts", run.stdout) if ok else None
    if not m:
        # A fresh vault the floor refuses (exit 2): the trust contract still arrives.
        return intent_only(root, "CONTEXT FLOOR: the full floor could not be built for this "
                                 "vault (hooks/context/context-floor.py refused it); INTENT.md still applies.")
    floor_path = m.group(1)
    the_map = run.stdout.strip()
    # The floor names its own read parts, sized to fit one Read each; pass them on verbatim.
    pm = re.search(r"by these line ranges \(each fits one Read\): ([0-9, -]+?) --", run.stdout)
    how = ("in these parts (line ranges, each fits one Read): %s," % pm.group(1).strip()) if pm \
        else "in parts of about 250 lines,"
    try:
        titles = titles_of(root)
    except Exception:
        titles = []
    sections = "\n".join(l for l in the_map.splitlines() if re.match(r"\s+\d+-\d+\s", l))

    head = ("CONTEXT FLOOR (compact, delivered at session start by hooks/context/floor-at-start.py)\n"
            "BEFORE ACTING: Read %s %s to its last line "
            "'=== END OF FLOOR'. What follows is a trimmed excerpt, not the floor.\n"
            "The trust contract in full: %s" % (floor_path, how, intent_path(root)))
    ttext = "\n".join(titles)

    def intent_fill(room):
        # leave the titles a third of the room, or what they need if less
        return intent_block(root, room - min(len(ttext) + 120, room // 3))

    return assemble(head, [
        ("== INTENT.md -- boundary sections: what you may do without asking ==", intent_fill),
        ("== Newest entries of each observed file (titles; bodies in the floor file) ==",
         lambda b: trim(ttext, b, floor_path) if ttext else ""),
        ("== Sections of the full floor file (lines, size) ==",
         lambda b: trim(sections, b, floor_path) if sections else ""),
    ])


def main():
    try:
        try:
            data = json.load(sys.stdin)
        except ValueError:
            data = {}
        if not isinstance(data, dict):
            data = {}
        if not inside_root(data.get("cwd") or os.getcwd(), ROOT):
            return
        m = mode(data, os.environ)
        if m is None:
            return
        if m == "intent":
            text = intent_only(ROOT, "INTENT.md -- the trust contract, delivered at session start "
                                     "by hooks/context/floor-at-start.py. This run is unattended: nobody is "
                                     "present to approve anything outside it.")
        else:
            text = compact(ROOT, data.get("session_id") or "")
        if text:
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                                     "additionalContext": text[:CEILING_CHARS]}}))
    except Exception:
        pass


if __name__ == "__main__":
    main()
    sys.exit(0)
