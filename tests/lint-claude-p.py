#!/usr/bin/env python3
"""Assert every shipped `claude -p` invocation names the tools it may use.

WHY
    A headless `claude -p` with no tool allowlist will use whatever its machine
    permits. Reported by an operator after a published RCE against Claude Code
    from a "summarise this website" request; the vendor's own reply is the load-
    bearing part — auto mode is a convenience feature backed by a best-effort
    classifier, NOT a security boundary. In a routine fleet a headless call
    spawning another headless call is the normal topology, so a rogue one does
    not look anomalous.

WHAT IT CHECKS, AND WHY IT IS NARROW
    Only `.py` and `.sh` under version control — the files that actually EXECUTE.
    Markdown is documentation; a doc that shows an unguarded call is a docs bug,
    not a live risk, and flagging it produced nothing but noise.

    Within those, it joins backslash continuations and strips comments FIRST,
    then looks for a statement that invokes `claude -p`. The first version of
    this check grepped line-by-line across every tracked file and was wrong five
    times out of five: two hits were continuation lines whose `--allowedTools`
    sat on the following line, and three were log strings that merely mention
    `claude -p`. A guard that flags the prose describing a call is measuring
    text, not behaviour.

THE THREE GUARDS THAT DO NOT WORK (so nobody re-invents them)
    --allowedTools ""          swallowed — the flag is variadic, and with the
                               prompt after it, the prompt is eaten
    --permission-mode manual   does NOT block; Bash still runs
    --disallowedTools Bash     a denylist: Write, Edit and Agent survive it

    The form that holds is an allowlist naming a tool the job needs (or one that
    does not exist, when it needs none) plus --strict-mcp-config — AND an
    explicit --permission-mode, because a machine-level permissions.defaultMode
    of "auto" silently outranks the allowlist. Measured 2026-09-04: without the
    mode flag the call created a file and reported permission_denials: [].

    None of this is verifiable by asking the agent what tools it has — under a
    restrictive allowlist it still lists Bash and Write, because it is describing
    its schema rather than its permissions. Only an absent side effect is
    evidence.
"""
import re
import subprocess
import sys

# tests/headless-allowlist.test.sh runs the OLD, uncontained recipe on purpose, as the
# control that proves the risk exists on the machine; flagging it would delete the proof.
SKIP_PREFIXES = ("skills/anthropic/", "skills/superpowers/", "tests/lint-claude-p.py",
                 "tests/headless-allowlist.test.sh")


def statements(text, is_python):
    """Yield (line_no, statement) with continuations joined and comments stripped."""
    out, buf, start = [], "", 0
    for i, raw in enumerate(text.splitlines(), 1):
        line = raw
        # Strip comments. In Python a '#' inside a string is not a comment, so only
        # strip when the '#' is the first non-space character — conservative on
        # purpose: under-stripping risks a false positive, never a false pass.
        stripped = line.lstrip()
        if stripped.startswith("#"):
            line = ""
        if not buf:
            start = i
        buf += " " + line.rstrip("\\")
        if line.rstrip().endswith("\\"):
            continue
        out.append((start, buf.strip()))
        buf = ""
    if buf.strip():
        out.append((start, buf.strip()))
    return out


def main():
    files = subprocess.run(["git", "ls-files", "*.py", "*.sh"],
                           capture_output=True, text=True).stdout.split()
    bad = []
    for f in files:
        if any(f.startswith(p) for p in SKIP_PREFIXES):
            continue
        try:
            text = open(f, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        if "claude" not in text:
            continue
        for lineno, st in statements(text, f.endswith(".py")):
            # The invocation SHAPE differs by language, and using the shell shape on
            # Python is what produced three false positives: a bare `claude -p` inside
            # a log string is prose, and Python code never invokes a binary that way.
            if f.endswith(".py"):
                # A subprocess argv list: [claude, "-p", …] or ["claude", "-p", …]
                shell_call = None
                py_call = re.search(r'\[\s*["\']?claude["\']?\s*,\s*["\']-p["\']', st)
            else:
                shell_call = re.search(r"(^|[^\w-])claude\s+-p\s+\S", st)
                py_call = None
            if not (shell_call or py_call):
                continue
            # `--tools` decides which tools EXIST; `--allowedTools` only pre-approves and
            # is additive to every "allow always" rule in the vault's settings.local.json,
            # so an allowlist alone inherits broad Read/Bash on a vault used daily
            # (reported privately 2026-09-21, reproduced with a canary). Require both
            # halves of the containment: the tool set, and dropping the local layer.
            if re.search(r"--tools\b", st) and "setting-sources" in st:
                continue
            bad.append(f"{f}:{lineno}: {st[:110]}")
    if bad:
        print("::error::A shipped `claude -p` invocation is not contained:")
        for b in bad:
            print("  " + b)
        print("Pass --tools sized to the job (--tools \"\" when it needs none) and")
        print("--setting-sources user,project, plus --strict-mcp-config (and an explicit")
        print("--permission-mode unless no write-capable tool exists). --allowedTools alone")
        print("inherits every accumulated 'allow always' rule. Prompt FIRST: the flags are variadic.")
        return 1
    print(f"OK: every shipped claude -p invocation names its tools ({len(files)} executable files scanned)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
