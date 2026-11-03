#!/usr/bin/env python3
"""Offer to replace USER.md's `## Anthropic accounts` section with a pointer.

The account list moved to ~/.aios/accounts.json (#254). The AIOS App from 0.14.0 and
Glass from 0.5.14 read it through `claude-switch --availability`, so from then on the
USER.md section does nothing, and editing it is confusing. Older surfaces still build
their account menus from it, so it may only go once every installed surface is new
enough.

    user-md-accounts-pointer.py check   [--user-md PATH]
    user-md-accounts-pointer.py replace [--user-md PATH] --backup-dir DIR

`check` prints one JSON object: {"offer": bool, "reason": str, "missing": [emails]}.
It never writes. `/aios:update` asks the operator only when `offer` is true.

`replace` runs the same check, refuses unless it passes, copies the old section to
DIR/USER.md-anthropic-accounts.md, then replaces the section's body with the pointer.
Nothing outside that section changes.

What blocks the offer, each with its reason:
  * the section has no numbered accounts (absent, or already the pointer)
  * ~/.aios/accounts.json is missing or invalid
  * an account in USER.md is not in accounts.json (it would be lost)
  * any installed App or Glass older than the versions above, or one whose version
    cannot be read. "Installed" means any of: the surface's file in ~/.aios/surfaces/
    (written by the running surface, with its version), an AIOS app bundle in
    /Applications or ~/Applications, or Glass in an editor's extensions folder, where
    the newest version in each editor counts. A missing surface file alone proves
    nothing: it is absent whenever that surface is closed.
"""

import argparse
import glob
import json
import os
import plistlib
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import _accounts  # noqa: E402

MIN_VERSION = {"app": (0, 14, 0), "glass": (0, 5, 14)}

POINTER = (
    "The account list lives in `~/.aios/accounts.json`, one per machine. Manage it with "
    "`claude-switch --list`, `--order`, `--enable`, `--disable` and `--add`; the AIOS App "
    "and Glass read it through `claude-switch --availability`. Editing this section "
    "changes nothing.\n"
)
BACKUP_NAME = "USER.md-anthropic-accounts.md"


def _home():
    return os.path.expanduser("~")


def _parse_version(text):
    m = re.match(r"\s*v?(\d+)\.(\d+)\.(\d+)", str(text or ""))
    return tuple(int(x) for x in m.groups()) if m else None


def _fmt(v):
    return ".".join(str(x) for x in v)


def installed_versions():
    """{surface: [(where, version-or-None)]} for every install this machine shows."""
    found = {"app": [], "glass": []}
    sdir = os.environ.get("AIOS_SURFACES_DIR") or os.path.join(_home(), ".aios", "surfaces")
    for surface in found:
        path = os.path.join(sdir, f"{surface}.json")
        if os.path.isfile(path):
            try:
                with open(path, encoding="utf-8") as f:
                    v = _parse_version(json.load(f).get("version"))
            except (OSError, ValueError, AttributeError):
                v = None
            found[surface].append((path, v))

    app_roots = os.environ.get("AIOS_APP_DIRS")
    app_roots = app_roots.split(os.pathsep) if app_roots else ["/Applications", os.path.join(_home(), "Applications")]
    for root in app_roots:
        for bundle in sorted(glob.glob(os.path.join(root, "AIOS*.app"))):
            v = None
            try:
                with open(os.path.join(bundle, "Contents", "Info.plist"), "rb") as f:
                    v = _parse_version(plistlib.load(f).get("CFBundleShortVersionString"))
            except (OSError, ValueError, plistlib.InvalidFileException):
                pass
            found["app"].append((bundle, v))

    ext_home = os.environ.get("AIOS_EXTENSIONS_HOME") or _home()
    for ext_dir in sorted(glob.glob(os.path.join(ext_home, ".*", "extensions"))):
        versions = []
        for d in glob.glob(os.path.join(ext_dir, "the-aios.aios-glass-*")):
            versions.append(_parse_version(os.path.basename(d)[len("the-aios.aios-glass-"):]))
        if versions:
            readable = [v for v in versions if v]
            found["glass"].append((ext_dir, max(readable) if readable else None))
    return found


def check(user_md):
    try:
        listed, _ = _accounts.parse_user_md(user_md)
    except _accounts.AccountsError as e:
        return {"offer": False, "reason": str(e), "missing": []}
    if not listed:
        return {"offer": False, "reason": "USER.md has no numbered accounts under ## Anthropic accounts: nothing to replace", "missing": []}

    if not os.path.isfile(_accounts.accounts_file()):
        return {"offer": False, "reason": f"{_accounts.accounts_file()} does not exist yet: run `claude-switch --list` once to create it", "missing": []}
    try:
        data = _accounts._read_file()
    except _accounts.AccountsError as e:
        return {"offer": False, "reason": str(e), "missing": []}
    known = {a["email"].lower() for a in data.get("accounts", [])}
    missing = [a["email"] for a in listed if a["email"].lower() not in known]
    if missing:
        return {"offer": False, "missing": missing,
                "reason": "these accounts are in USER.md but not in accounts.json, so replacing the section would lose them: "
                          + ", ".join(missing) + " (add each with `claude-switch --add <email>`)"}

    for surface, installs in installed_versions().items():
        need = MIN_VERSION[surface]
        for where, v in installs:
            if v is None:
                return {"offer": False, "missing": [], "reason": f"cannot read the {surface} version at {where}: keeping the section"}
            if v < need:
                return {"offer": False, "missing": [],
                        "reason": f"{surface} {_fmt(v)} at {where} still reads the section; it needs {_fmt(need)} or newer"}
    return {"offer": True, "reason": "every installed surface reads accounts.json", "missing": []}


def replace(user_md, backup_dir):
    verdict = check(user_md)
    if not verdict["offer"]:
        return verdict
    with open(user_md, encoding="utf-8") as f:
        lines = f.readlines()
    start = next(i for i, l in enumerate(lines) if l.startswith(_accounts.USER_MD_SECTION))
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    os.makedirs(backup_dir, exist_ok=True)
    with open(os.path.join(backup_dir, BACKUP_NAME), "w", encoding="utf-8") as f:
        f.writelines(lines[start:end])
    new = lines[:start + 1] + ["\n", POINTER, "\n"] + lines[end:]
    tmp = user_md + ".aios-tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.writelines(new)
    os.replace(tmp, user_md)
    return {"offer": True, "reason": "replaced; the old section is in " + os.path.join(backup_dir, BACKUP_NAME), "missing": []}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("action", choices=["check", "replace"])
    ap.add_argument("--user-md", default=_accounts._user_md())
    ap.add_argument("--backup-dir")
    a = ap.parse_args()
    if a.action == "replace" and not a.backup_dir:
        ap.error("replace needs --backup-dir")
    out = check(a.user_md) if a.action == "check" else replace(a.user_md, a.backup_dir)
    print(json.dumps(out, ensure_ascii=False))
    return 0 if (a.action == "check" or out["offer"]) else 1


if __name__ == "__main__":
    sys.exit(main())
