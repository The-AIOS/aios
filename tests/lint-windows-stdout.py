#!/usr/bin/env python3
"""Every hook that PRINTS non-ASCII must guard Windows stdout.

Windows consoles default to cp1252. A `print()` carrying an em dash, an arrow or
an emoji raises UnicodeEncodeError there and aborts the script — so on Windows the
failure is not a mangled character, it is the tool not running. The framework's
own prose style uses em dashes liberally, which makes this a standing trap rather
than an edge case: `hooks/buffer-status.py` scored 18 passed / 5 failed on Windows
purely from its report line, while passing 23 / 0 everywhere else.

Three hooks already carried the guard (`pipeline-executor.py`, `route-insight.py`,
`claude-identity/context-monitor.py`), so the convention existed and was simply
applied inconsistently. A rule that lives only in three files is folklore; this is
the check that makes it a contract.

Exit 0 = clean · 1 = a hook prints non-ASCII without the guard.
"""
import io
import os
import re
import sys

# This linter ECHOES the offending source lines, which are non-ASCII by
# definition — so without the very guard it enforces, it crashes on cp1252
# while reporting the defect. Found by mutating a hook to see the red line.
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PRINTS = re.compile(r"print\(|sys\.std(?:out|err)\.write")


def prints_non_ascii(src):
    """Lines that emit output AND carry a byte no cp1252 console can encode."""
    hits = []
    for n, line in enumerate(src.splitlines(), 1):
        if PRINTS.search(line) and any(ord(c) > 127 for c in line):
            hits.append((n, line.strip()[:88]))
    return hits


def main():
    bad = []
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, "hooks")):
        dirnames[:] = [d for d in dirnames if d not in {"__pycache__", ".venv", "custom"}]
        for fn in sorted(filenames):
            if not fn.endswith(".py"):
                continue
            p = os.path.join(dirpath, fn)
            src = io.open(p, encoding="utf-8").read()
            hits = prints_non_ascii(src)
            if not hits:
                continue
            if "reconfigure(encoding=" in src:
                continue
            rel = os.path.relpath(p, ROOT).replace(os.sep, "/")
            bad.append((rel, hits))

    if not bad:
        print("lint-windows-stdout: clean — every non-ASCII-printing hook guards Windows stdout")
        return 0

    print("lint-windows-stdout: these hooks print non-ASCII with no Windows stdout guard.")
    print("On a cp1252 console each raises UnicodeEncodeError and the tool does not run.\n")
    for rel, hits in bad:
        print(f"  {rel}")
        for n, line in hits[:3]:
            print(f"    {n}: {line}")
        if len(hits) > 3:
            print(f"    ... and {len(hits) - 3} more")
    print("\nAdd, after the imports (the form already used by pipeline-executor.py):\n")
    print('    if sys.platform == "win32":')
    print('        sys.stdout.reconfigure(encoding="utf-8")')
    print('        sys.stderr.reconfigure(encoding="utf-8")')
    return 1


if __name__ == "__main__":
    sys.exit(main())
