#!/usr/bin/env python3
"""guard-venture-mount.py — PreToolUse hook: block direct edits to company-context MOUNTS.

Files under `vault/00 - notes/context/ventures/{v}/` are MOUNTS of a canonical
company-context repo (synced via `/aios:company --sync`). Editing the mount directly is
silently reverted on the next sync AND never reaches the source of truth other operators
pull from. This hook fires on Edit/Write/MultiEdit/NotebookEdit and BLOCKS when the target
path is a mount — detected by a `.{v}-sync` marker in the venture folder — pointing at the
source repo instead.

Contract (Claude Code PreToolUse):
  stdin  = JSON {tool_name, tool_input:{file_path|notebook_path}, ...}
  exit 0 = allow (silent)
  exit 2 = BLOCK; stderr is fed back to Claude as the reason

Design guarantees (why this is safe to ship to operators):
  - FAIL-OPEN: any parse/logic error -> exit 0. A broken guardrail must never brick editing.
  - DETERMINISTIC: editing a mount is ALWAYS wrong, so false-positives are ~nil.
  - The legit sync path (rsync via Bash) is not an Edit/Write tool, so it never triggers.
  - ESCAPE HATCH: set AIOS_ALLOW_MOUNT_EDIT=1 to intentionally allow a mount edit.
"""
import json, os, sys, glob

GUARDED_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
MOUNT_SEGMENT = "/context/ventures/"


def allow():
    sys.exit(0)


def main():
    # Explicit, documented override for the rare intentional case.
    if os.environ.get("AIOS_ALLOW_MOUNT_EDIT"):
        allow()
    try:
        data = json.load(sys.stdin)
    except Exception:
        allow()  # fail-open on any malformed input
    if not isinstance(data, dict) or data.get("tool_name") not in GUARDED_TOOLS:
        allow()
    ti = data.get("tool_input") or {}
    path = ti.get("file_path") or ti.get("notebook_path")
    if not path:
        allow()

    norm = os.path.abspath(os.path.expanduser(path)).replace(os.sep, "/")
    idx = norm.find(MOUNT_SEGMENT)
    if idx == -1:
        allow()  # not under any ventures/ mount tree -> fine (incl. the source repo itself)

    rest = norm[idx + len(MOUNT_SEGMENT):]
    venture = rest.split("/")[0] if rest else ""
    if not venture:
        allow()
    venture_dir = norm[:idx + len(MOUNT_SEGMENT)] + venture

    # Authoritative signal: a `.{venture}-sync` marker (or any `.*-sync`) in the venture folder.
    marker = os.path.join(venture_dir, ".{}-sync".format(venture))
    if not os.path.isfile(marker):
        fallback = glob.glob(os.path.join(venture_dir, ".*-sync"))
        if not fallback:
            allow()  # ventures/ folder with no sync marker -> vault-native -> allow
        marker = fallback[0]

    repo = "(see marker file)"
    try:
        with open(marker, encoding="utf-8") as fh:
            for ln in fh:
                if ln.strip().startswith("repo="):
                    repo = ln.strip().split("=", 1)[1]
                    break
    except Exception:
        pass

    msg = (
        "⛔ BLOCKED: {fn} is a company-context MOUNT of {repo} (marker: {mk}).\n"
        "Editing the vault mount is silently reverted on the next `/aios:company --sync` and "
        "never reaches the source of truth other operators pull from.\n"
        "→ Edit the file in the {v}-context SOURCE repo, commit + push there, then "
        "`/aios:company --sync {v}` to land it in the vault. Infra files must NOT link to "
        "personal-vault notes.\n"
        "To override intentionally: set AIOS_ALLOW_MOUNT_EDIT=1."
    ).format(fn=os.path.basename(path), repo=repo, mk=os.path.basename(marker), v=venture)

    sys.stderr.write(msg + "\n")
    sys.exit(2)


if __name__ == "__main__":
    main()
