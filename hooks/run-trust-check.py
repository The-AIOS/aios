#!/usr/bin/env python3
"""Say, once, when AIOS's private run folder is not yet trusted in Claude Code (#323).

Every spawn and resume hands its session one fresh private folder, ~/.aios/run/handoff-<hex>,
through --add-dir. That is the isolation: a worker sees only its own task. Since Claude Code
2.1.326 each new folder raised a trust prompt, so an unattended spawn waited on a question nobody
saw. Trusting the parent ~/.aios/run once stops it (verified: new handoff folders under a trusted
parent open without a prompt) and changes nothing about what a session can see.

READ-ONLY. It never writes ~/.claude.json: trusting is the operator's decision, made in Claude
Code's own dialog. Prints one short paragraph when the folder exists and is untrusted, and nothing
otherwise. Always exits 0: this is advice, never a gate.

Usage: python3 hooks/run-trust-check.py      (AIOS_RUN_DIR overrides the folder, as the wrappers do)
"""
import json
import os
import sys

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")


def run_dir() -> str:
    return os.environ.get("AIOS_RUN_DIR") or os.path.join(os.path.expanduser("~"), ".aios", "run")


def claude_json_path() -> str:
    # Same rule as hooks/claude-identity/_cache.py: inside a relocated config dir first, else beside home.
    home = os.path.expanduser("~")
    cfg = os.environ.get("CLAUDE_CONFIG_DIR")
    if cfg and os.path.exists(os.path.join(cfg, ".claude.json")):
        return os.path.join(cfg, ".claude.json")
    return os.path.join(home, ".claude.json")


def _norm(p: str) -> str:
    p = os.path.normpath(p).replace("\\", "/").rstrip("/")
    return p.lower() if os.name == "nt" else p


def trusted(folder: str, claude_json: str) -> bool:
    try:
        with open(claude_json, encoding="utf-8") as fh:
            projects = json.load(fh).get("projects") or {}
    except (OSError, ValueError, AttributeError):
        return False
    want = {_norm(os.path.abspath(folder)), _norm(os.path.realpath(folder))}
    for key, entry in projects.items():
        if _norm(key) in want and isinstance(entry, dict) and entry.get("hasTrustDialogAccepted") is True:
            return True
    return False


def main() -> int:
    folder = run_dir()
    if not os.path.isdir(folder):
        return 0  # nothing has been spawned on this machine yet: nothing to ask about
    if trusted(folder, claude_json_path()):
        return 0
    if os.name == "nt":
        how = f'cd "{folder}"; claude'
    else:
        shown = folder.replace(os.path.expanduser("~"), "~", 1)
        how = f"cd {shown} && claude"
    print(
        f"Claude Code asks you to trust each new session folder under {folder}, so a spawn or resume can "
        "stop on a question nobody sees. Trusting that folder once ends it: Claude stops asking about "
        "AIOS's own private folder, and each session still sees only its own handoff folder.\n"
        f"To trust it, run `{how}`, choose Yes, then type /exit."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
