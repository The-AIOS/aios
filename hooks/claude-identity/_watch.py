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
import re
import subprocess
import sys
import time


HOME = os.path.expanduser("~")
# Claude Code relocates its whole config tree when CLAUDE_CONFIG_DIR is set, and
# the documented safe way to add a second account depends on that: log the new
# account into an ISOLATED config dir and capture from there, so the live
# credentials are never touched and no logout fires. Hard-coding ~/.claude here
# would make the watcher read one account's state while the operator works in
# another — silently, since every path would still resolve.
CONFIG_DIR = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(HOME, ".claude")
CACHE = os.path.join(CONFIG_DIR, "rate-limit-cache.json")
LOG = os.path.join(CONFIG_DIR, "quota-watch.log")
SWAP_LOG = os.path.join(CONFIG_DIR, "swap-log.jsonl")
IDENTITIES = os.path.join(CONFIG_DIR, "identities")
USER_MD = os.environ.get("USER_MD_PATH") or os.path.join(HOME, "aios", "USER.md")
STALE_AFTER_SECS = 1800  # 30 min
COOLDOWN_SECS = 900  # 15 min — prevent thrashing after a swap

# ── rotation thresholds ─────────────────────────────────────────────────────
# This module is the SINGLE owner of the default. claude-identity.sh used to
# carry its own `THRESHOLD_5H="${CLAUDE_QUOTA_5H:-98}"`, which nothing read and
# nothing exported — and the hot path (statusLine -> _cache.py -> _watch.py)
# never touches the shell at all, so an operator editing that line changed
# nothing and got no error. Two declarations of one value is one too many; the
# one the consumer reads is the only one that exists now.
DEFAULT_THRESHOLD_PCT = 98


def _threshold(name: str) -> tuple:
    """(value, source) for one threshold. `source` says where the value that is
    ACTUALLY in force came from — a rejected override reports the default, not
    'environment'. Mislabelling that is the same failure this fix exists for."""
    raw = os.environ.get(name)
    if raw is None or raw.strip() == "":
        return DEFAULT_THRESHOLD_PCT, "built-in default"
    try:
        v = int(raw)
    except ValueError:
        log(f"{name}={raw!r} is not an integer — using {DEFAULT_THRESHOLD_PCT}")
        return DEFAULT_THRESHOLD_PCT, f"built-in default ({name} rejected: not an integer)"
    if not 1 <= v <= 100:
        # A 0 would rotate on every tick; a 150 would never rotate. Both are
        # almost certainly typos, and both fail silently if we honour them.
        log(f"{name}={v} out of range 1-100 — using {DEFAULT_THRESHOLD_PCT}")
        return DEFAULT_THRESHOLD_PCT, f"built-in default ({name}={v} out of range 1-100)"
    return v, "environment"


def thresholds() -> tuple:
    """(5h, 7d) rotation thresholds actually in force."""
    return _threshold("CLAUDE_QUOTA_5H")[0], _threshold("CLAUDE_QUOTA_7D")[0]


def _swap_log_tail(limit: int = 40) -> list:
    """Most recent swap-log rows, newest first. Bounded read; malformed lines
    are skipped rather than aborting the scan."""
    if not os.path.exists(SWAP_LOG):
        return []
    rows = []
    try:
        with open(SWAP_LOG, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            if size == 0:
                return []
            block = min(65536, size)
            f.seek(-block, os.SEEK_END)
            lines = f.read().splitlines()
        # A partial first line is likely when we seek into the middle of the
        # file; json.loads rejects it and the skip below handles it.
        for raw in reversed(lines[-limit:]):
            try:
                rows.append(json.loads(raw.decode()))
            except Exception:
                continue
    except Exception:
        return []
    return rows


def last_actual_swap() -> dict:
    """The most recent row where the account genuinely changed.

    `declined` rows are NOT swaps. They must be skipped here: a decline means we
    looked and stayed put, so nothing about the session changed and there is
    nothing to debounce. Counting one would arm the cooldown at the exact moment
    the watcher most needs to keep looking — the other account's window may roll
    over seconds later, and we would not notice for another COOLDOWN_SECS."""
    for r in _swap_log_tail():
        if r.get("action") == "rotate" and r.get("rc") == 0:
            return r
    return {}


def recently_swapped() -> tuple[bool, int]:
    """Returns (True, seconds_since_last) if a swap happened within COOLDOWN_SECS.
    Thrashing guard: after a swap the running session keeps the old token in
    memory; its next turns report the OLD account's rate_limits against the NEW
    oauthAccount email in ~/.claude.json — without this cooldown we'd swap
    back immediately and ping-pong forever."""
    last = last_actual_swap()
    if not last:
        return False, 0
    elapsed = int(time.time() - (last.get("ts") or 0))
    return elapsed < COOLDOWN_SECS, elapsed


def log(msg: str) -> None:
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "a") as f:
        f.write(f"[{time.strftime('%Y-%m-%dT%H:%M:%S')}] {msg}\n")


def append_swap_log(row: dict) -> None:
    os.makedirs(os.path.dirname(SWAP_LOG), exist_ok=True)
    with open(SWAP_LOG, "a") as f:
        f.write(json.dumps(row) + "\n")


def notify(msg: str) -> None:
    """Best-effort desktop notification. Never raises, never blocks the tick.

    Platform-detected rather than macOS-only: `osascript` simply does not exist
    off macOS, and the except below swallows that — so on Linux every
    notification this module sends was silently dropped, including the two that
    matter most (no account has capacity; a rotation was not adopted). A missing
    notifier is still a no-op, but now it is the RIGHT notifier that is missing."""
    if sys.platform == "darwin":
        cmd = ["osascript", "-e",
               f'display notification "{msg}" with title "Claude quota watch"']
    else:
        # libnotify is near-universal on desktop Linux; absent on headless
        # boxes, where the log is the channel that matters anyway.
        cmd = ["notify-send", "Claude quota watch", msg]
    try:
        subprocess.run(cmd, check=False, timeout=5)
    except Exception:
        pass


def _read_active_email() -> str:
    """Read the post-swap active Anthropic account email from ~/.claude.json.
    Used to fill the swap-notification marker's `to` field — the cache still
    has the OLD email at this point (it was the trigger). Empty string on any
    error so the marker write doesn't crash the watch tick."""
    # Same beside-or-inside rule as the other components: .claude.json sits next
    # to the config dir normally and inside it when relocated.
    for p in (os.path.join(CONFIG_DIR, ".claude.json"),
              os.path.join(HOME, ".claude.json")):
        try:
            with open(p) as f:
                return json.load(f).get("oauthAccount", {}).get("emailAddress", "")
        except Exception:
            continue
    return ""


# ── did the live session actually adopt the swap? ───────────────────────────
# The one hole this design cannot close by itself. Rotating the credential is
# our code; a RUNNING session picking it up is Claude Code's internal behaviour
# (it stat()s the credential store on the API request path and purges its token
# caches when mtime changes). That was measured, but it is not a contract we
# control — an upstream change could remove it, and the failure would be MUTE:
# the swap succeeds, the log says "rotated", and the session keeps burning the
# capped account until it hits the wall the autopilot exists to avoid.
#
# The detector is cheap because we only ever rotate to an account with real
# capacity (pick_target). So after a successful swap the reported percentage
# MUST fall. If it is still high minutes later, the session never adopted.
ADOPTION_GRACE_SECS = 120   # let the session make its next request
ADOPTION_WINDOW_SECS = 900  # past this, stop looking
ADOPTION_DROP_PTS = 3       # minimum fall that counts as adoption
ALERT_FILE = os.path.join(CONFIG_DIR, "rotation-alert.json")


def check_adoption(cache: dict) -> None:
    """Warn if a completed rotation never reached the running session."""
    last = last_actual_swap()
    if not last:
        return
    now = time.time()
    elapsed = now - (last.get("ts") or 0)
    if elapsed < ADOPTION_GRACE_SECS or elapsed > ADOPTION_WINDOW_SECS:
        return
    # The cache must be NEWER than the swap, or we are reading the old photo and
    # would report a failure that has not had a chance to happen yet.
    if (cache.get("captured_at") or 0) <= (last.get("ts") or 0):
        return
    before = last.get("five_hour_pct") or 0
    current = cache.get("five_hour_pct") or 0
    if current < before - ADOPTION_DROP_PTS:
        # It fell: adopted. Clear any previous alert so a recovered system does
        # not keep showing a stale warning.
        if os.path.exists(ALERT_FILE):
            try:
                os.remove(ALERT_FILE)
            except OSError:
                pass
        return
    msg = (
        f"rotation to {_read_active_email()} happened {int(elapsed)}s ago but 5h usage "
        f"is still {round(current)}% (was {round(before)}% before the swap). The live "
        f"session did not adopt the new credential — most likely Claude Code stopped "
        f"re-reading the credential store. Restart open sessions and check whether an "
        f"update changed that behaviour."
    )
    log(f"ADOPTION FAILED: {msg}")
    notify(msg)
    try:
        with open(ALERT_FILE, "w") as f:
            json.dump({
                "ts": int(now),
                "kind": "adoption_failed",
                "message": msg,
                "pct_before": before,
                "pct_now": current,
            }, f)
    except Exception as e:
        log(f"alert write failed: {type(e).__name__}: {e}")


# ── where to rotate ─────────────────────────────────────────────────────────
# Rotation used to be a bare `switch`, which advances one position in the
# USER.md list and wraps. With exactly two accounts — the common case — that
# means exhausting B rotates straight back to A, whose 5h window has not rolled
# yet. The session lands on a dead account and then sits out the cooldown there,
# which is worse than not rotating at all.
#
# The data needed to avoid it is already in hand and was being thrown away:
# `rate_limits` carries `resets_at` per window. Persisting the ACTIVE account's
# limits on every tick is what lets the watcher reason about accounts it is not
# currently on — otherwise it is blind to every account but one, and blind is
# exactly what forces round-robin.


def parse_accounts() -> list:
    """Ordered account list from USER.md -> '## Anthropic accounts'.

    Position is preference, not a cycle: #1 is home, the rest are overflow.
    Same numbered-backtick format claude-identity.sh parses; kept in step with
    it deliberately, because two parsers disagreeing about the account list is
    the failure this file already fixed once for thresholds."""
    out = []
    try:
        in_sec = False
        with open(USER_MD, encoding="utf-8") as f:
            for line in f:
                if line.startswith("## Anthropic accounts"):
                    in_sec = True
                    continue
                if in_sec and line.startswith("## "):
                    break
                if in_sec:
                    m = re.match(r"\s*\d+\.\s*`([^`]+)`", line)
                    if m:
                        out.append(m.group(1))
    except FileNotFoundError:
        log(f"USER.md not found at {USER_MD} — cannot determine the account list")
    except Exception as e:
        log(f"could not parse accounts from {USER_MD}: {type(e).__name__}: {e}")
    return out


def state_path(email: str) -> str:
    return os.path.join(IDENTITIES, email, "last-limits.json")


def record_state(email: str, cache: dict) -> None:
    """Persist the active account's limits so that, once we have rotated away
    from it, we can still reason about when its window frees up."""
    if not email:
        return
    try:
        os.makedirs(os.path.join(IDENTITIES, email), exist_ok=True)
        dst = state_path(email)
        tmp = dst + ".tmp"
        with open(tmp, "w") as f:
            json.dump({
                "email": email,
                "recorded_at": int(time.time()),
                "five_hour_pct": cache.get("five_hour_pct") or 0,
                "five_hour_resets_at": cache.get("five_hour_resets_at"),
                "seven_day_pct": cache.get("seven_day_pct") or 0,
                "seven_day_resets_at": cache.get("seven_day_resets_at"),
            }, f, indent=2)
        os.replace(tmp, dst)
        os.chmod(dst, 0o600)
    except Exception as e:
        log(f"record_state({email}) failed: {type(e).__name__}: {e}")


def headroom(email: str, t5: int, t7: int) -> tuple:
    """(available, why) for an account we are not currently on.

    Available means: no evidence it is capped, or the window that capped it has
    already rolled over. Absence of evidence is treated as available on purpose
    — a never-seen account is the normal state right after setup, and refusing
    to rotate to it would make the feature useless on day one."""
    p = state_path(email)
    if not os.path.exists(p):
        return True, "no known state (assume fresh)"
    try:
        with open(p) as f:
            s = json.load(f)
    except Exception:
        return True, "state unreadable (assume fresh)"
    now = time.time()
    for pct_key, reset_key, thr, label in (
        ("five_hour_pct", "five_hour_resets_at", t5, "5h"),
        ("seven_day_pct", "seven_day_resets_at", t7, "7d"),
    ):
        pct = s.get(pct_key) or 0
        reset = s.get(reset_key)
        if pct < thr:
            continue
        if reset and now > reset:
            continue  # window rolled over — fresh again
        when = time.strftime("%H:%M", time.localtime(reset)) if reset else "unknown"
        return False, f"{label} at {round(pct)}% until {when}"
    return True, "under thresholds"


def pick_target(current: str, t5: int, t7: int) -> tuple:
    """(email_or_None, reason). Preference is USER.md order, but an account is
    only a candidate if its cap window has actually rolled."""
    accts = parse_accounts()
    if len(accts) < 2:
        return None, f"need >= 2 accounts in USER.md (found {len(accts)})"
    blocked = []
    for email in accts:
        if email == current:
            continue
        ok, why = headroom(email, t5, t7)
        if ok:
            return email, why
        blocked.append(f"{email} ({why})")
    return None, "all alternatives still capped: " + "; ".join(blocked)


def main(self_path: str) -> None:
    try:
        t5, t7 = thresholds()

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

        # Persist BEFORE deciding. This tick is the only moment we can observe
        # the active account's numbers; once we rotate away it goes dark until
        # we come back. The rotation decision below is only ever as good as this
        # record, so it must not sit behind any of the early returns.
        record_state(email, cache)

        # Deliberately BEFORE the cooldown check. The cooldown returns early,
        # and the cooldown window is exactly when a failed adoption is visible —
        # putting this after it would mean the one condition the detector exists
        # for is the one it never runs in.
        check_adoption(cache)

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

        # Where to — not a blind advance. Declining to rotate is a legitimate
        # outcome and a better one than landing on an account that is still
        # capped, so it is logged as its own action rather than as a failure.
        target, why = pick_target(email, t5, t7)
        if not target:
            log(f"NO ROTATION — {why}. Staying on {email}; its window rolls on its own.")
            append_swap_log({
                "ts": int(time.time()),
                "from": email,
                "action": "declined",
                "reason": f"{reason} | {why}",
                "five_hour_pct": pct5,
                "seven_day_pct": pct7,
                "rc": None,
            })
            notify(f"quota {round(pct5)}% — no account with capacity. {why}")
            return

        log(f"target: {target} ({why})")
        r = subprocess.run(
            [self_path, "switch", target], capture_output=True, text=True
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
    if len(sys.argv) >= 2 and sys.argv[1] == "--threshold":
        # Report the value THIS process would enforce. The point is that it is
        # answered by the consumer, so it cannot drift from what actually runs.
        t5, s5 = _threshold("CLAUDE_QUOTA_5H")
        t7, s7 = _threshold("CLAUDE_QUOTA_7D")
        print(f"5h: {t5}%  ({s5})")
        print(f"7d: {t7}%  ({s7})")
        sys.exit(0)
    if len(sys.argv) < 2:
        sys.stderr.write("_watch.py: usage: _watch.py <self_path> | --threshold\n")
        sys.exit(2)
    main(sys.argv[1])
