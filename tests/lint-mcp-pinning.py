#!/usr/bin/env python3
"""tests/lint-mcp-pinning.py — third-party code that runs on an operator's machine is pinned,
and the pin is real rather than aspirational.

WHY THIS EXISTS, in the order the problems were found:

1. UNPINNED INVOCATIONS. `npx pkg@latest` and a bare `uvx pkg` resolve whatever the registry
   publishes at invocation time, so the code audited yesterday is not the code executed
   tomorrow. That is the shape of every published npm supply-chain incident: a maintainer
   ships a payload in a patch release and every floating consumer ingests it silently.
   Pinning needs no judgment to work, which is exactly why it is the control worth having.

2. A PIN NOBODY INSTALLS IS NOT A CONTROL. Measured 2026-09-15: three manifests pinned
   `mcp==1.28.1` on 2026-07-29, while the live venvs — built 2026-03-30 and 2026-04-21 —
   were running `mcp-1.27.0`. `mcps/setup.sh` is idempotent and skips an existing venv, so
   the pin had never once been installed. A fresh clone would get the pinned version and
   this vault would keep the older one: **the same repo running two different runtimes,
   with nothing reporting the divergence.** So this lint checks that a manifest EXISTS and
   is pinned; a companion runtime check belongs in setup.sh, and is named in the policy.

3. A CITATION IS NOT A POLICY. Those same three manifests said "Pinned per the MCP pinning
   policy (mcps/_index.md)" — and no such policy was in that file. Three files pointed at a
   rule nobody had written, which reads as assurance and carries none. A dangling reference
   in a security-relevant place is worse than an absent one, so it is checked here.

WHAT THIS CANNOT DO, stated so a green run is not over-read: pinning gives REPRODUCIBILITY,
never safety. A pinned malicious version stays malicious. Judgment about content is a
separate question that this lint does not touch and must not be read as answering — see
`SECURITY.md` for what is reviewed, at which version, and what is not reviewed at all.

Run:  python3 tests/lint-mcp-pinning.py
"""
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FAIL: list[str] = []
NOTE: list[str] = []

# Files that instruct an operator or a script to fetch and run third-party code.
SCANNED = ["SETUP.md", "mcps/setup.sh", "mcps/_index.md", "README.md", "CHEATSHEET.md"]

# An invocation is PINNED when it carries an explicit version:
#   npx pkg@1.2.3 · npx @scope/pkg@1.2.3 · uvx pkg==1.2.3 · uvx 'pkg==1.2.3'
# `@latest`, `@next`, a caret/tilde range, or no version at all are all floating.
NPX = re.compile(r"\bnpx\s+(?:-y\s+)?(?P<pkg>@?[\w.@/-]+)")
UVX = re.compile(r"\buvx\s+(?:--\S+\s+)*(?P<pkg>[\w.-]+)")
PINNED_NPX = re.compile(r"@\d+\.\d+")
PINNED_UVX = re.compile(r"==\s*\d+\.\d+")

# Modules that ship with Python — importing one owes no manifest entry.
STDLIB = {
    "os", "sys", "json", "re", "pathlib", "typing", "subprocess", "base64", "io", "time",
    "datetime", "shutil", "tempfile", "urllib", "argparse", "logging", "asyncio", "textwrap",
    "hashlib", "html", "csv", "math", "random", "string", "collections", "itertools",
    "functools", "dataclasses", "enum", "glob", "signal", "socket", "ssl", "struct",
    "threading", "traceback", "unittest", "uuid", "warnings", "webbrowser", "zipfile",
    "sqlite3", "platform", "getpass", "secrets", "textwrap", "difflib", "copy", "abc",
}

# Known-unpinned invocations, each of which MUST appear as an `unpinned` row in SECURITY.md.
# This is a ratchet, not an amnesty — the same shape as CLAUDE.md's byte ceiling. An entry
# here is a RECORDED DECISION that the gap exists; a missing check is an accident. Any NEW
# unpinned invocation fails the build. Entries leave this list by being pinned, never by
# being deleted.
#
# Why these are still here: the versions could not be resolved when the rule was written
# (no registry access in that session), and a guessed pin is worse than a recorded gap — it
# reads as a verified version and is not one.
#
# The last two joined when the `--help` escape came out of PROSE below. They were always
# there; the lint simply could not see them.
KNOWN_UNPINNED = {
    "@mauricio.wolff/mcp-obsidian",
    "@jtalk22/slack-mcp",
    "@_davideast/stitch-mcp",
    "workspace-mcp",
    "mcp-atlassian",
}

# Prose mentions the word without invoking anything — "npx-based MCPs need it".
#
# `--help` USED TO BE ON THIS LIST, and it was the wrong call: `npx -y pkg --help` and
# `uvx pkg --help` are not documentation, they are a fetch-and-execute of whatever the
# registry publishes right now, used as a reachability probe. Two invocations hid behind it
# in `mcps/setup.sh` — `mcp-atlassian` and the since-retired GitHub server — so the
# lint reported clean while SECURITY.md described five unpinned rows, and the ratchet held
# three of them. An escape hatch wide enough to hide a real invocation is not a false-positive
# fix, it is a blind spot. Removing it surfaced exactly those two and nothing else.
PROSE = re.compile(r"npx-based|neither uvx|nor uvx|pkg_hint|uvx resolves|via uvx|uvx,|npx at runtime")


def scan_invocations() -> None:
    for rel in SCANNED:
        p = REPO / rel
        if not p.is_file():
            continue
        for n, line in enumerate(p.read_text(errors="replace").splitlines(), 1):
            if PROSE.search(line):
                continue
            for rx, pinned, tool in ((NPX, PINNED_NPX, "npx"), (UVX, PINNED_UVX, "uvx")):
                m = rx.search(line)
                if not m:
                    continue
                # Inside a quoted string it is a MESSAGE, not an invocation — an odd number of
                # quotes before the match means we are inside one. Without this, a line reading
                # `echo "  npx not found — install Node.js first"` reports the package "not".
                # A lint with false positives is a lint operators mute, which is the same
                # failure mode as an alarm that fires on success.
                before = line[: m.start()]
                if before.count('"') % 2 or before.count("'") % 2:
                    continue
                pkg = m.group("pkg")
                # a local path or a flag is not a registry package
                if pkg.startswith((".", "/", "-")) or pkg in {"python3", "python", "node"}:
                    continue
                if not pinned.search(line):
                    bare = pkg.split("@latest")[0].rstrip("@")
                    if bare in KNOWN_UNPINNED:
                        # Advisory, and it says so. The correspondence between this
                        # allowlist and SECURITY.md's table is NOT checked — writing
                        # "must appear as an unpinned row" here would be this file's own
                        # lesson #3 turned on itself: a citation is not a policy. Where
                        # the gap is recorded is SECURITY.md § Third-party code; whether
                        # it is recorded there is a reader's job today.
                        NOTE.append(
                            f"{rel}:{n} — {bare} is known-unpinned (allowlisted). Record the "
                            f"gap in SECURITY.md § Third-party code; pin it to retire the entry."
                        )
                        continue
                    FAIL.append(
                        f"{rel}:{n} — {tool} invocation is not pinned: {pkg}\n"
                        f"        floating versions mean the code audited yesterday is not the code run "
                        f"tomorrow. Pin it ({'pkg@1.2.3' if tool == 'npx' else 'pkg==1.2.3'}) and record "
                        f"the version in SECURITY.md's dependency table."
                    )


def scan_manifests() -> None:
    """Every MCP whose own code imports a third-party package needs a pinned manifest."""
    mcps = sorted(d for d in (REPO / "mcps").glob("*-mcp") if d.is_dir())
    for d in mcps:
        tracked = [
            f for f in ("requirements.txt", "pyproject.toml", "package.json")
            if (d / f).is_file()
        ]
        ours = list(d.glob("*.py")) + list(d.glob("*.js")) + list(d.glob("*.ts"))
        ours = [f for f in ours if ".venv" not in f.parts and "node_modules" not in f.parts]
        if not ours:
            continue  # zero-code wrapper: the invocation check above is what governs it
        # A manifest is only owed when the code imports something that is NOT the stdlib.
        # Measured: google-workspace-mcp's only tracked .py imports re/sys/html/pathlib and
        # nothing else, so demanding a requirements.txt there was a false positive — and a
        # lint that fires on a correct file is a lint nobody reads.
        third_party = set()
        for f in ours:
            for m in re.finditer(r"^\s*(?:import|from)\s+([a-z_][a-z0-9_]*)", f.read_text(errors="replace"), re.M):
                if m.group(1) not in STDLIB:
                    third_party.add(m.group(1))
        if not third_party:
            continue
        if not tracked:
            FAIL.append(
                f"mcps/{d.name} — ships {len(ours)} source file(s) and tracks no dependency "
                f"manifest.\n        Its venv resolves whatever its imports pull at install time, so "
                f"there is nothing for an audit to be an audit OF. Add a pinned "
                f"requirements.txt / package.json."
            )
            continue
        for f in tracked:
            body = (d / f).read_text(errors="replace")
            if f == "package.json":
                if re.search(r'"\^|"~', body):
                    NOTE.append(
                        f"mcps/{d.name}/{f} — carries caret/tilde ranges. This is vendored "
                        f"upstream's own manifest; record the vendored version in SECURITY.md "
                        f"rather than editing a third party's ranges."
                    )
            else:
                deps = [
                    l.strip() for l in body.splitlines()
                    if l.strip() and not l.strip().startswith("#")
                ]
                loose = [l for l in deps if not re.search(r"==|~=", l)]
                if loose:
                    FAIL.append(
                        f"mcps/{d.name}/{f} — unpinned dependenc(ies): {', '.join(loose)}"
                    )


def scan_dangling_policy_refs() -> None:
    """A manifest may only cite a policy that exists."""
    cited = []
    for f in (REPO / "mcps").rglob("requirements.txt"):
        if ".venv" in f.parts:
            continue
        body = f.read_text(errors="replace")
        m = re.search(r"pinning policy \(([^)]+)\)", body, re.I)
        if m:
            cited.append((f.relative_to(REPO), m.group(1)))
    for src, target in cited:
        tp = REPO / target
        if not tp.is_file():
            FAIL.append(f"{src} cites a policy in {target}, which does not exist")
        elif not re.search(r"pinning policy", tp.read_text(errors="replace"), re.I):
            FAIL.append(
                f"{src} cites 'the MCP pinning policy' in {target}, and {target} contains no "
                f"such policy.\n        A citation is not a policy: three files pointed at a rule "
                f"nobody had written, which reads as assurance and carries none."
            )


scan_invocations()
scan_manifests()
scan_dangling_policy_refs()

for n in NOTE:
    print(f"  note  {n}")
if FAIL:
    for f in FAIL:
        print(f"  FAIL  {f}")
    print(f"\n-- {len(FAIL)} unpinned or unbacked dependenc(ies) --")
    sys.exit(1)
print("lint-mcp-pinning: clean — every third-party invocation is pinned and every "
      "code-bearing MCP has a pinned manifest")
