#!/usr/bin/env python3
"""
_watch.py — quota-watch decision engine.

Reads the rate-limit cache that _cache.py maintains, applies swap rules
against configurable thresholds, and invokes claude-identity.sh `switch`
if warranted. Called by the `watch` subcommand (launchd entrypoint).

Design (2026-04-23): topology-independent rotate-only. Works for any
number of accounts (1, 2, N) and any number of machines (1, 2, N). When
the current account hits its rate-limit threshold, rotate to the next
account in USER.md. Round-robin alternation. No "primary" / "come-home"
semantics — those assumed a specific user topology (≥2 accounts + a
preferred "home" account) that doesn't generalize across teammates.

Thresholds (override via env):
  CLAUDE_QUOTA_5H          rotate when 5h pct >= this (default 98)
  CLAUDE_QUOTA_7D          rotate when 7d pct >= this (default 98)

Staleness: if cache is older than 30 min (no active Claude session),
we skip — nothing to react to, usage is frozen.

Cross-machine coordination (future work): when two machines share an
account pool, they can both rotate to the same account and compete for
its caps. Not solved here. Escape hatch: `claude-identity.sh switch <email>`
to force a specific account on a specific machine.
"""
import json
import os
import subprocess
import sys
import time


HOME = os.path.expanduser("~")
CACHE = os.path.join(HOME, ".claude", "rate-limit-cache.json")
LOG = os.path.join(HOME, ".claude", "quota-watch.log")
SWAP_LOG = os.path.join(HOME, ".claude", "swap-log.jsonl")
STALE_AFTER_SECS = 1800  # 30 min
COOLDOWN_SECS = 900  # 15 min — prevent thrashing after a swap


def recently_swapped() -> tuple[bool, int]:
    """Returns (True, seconds_since_last) if a swap happened within COOLDOWN_SECS.
    Thrashing guard: after a swap the running session keeps the old token in
    memory; its next turns report the OLD account's rate_limits against the NEW
    oauthAccount email in ~/.claude.json — without this cooldown we'd swap
    back immediately and ping-pong forever."""
    if not os.path.exists(SWAP_LOG):
        return False, 0
    try:
        with open(SWAP_LOG, "rb") as f:
            # read last line efficiently
            f.seek(0, os.SEEK_END)
            size = f.tell()
            if size == 0:
                return False, 0
            block = min(4096, size)
            f.seek(-block, os.SEEK_END)
            last_line = f.read().splitlines()[-1]
        last = json.loads(last_line.decode())
        elapsed = int(time.time() - last.get("ts", 0))
        return elapsed < COOLDOWN_SECS, elapsed
    except Exception:
        return False, 0


def log(msg: str) -> None:
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "a") as f:
        f.write(f"[{time.strftime('%Y-%m-%dT%H:%M:%S')}] {msg}\n")


def append_swap_log(row: dict) -> None:
    os.makedirs(os.path.dirname(SWAP_LOG), exist_ok=True)
    with open(SWAP_LOG, "a") as f:
        f.write(json.dumps(row) + "\n")


def notify(msg: str) -> None:
    try:
        subprocess.run(
            ["osascript", "-e",
             f'display notification "{msg}" with title "Claude quota watch"'],
            check=False,
            timeout=5,
        )
    except Exception:
        pass


def _read_active_email() -> str:
    """Read the post-swap active Anthropic account email from ~/.claude.json.
    Used to fill the swap-notification marker's `to` field — the cache still
    has the OLD email at this point (it was the trigger). Empty string on any
    error so the marker write doesn't crash the watch tick."""
    try:
        with open(os.path.join(HOME, ".claude.json")) as f:
            return json.load(f).get("oauthAccount", {}).get("emailAddress", "")
    except Exception:
        return ""


def main(self_path: str) -> None:
    try:
        t5 = int(os.environ.get("CLAUDE_QUOTA_5H", "98"))
        t7 = int(os.environ.get("CLAUDE_QUOTA_7D", "98"))

        if not os.path.exists(CACHE):
            log("no cache yet — skip (is the Stop hook installed?)")
            return

        try:
            cache = json.load(open(CACHE))
        except Exception as e:
            log(f"cache unreadable: {e}")
            return

        age = time.time() - (cache.get("captured_at") or 0)
        if age > STALE_AFTER_SECS:
            log(f"cache stale ({int(age)}s) — no active session; skip")
            return

        pct5 = cache.get("five_hour_pct") or 0
        pct7 = cache.get("seven_day_pct") or 0
        email = cache.get("email", "")

        # Thrashing guard — if we swapped recently, the session is still on
        # its old token and reporting misleading numbers against the new email.
        in_cooldown, elapsed = recently_swapped()
        if in_cooldown:
            log(
                f"cooldown active ({elapsed}s since last swap; "
                f"cache says {email} at 5h:{pct5}% 7d:{pct7}%) — skip"
            )
            return

        reason, action = None, None
        if pct5 >= t5:
            reason, action = f"5h at {pct5}% (>= {t5}%)", "rotate"
        elif pct7 >= t7:
            reason, action = f"7d at {pct7}% (>= {t7}%)", "rotate"

        if not action:
            log(f"ok — {email} at 5h:{round(pct5)}% 7d:{round(pct7)}% (no swap)")
            return

        log(f"TRIGGER ({action}): {reason}")

        r = subprocess.run(
            [self_path, "switch"], capture_output=True, text=True
        )
        log(
            f"swap result: rc={r.returncode} "
            f"stdout={r.stdout.strip()} stderr={r.stderr.strip()}"
        )

        append_swap_log({
            "ts": int(time.time()),
            "from": email,
            "action": action,
            "reason": reason,
            "five_hour_pct": pct5,
            "seven_day_pct": pct7,
            "rc": r.returncode,
        })

        # After a successful swap: write a swap-notification marker that the
        # statusLine renderer (context-monitor.py) surfaces as a prominent
        # in-session banner ("🔄 swapped j→cc Nm ago — restart pre-swap
        # sessions"). EVERY running session sees the swap on their next
        # statusLine refresh — no keystroke automation, no IDE hijack, no
        # alert beeps.
        #
        # The running session keeps burning the OLD account's in-memory token
        # until the user restarts it (README Lesson #4) — that's the deliberate
        # cost of not hijacking the IDE. The prior auto-respawn path used
        # osascript + System Events keystrokes into the IDE, which produced
        # focus contention + macOS alert beeps on multi-session swaps
        # (root-caused 2026-05-27).
        #
        # OPT-IN: set CLAUDE_AUTOSWAP_RESPAWN=1 to restore the legacy kill +
        # respawn behavior. Only meaningful for unattended overnight agents
        # that MUST keep working past the cap without a human present to
        # restart. For interactive use it's strictly noisier.
        if r.returncode != 0:
            # Swap failed — most commonly because there's only one account in
            # USER.md (rotation needs >= 2). Degrade quietly: no OS notification
            # and no in-session banner, both of which would falsely claim a swap
            # happened. The failed attempt is already in the swap-log + the
            # "swap result: rc=..." line above. The session simply rides its own
            # cap until the rate-limit window rolls over.
            log(f"swap did not happen (rc={r.returncode}) — no notification sent")
            return

        notify(f"swapped from {email}: {reason}")

        try:
            marker = os.path.join(HOME, ".claude", "swap-notification.json")
            with open(marker, "w") as f:
                json.dump({
                    "from": email,
                    "to": _read_active_email(),
                    "ts": int(time.time()),
                    "reason": reason,
                }, f)
        except Exception as e:
            log(f"swap-notification marker write failed: {type(e).__name__}: {e}")

        if os.environ.get("CLAUDE_AUTOSWAP_RESPAWN") == "1":
            resume_script = os.path.join(
                os.path.dirname(os.path.abspath(__file__)), "_resume.py"
            )
            if os.path.exists(resume_script):
                try:
                    rs = subprocess.run(
                        [sys.executable, resume_script],
                        capture_output=True,
                        text=True,
                        timeout=30,
                    )
                    log(f"resume (opt-in): {rs.stdout.strip() or '(no output)'}")
                    if rs.stderr.strip():
                        log(f"resume stderr: {rs.stderr.strip()}")
                except Exception as e:
                    log(f"resume invoke failed: {type(e).__name__}: {e}")
        else:
            log("auto-respawn skipped (default; opt-in via CLAUDE_AUTOSWAP_RESPAWN=1)")

    except Exception as e:
        # Never crash the launchd agent. Log and move on.
        log(f"watch crashed: {type(e).__name__}: {e}")


if __name__ == "__main__":
    # argv: self-path (claude-identity.sh)
    # Note: come-home removed 2026-04-23, so the second-arg "primary" from
    # claude-identity.sh `watch` is now accepted but ignored for back-compat.
    if len(sys.argv) < 2:
        sys.stderr.write("_watch.py: usage: _watch.py <self_path>\n")
        sys.exit(2)
    main(sys.argv[1])
