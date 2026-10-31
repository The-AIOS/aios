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


def blob_token_state(text: str) -> str:
    """"ok" | "empty:accessToken[+refreshToken]" | "unparseable". The one classifier:
    claude-identity.sh asks it before writing, the watcher before choosing a target,
    and two opinions about what a usable credential is would strand a rotation."""
    try:
        d = json.loads(text)
    except ValueError:
        return "unparseable"
    oa = d.get("claudeAiOauth", d) if isinstance(d, dict) else None
    if not isinstance(oa, dict):
        return "unparseable"
    missing = [k for k in ("accessToken", "refreshToken") if not str(oa.get(k) or "").strip()]
    return "empty:" + "+".join(missing) if missing else "ok"


def keychain_service() -> str:
    """The Keychain item Claude Code keeps the credential in -- the same name
    claude-identity.sh's keychain_service_default() derives. Measured against
    Claude Code 2.1.296: `Claude Code-credentials`, plus `-` and the first 8 hex
    of sha256(config dir, NFC) when CLAUDE_CONFIG_DIR is set and non-empty
    (CLAUDE_SECURESTORAGE_CONFIG_DIR, when set, replaces it in that rule).
    AIOS_KEYCHAIN_SERVICE overrides the whole name."""
    import hashlib
    import unicodedata
    override = os.environ.get("AIOS_KEYCHAIN_SERVICE")
    if override:
        return override
    base = "Claude Code-credentials"
    if "CLAUDE_SECURESTORAGE_CONFIG_DIR" in os.environ:
        d = os.environ["CLAUDE_SECURESTORAGE_CONFIG_DIR"]
    else:
        d = os.environ.get("CLAUDE_CONFIG_DIR", "")
    if not d:
        return base
    h = hashlib.sha256(unicodedata.normalize("NFC", d).encode("utf-8")).hexdigest()[:8]
    return base + "-" + h


def seat_state_base() -> str:
    """Base path of the seat's lock, generation and pending marker -- the same
    path claude-identity.sh computes. On macOS the state is per Keychain item
    (see keychain_service); on the file backend it is per config dir."""
    import sys
    home = os.path.expanduser("~")
    if sys.platform == "darwin":
        return os.path.join(home, ".claude", ".switch-" + keychain_service())
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(home, ".claude")
    return os.path.join(cfg, ".switch")


def seat_generation() -> int:
    """Completed swaps so far (0 if none). See claude-identity.sh."""
    try:
        with open(seat_state_base() + ".gen", encoding="utf-8") as f:
            return int(f.read().strip() or 0)
    except (OSError, ValueError):
        return 0
