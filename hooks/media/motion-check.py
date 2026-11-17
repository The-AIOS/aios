#!/usr/bin/env python3
"""motion-check.py — measure a motion piece instead of watching it.

WHY. In motion work every real quality fix comes from an instrument, not a smarter prompt: a pixel
count, a per-frame audit against the brief's numbers, a frame where something pops, a decoded
soundtrack whose hits land milliseconds late. The model cannot hear and sees only the frames it is
shown, so a check left to "watching it" is a check that does not happen. These are those
instruments. Rendering is hooks/media/motion-render.py; the loop that uses both is skills/aios/motion-lab.

USAGE
  motion-check.py contract    PAGE.html                    static lint against the render contract
  motion-check.py determinism PAGE.html --frames 0,84 [--fps 60] [--size WxH]
                                                           render each frame twice: identical?
  motion-check.py seam        DIR [--factor 3]             last frame -> first, vs the median step
  motion-check.py pops        DIR [--factor 4]             frames whose change jumps past neighbours
  motion-check.py framing     DIR [--margin 0.03] [--bleed] the subject inside the safe margins, on a
                                                           ground that stays ground; hero height per frame
  motion-check.py assert      PAGE.html CHECKS.json [--fps 60] [--size WxH]
                                                           [{"frame":84,"expr":"p.scale","expect":1.08,"tol":0.01}]
                                                           evaluated against window.__probe(t) as `p`;
                                                           `at(F)` is the probe at another frame, e.g.
                                                           {"frame":479,"expr":"p.x - at(0).x","expect":0,"tol":0.001}
  motion-check.py audio       FILM.mp4|SOUND.wav [--events EVENTS.json --fps 60] [--silent]
                                                           --silent: the brief has no sound, so N/A
                                                           (and FAIL if a sound track is present)
                                                           loudness, true peak, band energy, hit timing

Every subcommand prints one line per check (`PASS` / `FAIL` / `WARN`, then the numbers) and a final
`RESULT` line. Exit 0 all pass · 1 something failed · 2 a dependency or input is missing. A check
that could not run says so and exits 2: it never reports a pass it did not measure.

The house targets (references/numbers.md): integrated loudness -14 LUFS (+-1), true peak <= -1 dBTP,
each hit 1 frame after its picture (+-1 frame), and most energy above 60 Hz (phone speakers play
almost nothing below it).
"""
import argparse
import glob
import hashlib
import json
import os
import re
import shutil
import statistics
import subprocess
import sys

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
FAILS = []


def line(status, name, detail=""):
    print("%-4s %s%s" % (status, name, ("  " + detail) if detail else ""))
    if status == "FAIL":
        FAILS.append(name)


def finish():
    print("RESULT %s" % ("PASS" if not FAILS else "FAIL (%d): %s" % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)


def die(msg, code=2):
    print("motion-check: " + msg, file=sys.stderr)
    sys.exit(code)


# ── contract ─────────────────────────────────────────────────────────────────────────────────────
PINNED = re.compile(r"@\d+\.\d+(\.\d+)?|/\d+\.\d+\.\d+/|[?&]v(er(sion)?)?=\d")
ALLOWED_HOSTS = ("cdn.jsdelivr.net", "unpkg.com", "cdnjs.cloudflare.com", "esm.sh",
                 "fonts.googleapis.com", "fonts.gstatic.com")


def cmd_contract(a):
    try:
        with open(a.page, encoding="utf-8") as f:
            src = f.read()
    except OSError as e:
        die("cannot read %s: %s" % (a.page, e))
    lines = src.splitlines()

    def hits(rx):
        return [(i + 1, l.strip()[:90]) for i, l in enumerate(lines)
                if re.search(rx, l) and not l.strip().startswith("//")]

    has_script = bool(re.search(r"<script\b", src, re.I))
    rules = [
        ("no wall clock", r"\bDate\.now\s*\(|\bperformance\.now\s*\(|new\s+Date\s*\(\s*\)",
         "time must come from t, never the clock"),
        ("no timers", r"\bset(Timeout|Interval)\s*\(", "a timer runs on the machine's speed, not on t"),
        ("no animation-frame loop", r"\brequestAnimationFrame\s*\(", "motion driven by rAF cannot be frozen at t"),
        ("no unseeded random", r"\bMath\.random\s*\(", "use a seeded PRNG (e.g. mulberry32(seed))"),
        ("no runtime network", r"\bfetch\s*\(|XMLHttpRequest|new\s+WebSocket", "everything the piece needs is in the file"),
    ]
    for name, rx, why in rules:
        h = hits(rx)
        if h:
            line("FAIL", name, "%s -- line %d: %s" % (why, h[0][0], h[0][1]) + (" (+%d more)" % (len(h) - 1) if len(h) > 1 else ""))
        else:
            line("PASS", name)

    # external resources: only pinned libraries from known CDNs, and fonts
    urls = re.findall(r"""(?:src|href)\s*=\s*["'](https?://[^"']+)["']|from\s+["'](https?://[^"']+)["']|import\s*\(\s*["'](https?://[^"']+)["']""", src)
    urls = [u for t in urls for u in t if u]
    # Import maps hide their URLs from the attribute scan (`import * as THREE from "three"`).
    for block in re.findall(r'<script[^>]*type=["\']importmap["\'][^>]*>(.*?)</script>', src, re.S | re.I):
        try:
            imports = json.loads(block).get("imports", {})
        except ValueError:
            line("FAIL", "import map parses", "the importmap block is not valid JSON")
            continue
        urls += [u for u in imports.values() if isinstance(u, str) and u.startswith("http")]
    bad_host = [u for u in urls if not any(h in u for h in ALLOWED_HOSTS)]
    unpinned = [u for u in urls if "fonts.g" not in u and not PINNED.search(u)]
    line("FAIL" if bad_host else "PASS", "only known hosts", ("not allowed: " + bad_host[0]) if bad_host else "%d external url(s)" % len(urls))
    line("FAIL" if unpinned else "PASS", "libraries pinned to a version", ("unpinned: " + unpinned[0]) if unpinned else "")

    if has_script and "renderAt" not in src:
        line("FAIL", "exposes renderAt(t)", "the page has script but no window.renderAt -- JS-driven motion cannot be frozen")
    else:
        line("PASS", "exposes renderAt(t)", "" if has_script else "no script: CSS animations are frozen via getAnimations()")
    finish()


# ── frame diffs ──────────────────────────────────────────────────────────────────────────────────
def need_pil():
    try:
        from PIL import Image, ImageChops  # noqa: F401
    except ImportError:
        die("needs Pillow (pip install pillow)")


def frames(d):
    fs = sorted(glob.glob(os.path.join(d, "frame_*.png")))
    if len(fs) < 3:
        die("need at least 3 frame_*.png in %s (render with motion-render.py frames --all)" % d)
    return fs


def diff(a, b):
    """Mean absolute pixel difference, 0..255, on a downscaled greyscale copy (fast, stable)."""
    from PIL import Image, ImageChops, ImageStat
    A = Image.open(a).convert("L").resize((256, 256))
    B = Image.open(b).convert("L").resize((256, 256))
    return ImageStat.Stat(ImageChops.difference(A, B)).mean[0]


def cmd_seam(a):
    need_pil()
    fs = frames(a.dir)
    steps = [diff(fs[i - 1], fs[i]) for i in range(1, len(fs))]
    med = statistics.median(steps)
    seam = diff(fs[-1], fs[0])
    floor = 0.5
    limit = max(med * a.factor, floor)
    detail = "last->first %.3f vs median step %.3f (limit %.3f)" % (seam, med, limit)
    line("FAIL" if seam > limit else "PASS", "seam", detail)
    finish()


def cmd_pops(a):
    need_pil()
    fs = frames(a.dir)
    steps = [diff(fs[i - 1], fs[i]) for i in range(1, len(fs))]
    floor = 0.5
    flagged = []
    for i, s in enumerate(steps):
        # A pop is a one-frame SPIKE: out of line with the steps on BOTH sides. Comparing with all
        # neighbours at once flagged every intentional move out of a still hold (measured on a
        # logo sting: an 8-frame pulse after 2 s of rest read as 4 "pops"), because a move's first
        # step follows stillness. A real pop also stands out against what comes after it.
        prev, nxt = steps[max(0, i - 3):i], steps[i + 1:i + 4]
        sides = [statistics.median(x) for x in (prev, nxt) if x]
        ref = max(sides) if sides else 0.0
        if s > max(ref * a.factor, floor):
            flagged.append((os.path.basename(fs[i + 1])[6:11].lstrip("0") or "0", s, ref))
    if flagged:
        f0 = flagged[0]
        line("FAIL", "pops", "%d frame(s); first at frame %s (change %.3f vs neighbours %.3f)" % (len(flagged), f0[0], f0[1], f0[2]))
    else:
        line("PASS", "pops", "%d steps, median %.3f" % (len(steps), statistics.median(steps)))
    finish()


# ── determinism + assert (render through motion-render's stage) ─────────────────────────────────
def stage(page, size):
    import importlib.util
    spec = importlib.util.spec_from_file_location("motion_render", os.path.join(HERE, "motion-render.py"))
    mr = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mr)
    return mr, mr.Stage(page, mr.parse_size(size))


def cmd_determinism(a):
    import tempfile
    idx = [int(x) for x in a.frames.split(",") if x.strip()]
    tmp = tempfile.mkdtemp(prefix="motion-det-")
    try:
        digests = {}
        for run in (0, 1):
            mr, st = stage(a.page, a.size)  # a fresh page each run: state must not leak between frames
            try:
                fps = a.fps or st.meta.get("fps") or 60
                for i in (idx if run == 0 else list(reversed(idx))):
                    p = os.path.join(tmp, "r%d_%d.png" % (run, i))
                    st.shot(i / float(fps), p)
                    from PIL import Image
                    digests.setdefault(i, []).append(hashlib.sha256(Image.open(p).convert("RGB").tobytes()).hexdigest())
            finally:
                st.close()
        for i in idx:
            same = digests[i][0] == digests[i][1]
            line("PASS" if same else "FAIL", "frame %d renders identically twice" % i,
                 "" if same else "rendered in a different order, the pixels differ: state, a clock or randomness leaks")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    finish()


def cmd_assert(a):
    try:
        with open(a.checks, encoding="utf-8") as f:
            checks = json.load(f)
    except (OSError, ValueError) as e:
        die("cannot read checks %s: %s" % (a.checks, e))
    mr, st = stage(a.page, a.size)
    try:
        fps = a.fps or st.meta.get("fps") or 60
        if not st.meta.get("hasProbe"):
            die("the page has no window.__probe(t); assertions are evaluated against it")
        for c in checks:
            fr, expr, expect = c["frame"], c["expr"], c["expect"]
            tol = float(c.get("tol", 0))
            t = fr / float(fps)
            st.page.evaluate(mr.FREEZE_JS, t)
            got = st.page.evaluate("([t, e, fps]) => { const p = window.__probe(t); const at = (f) => window.__probe(f / fps);"
                                   " return Function('p', 'at', 'return (' + e + ')')(p, at); }", [t, expr, fps])
            if isinstance(expect, (int, float)) and isinstance(got, (int, float)):
                ok = abs(got - expect) <= tol
            else:
                ok = got == expect
            line("PASS" if ok else "FAIL", "f%d %s" % (fr, c.get("name") or expr),
                 "got %r, expect %r%s" % (got, expect, (" +-%g" % tol) if tol else ""))
    finally:
        st.close()
    finish()


# ── audio ────────────────────────────────────────────────────────────────────────────────────────
def ffmpeg_stderr(args):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats"] + args, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return r.returncode, r.stderr


def band_power(path, af):
    rc, err = ffmpeg_stderr(["-i", path, "-af", af + ",astats=metadata=0:reset=0", "-f", "null", "-"])
    m = re.findall(r"RMS level dB:\s*(-?[\d.]+|-inf)", err)
    if rc != 0 or not m:
        return None
    v = m[-1]
    return 0.0 if v == "-inf" else 10 ** (float(v) / 10.0)


def onsets(path, rate=48000, hop_ms=5):
    rc = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(rate), "-f", "s16le", "-"],
                        capture_output=True)
    if rc.returncode != 0:
        return None
    import array
    pcm = array.array("h"); pcm.frombytes(rc.stdout)
    hop = int(rate * hop_ms / 1000)
    env = []
    for i in range(0, len(pcm) - hop, hop):
        seg = pcm[i:i + hop]
        env.append(sum(abs(x) for x in seg) / hop)
    if not env:
        return []
    peak = max(env) or 1
    thr = max(peak * 0.25, statistics.median(env) * 4)
    out, armed = [], True
    for i, e in enumerate(env):
        if armed and e >= thr:
            out.append(i * hop_ms / 1000.0)
            armed = False
        elif e < thr * 0.5:
            armed = True
    return out


def cmd_audio(a):
    if not shutil.which("ffmpeg"):
        die("needs ffmpeg on PATH")
    if not os.path.isfile(a.media):
        die("no such file: %s" % a.media)
    rc, err = ffmpeg_stderr(["-i", a.media, "-af", "ebur128=peak=true", "-f", "null", "-"])
    lufs = re.findall(r"\bI:\s*(-?[\d.]+)\s*LUFS", err)
    peak = re.findall(r"Peak:\s*(-?[\d.]+|-inf)\s*dBFS", err)
    if a.silent:
        # A silent brief: the check does not apply, and saying so is a verdict, not a failure to run.
        if bool(lufs) and rc == 0:
            line("FAIL", "silent by brief", "a sound track is present (%.1f LUFS) but the brief is silent" % float(lufs[-1]))
            return finish()
        print("N/A  audio  silent by brief: no sound track, as the brief says")
        print("RESULT N/A")
        sys.exit(0)
    if rc != 0 or not lufs:
        die("could not measure loudness (no audio stream?); if the brief is silent, pass --silent")
    L = float(lufs[-1])
    line("PASS" if abs(L - a.lufs) <= 1.0 else "FAIL", "integrated loudness", "%.1f LUFS (target %.0f +-1)" % (L, a.lufs))
    if peak:
        P = -999.0 if peak[-1] == "-inf" else float(peak[-1])
        line("PASS" if P <= -1.0 else "FAIL", "true peak", "%.1f dBTP (limit -1.0)" % P)
    total = band_power(a.media, "anull")
    low = band_power(a.media, "lowpass=f=60")
    mid = band_power(a.media, "highpass=f=200,lowpass=f=6000")
    if total:
        ls, ms = (low or 0) / total, (mid or 0) / total
        line("WARN" if ls > 0.5 else "PASS", "energy under 60 Hz", "%.0f%% (phone speakers play almost none of it)" % (ls * 100))
        line("PASS", "energy 200 Hz - 6 kHz", "%.0f%%" % (ms * 100))
    if a.events:
        try:
            with open(a.events, encoding="utf-8") as f:
                ev = json.load(f)
        except (OSError, ValueError) as e:
            die("cannot read events %s: %s" % (a.events, e))
        hits = onsets(a.media)
        if hits is None:
            die("could not decode audio for onset detection")
        frame_ms = 1000.0 / a.fps
        for e in ev:
            fr = e["frame"] if isinstance(e, dict) else int(e)
            want = (fr + 1) / a.fps  # a hit lands one frame after its picture
            near = min(hits, key=lambda h: abs(h - want)) if hits else None
            if near is None:
                line("FAIL", "hit for frame %d" % fr, "no onset found")
                continue
            off = (near - want) * 1000
            line("PASS" if abs(off) <= frame_ms else "FAIL", "hit for frame %d" % fr,
                 "onset at %.3f s, %+.0f ms from frame %d+1 (tolerance %.0f ms)" % (near, off, fr, frame_ms))
    finish()


def cmd_framing(a):
    """The two faults a contact sheet shows and an eye forgives: a subject cut by the frame edge, and
    a ground that is not ground (a grey floor plane, a lit sweep) so the whole frame turns to mid-tone
    mud and nothing reads as the hero. Measured, not judged: the ground is the colour of the four
    corners; the subject is every pixel that differs from it."""
    need_pil()
    from PIL import Image, ImageChops
    fs = frames(a.dir)
    pick = fs[::max(1, len(fs) // 24)]
    tol = 24
    worst_edge, muddy, heights = None, [], []
    for f in pick:
        im = Image.open(f).convert("RGB")
        W, H = im.size
        im = im.resize((max(1, W // 4), max(1, H // 4)))
        w, h = im.size
        px = im.load()
        cs = [px[1, 1], px[w - 2, 1], px[1, h - 2], px[w - 2, h - 2]]
        g = tuple(sorted(c[i] for c in cs)[1] for i in range(3))
        d = ImageChops.difference(im, Image.new("RGB", im.size, g)).split()
        m = ImageChops.lighter(ImageChops.lighter(d[0], d[1]), d[2]).point(lambda v: 255 if v > tol else 0)
        hist = m.histogram()
        ground_share = hist[0] / float(w * h)
        bb = m.getbbox()
        n = os.path.basename(f)[6:11].lstrip("0") or "0"
        if not bb:
            continue
        x0, y0, x1, y1 = bb[0] / w, bb[1] / h, bb[2] / w, bb[3] / h
        heights.append((y1 - y0, n))
        gap = min(x0, y0, 1 - x1, 1 - y1)
        if worst_edge is None or gap < worst_edge[0]:
            worst_edge = (gap, n)
        if ground_share < 0.4:
            muddy.append((n, ground_share))
    if not heights:
        line("FAIL", "framing", "every sampled frame is empty ground")
        return finish()
    if a.bleed:
        line("PASS", "safe margins", "skipped: --bleed (full-frame by intent; say so in the brief)")
        line("PASS", "ground stays ground", "skipped: --bleed")
    else:
        gap, n = worst_edge
        line("FAIL" if gap < a.margin else "PASS", "safe margins",
             "closest to an edge %.1f%% of the frame at f%s (limit %.0f%%)" % (gap * 100, n, a.margin * 100))
        line("FAIL" if muddy else "PASS", "ground stays ground",
             ("%d/%d frames are mostly not ground; first f%s at %.0f%% ground -- a lit floor or sweep "
              "turns the frame to mid-tone; float the subject on the ground, or pass --bleed if intended"
              % (len(muddy), len(heights), muddy[0][0], muddy[0][1] * 100)) if muddy else "")
    top = max(heights)
    # Everything that is not ground, together: a scene of three small objects spread wide reads as
    # "big" here. The HERO's own share is a number the page knows (assert it from __probe).
    line("PASS" if top[0] >= 0.33 else "WARN", "subject height",
         "everything not ground spans %.0f%% of the frame height at f%s (the hero's own share: assert it via __probe)" % (top[0] * 100, top[1]))
    finish()


def main():
    ap = argparse.ArgumentParser(prog="motion-check.py", description=__doc__.split("\n")[0])
    sp = ap.add_subparsers(dest="cmd", required=True)
    c = sp.add_parser("contract"); c.add_argument("page")
    d = sp.add_parser("determinism"); d.add_argument("page"); d.add_argument("--frames", required=True)
    d.add_argument("--fps", type=float); d.add_argument("--size", default="1920x1080")
    s = sp.add_parser("seam"); s.add_argument("dir"); s.add_argument("--factor", type=float, default=3.0)
    p = sp.add_parser("pops"); p.add_argument("dir"); p.add_argument("--factor", type=float, default=4.0)
    fr = sp.add_parser("framing"); fr.add_argument("dir"); fr.add_argument("--margin", type=float, default=0.03)
    fr.add_argument("--bleed", action="store_true")
    x = sp.add_parser("assert"); x.add_argument("page"); x.add_argument("checks")
    x.add_argument("--fps", type=float); x.add_argument("--size", default="1920x1080")
    u = sp.add_parser("audio"); u.add_argument("media"); u.add_argument("--events")
    u.add_argument("--fps", type=float, default=60); u.add_argument("--lufs", type=float, default=-14.0)
    u.add_argument("--silent", action="store_true")
    a = ap.parse_args()
    {"contract": cmd_contract, "determinism": cmd_determinism, "seam": cmd_seam, "pops": cmd_pops, "framing": cmd_framing,
     "assert": cmd_assert, "audio": cmd_audio}[a.cmd](a)


if __name__ == "__main__":
    main()
