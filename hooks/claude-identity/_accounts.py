#!/usr/bin/env python3
"""
_accounts.py — the one owner of the account list, and of a credential's expiry.

The list used to be a numbered section of USER.md, read by three separate parsers
(claude-identity.sh, _watch.py, context-monitor.py). An operator-written document
was therefore a runtime input: a reworded line could drop an account from rotation
with no error, and there was nowhere to record that an account is kept but not
rotated. It now lives in a data file, machine-local and never committed:

    ~/.aios/accounts.json        override the path with AIOS_ACCOUNTS_FILE

    {"version": 1,
     "accounts": [{"email": "a@example.com", "alias": "work", "plan": "max",
                   "rotation": true, "reason": ""}],
     "history": [{"at": "2026-01-31", "note": "free text, kept for the operator"}]}

Position in `accounts` is rotation preference. Only `email` is required. A file
that fails validation stops the tool with the reason: a guessed list would rotate
to the wrong account, and that fails silently, weeks later.

Migration: the first use on a machine with no data file imports the USER.md list,
in order, and keeps that section's whole text in `history`. USER.md is never
written. Once the file exists USER.md is not read for accounts.

USER_MD_PATH, when set and AIOS_ACCOUNTS_FILE is not, keeps the old behaviour: that
file is read as the list, nothing is imported and nothing can be changed. It is how
an operator with USER.md elsewhere has always pointed at it, and how a test fixture
stays away from a real list.

Credentials: this module reads `refreshTokenExpiresAt` and nothing else, and never
prints or logs a credential. A live credential arrives on stdin, never in argv.

CLI (driven by claude-identity.sh):
    rotation                       emails in rotation, in order
    table                          email, alias, rotation, plan, reason (unit-separated)
    resolve NAME                   email for an alias or email
    next CURRENT                   the account a manual rotation lands on
    expiry --email E | --stdin     "expired DATE" | "ok DATE" | "unknown"
    order a,b,c --current C        reorder, showing where you would fall
    enable NAME --current C
    disable NAME [--reason R] --current C
    add EMAIL [--alias A] [--plan P] [--disabled] [--reason R] --current C
"""
import contextlib
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _fs import write_json_atomic  # noqa: E402

# Text from the data file carries accents and dashes. On a Windows console stdout
# defaults to cp1252, so print() would raise on the first one (see _watch.py).
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        try:
            _stream.reconfigure(encoding="utf-8", errors="replace")
        except (ValueError, OSError):
            pass

SCHEMA_VERSION = 1
ACCOUNT_KEYS = {"email", "alias", "plan", "rotation", "reason"}
HISTORY_KEYS = {"at", "note"}
USER_MD_SECTION = "## Anthropic accounts"


class AccountsError(Exception):
    """The account list cannot be trusted, or a change to it was refused."""


# ---- paths ------------------------------------------------------------------

def accounts_file() -> str:
    return os.environ.get("AIOS_ACCOUNTS_FILE") or os.path.join(os.path.expanduser("~"), ".aios", "accounts.json")


def log_file() -> str:
    return os.path.splitext(accounts_file())[0] + "-log.jsonl"


def identities_dir() -> str:
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    return os.path.join(cfg, "identities")


def _legacy_user_md() -> str:
    """The USER.md to read as the list, when the environment asks for the old mode."""
    if os.environ.get("AIOS_ACCOUNTS_FILE"):
        return ""
    return os.environ.get("USER_MD_PATH") or ""


def _user_md() -> str:
    # Self-located: this file is at hooks/claude-identity/, so the repo root is two
    # parents up, whether or not the operator has a ~/aios symlink.
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
    return os.path.join(root, "USER.md")


# ---- validation -------------------------------------------------------------

def validate(data, source: str) -> dict:
    def bad(why):
        raise AccountsError(f"{source} is invalid: {why}. Fix the file; nothing was rotated or changed.")

    if not isinstance(data, dict):
        bad("the top level must be an object")
    unknown = set(data) - {"version", "accounts", "history"}
    if unknown:
        bad(f"unknown key(s) {sorted(unknown)}")
    if data.get("version") != SCHEMA_VERSION:
        bad(f"version must be {SCHEMA_VERSION}, found {data.get('version')!r}")
    accounts = data.get("accounts")
    if not isinstance(accounts, list):
        bad("`accounts` must be a list")
    seen = set()
    for i, a in enumerate(accounts, 1):
        where = f"account {i}"
        if not isinstance(a, dict):
            bad(f"{where} must be an object")
        # An unknown key is almost always a typo, and a mistyped `rotation` would
        # otherwise leave the account in rotation while the file says it is out.
        unknown = set(a) - ACCOUNT_KEYS
        if unknown:
            bad(f"{where} has unknown key(s) {sorted(unknown)}")
        email = a.get("email")
        if not isinstance(email, str) or not re.fullmatch(r"[^@\s]+@[^@\s]+", email):
            bad(f"{where} needs an `email`, found {email!r}")
        if not isinstance(a.get("rotation", True), bool):
            bad(f"{email}: `rotation` must be true or false")
        for key in ("alias", "plan", "reason"):
            if not isinstance(a.get(key, ""), str):
                bad(f"{email}: `{key}` must be text")
        alias = a.get("alias", "")
        if alias.startswith("-") or re.search(r"[\x1f\t\r\n,]", alias):
            bad(f"{email}: alias {alias!r} cannot start with a dash, or hold a comma or a line break")
        for name in filter(None, (email.lower(), alias.lower())):
            if name in seen:
                bad(f"{name!r} appears twice")
            seen.add(name)
    history = data.get("history", [])
    if not isinstance(history, list):
        bad("`history` must be a list")
    for h in history:
        if not isinstance(h, dict) or set(h) - HISTORY_KEYS or not isinstance(h.get("note"), str):
            bad("each `history` entry must be an object with a text `note` and optionally `at`")
    return data


# ---- USER.md (import and legacy mode) ---------------------------------------

def parse_user_md(path: str) -> tuple:
    """(accounts, the section's text). A missing file is an empty list."""
    accounts, lines, in_sec = [], [], False
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if line.startswith(USER_MD_SECTION):
                    in_sec = True
                elif in_sec and line.startswith("## "):
                    break
                if not in_sec:
                    continue
                lines.append(line)
                m = re.match(r"\s*\d+\.\s*`([^`]+)`(.*)$", line)
                if m:
                    entry = {"email": m.group(1), "rotation": True}
                    a = re.search(r"alias\s+\*\*([^*]+)\*\*", m.group(2))
                    if a:
                        entry["alias"] = a.group(1).strip()
                    accounts.append(entry)
    except FileNotFoundError:
        return [], ""
    except (OSError, UnicodeDecodeError) as e:
        raise AccountsError(f"could not read {path}: {type(e).__name__}: {e}")
    return accounts, "".join(lines)


# ---- reading and writing ----------------------------------------------------

@contextlib.contextmanager
def _lock():
    """One writer at a time. The watcher, every statusLine and the operator's shell
    can all reach the first-use import at once, and a change is read-modify-write."""
    path = accounts_file() + ".lock"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a+") as f:
        try:
            import fcntl
        except ImportError:
            import msvcrt  # native Windows Python: LK_LOCK retries for ~10s, then raises
            f.seek(0)
            msvcrt.locking(f.fileno(), msvcrt.LK_LOCK, 1)
            try:
                yield
            finally:
                f.seek(0)
                msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)
            return
        fcntl.flock(f, fcntl.LOCK_EX)
        yield  # released when the file closes


def _read_file() -> dict:
    path = accounts_file()
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (ValueError, UnicodeDecodeError) as e:
        raise AccountsError(f"{path} is not valid JSON ({e}). Fix the file; nothing was rotated or changed.")
    except OSError as e:
        raise AccountsError(f"could not read {path}: {type(e).__name__}: {e}")
    return validate(data, path)


def _write_file(data: dict) -> None:
    write_json_atomic(accounts_file(), data, ensure_ascii=False)


def _log(row: dict) -> None:
    row = {"ts": int(time.time()), **row}
    with open(log_file(), "a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def _import_user_md() -> dict:
    """Create the data file from USER.md, if USER.md has a list. Returns the data."""
    with _lock():
        if os.path.exists(accounts_file()):  # another process won the race
            return _read_file()
        path = _user_md()
        accounts, text = parse_user_md(path)
        data = {"version": SCHEMA_VERSION, "accounts": accounts, "history": []}
        if not accounts:
            return data  # nothing to migrate: a new install, no file yet
        data["history"].append({
            "at": time.strftime("%Y-%m-%d"),
            "note": "Imported from USER.md. The section's text at that moment:\n\n" + text.strip(),
        })
        validate(data, f"the list in {path}")
        _write_file(data)
        _log({"action": "import", "from": path, "order": [a["email"] for a in accounts]})
        return data


def load() -> dict:
    legacy = _legacy_user_md()
    if legacy:
        accounts, _ = parse_user_md(legacy)
        return validate({"version": SCHEMA_VERSION, "accounts": accounts}, f"the list in {legacy}")
    if os.path.exists(accounts_file()):
        return _read_file()
    return _import_user_md()


def missing_list_problem() -> str:
    """Why an empty list is a fault here, or "". Zero accounts is how a one-account
    install legitimately looks, and it must stay quiet. On a machine that has had a
    rotation (a change was logged, or two identities are captured), it means the list
    was lost, and rotation is off with nothing to show for it until the day of the cap."""
    if _legacy_user_md() or load()["accounts"]:
        return ""
    captured = 0
    try:
        for name in os.listdir(identities_dir()):
            if os.path.isfile(os.path.join(identities_dir(), name, "keychain.json")):
                captured += 1
    except OSError:
        pass
    if not os.path.exists(log_file()) and captured < 2:
        return ""
    return (f"no account list: {accounts_file()} is missing or empty and USER.md has none to import, "
            "so rotation is off. Add them back with: claude-switch --add <email>")


def rotation() -> list:
    return [a["email"] for a in load()["accounts"] if a.get("rotation", True)]


def aliases() -> dict:
    """{email: alias} for the statusline, which must render even with a broken file."""
    try:
        return {a["email"]: a["alias"] for a in load()["accounts"] if a.get("alias")}
    except Exception:
        return {}


def resolve(name: str, data: dict = None) -> str:
    """The email for an alias or email; an unknown email passes through, because a
    captured account does not have to be listed to be switched to by hand."""
    for a in (data or load())["accounts"]:
        if name.lower() in (a["email"].lower(), a.get("alias", "").lower()):
            return a["email"]
    if "@" in name:
        return name
    raise AccountsError(f"no account or alias named {name!r}. See: claude-switch --list")


# ---- expiry -----------------------------------------------------------------

def blob_refresh_expiry(text: str):
    """refreshTokenExpiresAt in seconds, or None when the blob does not state one."""
    try:
        oauth = json.loads(text).get("claudeAiOauth", {})
        return float(oauth["refreshTokenExpiresAt"]) / 1000
    except (ValueError, TypeError, KeyError, AttributeError):
        return None


def saved_refresh_expiry(email: str):
    try:
        with open(os.path.join(identities_dir(), email, "keychain.json"), encoding="utf-8") as f:
            return blob_refresh_expiry(f.read())
    except (OSError, UnicodeDecodeError):
        return None


def _day(ts: float) -> str:
    return time.strftime("%Y-%m-%d", time.localtime(ts))


def expiry_verdict(ts) -> str:
    if ts is None:
        return "unknown"
    return ("expired " if ts < time.time() else "ok ") + _day(ts)


def saved_problem(email: str) -> str:
    """Why switching to this saved identity would end at a login screen, or "".

    An account that states no expiry is not a problem: the field is absent from
    older credentials, and absence of evidence must not take one out of rotation."""
    ts = saved_refresh_expiry(email)
    if ts is not None and ts < time.time():
        return f"refresh token expired {_day(ts)}, needs /login"
    return ""


def next_for_manual_rotation(current: str) -> tuple:
    """(target, skipped). One position forward and wrapping, past expired accounts."""
    accts = rotation()
    start = accts.index(current) + 1 if current in accts else 0
    skipped = []
    for email in accts[start:] + accts[:start]:
        if email == current:
            continue
        why = saved_problem(email)
        if not why:
            return email, skipped
        skipped.append(f"{email} ({why})")
    return "", skipped


# ---- changes ----------------------------------------------------------------

def _fall_target(current: str) -> str:
    """Where the watcher would send this seat right now, from its own decision."""
    import _watch
    t5, t7 = _watch.thresholds()
    target, why = _watch.pick_target(current, t5, t7)
    return target or f"nowhere ({why})"


def _refuse_in_legacy() -> None:
    if _legacy_user_md():
        raise AccountsError(
            "USER_MD_PATH is set, so the list is read from that file and cannot be changed "
            f"here. Unset it to move to {accounts_file()}."
        )


def _apply(action: str, current: str, change, **log_fields) -> None:
    """Run `change` on the list under the lock, showing and logging where the seat
    falls before and after. Reordering moves a fallback without a single error, and
    the symptom is a surprising rotation much later, so the effect is always shown."""
    _refuse_in_legacy()
    load()  # first use: import before taking the lock this needs
    before_fall = _fall_target(current)
    with _lock():
        data = _read_file() if os.path.exists(accounts_file()) else {
            "version": SCHEMA_VERSION, "accounts": [], "history": []}
        before = [a["email"] for a in data["accounts"] if a.get("rotation", True)]
        change(data)
        validate(data, "the requested change")
        _write_file(data)
        after = [a["email"] for a in data["accounts"] if a.get("rotation", True)]
    after_fall = _fall_target(current)
    _log({"action": action, "from": current, "before": before, "after": after,
          "fall_before": before_fall, "fall_after": after_fall, **log_fields})
    print(f"Rotation: {' > '.join(after) or '(empty)'}")
    print(f"From {current or 'no active account'}, you would fall to:")
    print(f"  before: {before_fall}")
    print(f"  after:  {after_fall}")
    print(f"Logged to {log_file()}")


def _find(data: dict, name: str) -> dict:
    email = resolve(name, data)
    for a in data["accounts"]:
        if a["email"] == email:
            return a
    raise AccountsError(f"{name} is not in {accounts_file()}. Add it with: claude-switch --add {name}")


def cmd_order(names: list, current: str) -> None:
    def change(data):
        wanted = [resolve(n, data) for n in names]
        enabled = [a["email"] for a in data["accounts"] if a.get("rotation", True)]
        if len(set(wanted)) != len(wanted) or set(wanted) != set(enabled):
            raise AccountsError(
                "--order must name every account in rotation exactly once.\n"
                f"  in rotation: {', '.join(enabled)}\n  given:       {', '.join(wanted)}\n"
                "Use --enable or --disable to change who is in it."
            )
        by_email = {a["email"]: a for a in data["accounts"]}
        rest = [a for a in data["accounts"] if not a.get("rotation", True)]
        data["accounts"] = [by_email[e] for e in wanted] + rest
    _apply("order", current, change)


def cmd_enable(name: str, current: str) -> None:
    def change(data):
        a = _find(data, name)
        a["rotation"] = True
        a.pop("reason", None)
    _apply("enable", current, change, account=name)
    # Allowed, because the order of `/login` and --enable is the operator's. Said
    # out loud, because the watcher will pass over this account until it is renewed.
    why = saved_problem(resolve(name))
    if why:
        print(f"warning: {name}: {why}. The watcher skips it until then.", file=sys.stderr)


def cmd_disable(name: str, reason: str, current: str) -> None:
    def change(data):
        a = _find(data, name)
        a["rotation"] = False
        if reason:
            a["reason"] = reason
    _apply("disable", current, change, account=name, reason=reason)


def cmd_add(email: str, alias: str, plan: str, disabled: bool, reason: str, current: str) -> None:
    def change(data):
        entry = {"email": email, "rotation": not disabled}
        if alias:
            entry["alias"] = alias
        if plan:
            entry["plan"] = plan
        if reason:
            entry["reason"] = reason
        data["accounts"].append(entry)
    _apply("add", current, change, account=email)


# ---- CLI --------------------------------------------------------------------

def _cli(argv: list) -> None:
    import argparse  # here, not at the top: the statusLine path never needs it
    p = argparse.ArgumentParser(prog="_accounts.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("rotation")
    sub.add_parser("table")
    sub.add_parser("resolve").add_argument("name")
    sub.add_parser("next").add_argument("current", nargs="?", default="")
    x = sub.add_parser("expiry")
    x.add_argument("--email")
    x.add_argument("--stdin", action="store_true")
    o = sub.add_parser("order")
    o.add_argument("names")
    o.add_argument("--current", default="")
    e = sub.add_parser("enable")
    e.add_argument("name")
    e.add_argument("--current", default="")
    d = sub.add_parser("disable")
    d.add_argument("name")
    d.add_argument("--reason", default="")
    d.add_argument("--current", default="")
    a = sub.add_parser("add")
    a.add_argument("email")
    a.add_argument("--alias", default="")
    a.add_argument("--plan", default="")
    a.add_argument("--disabled", action="store_true")
    a.add_argument("--reason", default="")
    a.add_argument("--current", default="")
    args = p.parse_args(argv)

    if args.cmd == "rotation":
        for email in rotation():
            print(email)
    elif args.cmd == "table":
        data = load()
        for a in data["accounts"]:
            # \x1f, not a tab: `read` collapses runs of a whitespace IFS, so an account
            # with no alias would shift every field after it.
            print("\x1f".join([a["email"], a.get("alias", ""), "1" if a.get("rotation", True) else "0",
                               a.get("plan", ""), " ".join(a.get("reason", "").split())]))
    elif args.cmd == "resolve":
        print(resolve(args.name))
    elif args.cmd == "next":
        target, skipped = next_for_manual_rotation(args.current)
        for s in skipped:
            print(f"skipping {s}", file=sys.stderr)
        print(target)
    elif args.cmd == "expiry":
        ts = blob_refresh_expiry(sys.stdin.read()) if args.stdin else saved_refresh_expiry(args.email or "")
        print(expiry_verdict(ts))
    elif args.cmd == "order":
        cmd_order([n.strip() for n in args.names.split(",") if n.strip()], args.current)
    elif args.cmd == "enable":
        cmd_enable(args.name, args.current)
    elif args.cmd == "disable":
        cmd_disable(args.name, args.reason, args.current)
    elif args.cmd == "add":
        cmd_add(args.email, args.alias, args.plan, args.disabled, args.reason, args.current)


if __name__ == "__main__":
    try:
        _cli(sys.argv[1:])
    except AccountsError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(2)
