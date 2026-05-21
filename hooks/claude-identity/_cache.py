#!/usr/bin/env python3
"""
_cache.py — Claude Code statusLine payload reader.

Reads a JSON payload from stdin (the statusLine input via tee), extracts the
rate_limits object + current account email, and writes a small cache file at
~/.claude/rate-limit-cache.json. Invoked by the `cache` subcommand of
claude-identity.sh.

After writing the cache, fires a fire-and-forget `_watch.py` invocation
to evaluate threshold-crossing for fast (sub-30s) account rotation. The
launchd watcher remains as a 30-min safety net for sessions where the
statusLine path is broken or absent.

Silent on success and on benign failures (empty input, malformed JSON, no
rate_limits field). We do NOT want this script to ever break a turn — the
statusLine refreshes several times per turn and a crash here would surface
noise to the user. If something goes wrong we drop a note to stderr and exit 0.
"""
import json
import os
import subprocess
import sys
import time

# Fire _watch.py at most once per WATCH_TICK_SECS to avoid spawning a
# subprocess on every statusLine render (~4-6/turn).
WATCH_TICK_SECS = 30


def main():
    home = os.path.expanduser("~")
    cache_path = os.path.join(home, ".claude", "rate-limit-cache.json")
    claude_json = os.path.join(home, ".claude.json")

    try:
        payload = sys.stdin.read()
    except Exception:
        return
    if not payload.strip():
        return

    try:
        data = json.loads(payload)
    except Exception:
        return

    rate_limits = data.get("rate_limits") or {}
    if not rate_limits:
        return

    email = ""
    try:
        with open(claude_json) as f:
            email = json.load(f).get("oauthAccount", {}).get("emailAddress", "")
    except Exception:
        pass

    out = {
        "email": email,
        "captured_at": int(time.time()),
        "five_hour_pct": rate_limits.get("five_hour", {}).get("used_percentage", 0),
        "five_hour_resets_at": rate_limits.get("five_hour", {}).get("resets_at"),
        "seven_day_pct": rate_limits.get("seven_day", {}).get("used_percentage", 0),
        "seven_day_resets_at": rate_limits.get("seven_day", {}).get("resets_at"),
    }

    tmp = cache_path + ".tmp"
    try:
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        with open(tmp, "w") as f:
            json.dump(out, f, indent=2)
        os.replace(tmp, cache_path)
        os.chmod(cache_path, 0o600)
    except Exception as e:
        sys.stderr.write(f"claude-identity cache: write failed: {e}\n")
        return

    # Fire-and-forget watch invocation (rate-limited so we don't spawn on
    # every statusLine render). Any failure here is non-fatal — the launchd
    # safety-net will still catch threshold crossings within 30 min.
    try:
        kick_watcher(home)
    except Exception as e:
        sys.stderr.write(f"claude-identity cache: watch kick skipped: {e}\n")


def kick_watcher(home: str) -> None:
    """Spawn _watch.py in the background if at least WATCH_TICK_SECS have
    elapsed since the last kick. Touches a tick marker so subsequent
    statusLine renders don't pile up subprocesses."""
    tick_path = os.path.join(home, ".claude", "watch-tick")
    now = time.time()
    if os.path.exists(tick_path):
        try:
            if now - os.path.getmtime(tick_path) < WATCH_TICK_SECS:
                return
        except OSError:
            pass

    self_dir = os.path.dirname(os.path.abspath(__file__))
    watcher = os.path.join(self_dir, "_watch.py")
    self_sh = os.path.join(self_dir, "claude-identity.sh")
    if not os.path.exists(watcher) or not os.path.exists(self_sh):
        return

    try:
        # Touch tick marker BEFORE spawn so concurrent statusLine renders
        # see the fresh timestamp and skip.
        with open(tick_path, "w") as f:
            f.write(str(int(now)))
    except OSError:
        pass

    subprocess.Popen(
        [sys.executable, watcher, self_sh],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


if __name__ == "__main__":
    main()
