#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Vendored sources match the pin they record — file by file
#
# WHY
# Each vendored folder records where it came from in `.upstream-sync`, and until
# 2026-09-23 nothing ever re-read it. skills/superpowers recorded f2cbfbe (v5.1.0)
# while every one of its 46 files matched v5.0.7 — the record was wrong from the
# day it was written, and staleness was measured against a pin the files never
# had. A record nobody reads is not a record.
#
# WHAT IT CHECKS (offline, every CI run — canonical-only, Tier 0)
#   For each folder carrying `.upstream-manifest` (sha256 of every vendored file,
#   written when the folder is vendored or refreshed):
#     · every listed file exists and matches its hash (CRLF-normalised)
#     · no file sits in the folder unlisted (a local edit or addition)
#     · `.upstream-sync` names repo= and hash=
#   A control mutates a copy three ways (edit, add, delete) and must catch each.
#
# MAINTAINER MODES (never in CI — vendoring is the maintainer's call, not a check)
#   --record <dir>     rewrite <dir>/.upstream-manifest after a re-vendor
#   --upstream <dir>   clone the recorded repo at hash= and prove every file
#                      matches it under root= (needs network)
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PYBIN=""
for _c in python3 python "py -3"; do if $_c -c 'import sys' >/dev/null 2>&1; then PYBIN="$_c"; break; fi; done
[ -n "$PYBIN" ] || { echo "SKIP: no working Python" >&2; exit 0; }

$PYBIN - "$@" <<'PY'
import hashlib, os, shutil, subprocess, sys, tempfile

def h(path):
    return hashlib.sha256(open(path, "rb").read().replace(b"\r\n", b"\n")).hexdigest()

def meta(d):
    out = {}
    for line in open(os.path.join(d, ".upstream-sync"), encoding="utf-8"):
        if "=" in line:
            k, v = line.rstrip("\n").split("=", 1); out[k.strip()] = v.strip()
    return out

def files_in(d):
    out = []
    for root, dirs, fs in os.walk(d):
        dirs[:] = [x for x in dirs if x not in ("__pycache__", ".git")]
        for f in fs:
            if f in (".upstream-sync", ".upstream-manifest") or f.endswith(".pyc") or f == ".DS_Store":
                continue
            out.append(os.path.relpath(os.path.join(root, f), d).replace(os.sep, "/"))
    return sorted(out)

def load_manifest(d):
    m = {}
    for line in open(os.path.join(d, ".upstream-manifest"), encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        digest, rel = line.rstrip("\n").split("  ", 1); m[rel] = digest
    return m

def check(d):
    """-> list of problems (empty = matches its record)."""
    probs = []
    md = meta(d)
    for k in ("repo", "hash"):
        if not md.get(k):
            probs.append(f"{d}/.upstream-sync has no {k}=")
    m = load_manifest(d)
    have = set(files_in(d))
    for rel, digest in m.items():
        p = os.path.join(d, rel)
        if not os.path.isfile(p):
            probs.append(f"missing: {d}/{rel}")
        elif h(p) != digest:
            probs.append(f"differs from the pin: {d}/{rel}")
    for rel in sorted(have - set(m)):
        probs.append(f"not in the vendored record: {d}/{rel}")
    return probs

def record(d):
    fs = files_in(d)
    with open(os.path.join(d, ".upstream-manifest"), "w", encoding="utf-8", newline="\n") as out:
        out.write("# sha256 of every vendored file, recorded against the pin in .upstream-sync.\n"
                  "# Regenerate ONLY when re-vendoring: tests/vendored-pins.test.sh --record\n")
        for rel in fs:
            out.write(f"{h(os.path.join(d, rel))}  {rel}\n")
    print(f"recorded {len(fs)} files in {d}/.upstream-manifest")

def upstream(d):
    md = meta(d); tmp = tempfile.mkdtemp()
    subprocess.run(["git", "clone", "-q", md["repo"], tmp], check=True)
    subprocess.run(["git", "-C", tmp, "checkout", "-q", md["hash"]], check=True)
    root = md.get("root", md.get("subdir", ""))
    bad = [rel for rel, dg in load_manifest(d).items()
           if not os.path.isfile(os.path.join(tmp, root, rel)) or h(os.path.join(tmp, root, rel)) != dg]
    shutil.rmtree(tmp, ignore_errors=True)
    n = len(load_manifest(d))
    print(f"{d}: {n - len(bad)}/{n} files match {md['repo']}@{md['hash']}" + ("" if not bad else f" — first mismatch: {bad[0]}"))
    return 0 if not bad else 1

args = sys.argv[1:]
if args[:1] == ["--record"]:
    record(args[1]); sys.exit(0)
if args[:1] == ["--upstream"]:
    sys.exit(upstream(args[1]))

PASS = FAIL = 0
def ok(m):
    global PASS; PASS += 1; print("  ✓ " + m)
def no(m, why=""):
    global FAIL; FAIL += 1; print("  ✗ " + m + ("\n      " + why if why else ""))

dirs = sorted(os.path.dirname(os.path.join(r, f)) for r, _, fs in os.walk(".")
              for f in fs if f == ".upstream-manifest" and "/.git" not in r)
if not dirs:
    no("no vendored folder carries .upstream-manifest", "the guard would pass by measuring nothing")
for d in dirs:
    d = os.path.relpath(d)
    probs = check(d)
    if probs: no(f"{d} does not match its vendored record ({len(probs)})", "; ".join(probs[:3]))
    else: ok(f"{d}: {len(load_manifest(d))} files match the recorded pin")

# control: a copy mutated three ways must fail three ways
if dirs:
    src = os.path.relpath(dirs[0]); tmp = tempfile.mkdtemp(); c = os.path.join(tmp, "v")
    shutil.copytree(src, c)
    rels = sorted(load_manifest(c))
    open(os.path.join(c, rels[0]), "ab").write(b"\nlocal edit\n")
    os.remove(os.path.join(c, rels[-1]))
    open(os.path.join(c, "extra.md"), "w").write("added locally\n")
    got = " ".join(check(c))
    for kind in ("differs from the pin", "missing:", "not in the vendored record"):
        if kind in got: ok(f"control: catches '{kind}'")
        else: no(f"control: blind to '{kind}'", "a guard that cannot see this passes on a drifted folder")
    shutil.rmtree(tmp, ignore_errors=True)

print(f"\n  {PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
PY
