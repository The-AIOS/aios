#!/usr/bin/env python3
"""page-fit — measure whether each fixed-size page of a report HTML fits its sheet.

    uv run ~/aios/hooks/page-fit.py [--expect N] <report.html>

Report commands (/weekly-learnings, /learned) lay content into `<div class="page">`
boxes sized to A4 with `min-height: 297mm`. A box that grows past its sheet still
reads fine as HTML — HTML has no page — and only splits across extra sheets when
printed. So "fit exactly N pages" was a judgment about item counts that nothing
measured (#156: two of three pages of a real report overflowed; the PDF ran to six).

This renders the file in headless Chrome/Chromium, reads every `.page` box height,
and compares it with one A4 sheet at 96 dpi (297 mm = 1122.5 px).

Exit codes — a measurement that did not happen is never reported as a fit:
    0  every page fits (and, with --expect, the page count matches)
    1  at least one page overflows, or the count is wrong — each is named, with px
    2  could not measure: no browser, unreadable file, no `.page` boxes, bad output
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

A4_PX = 297 / 25.4 * 96          # 1122.52 px — one sheet's height at CSS 96 dpi
TOLERANCE = 1.0                  # sub-pixel rounding, never content

PROBE = """<script>
window.addEventListener('load', function () {
  var go = function () {
    var h = Array.prototype.map.call(document.querySelectorAll('.page'),
      function (p) { return Math.round(p.getBoundingClientRect().height * 10) / 10; });
    document.title = 'PAGEFIT:' + JSON.stringify(h);
  };
  (document.fonts && document.fonts.ready) ? document.fonts.ready.then(go) : go();
});
</script>"""


def browsers():
    """Candidate Chrome/Chromium binaries, most specific first. Env override wins."""
    env = os.environ.get("AIOS_CHROME")
    if env:
        yield env
    yield "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    yield "/Applications/Chromium.app/Contents/MacOS/Chromium"
    for name in ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "chrome"):
        found = shutil.which(name)
        if found:
            yield found
    for root in (os.environ.get("PROGRAMFILES"), os.environ.get("PROGRAMFILES(X86)"),
                 os.environ.get("LOCALAPPDATA")):
        if root:
            yield os.path.join(root, "Google", "Chrome", "Application", "chrome.exe")


def find_browser():
    return next((b for b in browsers() if b and os.path.isfile(b)), None)


def verdict(heights, expect=None):
    """Pure: heights in px → (exit code, report lines). Kept separate so it is testable
    without a browser."""
    lines, over = [], 0
    for i, h in enumerate(heights, 1):
        excess = h - A4_PX
        if excess > TOLERANCE:
            over += 1
            lines.append("page %d: %.0f px — OVER by %.0f px (trim this page)" % (i, h, excess))
        else:
            lines.append("page %d: %.0f px — fits" % (i, h))
    bad = over > 0
    if expect is not None and len(heights) != expect:
        bad = True
        lines.append("page count: %d — expected %d" % (len(heights), expect))
    lines.append("VERDICT: %s (A4 = %.0f px)" % ("OVERFLOW" if bad else "FITS", A4_PX))
    return (1 if bad else 0), lines


def stream_measurement(cmd, deadline):
    """Run the browser, return the PAGEFIT match from its stdout (or None), and kill
    the whole process tree either way."""
    import threading
    kw = {"start_new_session": True} if os.name != "nt" else \
         {"creationflags": getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)}
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, **kw)
    found = []
    def reader():
        # os.read returns whatever is available. A buffered read(n) blocks until n
        # bytes OR EOF — and a browser that never exits never sends EOF, so a DOM
        # shorter than n would hang the reader on exactly the small, fitting report.
        buf = b""
        fd = proc.stdout.fileno()
        while True:
            chunk = os.read(fd, 65536)
            if not chunk:
                return
            buf += chunk
            m = re.search(r"PAGEFIT:(\[[^<]*\])", buf.decode("utf-8", "replace"))
            if m:
                found.append(m)
                return
    t = threading.Thread(target=reader, daemon=True)
    t.start()
    t.join(deadline)
    try:
        if os.name != "nt":
            os.killpg(proc.pid, 9)
        else:
            proc.kill()
    except (ProcessLookupError, PermissionError, OSError):
        pass
    return found[0] if found else None


def measure(path, browser):
    with open(path, encoding="utf-8") as f:
        html = f.read()
    if not re.search(r'class="[^"]*\bpage\b', html):
        return None, "no .page boxes in %s — nothing to measure" % path
    probed = re.sub(r"</body>", PROBE + "</body>", html, count=1, flags=re.I)
    if probed == html:
        probed = html + PROBE
    tmpdir = tempfile.mkdtemp(prefix="page-fit-")
    probe_path = os.path.join(tmpdir, "probe.html")
    with open(probe_path, "w", encoding="utf-8") as f:
        f.write(probed)
    cmd = [browser, "--headless", "--disable-gpu", "--no-first-run",
           "--user-data-dir=" + os.path.join(tmpdir, "profile"),
           "--window-size=900,2000", "--virtual-time-budget=8000", "--dump-dom",
           "file://" + os.path.abspath(probe_path)]
    # Read the DOM as it streams and stop at the measurement. Do NOT wait for the
    # process to exit: desktop Chrome can print the full DOM and then stay alive
    # (its updater holds the process), so `subprocess.run(timeout=…)` times out on
    # a render that had already succeeded.
    try:
        m = stream_measurement(cmd, deadline=60)
    except OSError as e:
        return None, "browser did not start: %s" % e
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
    if not m:
        return None, "browser ran but reported no measurement (probe never fired)"
    heights = json.loads(m.group(1))
    if not heights:
        return None, "probe found zero .page boxes after render"
    return heights, None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("html")
    ap.add_argument("--expect", type=int, help="the number of pages the report must be")
    a = ap.parse_args(argv)
    if not os.path.isfile(a.html):
        print("page-fit: cannot read %s" % a.html, file=sys.stderr)
        return 2
    browser = find_browser()
    if not browser:
        print("page-fit: no Chrome/Chromium found (set AIOS_CHROME) — NOT measured, "
              "so the page fit is unknown, not confirmed", file=sys.stderr)
        return 2
    heights, err = measure(a.html, browser)
    if err:
        print("page-fit: %s — NOT measured" % err, file=sys.stderr)
        return 2
    code, lines = verdict(heights, a.expect)
    print("\n".join(lines))
    return code


if __name__ == "__main__":
    sys.exit(main())
