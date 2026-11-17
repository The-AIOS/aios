#!/usr/bin/env python3
"""motion-render.py — render code-drawn motion frame by frame, and the views that review it.

WHY. Motion an agent writes as code (one HTML file, every frame a pure function of t) can be
rendered exactly: freeze the page at t = i/fps, save the frame, repeat. That makes frames
reproducible, an edit one number and a re-render, and -- the point -- lets the model LOOK at its own
work. It cannot review a video it is not shown, and it cannot sample its own frames back out of an
MP4 (scene-change detection finds 0 cuts in a continuous loop; a periodic sampler takes 1 frame of
480). You own the source, so render the frames you want. The skill that drives this loop is
skills/aios/motion-lab; the checks that grade it are hooks/media/motion-check.py.

THE PAGE CONTRACT (references/contract.md has the full house version):
  - `window.renderAt(t)` draws the frame at t seconds (may return a Promise). CSS animations are
    frozen too: every `document.getAnimations()` is paused and seeked to t.
  - optional `window.__duration` (seconds) and `window.__fps`; flags override them.
  - optional `window.__ready` (truthy, or a Promise) -- waited for before the first frame, after
    `document.fonts.ready`.
  - optional `window.__probe(t)` -> {name: number, ...} for the speed graph and motion-check assert.

USAGE
  motion-render.py frames PAGE.html --out DIR [--fps 60] [--duration 6] [--size 1920x1080]
                   [--all | --frames 0,24,48] [--subframes N]
  motion-render.py sheet  DIR --out sheet.png [--count 12 | --every K] [--cols 4] [--width 1600]
  motion-render.py onion  DIR --range A:B --out onion.png
  motion-render.py speed  PAGE.html --out speed.png [--fps 60] [--duration 6] [--size WxH] [--corner 0.5] [--allow F,F]
  motion-render.py export DIR --out film.mp4 [--fps N, default: the fps DIR was rendered at] [--audio sound.wav] [--gif out.gif --gif-fps 25]

Frames are written as DIR/frame_00000.png. A loop renders frames 0..N-1 (N = duration*fps): frame
N would equal frame 0, and rendering it puts a stutter at the seam.

Needs Python Playwright with Chromium, Pillow, and ffmpeg (for export). WebGL (Three.js) works in
the stock headless Chromium through its software renderer, deterministically; no flags needed. Use
`preserveDrawingBuffer: true` on the WebGL renderer so a screenshot captures the drawn frame. Each subcommand says which
one is missing instead of failing obscurely. Exit 0 ok · 1 bad input · 2 a dependency is missing.
"""
import argparse
import glob
import json
import os
import shutil
import subprocess
import sys

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

FREEZE_JS = """async (t) => {
  if (typeof window.renderAt === 'function') { await window.renderAt(t); }
  for (const a of document.getAnimations()) { a.pause(); a.currentTime = t * 1000; }
  await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
}"""

READY_JS = """async () => {
  if (document.fonts && document.fonts.ready) { await document.fonts.ready; }
  if ('__ready' in window) {
    const r = window.__ready;
    if (r && typeof r.then === 'function') { await r; }
    else { for (let i = 0; i < 300 && !window.__ready; i++) { await new Promise(s => setTimeout(s, 20)); } }
  }
  return { duration: window.__duration ?? null, fps: window.__fps ?? null,
           hasRenderAt: typeof window.renderAt === 'function', hasProbe: typeof window.__probe === 'function' };
}"""


def die(msg, code=1):
    print("motion-render: " + msg, file=sys.stderr)
    sys.exit(code)


def need_pil():
    try:
        from PIL import Image  # noqa: F401
    except ImportError:
        die("needs Pillow (pip install pillow)", 2)


def need_playwright():
    try:
        from playwright.sync_api import sync_playwright
        return sync_playwright
    except ImportError:
        die("needs Python Playwright with Chromium (pip install playwright && playwright install chromium)", 2)


def parse_size(s):
    try:
        w, h = s.lower().split("x")
        return int(w), int(h)
    except ValueError:
        die("--size must look like 1080x1080, got %r" % s)


def page_url(path):
    if path.startswith(("http://", "https://", "file://")):
        return path
    p = os.path.abspath(path)
    if not os.path.isfile(p):
        die("no such page: %s" % path)
    import pathlib
    return pathlib.Path(p).as_uri()  # file:///C:/... on Windows, file:///Users/... elsewhere


class Stage:
    """One headless page, loaded once, frozen at any t on request."""

    def __init__(self, page_path, size):
        self._pw_cm = need_playwright()()
        self.pw = self._pw_cm.__enter__()
        try:
            self.browser = self.pw.chromium.launch()
        except Exception as e:  # browser binary missing
            self._pw_cm.__exit__(None, None, None)
            die("Chromium did not launch (%s). Run: playwright install chromium" % str(e).splitlines()[0], 2)
        w, h = size
        self.page = self.browser.new_page(viewport={"width": w, "height": h}, device_scale_factor=1)
        self.page.goto(page_url(page_path))
        self.page.wait_for_load_state("load")
        self.meta = self.page.evaluate(READY_JS)
        # Warm-up: headless Chromium can hand back blank screenshots until its compositor has
        # produced a first frame (measured: the first 19 frames of a 30 fps render came out white,
        # and the seam check rightly failed). Re-render t=0 until two screenshots agree.
        prev = None
        for _ in range(60):
            self.page.evaluate(FREEZE_JS, 0)
            cur = self.page.screenshot()
            if cur == prev:
                break
            prev = cur
            self.page.wait_for_timeout(50)

    def shot(self, t, path):
        self.page.evaluate(FREEZE_JS, t)
        self.page.screenshot(path=path)

    def probe(self, t):
        self.page.evaluate(FREEZE_JS, t)
        return self.page.evaluate("(t) => window.__probe ? window.__probe(t) : null", t)

    def close(self):
        try:
            self.browser.close()
        finally:
            self._pw_cm.__exit__(None, None, None)


def timing(args, meta):
    fps = args.fps or meta.get("fps") or 60
    dur = args.duration or meta.get("duration")
    if not dur:
        die("no duration: pass --duration, or set window.__duration in the page")
    n = int(round(float(dur) * float(fps)))
    return float(fps), float(dur), n


def average_linear(paths, out):
    """Average sub-frame renders in linear light (motion blur). sRGB -> linear -> mean -> sRGB."""
    from PIL import Image
    try:
        import numpy as np
    except ImportError:
        print("motion-render: numpy not installed -- motion blur averaged in sRGB, trails slightly dark "
              "(pip install numpy for linear light)", file=sys.stderr)
        imgs = [Image.open(p).convert("RGB") for p in paths]
        acc = imgs[0]
        for i, im in enumerate(imgs[1:], start=2):
            acc = Image.blend(acc, im, 1.0 / i)
        acc.save(out)
        return
    arr = [np.asarray(Image.open(p).convert("RGB"), dtype=np.float64) / 255.0 for p in paths]
    lin = [np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4) for a in arr]
    m = sum(lin) / len(lin)
    srgb = np.where(m <= 0.0031308, m * 12.92, 1.055 * np.power(m, 1 / 2.4) - 0.055)
    Image.fromarray(np.clip(np.round(srgb * 255), 0, 255).astype("uint8")).save(out)


def cmd_frames(args):
    size = parse_size(args.size)
    os.makedirs(args.out, exist_ok=True)
    st = Stage(args.page, size)
    try:
        fps, dur, n = timing(args, st.meta)
        if not st.meta.get("hasRenderAt"):
            print("motion-render: note: no window.renderAt -- only CSS animations will be frozen", file=sys.stderr)
        if args.frames:
            idx = [int(x) for x in args.frames.split(",") if x.strip()]
        elif args.all:
            idx = list(range(n))
        else:
            die("say which frames: --all, or --frames 0,24,48")
        bad = [i for i in idx if i < 0 or i >= n]
        if bad:
            die("frame(s) %s outside 0..%d (a loop renders 0..N-1)" % (bad, n - 1))
        sub = max(1, args.subframes)
        if sub > 1:
            need_pil()
        tmp = os.path.join(args.out, ".sub")
        for i in idx:
            out = os.path.join(args.out, "frame_%05d.png" % i)
            if sub == 1:
                st.shot(i / fps, out)
            else:
                os.makedirs(tmp, exist_ok=True)
                parts = []
                for k in range(sub):
                    p = os.path.join(tmp, "s%02d.png" % k)
                    st.shot((i + k / sub) / fps, p)
                    parts.append(p)
                average_linear(parts, out)
        if os.path.isdir(tmp):
            shutil.rmtree(tmp, ignore_errors=True)
        # export only sees the folder, so the timing the page declared travels with the frames
        with open(os.path.join(args.out, "render.json"), "w", encoding="utf-8") as fh:
            json.dump({"fps": fps, "duration": dur, "size": args.size}, fh)
        print(json.dumps({"out": args.out, "frames": len(idx), "of": n, "fps": fps, "duration": dur,
                          "size": args.size, "subframes": sub}))
    finally:
        st.close()


def frame_files(d):
    fs = sorted(glob.glob(os.path.join(d, "frame_*.png")))
    if not fs:
        die("no frame_*.png in %s (render them with: motion-render.py frames ...)" % d)
    return fs


def frame_no(path):
    return int(os.path.basename(path)[6:11])


def cmd_sheet(args):
    need_pil()
    from PIL import Image, ImageDraw
    fs = frame_files(args.dir)
    if args.every:
        pick = fs[::args.every]
    else:
        k = max(1, args.count)
        pick = [fs[min(len(fs) - 1, round(i * (len(fs) - 1) / max(1, k - 1)))] for i in range(k)] if k > 1 else fs[:1]
    cols = max(1, args.cols)
    rows = (len(pick) + cols - 1) // cols
    first = Image.open(pick[0])
    cw = args.width // cols
    ch = round(first.height * cw / first.width)
    label_h = 18
    sheet = Image.new("RGB", (cw * cols, (ch + label_h) * rows), (24, 24, 24))
    draw = ImageDraw.Draw(sheet)
    for n, p in enumerate(pick):
        im = Image.open(p).convert("RGB").resize((cw, ch))
        x, y = (n % cols) * cw, (n // cols) * (ch + label_h)
        sheet.paste(im, (x, y + label_h))
        draw.text((x + 4, y + 3), "f%d" % frame_no(p), fill=(230, 230, 230))
    sheet.save(args.out)
    print(json.dumps({"out": args.out, "frames": [frame_no(p) for p in pick]}))


def cmd_onion(args):
    need_pil()
    from PIL import Image
    try:
        a, b = [int(x) for x in args.range.split(":")]
    except ValueError:
        die("--range must look like 80:92")
    fs = [f for f in frame_files(args.dir) if a <= frame_no(f) <= b]
    if not fs:
        die("no frames in range %s" % args.range)
    base = Image.open(fs[0]).convert("RGBA")
    for p in fs[1:]:
        layer = Image.open(p).convert("RGBA")
        base = Image.blend(base, layer, 0.25)
    base.convert("RGB").save(args.out)
    print(json.dumps({"out": args.out, "frames": [frame_no(f) for f in fs]}))


def cmd_speed(args):
    need_pil()
    from PIL import Image, ImageDraw
    st = Stage(args.page, parse_size(args.size))
    try:
        fps, dur, n = timing(args, st.meta)
        if not st.meta.get("hasProbe"):
            die("the page has no window.__probe(t) -> {name: number}; the speed graph plots what it returns")
        series = {}
        for i in range(n):
            p = st.probe(i / fps) or {}
            for k, v in p.items():
                if isinstance(v, (int, float)):
                    series.setdefault(k, [None] * n)[i] = float(v)
    finally:
        st.close()
    # Per-frame velocity of each probed value (signed, so a reversal is seen), normalised per series.
    # A CORNER is a one-frame jump in velocity: a dead start, an ease-out launched from rest, a move that
    # stops instead of landing. A smooth piece has none; a frame that jumps by more than half the value's
    # range is a wrap or a cut, judged by `pops`, not here.
    W, pad = 1200, 30
    allow = {int(x) for x in str(args.allow).split(",") if x.strip().isdigit()}
    speeds, corners = {}, {}
    for k, vals in series.items():
        v = [(vals[i] or 0) for i in range(n)]
        rng = (max(v) - min(v)) or 0.0
        if rng == 0:
            continue  # a constant (a reference value, a fixed slot) has no motion to graph
        vel = [v[i] - v[i - 1] for i in range(1, n)]               # vel[j] = change into frame j+1
        jump = [abs(d) > 0.5 * rng for d in vel]
        mx = max([abs(d) for d, j in zip(vel, jump) if not j] or [0.0])
        speeds[k] = [0.0] + [abs(d) for d in vel]
        if mx == 0:
            continue
        hits = []
        for j in range(1, len(vel)):
            if jump[j] or jump[j - 1] or (j + 1) in allow:
                continue
            dv = abs(vel[j] - vel[j - 1])
            if dv > args.corner * mx:
                hits.append((j + 1, dv / mx))
        if hits:
            corners[k] = hits
    if not speeds:
        die("every probed value is constant: nothing moves, so there is no speed to graph")
    img = Image.new("RGB", (W, 160 * len(speeds)), (20, 20, 20))
    dr = ImageDraw.Draw(img)
    csv = ["frame," + ",".join("d_" + k for k in speeds)]
    for row, (k, sp) in enumerate(speeds.items()):
        top = row * 160
        mx = max(sp) or 1.0
        pts = [(pad + i * (W - 2 * pad) / max(1, n - 1), top + 140 - sp[i] / mx * 110) for i in range(n)]
        dr.line(pts, fill=(255, 140, 90), width=2)
        for fr, _ in corners.get(k, []):
            x = pad + fr * (W - 2 * pad) / max(1, n - 1)
            dr.line([(x, top + 24), (x, top + 150)], fill=(255, 60, 60), width=1)
        dr.text((pad, top + 8), "%s  (max %.4g / frame)%s" % (k, mx, ("  CORNERS: %d" % len(corners[k])) if k in corners else ""),
                fill=(220, 220, 220))
    for i in range(n):
        csv.append(str(i) + "," + ",".join("%.6g" % speeds[k][i] for k in speeds))
    img.save(args.out)
    with open(os.path.splitext(args.out)[0] + ".csv", "w", encoding="utf-8") as f:
        f.write("\n".join(csv) + "\n")
    for k in speeds:
        if k in corners:
            h = corners[k]
            print("FAIL  corners: %s -- %d; first at f%d (velocity jumped %.0f%% of top speed in one frame)%s"
                  % (k, len(h), h[0][0], h[0][1] * 100, (", also " + ", ".join("f%d" % f for f, _ in h[1:4])) if len(h) > 1 else ""))
        else:
            print("PASS  corners: %s" % k)
    print(json.dumps({"out": args.out, "series": list(speeds), "constant_skipped": [k for k in series if k not in speeds],
                      "corners": {k: [f for f, _ in h] for k, h in corners.items()}, "frames": n}))
    print("RESULT %s" % ("PASS" if not corners else "FAIL (%d series with corners): %s" % (len(corners), ", ".join(corners))))
    sys.exit(1 if corners else 0)


def cmd_export(args):
    if not shutil.which("ffmpeg"):
        die("needs ffmpeg on PATH", 2)
    fs = frame_files(args.dir)
    nums = [frame_no(f) for f in fs]
    if nums != list(range(nums[0], nums[0] + len(nums))):
        die("frames are not a contiguous run (render with --all before exporting)")
    if args.fps is None:                     # flag > the fps the frames were rendered at > 60
        try:
            with open(os.path.join(args.dir, "render.json"), encoding="utf-8") as fh:
                args.fps = float(json.load(fh)["fps"])
        except (OSError, ValueError, KeyError):
            args.fps = 60.0
            print("motion-render: note: no render.json in %s and no --fps: exporting at 60 fps" % args.dir,
                  file=sys.stderr)
    pattern = os.path.join(args.dir, "frame_%05d.png")
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(args.fps), "-start_number", str(nums[0]),
           "-i", pattern]
    if args.audio:
        cmd += ["-i", args.audio, "-c:a", "aac", "-b:a", "192k", "-shortest"]
    cmd += ["-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p", "-crf", "18",
            "-movflags", "+faststart", args.out]
    r = subprocess.run(cmd)
    if r.returncode != 0:
        die("ffmpeg failed (exit %d)" % r.returncode)
    out = {"mp4": args.out, "frames": len(fs), "fps": args.fps}
    if args.gif:
        need_pil()
        from PIL import Image
        # Resample to the GIF rate by time, then set per-frame delays. GIF delays are hundredths of a
        # second, so 24 fps (41.67 ms) cannot be expressed: five frames at 40 ms then one at 50 ms
        # averages to exactly 24 fps instead of drifting 4%.
        gfps = float(args.gif_fps)
        total = len(fs) / float(args.fps)
        m = int(round(total * gfps))
        pick = [fs[min(len(fs) - 1, int(i * args.fps / gfps))] for i in range(m)]
        if abs(gfps - 24) < 1e-6:
            delays = [50 if (i % 6) == 5 else 40 for i in range(m)]
        else:
            delays = [int(round(1000 / gfps / 10.0)) * 10] * m
        frames = [Image.open(p).convert("RGB") for p in pick]
        # One palette for the whole GIF, built from frames sampled ACROSS the piece. Taking it from
        # frame 0 alone mapped a sting that opens on an empty frame to solid black (a 2 KB GIF).
        sample = frames[::max(1, len(frames) // 16)][:16]
        w, h = frames[0].size
        tw, th = max(1, w // 4), max(1, h // 4)
        tile = Image.new("RGB", (tw * len(sample), th))
        for i, fr in enumerate(sample):
            tile.paste(fr.resize((tw, th)), (i * tw, 0))
        pal = tile.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
        q = [f.quantize(palette=pal, dither=Image.Dither.FLOYDSTEINBERG) for f in frames]
        q[0].save(args.gif, save_all=True, append_images=q[1:], duration=delays, loop=0, optimize=False, disposal=1)
        out.update({"gif": args.gif, "gif_frames": m, "gif_ms": sum(delays)})
    print(json.dumps(out))


def main():
    ap = argparse.ArgumentParser(prog="motion-render.py", description=__doc__.split("\n")[0])
    sp = ap.add_subparsers(dest="cmd", required=True)
    f = sp.add_parser("frames"); f.add_argument("page"); f.add_argument("--out", required=True)
    f.add_argument("--fps", type=float); f.add_argument("--duration", type=float)
    f.add_argument("--size", default="1920x1080"); f.add_argument("--all", action="store_true")
    f.add_argument("--frames"); f.add_argument("--subframes", type=int, default=1)
    s = sp.add_parser("sheet"); s.add_argument("dir"); s.add_argument("--out", required=True)
    s.add_argument("--count", type=int, default=12); s.add_argument("--every", type=int)
    s.add_argument("--cols", type=int, default=4); s.add_argument("--width", type=int, default=1600)
    o = sp.add_parser("onion"); o.add_argument("dir"); o.add_argument("--range", required=True)
    o.add_argument("--out", required=True)
    v = sp.add_parser("speed"); v.add_argument("page"); v.add_argument("--out", required=True)
    v.add_argument("--fps", type=float); v.add_argument("--duration", type=float)
    v.add_argument("--size", default="1920x1080")
    v.add_argument("--corner", type=float, default=0.5,
                   help="a one-frame change in velocity above this share of the series' top speed is a corner")
    v.add_argument("--allow", default="", help="frames where a corner is intended (a cut, a snap), e.g. 120,240")
    e = sp.add_parser("export"); e.add_argument("dir"); e.add_argument("--out", required=True)
    e.add_argument("--fps", type=float); e.add_argument("--audio")
    e.add_argument("--gif"); e.add_argument("--gif-fps", type=float, default=25)
    a = ap.parse_args()
    {"frames": cmd_frames, "sheet": cmd_sheet, "onion": cmd_onion, "speed": cmd_speed,
     "export": cmd_export}[a.cmd](a)


if __name__ == "__main__":
    main()
