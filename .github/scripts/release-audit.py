#!/usr/bin/env python3
"""Two independent, read-only audits of a release before it is cut (#267, part b).

    python3 .github/scripts/release-audit.py run   --base origin/main --head HEAD --out "${TMPDIR:-/tmp}/release-audit/v0.8.17"
    python3 .github/scripts/release-audit.py check --out "${TMPDIR:-/tmp}/release-audit/v0.8.17"

(Keep --out outside the repo, so the reports are never committed.)

WHY TWO, AND WHY THESE TWO
    The work in a release is reviewed by Claude sessions. A model cannot dock points for a
    blind spot it shares (MODEL-ROUTING.md § Judge independence), so one audit comes from
    outside the Claude family, through hooks/openrouter.py. The other is a fresh Claude
    session that has never seen how the work was made. Either can block the release.

READ-ONLY BY CONSTRUCTION
    Both reviewers receive the diff as text and return text. The Claude audit runs as
    `claude -p` with no tools (`--tools ""`), no local settings layer and no MCP servers,
    so it cannot read, write or run anything. The outside audit goes through
    openrouter.py, which has no tools at all. The diff of a public repository is public,
    so sending it to a third party exposes nothing; never point this at a private repo.

WHAT IS SENT
    The release diff minus CHANGELOG.md, and minus the docs of any vendored folder this
    release touches that is PROVEN byte for byte against its upstream (vendored-pins
    --upstream). Those are upstream's files, unmodified; re-reading them was most of a
    release's audit time and its findings were upstream's choices. Scripts and every
    SKILL.md inside those folders are always sent: a SKILL.md is behaviour. The brief, both reports and left-out.txt name what was left
    out. --all sends everything.

THE GATE
    `check` exits 0 only when both reports exist and each ends in `VERDICT: PASS`.
    No outside key configured -> the outside report says NOT RUN and `check` blocks: an
    audit that did not happen must never read like one that found nothing.

Maintainer tooling: it lives under .github/ and never reaches an operator's vault.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAX_DIFF = int(os.environ.get("AIOS_AUDIT_MAX_DIFF", "180000"))  # characters per chunk
VERDICT = re.compile(r"^VERDICT:\s*(PASS|BLOCK)\b", re.M)

BRIEF = """You are auditing a release of an open-source framework that runs inside its users'
own Claude Code sessions, with access to their notes, mail and calendars. Read the diff
below and answer one question: who gets hurt if this ships? Consider a new user on an
empty install, an existing user updating, Windows and Linux users, and anyone whose data
or accounts the change touches. List concrete problems most severe first, each with the
file and what goes wrong. Ignore style. End with exactly one line:
VERDICT: PASS   (nothing that hurts a user)
VERDICT: BLOCK  (at least one problem that would hurt a user)"""


def sh(cmd, **kw):
    # A call given no input gets an empty stdin, never the caller's: a reviewer that read
    # stdin would otherwise wait on the terminal forever.
    if "input" not in kw:
        kw["stdin"] = subprocess.DEVNULL
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", timeout=900, **kw)


def guard_public_repo():
    """Refuse anywhere but a clone of the public framework repo.

    The diff goes to a third party. Run from an operator's live vault (a tree carrying
    `.aios-update`), origin/main...HEAD would include their notes, USER.md and INTENT.md,
    and their observed context would leave the machine. So this refuses unless the tree is
    a clone of The-AIOS/aios, and never runs where `.aios-update` exists."""
    if (ROOT / ".aios-update").exists():
        sys.exit("release-audit: this tree carries .aios-update, so it is an operator's vault. "
                 "Its diff would send private notes to a third party. Run it in a clone of The-AIOS/aios.")
    url = sh(["git", "-C", str(ROOT), "remote", "get-url", "origin"]).stdout.strip().lower()
    if not re.search(r"github\.com[:/]the-aios/aios(\.git)?$", url):
        sys.exit(f"release-audit: origin is {url or 'not set'}, not The-AIOS/aios. "
                 "The diff goes to a third party, so this only runs in a clone of the public framework repo.")


SCRIPT_EXT = (".py", ".sh", ".bash", ".js", ".mjs", ".cjs", ".ts", ".ps1", ".rb", ".pl", ".cmd", ".bat")


def is_script(path, head):
    """True for a file that runs: a script extension, or committed with the exec bit."""
    if path.lower().endswith(SCRIPT_EXT):
        return True
    r = sh(["git", "-C", str(ROOT), "ls-tree", head, "--", path])
    return r.stdout.startswith("100755")


def proven_vendored(base, head, audit_all=False):
    """(left_out_paths, notes) for vendored folders this release touches.

    A vendored folder (one carrying .upstream-sync) holds upstream's files byte for byte.
    Two models re-reading upstream's docs on every pin refresh is most of an audit's time,
    and its findings are upstream's choices, which a re-vendor cannot change. So when the
    folder is PROVEN against its upstream (tests/vendored-pins.test.sh --upstream), its
    reference files are left out; its scripts and every SKILL.md (instructions the model
    follows, so behaviour) are always read. Not proven: nothing is left
    out. --all leaves nothing out."""
    if audit_all:
        return [], []
    changed = sh(["git", "-C", str(ROOT), "diff", "--no-renames", "--name-only", f"{base}...{head}"]).stdout.split("\n")
    syncs = sh(["git", "-C", str(ROOT), "ls-tree", "-r", "--name-only", head]).stdout.split("\n")
    folders = sorted({os.path.dirname(f) for f in syncs if f.endswith("/.upstream-sync")})
    checker = os.environ.get("AIOS_AUDIT_PIN_CHECK")
    checker = checker.split() if checker else ["bash", str(ROOT / "tests" / "vendored-pins.test.sh"), "--upstream"]
    left_out, notes = [], []
    for d in folders:
        mine = [f for f in changed if f.startswith(d + "/")]
        if not mine:
            continue
        r = sh(checker + [d], cwd=str(ROOT))
        if r.returncode != 0:
            notes.append(f"{d}: NOT proven against its upstream, so audited in full")
            continue
        # A SKILL.md is behaviour, not reference: the model follows it, so it is always read.
        skip = [f for f in mine if not is_script(f, head) and os.path.basename(f) != "SKILL.md"
                and not f.endswith((".upstream-sync", ".upstream-manifest"))]
        left_out += skip
        notes.append(f"{d}: proven byte for byte against its upstream; {len(skip)} reference file(s) left out, "
                     f"{len(mine) - len(skip)} SKILL.md, script or record file(s) audited")
    return left_out, notes


def diff_chunks(base, head, left_out=()):
    """The release diff in chunks no larger than MAX_DIFF, split at file boundaries.

    Never truncated: a release audited on part of its diff could pass on the part nobody
    read. Every chunk goes to both reviewers, and the release passes only if every chunk
    does. A single file larger than the limit is split by lines, and says so. The only
    files not sent are `left_out`: proven vendored docs, named in the brief and reports."""
    spec = [".", ":(exclude)CHANGELOG.md"] + [f":(exclude,literal){p}" for p in left_out]
    r = sh(["git", "-C", str(ROOT), "diff", f"{base}...{head}", "--"] + spec)
    if r.returncode != 0:
        sys.exit(f"release-audit: git diff failed: {r.stderr.strip()}")
    files = re.split(r"(?m)^(?=diff --git )", r.stdout)
    chunks, cur = [], ""
    for f in (x for x in files if x):
        while len(f) > MAX_DIFF:
            cut = f.rfind("\n", 0, MAX_DIFF) + 1 or MAX_DIFF
            if cur:
                chunks.append(cur); cur = ""
            chunks.append(f[:cut] + "\n[this file continues in the next part]\n")
            f = f[cut:]
        if len(cur) + len(f) > MAX_DIFF and cur:
            chunks.append(cur); cur = ""
        cur += f
    if cur or not chunks:
        chunks.append(cur)
    return chunks


def verdict(text):
    m = VERDICT.findall(text or "")
    return m[-1] if m else "NONE"


def run_outside(brief_path):
    cmd = os.environ.get("AIOS_AUDIT_OUTSIDE")
    cmd = cmd.split() if cmd else [sys.executable, str(ROOT / "hooks" / "openrouter.py")]
    r = sh(cmd + ["--prompt-file", str(brief_path)])
    if r.returncode != 0:
        return ("NOT RUN: the outside-family audit did not run.\n"
                f"{(r.stderr or r.stdout).strip()}\n\n"
                "Configure an OpenRouter or Gemini key (hooks/openrouter.py --check says which),"
                " then run again. VERDICT: NOT RUN\n")
    return r.stdout


def run_claude(brief_path):
    # Read-only and context-free: no tools, no MCP servers, no project settings layer (a
    # repo's own .claude/ could carry hooks), every hook disabled, and run from an empty
    # folder so nothing local is picked up.
    cmd = os.environ.get("AIOS_AUDIT_CLAUDE", "claude").split()
    prompt = "Audit the release described on stdin, exactly as it instructs."
    with tempfile.TemporaryDirectory(prefix="release-audit-") as empty:
        settings = Path(empty) / "settings.json"
        settings.write_text(json.dumps({"disableAllHooks": True}), encoding="utf-8")
        r = sh(cmd + ["-p", prompt, "--tools", "", "--setting-sources", "user", "--settings", str(settings),
                      "--strict-mcp-config", "--permission-mode", "default"],
               input=Path(brief_path).read_text(encoding="utf-8"), cwd=empty)
    if r.returncode != 0:
        return f"NOT RUN: the fresh-context Claude audit failed.\n{(r.stderr or r.stdout).strip()}\nVERDICT: NOT RUN\n"
    return r.stdout


def cmd_run(a):
    guard_public_repo()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    left_out, notes = proven_vendored(a.base, a.head, getattr(a, "all", False))
    chunks = diff_chunks(a.base, a.head, left_out)
    scope = ""
    if notes:
        scope = ("\n\nScope of this audit. Vendored upstream folders in this release:\n- " + "\n- ".join(notes) +
                 "\nFiles left out are upstream's own, unmodified; judge only what is shown.")
        (out / "left-out.txt").write_text("\n".join(notes + [""] + left_out) + "\n", encoding="utf-8")
        for n in notes:
            print("scope: " + n)
    reports = {"outside": [], "claude": []}
    for i, chunk in enumerate(chunks, 1):
        part = f" (part {i} of {len(chunks)})" if len(chunks) > 1 else ""
        brief = out / (f"brief-{i}.md" if len(chunks) > 1 else "brief.md")
        brief.write_text(BRIEF + scope + f"\n\n--- DIFF{part} ---\n" + chunk, encoding="utf-8")
        for name, fn in (("outside", run_outside), ("claude", run_claude)):
            reports[name].append((part, fn(brief)))
    for name, parts in reports.items():
        # One report per reviewer; its last line is the release verdict: PASS only if
        # every part passed.
        worst = "PASS" if all(verdict(t) == "PASS" for _, t in parts) else \
            next(verdict(t) for _, t in parts if verdict(t) != "PASS")
        text = "\n\n".join(f"## Report{p}\n\n{t.strip()}" for p, t in parts)
        if notes:
            text = "Scope: " + "; ".join(notes) + "\n\n" + text
        text += f"\n\nVERDICT: {worst if worst in ('PASS', 'BLOCK') else 'BLOCK'}\n"
        if worst not in ("PASS", "BLOCK"):
            text = text.replace("VERDICT: BLOCK\n", "A part did not run or gave no verdict: blocked.\nVERDICT: BLOCK\n")
        (out / f"{name}.md").write_text(text, encoding="utf-8")
        print(f"{name}: {verdict(text)}  ({out / (name + '.md')}, {len(parts)} part(s))")
    return cmd_check(a)


def cmd_check(a):
    out = Path(a.out)
    ok = True
    for name in ("outside", "claude"):
        p = out / f"{name}.md"
        if not p.is_file():
            print(f"BLOCKED: no {name} audit report at {p}")
            ok = False
            continue
        v = verdict(p.read_text(encoding="utf-8"))
        if v != "PASS":
            print(f"BLOCKED: the {name} audit says {v if v != 'NONE' else 'nothing (no VERDICT line)'}: {p}")
            ok = False
    print("release audits: both PASS" if ok else "release audits: the release may not be cut")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--base", default="origin/main")
    r.add_argument("--head", default="HEAD")
    r.add_argument("--out", required=True)
    r.add_argument("--all", action="store_true", help="audit vendored folders in full, even when proven")
    c = sub.add_parser("check")
    c.add_argument("--out", required=True)
    a = ap.parse_args()
    return cmd_run(a) if a.cmd == "run" else cmd_check(a)


if __name__ == "__main__":
    sys.exit(main())
