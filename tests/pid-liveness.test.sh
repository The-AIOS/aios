#!/usr/bin/env bash
# Liveness checks must not end the process they check (#303). On Windows, os.kill(pid, 0) is
# TerminateProcess, not a probe, so a "is it alive?" check closed every session it looked at.
# One shared check lives in hooks/claude-identity/_fs.py; this test fakes Windows and fails if
# _resume.py or _watch.py would call os.kill there, and lints the tree for any other signal-0
# probe. Usage: bash tests/pid-liveness.test.sh [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1
export AIOS_QUOTA_NOTIFY=0   # never put a desktop banner up from a test (watch-notify-isolation)
python3 - <<'PY'
import os, re, sys, types
ok = fail = 0
def check(name, cond):
    global ok, fail
    if cond: ok += 1; print("  ok   " + name)
    else: fail += 1; print("  FAIL " + name)
print("pid-liveness")

# 1. Lint: os.kill(<pid>, 0) appears only inside the one shared check.
ALLOWED = os.path.join("hooks", "claude-identity", "_fs.py")
probe = re.compile(r"os\.kill\(\s*[^,()]+,\s*0\s*\)")
hits = []
for base in ("hooks", "mcps", "plugins", "skills"):
    for d, _, files in os.walk(base):
        if "/." in d or "node_modules" in d or ".venv" in d: continue
        for f in files:
            if not f.endswith(".py"): continue
            p = os.path.join(d, f)
            for n, line in enumerate(open(p, encoding="utf-8", errors="ignore"), 1):
                code = line.split("#", 1)[0]
                if probe.search(code) and '"""' not in line and p != ALLOWED:
                    hits.append("%s:%d" % (p, n))
check("no signal-0 probe outside %s%s" % (ALLOWED, (" (found: " + ", ".join(hits) + ")") if hits else ""), not hits)

# 2. Behaviour: on a faked Windows, the checks never call os.kill and still answer.
sys.path.insert(0, os.path.join("hooks", "claude-identity"))
calls = []
real_kill, real_name = os.kill, os.name
class K32:
    def OpenProcess(self, access, inherit, pid): return 7 if pid == 4242 else 0
    def GetLastError(self): return 87
    def GetExitCodeProcess(self, h, ref): ref._obj.value = 259; return 1
    def CloseHandle(self, h): return 1
fake = types.ModuleType("ctypes")
fake.windll = types.SimpleNamespace(kernel32=K32())
class ULong:
    def __init__(self): self.value = 0
fake.c_ulong = ULong
fake.byref = lambda o: types.SimpleNamespace(_obj=o)
try:
    import _fs, _resume
    sys.modules["ctypes"] = fake
    os.kill = lambda *a: calls.append(a)
    os.name = "nt"
    alive = _resume.is_pid_alive(4242)
    dead = _resume.is_pid_alive(999)
    alive2 = getattr(_fs, "pid_alive", lambda p: None)(4242)
finally:
    os.kill, os.name = real_kill, real_name
    sys.modules.pop("ctypes", None)
check("_resume.is_pid_alive never calls os.kill on Windows", not calls)
check("a running process reads alive, a missing one dead", alive is True and dead is False and alive2 is True)
watch = open(os.path.join("hooks", "claude-identity", "_watch.py"), encoding="utf-8").read()
check("_watch.py uses the shared check", "pid_alive as _pid_alive" in watch and "def _pid_alive" not in watch)
check("on macOS/Linux the shared check still sees this process", getattr(_fs, "pid_alive", lambda p: None)(os.getpid()) is True)
# 3. On real Windows (the CI lane), asking about a live child must not end it.
if os.name == "nt":
    import subprocess, time
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
    try:
        time.sleep(0.5)
        seen = _fs.pid_alive(child.pid)
        time.sleep(0.5)
        check("real Windows: a live child reads alive", seen is True)
        check("real Windows: asking did not end it", child.poll() is None)
    finally:
        child.kill()
print("%d passed, %d failed" % (ok, fail))
sys.exit(1 if fail else 0)
PY
