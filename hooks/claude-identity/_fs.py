"""
_fs.py — the one atomic JSON writer shared by _cache.py and _watch.py.

Kept in its own module so the statusLine path (_cache.py, several runs per
turn) does not load the whole watcher just to write a file.
"""
import json
import os
import tempfile


def write_json_atomic(dst: str, data: dict) -> None:
    """Publish `data` at `dst` as a complete file, mode 0600, or not at all.

    A FIXED temp name (dst + ".tmp") is not atomic once there are two writers:
    both open the same inode, one renames it into place, and the other keeps
    writing into what is now the published file -- a reader sees a torn or
    mixed JSON, and the second rename then fails because the temp name is gone.
    Several sessions write these files at once, so each writer gets its own
    temp from mkstemp (created 0600, in the destination dir so the rename
    stays on one filesystem)."""
    d = os.path.dirname(dst)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix="." + os.path.basename(dst) + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, dst)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def seat_state_base() -> str:
    """Base path of the seat's lock, generation and pending marker -- the same
    path claude-identity.sh computes. On macOS the credential is one Keychain
    item per user whatever CLAUDE_CONFIG_DIR says, so the state is per item;
    on the file backend it is per config dir."""
    import sys
    home = os.path.expanduser("~")
    if sys.platform == "darwin":
        svc = os.environ.get("AIOS_KEYCHAIN_SERVICE") or "Claude Code-credentials"
        return os.path.join(home, ".claude", ".switch-" + svc)
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(home, ".claude")
    return os.path.join(cfg, ".switch")


def seat_generation() -> int:
    """Completed swaps so far (0 if none). See claude-identity.sh."""
    try:
        with open(seat_state_base() + ".gen") as f:
            return int(f.read().strip() or 0)
    except (OSError, ValueError):
        return 0
