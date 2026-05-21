#!/usr/bin/env python3
"""
_resume.py — after an auto-swap, continue any active Claude Code sessions.

The problem: `claude-switch` rewrites the Keychain + ~/.claude.json, but a
running Claude Code session holds the OLD account's OAuth token in memory.
It keeps working for ~1h until refresh, then fails (the refresh token
belongs to the OLD account, Keychain now has the NEW). Session stalls.

The fix: right after the swap, kill each active session and respawn with
`--resume <session-id>` + an auto-resume prompt so Claude wakes up with
the EXACT transcript that was in flight and immediately picks up work.
No human input needed.

Why --resume <id> and not --continue (fix 2026-04-23): `--continue` picks
the most-recently-modified session in the project directory — it ignores
`--name`, so when N sessions respawn in parallel after a swap, they ALL
load the same (most recent) transcript. Cross-contamination: agent A's
terminal tab ends up running agent B's transcript, etc. The fix is to
capture each session's session_id via lsof BEFORE kill, then respawn each
with `--resume <its-own-session-id>` so transcripts stay isolated.

Belt-and-suspenders: before each kill, _resume.py also writes a pre-swap
marker to /tmp/swap-marker-{name}-{ts}.json with session metadata + git
status. The resume prompt instructs Claude to read the marker and
reconcile filesystem state vs. transcript expectation before doing any
new work. Handles the narrow window where a tool call modified files but
the tool result hadn't yet been appended to the JSONL when the kill hit.

Scope: runs on the machine where the swap happened — each machine's
watcher handles its own sessions. No cross-machine coordination; each
machine owns its own respawns.

Discovery: reads ~/.claude/sessions/*.json (filename is PID, cwd + sessionId
inside). On Claude Code 2.1.121+, the session JSON also includes a `name`
field — the user-facing session name written by the binary itself, which
survives arg-rewrites and manual `claude --resume X` invocations. We read
identity in priority order: `CLAUDE_AGENT_NAME` env (set by spawn wrapper)
→ JSON `name` field → `--name` from ps args. Session UUID (the transcript
file) is discovered via `lsof -p PID` or read from the JSON's sessionId.
Sessions without a discoverable name are skipped (no respawn) so we never
corrupt them with a UUID-as-name.

Respawn: uses osascript to open Terminal.app or an IDE terminal tab with
the same name + cwd + --resume <session_id> + --remote-control + initial
prompt. Matches the spawn wrapper pattern in ~/.zshrc.

Auto-resume prompt: references the pre-swap marker file. Claude sees it
as the first user turn after resume, reads the marker, reconciles state,
then continues only work the user had explicitly approved.

Dry-run: pass `--dry-run` to skip kills + respawns but still write markers.
Useful for verifying the fix before the next real swap fires.
"""
import json
import os
import subprocess
import sys
import time
from glob import glob


SESSIONS_DIR = os.path.expanduser("~/.claude/sessions")

# Prompt tuning note (2026-04-22):
# The first version said "Continue your previous work." That reads as a
# command — the agent scans the transcript for whatever was in flight and
# auto-executes it. When the transcript contained a PROPOSAL-not-yet-
# approved (e.g., "should I build a stall monitor?"), the agent
# auto-approved itself and started shipping. Bad.
# The fix is to phrase the prompt as status, not instruction: acknowledge
# the swap, but only resume work the user EXPLICITLY approved. Pending
# proposals or open questions must wait for a human reply.
#
# 2026-04-23 update: prompt now references a pre-swap marker file so the
# resumed session can reconcile filesystem state vs. transcript expectation.
# Built per-session via build_resume_prompt() because marker_path is unique.
def build_resume_prompt(name: str, cwd: str, marker_path: str) -> str:
    ts = time.strftime("%Y-%m-%d %H:%M:%S %Z")
    return (
        f"Account swap executed by the quota-watch autopilot at {ts}. Your session "
        f"was killed and respawned with --resume <session-id> so the transcript is "
        f"exactly yours (not cross-contaminated with a sibling session).\n"
        f"\n"
        f"**Before continuing any work — verified-resume checklist:**\n"
        f"1. Read `{marker_path}` — the pre-swap snapshot captured just before kill. "
        f"It contains your session_id, cwd, and the git status at kill time.\n"
        f"2. Run `git status` in `{cwd}` and compare against the marker's `git_status` "
        f"field. If they match, filesystem state matches your transcript — continue.\n"
        f"3. If they differ (files modified on disk but not reflected in your last "
        f"transcript turn), the kill landed mid-tool-use — a write succeeded on disk "
        f"but the tool result never reached your transcript. Reconcile BEFORE new work: "
        f"re-read the affected files to understand current state, then either continue "
        f"from there or flag the discrepancy to the user.\n"
        f"\n"
        f"Only resume work the user has EXPLICITLY approved in the transcript. If the "
        f"last turn was a proposal or a question awaiting their answer, do NOT "
        f"auto-approve yourself — stand by for the user's next prompt."
    )

# Post-swap wait — Anthropic's backend takes ~2-3s to fully propagate a
# new account's auth. If we spawn `claude --continue` too fast, Remote
# Control's /login endpoint returns 401 or Cloudflare 502, and the new
# session halts before it can establish. Empirically 3s is reliable; bump
# this if 401/502 errors still appear in quota-watch.log.
POST_SWAP_WAIT_SECS = 3


def is_pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def env_var_from_pid(pid: int, key: str) -> str:
    """Read a single env var from a running process via macOS `ps -E`.

    `ps -E -p <pid> -o command=` prepends env (KEY=VALUE pairs) to the
    command line. We tokenize and return the value of the first token
    that starts with `<key>=`. Empty string if not found.

    Used to read `CLAUDE_AGENT_NAME` — the canonical, spawn-wrapper-set
    identity — before falling back to fragile arg-parsing."""
    try:
        r = subprocess.run(
            ["ps", "-E", "-p", str(pid), "-o", "command="],
            capture_output=True, text=True, timeout=3,
        )
        if r.returncode != 0:
            return ""
        out = r.stdout.strip()
    except Exception:
        return ""
    prefix = key + "="
    for tok in out.split():
        if tok.startswith(prefix):
            return tok[len(prefix):]
    return ""


def session_name_from_ps(pid: int) -> str:
    """Extract the session name from a claude process's CLI args.

    Returns the value of `--name` if present, empty string otherwise.
    `--resume <X>` is NOT consulted: its value is always a session UUID,
    never a name, and using it as a name was the root cause of the
    2026-04-28 corruption mode (see bug history below).

    This function is the last-resort fallback for sessions launched
    without the spawn wrapper. The canonical reader is
    `session_name_from_pid()`, which prefers the `CLAUDE_AGENT_NAME`
    env var.

    Bug history:
    - 2026-04-28 (fix 1): preferred `--name` over `--resume` after
      Claude Code 2.1.117+ started inserting `--resume <uuid>` before
      `--name` in the args. Linear-walk parser returned the UUID.
    - 2026-04-28 (fix 2 — this version): dropped the `--resume`
      fallback entirely. Sessions invoked manually as
      `claude --resume <uuid>` with no name and no env var are now
      skipped by the swap (treated like plain `claude`) instead of
      respawned with the UUID as the name. Skipping is strictly safer:
      the session keeps running on the new account; it just doesn't
      get a swap-marker + verified-resume prompt."""
    try:
        r = subprocess.run(
            ["ps", "-p", str(pid), "-o", "command="],
            capture_output=True, text=True, timeout=3,
        )
        if r.returncode != 0:
            return ""
        cmd = r.stdout.strip()
    except Exception:
        return ""
    parts = cmd.split()

    for i, tok in enumerate(parts):
        if tok == "--name" and i + 1 < len(parts):
            nxt = parts[i + 1]
            if not nxt.startswith("-"):
                return nxt
    return ""


# Curated word pools for tier-4 auto-baptism. Kept short and memorable.
# 30 × 30 = 900 combos; collision odds < 5% across ~10 concurrent sessions.
_AUTO_ADJ = (
    "wandering","gentle","happy","sleepy","clever","quiet","brave",
    "quirky","sunny","witty","jolly","calm","bold","fancy","fuzzy",
    "lucky","mellow","nimble","plucky","silly","spry","tidy","zesty",
    "misty","nifty","peppy","rosy","snazzy","spiffy","jaunty",
)
_AUTO_ANI = (
    "otter","llama","panda","fox","sloth","koala","badger","raven",
    "lemur","newt","quokka","tapir","yak","ibex","goose","heron",
    "mole","narwhal","octopus","puffin","quetzal","raccoon","seal",
    "toucan","urchin","viper","wombat","kiwi","ferret","capybara",
)


def auto_name(session_id: str) -> str:
    """Deterministic <adjective>-<animal> name derived from session_id.

    Same session_id always maps to the same name. After the first swap
    respawn, the auto-name lands in `--name` args of the new claude
    process, so subsequent swaps read it via tier 3 — no need to
    re-derive. The pool is intentionally whimsical (`wandering-otter`,
    `peppy-narwhal`) so it's obviously an auto-baptism in claude.ai/code
    listings, not a real user-chosen name."""
    import hashlib
    h = int(hashlib.md5(session_id.encode()).hexdigest(), 16)
    adj = _AUTO_ADJ[h % len(_AUTO_ADJ)]
    ani = _AUTO_ANI[(h // len(_AUTO_ADJ)) % len(_AUTO_ANI)]
    return f"{adj}-{ani}"


def session_name_from_pid(pid: int, info: dict | None = None) -> str:
    """Canonical session-name reader.

    Priority:
    1. `CLAUDE_AGENT_NAME` env var — set by the spawn wrapper, untouched
       by Claude Code. Stable surface we own.
    2. `name` field in the session JSON at `~/.claude/sessions/<pid>.json`
       — added by Claude Code 2.1.121+. Stable, written by the binary itself,
       survives arg-rewrites and manual `claude --resume <X>` invocations.
       Pass `info` (the parsed JSON dict) to enable this tier.
    3. `--name <name>` from ps args — fallback for sessions launched on
       Claude Code versions that don't write the JSON name yet.
    4. Auto-baptized name derived deterministically from `info["sessionId"]`
       — only for `entrypoint == "cli"` sessions. Catches plain `claude`
       invocations (no name, no env, no flag) so the swap can still
       respawn them. After the first swap, the auto-name is baked into
       `--name` args of the respawn, so this tier doesn't fire again.

    `--resume` is never consulted (its value is always a session UUID,
    never a name). SDK subprocesses (`entrypoint != "cli"`) skip tier 4
    and return empty — they're internal claude children, not respawnable.

    Reading from env first prevents the 2026-04-28 corruption mode where
    Claude Code's internal arg-rewrite caused our ps-args parser to leak
    the session UUID into `--name`. The JSON tier (added 2026-04-28) and
    auto-baptize tier (added 2026-04-28) close the gap for sessions that
    don't go through the spawn wrapper — including teammates' main
    sessions launched as plain `claude`."""
    env_name = env_var_from_pid(pid, "CLAUDE_AGENT_NAME")
    if env_name:
        return env_name
    if info:
        json_name = info.get("name")
        if isinstance(json_name, str) and json_name:
            return json_name
    args_name = session_name_from_ps(pid)
    if args_name:
        return args_name
    # Tier 4: auto-baptize unnamed CLI sessions
    if info and info.get("entrypoint") == "cli":
        sid = info.get("sessionId")
        if isinstance(sid, str) and sid:
            return auto_name(sid)
    return ""


def tty_for_pid(pid: int) -> str:
    """Return the absolute TTY path for a pid (e.g. /dev/ttys003), or '' if
    not detectable. We use it later to close the exact Terminal.app tab that
    was hosting the old session."""
    try:
        r = subprocess.run(
            ["ps", "-p", str(pid), "-o", "tty="],
            capture_output=True, text=True, timeout=3,
        )
        if r.returncode != 0:
            return ""
        name = r.stdout.strip()
        if not name or name == "??":
            return ""
        return f"/dev/{name}" if not name.startswith("/dev/") else name
    except Exception:
        return ""


def session_id_from_pid(pid: int, info: dict) -> str:
    """Find the session UUID for a live Claude session.

    Primary path: `~/.claude/sessions/{pid}.json` already contains a
    `sessionId` field on Claude Code 2.1.118+. This is the authoritative
    source — works for active AND idle sessions, no permissions issues.

    Fallback: `lsof -p PID` looking for an open .jsonl under
    ~/.claude/projects/ — only works when Claude is actively writing
    the transcript. Useful on older Claude Code versions where sessionId
    wasn't in the sessions JSON.

    Returns '' if both fail — caller falls back to --continue for that
    one session (pre-fix behavior, no worse)."""
    # Primary: sessions JSON (already loaded by main loop, passed in as info)
    sid = info.get("sessionId", "") or ""
    if sid:
        return sid

    # Fallback: lsof. Only fires on old Claude Code versions without
    # sessionId in the sessions JSON.
    try:
        r = subprocess.run(
            ["lsof", "-p", str(pid), "-Fn"],
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode != 0:
            return ""
    except Exception:
        return ""

    # lsof -Fn format: each line starts with a type char, 'n' = file name.
    candidates: list[tuple[float, str]] = []
    for line in r.stdout.splitlines():
        if not line.startswith("n"):
            continue
        path = line[1:]
        if "/.claude/projects/" not in path or not path.endswith(".jsonl"):
            continue
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            mtime = 0.0
        candidates.append((mtime, path))
    if not candidates:
        return ""
    candidates.sort(reverse=True)
    return os.path.basename(candidates[0][1]).replace(".jsonl", "")


def write_swap_marker(name: str, session_id: str, cwd: str) -> str:
    """Write a pre-swap snapshot to /tmp so the resumed session can
    reconcile filesystem vs. transcript state. Always returns the marker
    path (even on partial failure — the file is cheap and helpful even if
    git fields are blank)."""
    ts = time.strftime("%Y%m%dT%H%M%S")
    path = f"/tmp/swap-marker-{name}-{ts}.json"
    marker = {
        "kill_time": time.strftime("%Y-%m-%d %H:%M:%S %Z"),
        "name": name,
        "session_id": session_id or "",
        "cwd": cwd,
        "git_status": "",
        "git_diff_stat": "",
    }
    # Capture git state if cwd is a git repo — this is the belt-and-
    # suspenders check. On wake, Claude reconciles these against the
    # transcript's last recorded state.
    if cwd and os.path.isdir(os.path.join(cwd, ".git")):
        try:
            r = subprocess.run(
                ["git", "-C", cwd, "status", "-s"],
                capture_output=True, text=True, timeout=5,
            )
            if r.returncode == 0:
                marker["git_status"] = r.stdout.strip()
        except Exception:
            pass
        try:
            r = subprocess.run(
                ["git", "-C", cwd, "diff", "--stat"],
                capture_output=True, text=True, timeout=5,
            )
            if r.returncode == 0:
                marker["git_diff_stat"] = r.stdout.strip()
        except Exception:
            pass
    try:
        with open(path, "w") as f:
            json.dump(marker, f, indent=2)
    except Exception:
        pass  # marker is belt-and-suspenders; failing to write isn't fatal
    return path


def detect_ide() -> str:
    """Match the spawn wrapper's IDE detection (~/.zshrc). Priority:
    Antigravity > VS Code > Cursor. Returns '' if none running — caller
    falls back to Terminal.app. A headless machine (no IDE running)
    always gets ''.

    Critical: match pgrep flags exactly to the spawn wrapper. Earlier
    version used `-f` (full command line) everywhere, which false-matched
    on a headless box when a shell contained "Cursor" in its args. `-q` alone
    matches only the process name (correct for Antigravity + Cursor);
    `-qf` is needed for VS Code because "Visual Studio Code" lives in
    args, not the process name."""
    # Flag choices caught two real bugs empirically:
    # - Antigravity's actual process name is "Antigravity Hel[per]" (truncated
    #   by macOS, with a space). `-xq "Antigravity"` misses it → falls through
    #   to VS Code matcher → false-positive because Antigravity is built on
    #   VS Code (its bundle path contains "Visual Studio Code"). Use `-q`
    #   (substring) for Antigravity, matching the spawn wrapper's pattern.
    # - Cursor: plain `-q "Cursor"` false-matches macOS's CursorUIViewService
    #   on headless machines. `-xq` (exact) keeps the true Cursor.app while
    #   rejecting the system helper.
    # - VS Code: process name isn't "Visual Studio Code" — use `-qf` (full
    #   cmdline match) because the string lives in the bundle path.
    # Order matters: Antigravity first so it catches before the VS Code
    # matcher (which would also match Antigravity via its bundle).
    candidates = [
        ("Antigravity", ["pgrep", "-q", "Antigravity"]),
        ("Visual Studio Code", ["pgrep", "-qf", "Visual Studio Code"]),
        ("Cursor", ["pgrep", "-xq", "Cursor"]),
    ]
    for app_name, cmd in candidates:
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
            if r.returncode == 0:
                return app_name
        except Exception:
            continue
    return ""


def close_terminal_tab_by_tty(tty: str) -> None:
    """Close the Terminal.app window hosting a tab whose tty matches.
    Terminal.app's AppleScript doesn't support `close tab` directly
    (rc=-1708) — we have to close the parent window. For single-tab
    windows (the common case on a headless machine) this is what we want.
    For multi-tab windows we skip the close to avoid killing other live
    tabs. Silent on error — this is cleanup, not critical path."""
    if not tty:
        return
    script = (
        'tell application "Terminal"\n'
        '  repeat with w in windows\n'
        f'    if (count of tabs of w) is 1 and tty of (first tab of w) is "{tty}" then\n'
        '      close w saving no\n'
        '      return\n'
        '    end if\n'
        '  end repeat\n'
        'end tell'
    )
    try:
        subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=5,
        )
    except Exception:
        pass  # best-effort


def _write_prompt_to_tempfile(name: str, prompt: str) -> str:
    """Route the prompt through a temp file so apostrophes, parens, and
    quotes in it can't break the AppleScript keystroke / `do script`
    single-quoting. The bootstrap string that gets interpolated into
    the shell command has no special chars — safe everywhere.

    Mirrors the spawn-wrapper fix in ~/.zshrc (Apr 22) where `$task`
    always goes to /tmp/spawn-task-$name.md and only a fixed bootstrap
    prompt is interpolated. Same class of bug, same fix."""
    path = f"/tmp/resume-prompt-{name}.md"
    with open(path, "w") as f:
        f.write(prompt + "\n")
    return path


def respawn_in_terminal(name: str, cwd: str, prompt: str, session_id: str) -> tuple[bool, str]:
    """Terminal.app path — always works, used on headless boxes and as
    fallback when no IDE is running.

    Routes through `_claude_with_respawn` (defined in ~/.zshrc) so the
    new tab IS a wrapped session. Subsequent swaps use the in-place
    path and stay in this tab. Without the wrapper indirection, every
    swap would open ANOTHER new tab — tab proliferation."""
    prompt_file = _write_prompt_to_tempfile(name, prompt)
    bootstrap = f"Read {prompt_file} and follow the instructions inside."
    inner = (
        f'cd "{cwd}" && '
        f'_claude_with_respawn "{name}" "{bootstrap}" "{session_id}"'
    )
    outer = f'tell application "Terminal" to do script "{inner.replace(chr(34), chr(92) + chr(34))}"'
    try:
        r = subprocess.run(
            ["osascript", "-e", outer],
            capture_output=True, text=True, timeout=10,
        )
        if r.returncode == 0:
            return True, "Terminal.app"
        return False, f"Terminal osascript rc={r.returncode}: {r.stderr.strip()}"
    except Exception as e:
        return False, f"Terminal error: {type(e).__name__}: {e}"


def respawn_in_ide(ide_app: str, name: str, cwd: str, prompt: str, session_id: str) -> tuple[bool, str]:
    """IDE path — opens a new terminal tab INSIDE the running IDE
    (Antigravity / VS Code / Cursor) via keystrokes, matching the spawn
    wrapper's behavior in ~/.zshrc. The old tab (dead shell) remains — the
    user can close it manually. We prioritize a clean new working tab over
    perfect cleanup on the IDE path.

    Mirrors the applescript block in spawn() from ~/.zshrc.

    Routes through `_claude_with_respawn` (defined in the new shell from
    its just-loaded ~/.zshrc) so the new tab IS a wrapped session.
    Subsequent swaps use the in-place path and stay in this tab — eventual
    convergence to in-place even for sessions originally launched outside
    the wrapper (plain `claude`, manual `--resume`, etc.)."""
    prompt_file = _write_prompt_to_tempfile(name, prompt)
    bootstrap = f"Read {prompt_file} and follow the instructions inside."
    # The command typed into the new IDE terminal tab — bootstrap has no
    # apostrophes / parens / special chars, so single-quote wrapping is safe.
    inner = (
        f"cd '{cwd}' && "
        f"_claude_with_respawn '{name}' '{bootstrap}' '{session_id}'"
    )
    script = f'''
        tell application "{ide_app}" to activate
        delay 0.5
        tell application "System Events"
          tell process "{ide_app}"
            keystroke "`" using {{control down, shift down}}
            delay 0.8
            keystroke return
            delay 1
            keystroke "P" using {{command down, shift down}}
            delay 0.5
            keystroke "Terminal: Rename"
            delay 0.5
            keystroke return
            delay 0.3
            keystroke "{name}"
            keystroke return
            delay 1
            keystroke "{inner}"
            delay 0.3
            keystroke return
          end tell
        end tell
    '''
    try:
        r = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=15,
        )
        if r.returncode == 0:
            return True, f"{ide_app} new terminal tab"
        return False, f"IDE osascript rc={r.returncode}: {r.stderr.strip()}"
    except Exception as e:
        return False, f"IDE error: {type(e).__name__}: {e}"


def write_in_place_signal(name: str, session_id: str, prompt: str) -> None:
    """Write the three files the spawn-wrapper's `_claude_with_respawn` loop
    polls for after claude exits:

      /tmp/swap-respawn-{name}.flag      — signal: respawn me
      /tmp/swap-respawn-{name}.session   — session UUID for --resume
      /tmp/resume-prompt-{name}.md       — verified-resume bootstrap

    Must be written BEFORE SIGTERM so the wrapper sees them on the first
    check after claude exits. The wrapper consumes (deletes) .flag and
    .session after read; the prompt file is reused on next swap.

    Used only when the killed process has CLAUDE_RESPAWN_CAPABLE=1 in env
    (set by `_claude_with_respawn` in ~/.zshrc). Sessions launched without
    the wrapper get the legacy AppleScript respawn path."""
    with open(f"/tmp/swap-respawn-{name}.session", "w") as f:
        f.write(session_id)
    with open(f"/tmp/resume-prompt-{name}.md", "w") as f:
        f.write(prompt + "\n")
    # Flag last — the wrapper short-circuits if absent, so we want everything
    # else on disk before the flag exists.
    with open(f"/tmp/swap-respawn-{name}.flag", "w") as f:
        pass


def wait_for_new_claude(name: str, killed_pid: int, timeout: float = 8.0) -> tuple[int, str]:
    """Poll for a new claude process that's the wrapper's respawn of the
    just-killed session. Match criteria:
      - pid != killed_pid
      - CLAUDE_AGENT_NAME env equals `name`
    Returns (pid, msg). pid == 0 means timeout — respawn unverified.

    Validates that the in-place respawn loop actually worked. Replaces the
    osascript-rc==0 lie (which only meant 'AppleScript ran', not 'a tab
    actually got created and the command actually got typed')."""
    deadline = time.time() + timeout
    last_seen: list[int] = []
    while time.time() < deadline:
        try:
            r = subprocess.run(
                ["pgrep", "-f", "claude --"],
                capture_output=True, text=True, timeout=2,
            )
            if r.returncode == 0:
                last_seen = []
                for s in r.stdout.split():
                    try:
                        p = int(s)
                    except ValueError:
                        continue
                    if p == killed_pid:
                        continue
                    last_seen.append(p)
                    if env_var_from_pid(p, "CLAUDE_AGENT_NAME") == name:
                        return p, f"in-place respawn verified (pid {p})"
        except Exception:
            pass
        time.sleep(0.5)
    return 0, (
        f"in-place respawn UNVERIFIED — no claude pid with "
        f"CLAUDE_AGENT_NAME={name} appeared within {timeout}s "
        f"(saw {len(last_seen)} other claude pids)"
    )


def respawn_session(name: str, cwd: str, prompt: str, old_tty: str, ide: str, session_id: str) -> tuple[bool, str]:
    """Dispatch: IDE path if we're inside a running IDE, else Terminal.app.
    If the IDE path fails (app not actually responding, osascript error,
    etc.), FALL BACK to Terminal.app so we never leave the session
    orphaned — the whole point of resume is continuity, and "no window at
    all" is the worst outcome.
    Always tries to close the old Terminal.app tab by tty as cleanup
    (harmless if the old session was in an IDE — the tty won't match any
    Terminal window, osascript no-ops)."""
    if ide:
        ok, msg = respawn_in_ide(ide, name, cwd, prompt, session_id)
        if not ok:
            # Fall back to Terminal.app — better a Terminal window than nothing
            ok_fb, msg_fb = respawn_in_terminal(name, cwd, prompt, session_id)
            if ok_fb:
                msg = f"{ide} failed ({msg}); fell back to Terminal.app"
                ok = True
    else:
        ok, msg = respawn_in_terminal(name, cwd, prompt, session_id)
    # Always attempt tab close — if the old session was in Terminal.app,
    # this keeps state clean. If it was in an IDE, the no-match branch
    # costs nothing and leaves the IDE tab alone.
    close_terminal_tab_by_tty(old_tty)
    return ok, msg


def main() -> None:
    # Dry-run mode: skip kills + respawns, still write markers so the user
    # can inspect what WOULD happen. Useful to verify the fix before the
    # next real swap fires.
    dry_run = "--dry-run" in sys.argv

    if not os.path.isdir(SESSIONS_DIR):
        print("no sessions dir — nothing to resume", file=sys.stderr)
        return

    # Detect IDE once per invocation — either we're running in a machine with
    # Antigravity/VS Code/Cursor alive (IDE scenario) or we're not (headless).
    # Same code, same detection, branches on the result.
    ide = detect_ide()

    restarted: list[str] = []
    skipped: list[str] = []
    failed: list[str] = []
    dry_run_plan: list[str] = []

    for path in glob(os.path.join(SESSIONS_DIR, "*.json")):
        pid_str = os.path.basename(path).replace(".json", "")
        try:
            pid = int(pid_str)
        except ValueError:
            continue

        try:
            with open(path) as f:
                info = json.load(f)
        except Exception:
            skipped.append(f"{pid_str} (unreadable)")
            continue

        cwd = info.get("cwd", "") or ""

        if not is_pid_alive(pid):
            # Stale session file — Claude Code cleans these up on its own usually
            skipped.append(f"{pid} — dead")
            continue

        # Pull session name in priority order:
        # 1. CLAUDE_AGENT_NAME env (canonical, spawn-wrapper-set)
        # 2. name field in session JSON (Claude Code 2.1.121+ writes it)
        # 3. --name flag in ps args (legacy fallback)
        # `--resume`'s value is never used (it's a UUID, not a name).
        name = session_name_from_pid(pid, info)
        if not name:
            # No CLAUDE_AGENT_NAME and no --name flag — can't respawn cleanly.
            # Includes plain `claude` and bare `claude --resume <uuid>` invocations.
            # Session keeps running on the new account; just no marker + resume prompt.
            skipped.append(f"{pid} — no CLAUDE_AGENT_NAME / --name, skip")
            continue

        # Capture TTY + session_id BEFORE killing so we can:
        # - close that Terminal tab later (tty, legacy path only)
        # - respawn with --resume <session_id> (transcript isolation)
        old_tty = tty_for_pid(pid)
        session_id = session_id_from_pid(pid, info)

        # Detect whether the parent shell is running `_claude_with_respawn`
        # (the spawn-wrapper's in-place auto-respawn loop). If so, we just
        # signal the wrapper + SIGTERM and the same terminal re-launches
        # claude. Falls back to legacy AppleScript respawn for sessions
        # launched directly without the wrapper.
        respawn_capable = env_var_from_pid(pid, "CLAUDE_RESPAWN_CAPABLE") == "1"

        # Write pre-swap marker with git status — Claude reads it on wake
        # to reconcile filesystem vs. transcript expectation.
        marker_path = write_swap_marker(name, session_id, cwd)

        # Build per-session resume prompt referencing the marker
        prompt = build_resume_prompt(name, cwd, marker_path)

        if dry_run:
            mode = "in-place" if (respawn_capable and session_id) else "legacy-applescript"
            dry_run_plan.append(
                f"{name} pid={pid} mode={mode} session_id={session_id or 'UNKNOWN'} marker={marker_path}"
            )
            continue

        # If capable: write the in-place signal files BEFORE the kill so the
        # wrapper sees them on its first post-exit check.
        if respawn_capable and session_id:
            write_in_place_signal(name, session_id, prompt)

        # Kill + respawn
        try:
            os.kill(pid, 15)  # SIGTERM
        except OSError as e:
            failed.append(f"{pid} ({name}) kill: {e}")
            continue

        # Wait long enough for the old shell to settle AND for Anthropic's
        # backend to fully recognize the just-swapped account. (For the
        # in-place path the wrapper also sleeps 3s before re-launch — both
        # serve different goals: this gives the kill time to flush; the
        # wrapper's gives the auth state time to propagate before the new
        # claude makes its first API call.)
        time.sleep(POST_SWAP_WAIT_SECS)

        if respawn_capable and session_id:
            # In-place path: poll for the wrapper-respawned claude.
            new_pid, msg = wait_for_new_claude(name, killed_pid=pid, timeout=8.0)
            ok = new_pid > 0
            target = "in-place"
        else:
            # Legacy path: AppleScript opens a new tab and keystrokes the command.
            ok, msg = respawn_session(name, cwd, prompt, old_tty, ide, session_id)
            target = ide if ide else "Terminal.app"

        if ok:
            id_hint = f" id={session_id[:8]}" if session_id else " id=UNKNOWN(--continue fallback)"
            restarted.append(f"{name}@{os.path.basename(cwd)}{id_hint} [{target}]")
        else:
            failed.append(f"{name}: {msg}")

    # Dry-run summary — don't pretend we restarted anything
    if dry_run:
        print(f"resume [DRY-RUN]: would respawn {len(dry_run_plan)} sessions")
        for entry in dry_run_plan:
            print(f"  {entry}")
        if skipped:
            print("  skipped:", "; ".join(skipped[:5]) + ("..." if len(skipped) > 5 else ""))
        return

    # Print summary — watcher captures this in quota-watch.log via its subprocess.run
    print(f"resume: restarted={len(restarted)} skipped={len(skipped)} failed={len(failed)}")
    if restarted:
        print("  restarted:", ", ".join(restarted))
    if failed:
        print("  failed:", "; ".join(failed))
    if skipped:
        print("  skipped:", "; ".join(skipped[:5]) + ("..." if len(skipped) > 5 else ""))


if __name__ == "__main__":
    main()
