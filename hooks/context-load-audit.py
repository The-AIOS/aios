#!/usr/bin/env python3
"""context-load-audit — did a spawned worker actually load operator context?

WHY THIS IS A HOOK AND NOT PROSE IN A COMMAND FILE.
`CLAUDE.md` tells a worker to load context and nothing reports when it doesn't;
the failure is silent by construction — the worker still answers and still sounds
right. So /aios:housekeeping measures it. But a measurement described in prose is
re-implemented by whoever runs it, and the obvious implementation is wrong in a
specific, reproducible way (see CD-RESOLUTION below): it was written that way
once and reported three workers at zero that had in fact read the floor. A check
that under-reports is worse than no check, because its clean answer is trusted.
So the instrument ships as code, and the command calls it.

WHAT IT READS. `~/.claude/projects/*/<sessionId>.jsonl` — the transcript. Only
`tool_use` events, never prose and never `tool_result`: a transcript mentions
context paths constantly, and only a tool call is evidence a file was opened.

COMPACTION DOES NOT AFFECT IT. Compaction rewrites the model's context window;
the transcript on disk is append-only. Measured on a live session with 8
compaction events: all 10,241 tool_use records spanning seven weeks were still
present. The audit therefore sees what a session DID, not what it still
remembers — which is the question being asked.

CD-RESOLUTION, the bug this exists to not repeat. A worker frequently does
`cd "<vault>/00 - notes/context/observed" && grep '^### ' antifragile.md …`.
Matching only `context/(declared|observed)/<file>.md` misses every one of those,
because after the `cd` the paths are bare. Commands are therefore scanned for a
`cd` into the context tree, and bare context filenames in such a command count.

DEPTH. Reading the `###` titles of a file is the floor; reading the file is the
full load. They are counted separately, because a floor that silently degrades
into nothing looks identical to a floor that is firing if you only count files.

PRIMARIES, the control, are the session names the operator declared in USER.md's
`## Identity` table (plus any `--primary NAME`). Never a list written here: a list of
names in canonical is one operator's session names shipped to every vault, where it
matches nothing and turns the operator's real primary into a "worker" under suspicion.

Usage:  context-load-audit.py [--min-tools N] [--cap N] [--primary NAME]... [--json] [--session SID]
"""
import argparse
import glob
import json
import os
import re
import sys

# Windows consoles are cp1252: a print() carrying an em dash raises UnicodeEncodeError
# and the hook does NOT RUN -- the failure is absence, not a mangled glyph.
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

# DERIVED, never hardcoded. The first version of this list named nine files by hand --
# and four of them were personal files from a single vault, which is both a canonical leak
# and a list that matches nothing in another operator's vault. Both folders vary: operators
# rename these, add their own, and write them in their own language.
def _context_names(root):
    """Filenames actually present in this vault's context folders."""
    names = set()
    base = os.path.join(root, "vault", "00 - notes", "context")
    for sub in ("declared", "observed"):
        d = os.path.join(base, sub)
        if not os.path.isdir(d):
            continue
        for fn in os.listdir(d):
            if fn.endswith(".md") and fn != "_index.md":
                names.add(fn[:-3])
    return names


# SELF-LOCATE. The framework must not hardcode its install path -- an operator who
# cloned elsewhere, or a CI checkout, has no ~/aios. This file lives in hooks/, so the
# repo root is two levels up; AIOS_VAULT overrides for tests and odd layouts.
def _declared_names(root):
    d = os.path.join(root, "vault", "00 - notes", "context", "declared")
    if not os.path.isdir(d):
        return set()
    return {f[:-3] for f in os.listdir(d) if f.endswith(".md") and f != "_index.md"}


VAULT_ROOT = os.environ.get(
    "AIOS_VAULT", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONTEXT_FILES = sorted(_context_names(VAULT_ROOT))
DECLARED_NAMES = _declared_names(VAULT_ROOT)

PATH_RE = re.compile(r"context/(?:declared|observed)/([A-Za-z0-9_\-]+)\.md")
# Bare filenames only count after a cd into the context tree; without a derived list we
# cannot resolve them, so NAME_RE is disabled rather than guessing (an empty alternation
# would match everywhere).
NAME_RE = (re.compile(r"\b(" + "|".join(map(re.escape, CONTEXT_FILES)) + r")(?:\.md)?\b")
           if CONTEXT_FILES else None)
CD_INTO_CONTEXT = re.compile(r"cd\s+[\"']?[^\"'&|;]*context/(declared|observed)")
CTX_MENTION = re.compile(r"context/(?:declared|observed)|notes/context")

# THE FLOOR COMMAND. A worker that runs this has loaded the entire floor in one call --
# the map, the recent entries of every observed file, and INTENT.md. Matching only file
# paths would score that worker at ZERO, i.e. report the correct behaviour as the worst
# possible behaviour. Same failure as the cd-relative miss, one layer up: the detector
# must know what correct looks like under the rule it is auditing.
FLOOR_CMD = re.compile(r"context-floor\.py")

# OUTWARD-FACING ACTION: the worker produced something that will be read as the operator's
# words or acts on their behalf. This is what makes FIT measurable instead of subjective.
# "Was the answer good" is a judgment call; "did a worker that published in the operator's
# name ever read the file that says how the operator writes" is a fact on the transcript --
# and it is precisely the failure that does not announce itself, since the output reads
# fluent and correct either way.
OUTWARD = re.compile(
    r"03 - export/|send_gmail_message|draft_gmail_message|slack_send_message|"
    r"create_presentation|create_doc\b|forum_send_message|gh pr comment|gh issue comment",
    re.I)

TITLES_ONLY = re.compile(r"grep\s+[^|]*'?\^#{2,3}\s|head\s+-\d+|--?l\b")


ITALIC = re.compile(r"^(\*(?!\*)|_(?!_))")   # *x* or _x_, but not **x** or __x__
# A GFM table's delimiter row: `| --- | :---: |`, outer pipes optional.
DELIM_ROW = re.compile(r"^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?$")


def _cells(s):
    s = s.strip()
    s = s[1:] if s.startswith("|") else s
    s = s[:-1] if s.endswith("|") else s
    return [c.strip() for c in s.split("|")]


def _primary_names(root):
    """Session names declared in USER.md's `## Identity` table.

    Only the FIRST table under a `## Identity` heading is read. A table is what GFM says it
    is -- a header row followed by a delimiter row -- so explanatory text or a blockquote
    that happens to contain a `|` never starts one. It ends at the first line that is not a
    row, so nothing after it contributes, however the next section's heading is written.
    Lines inside a fenced code block are not rows. Rows whose name cell is ITALIC are the
    template's EXAMPLE rows ("EXAMPLE ONLY (Claude: ignore these)") and are skipped; a bold
    name is a real name. An absent or unreadable USER.md yields no names, and main() then
    aborts saying how to declare one.
    """
    try:
        with open(os.path.join(root, "USER.md"), encoding="utf-8", errors="replace") as fh:
            lines = [l.rstrip("\r") for l in fh.read().split("\n")]
    except OSError:
        return set()
    # Blank out fenced code first, so nothing inside a fence is a heading or a row.
    # CommonMark fences: at most 3 spaces of indent; a backtick opener has no backtick after
    # it; a closer is the SAME character, at least as long, and nothing else on the line.
    # An unclosed fence runs to the end of the file.
    fence = None
    for i, l in enumerate(lines):
        f = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", l)
        if fence:
            if f and f.group(1)[0] == fence[0] and len(f.group(1)) >= len(fence) \
                    and not f.group(2).strip():
                fence = None
            lines[i] = ""
        elif f and not (f.group(1)[0] == "`" and "`" in f.group(2)):
            fence = f.group(1)
            lines[i] = ""
    names, inside, i = set(), False, 0
    while i < len(lines):
        l = lines[i]
        # An ATX heading of level 1-2: up to 3 spaces of indent, optional closing hashes.
        m = re.match(r"^ {0,3}(#{1,2})(?:[ \t]+(.*?))?[ \t]*$", l)
        if m:
            title = re.sub(r"(^|[ \t]+)#+$", "", m.group(2) or "").strip()
            inside = title.lower() == "identity"
            i += 1
            continue
        nxt = lines[i + 1] if i + 1 < len(lines) else ""
        if inside and "|" in l and not l.lstrip().startswith(">") and DELIM_ROW.match(nxt.strip()):
            i += 2                                   # header row + delimiter row
            while i < len(lines) and "|" in lines[i] and not lines[i].lstrip().startswith(">") \
                    and not re.match(r"^ {0,3}#{1,6}(\s|$)", lines[i]):   # a heading ends it
                cell = _cells(lines[i])[0]
                if cell and not ITALIC.match(cell):
                    name = cell.strip("*_`").strip()   # `name`, **name** and name are the same name
                    if name:
                        names.add(name)
                i += 1
            break                                    # only the first table
        i += 1
    return names


PRIMARY_NAMES = _primary_names(VAULT_ROOT)


def tool_inputs(path, cap):
    """Yield (tool_name, serialized_input) for the first `cap` tool_use events."""
    n = 0
    with open(path, encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            if '"tool_use"' not in line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue

            def walk(o):
                if isinstance(o, dict):
                    if o.get("type") == "tool_use":
                        yield o.get("name", ""), json.dumps(o.get("input", {}))[:4000]
                    for v in o.values():
                        yield from walk(v)
                elif isinstance(o, list):
                    for v in o:
                        yield from walk(v)

            for item in walk(rec):
                yield item
                n += 1
                if cap and n >= cap:
                    return


def audit(path, cap):
    """Loading is measured over the first `cap` calls; FIT over the whole transcript.

    The cap answers "did it load context at the START". Fit asks a different question --
    "was a declared/ file read BEFORE the first outward action" -- and an outward action,
    or the declared read that preceded it, can happen at call 300. Capping fit at the
    loading window reported workers that did read declared/ as misses, and dropped
    workers whose outward action came late (measured: 13 names with the cap, 16 without,
    and not the same 13).
    """
    read_full, read_titles, tools, loaded = set(), set(), 0, 0
    floor = False
    outward = False
    declared_all, declared_first = set(), False
    ventures = set()
    for _name, inp in tool_inputs(path, 0):
        tools += 1
        loading = not cap or tools <= cap
        loaded += loading
        if FLOOR_CMD.search(inp):
            if loading:
                floor = True      # one call = the whole floor
            hits, found = set(), []
        else:
            found = [(m.start(), m.group(1)) for m in PATH_RE.finditer(inp)]
            # CD-RESOLUTION: after a cd into the context tree, bare filenames are context files.
            if NAME_RE and (CD_INTO_CONTEXT.search(inp) or CTX_MENTION.search(inp)):
                found += [(m.start(), m.group(1)) for m in NAME_RE.finditer(inp)]
            hits = {n for _, n in found}
        dec = hits & DECLARED_NAMES
        # Where in the call each declared read was MATCHED -- the same matches that made it
        # a hit, never a fresh substring search (which finds the name inside other words).
        dec_pos = [pos for pos, n in found if n in DECLARED_NAMES] if dec else []
        declared_all |= dec
        out_m = OUTWARD.search(inp)
        if dec and not outward:
            # One call can both read and act (`cp draft export/ && cat voice.md`). It counts
            # as read-first only when a declared name appears BEFORE the outward action in
            # the call's text; otherwise the order is not shown, and it is not credited.
            if not out_m or min(dec_pos) < out_m.start():
                declared_first = True
        if out_m:
            outward = True
        if not loading:
            continue
        for m in re.finditer(r"context/ventures/([A-Za-z0-9_\-]+)", inp):
            ventures.add(m.group(1))
        if hits:
            (read_titles if TITLES_ONLY.search(inp) else read_full).update(hits)
    return {
        # `tools` is the LOADING window, as before (it feeds --min-tools); `tools_total`
        # is what the fit check read.
        "tools": loaded, "tools_total": tools, "full": read_full, "titles": read_titles - read_full,
        "floor": floor, "outward": outward, "ventures": sorted(ventures),
        "declared": sorted(declared_all), "declared_before_outward": declared_first,
    }


def agent_name(path):
    with open(path, encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            if '"agent-name"' in line:
                m = re.search(r'"agentName":"([^"]*)"', line)
                if m:
                    return m.group(1)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-tools", type=int, default=20,
                    help="ignore sessions below this many tool calls (probes never had work to contextualise)")
    ap.add_argument("--cap", type=int, default=120,
                    help="how many tool calls from the start count as LOADING; 0 = whole "
                         "transcript. Fit (outward vs declared/) always reads all of it")
    ap.add_argument("--primary", action="append", default=[],
                    help="a primary session name, in addition to USER.md's ## Identity table")
    ap.add_argument("--session", help="audit one sessionId prefix instead of sweeping")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    root = os.path.expanduser("~/.claude/projects")
    pattern = f"{root}/*/{a.session}*.jsonl" if a.session else f"{root}/*/*.jsonl"
    primaries = PRIMARY_NAMES | set(a.primary)
    rows = []
    for f in glob.glob(pattern):
        if os.path.getsize(f) < 2000 and not a.session:
            continue
        name = agent_name(f)
        if not name:
            continue
        r = audit(f, a.cap)
        if r["tools"] < a.min_tools and not a.session:
            continue
        full, titles, floor = r["full"], r["titles"], r["floor"]
        rows.append({
            "name": name, "primary": name in primaries,
            "tools": r["tools"], "tools_total": r["tools_total"], "full": sorted(full), "titles_only": sorted(titles),
            "floor_cmd": floor, "outward": r["outward"], "ventures": r["ventures"],
            # Declared reads are what makes an outward-facing deliverable sound like them.
            "declared": r["declared"],
            "declared_before_outward": r["declared_before_outward"],
            # A single context-floor.py call IS the whole floor. Counting only files
            # would score the worker that did exactly the right thing at zero.
            "total": len(full) + len(titles) + (1 if floor else 0),
        })

    if a.json:
        print(json.dumps(rows, indent=2))
        return 0

    primaries = [r for r in rows if r["primary"]]
    workers = [r for r in rows if not r["primary"]]

    # CONTROL FIRST. Primaries run the full ritual; if they do not score, the instrument is
    # broken and every worker number below it is untrustworthy. Say so instead of reporting.
    # ONE rule: findings require a validated control. Both "primaries exist but none
    # scored" and "no primary found at all" mean the same thing -- the instrument is
    # unvalidated -- and in both cases a worker reading nothing is indistinguishable
    # from the detector seeing nothing. Reporting a zero without a control is the
    # failure this whole hook exists to avoid, one level up.
    scored = sum(1 for r in primaries if r["total"] > 0)
    if not CONTEXT_FILES:
        print("note: no context folders found under %s -- bare-filename reads after a cd"
              % VAULT_ROOT)
        print("      cannot be resolved, so counts below are a LOWER BOUND, not a total.")
        print("      Set AIOS_VAULT to the vault root to resolve them.")
    if not primaries:
        print("ABORT: no primary session found, so the detector has no control.")
        if not primaries:
            print("       No primary is declared: add your main session names to the")
            print("       `## Identity` table in USER.md, or pass --primary NAME.")
        print("       A worker reading nothing and a detector seeing nothing are the same")
        print("       output here. Not reporting findings from an unvalidated instrument.")
        return 2
    print(f"control — primary sessions: {scored}/{len(primaries)} loaded context")
    if scored == 0:
        print("  ABORT: no primary session shows a context read. The detector is broken,")
        print("         not the workers. Fix it before trusting anything below.")
        return 2

    if not workers:
        print("no spawned workers met the threshold")
        return 0

    buckets = {"0": 0, "1-2": 0, "3-6": 0, "7+": 0}
    for r in workers:
        t = r["total"]
        buckets["0" if t == 0 else "1-2" if t <= 2 else "3-6" if t <= 6 else "7+"] += 1
    print(f"\nspawned workers with >= {a.min_tools} tool calls: {len(workers)}")
    for k, v in buckets.items():
        print(f"  {k:>4} context files: {v}")

    zero = [r for r in workers if r["total"] == 0]
    if zero:
        print("\nloaded NOTHING despite doing real work:")
        for r in sorted(zero, key=lambda r: -r["tools"]):
            print(f"  {r['name'][:32]:32s} {r['tools']:4d} tool calls")
        print("\n  These are the ones to look at. Report only — decide per worker whether the")
        print("  task genuinely needed no operator context.")

    # FIT, not volume. "Was the answer good" is a judgment call. "Did a worker that
    # published in the operator's name ever read the file that says how they write" is a
    # fact on the transcript -- and it is the failure that does NOT announce itself,
    # because the output reads fluent and correct either way. This is the one place the
    # audit reports on JUDGEMENT rather than quantity.
    miss = [r for r in workers if r.get("outward") and not r.get("declared_before_outward")]
    out_n = sum(1 for r in workers if r.get("outward"))
    print("\nfit — workers whose output went outward: %d of %d" % (out_n, len(workers)))
    if miss:
        print("  %d acted outward before reading any declared/ file:" % len(miss))
        for r in sorted(miss, key=lambda r: -r["tools"]):
            print("    %-30s %3d tool calls" % (r["name"][:30], r["tools"]))
        print("  Not automatically wrong -- judge each. But this is the shape of work that")
        print("  comes back fluent, correct, and not theirs, with nothing in it looking off.")
    else:
        print("  every outward-facing worker read a declared/ file before acting outward.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
