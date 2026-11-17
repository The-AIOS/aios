#!/usr/bin/env bash
# tests/motion-lab.test.sh
#
# hooks/media/motion-render.py + hooks/media/motion-check.py, the instruments behind skills/aios/motion-lab.
# The skill's acceptance bar is "reproduces one 6 s loop with every check green", so the example
# loop is rendered and checked end to end -- and every check is also shown to FAIL on a planted
# defect, because a check that cannot fail is not a check.
#
# Layers, each skipped (and said so) when its dependency is absent -- CI has no browser:
#   always    contract lint (stdlib): the example passes; one mutant per rule fails
#   Pillow    seam + pops + framing on synthetic frame sequences, with planted defects
#   ffmpeg    audio: a beep one frame after frame 59 is found on time; a late one is not
#   browser   the example loop: render all frames, seam, pops, determinism, speed, sheet, export;
#             a move launched from rest is caught as a speed corner
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
R="$ROOT/hooks/media/motion-render.py"; C="$ROOT/hooks/media/motion-check.py"
EX="$ROOT/skills/aios/motion-lab/examples/loop-6s.html"
PYBIN="${PYBIN:-python3}"
PASS=0; FAIL=0; SKIP=0
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
no(){ echo "  ✗ $1"; [ -n "${2:-}" ] && echo "      $2"; FAIL=$((FAIL+1)); }
skip(){ echo "  - SKIP $1"; SKIP=$((SKIP+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

echo "── contract (stdlib) ──"
$PYBIN "$C" contract "$EX" > "$T/c.out" 2>&1 && ok "the example loop passes every contract rule" || no "example fails its own contract" "$(cat "$T/c.out")"
mutant(){ # name, sed expression applied to a copy of the example
  sed "$2" "$EX" > "$T/m.html"
  if $PYBIN "$C" contract "$T/m.html" > "$T/m.out" 2>&1; then no "mutant not caught: $1"; else
    grep "FAIL $1" "$T/m.out" >/dev/null && ok "caught: $1" || no "mutant failed for the wrong rule: $1" "$(grep FAIL "$T/m.out")"; fi
}
mutant "no wall clock"          's#const TAU = Math.PI \* 2;#const TAU = Math.PI * 2; const now = Date.now();#'
mutant "no timers"              's#window.__ready = true;#setTimeout(() => {}, 10); window.__ready = true;#'
mutant "no unseeded random"     's#const rnd = mulberry32(7);#const rnd = Math.random;  const z = Math.random();#'
mutant "no runtime network"     's#window.__ready = true;#fetch("data.json"); window.__ready = true;#'
mutant "libraries pinned to a version" 's#<title>#<script src="https://cdn.jsdelivr.net/npm/gsap/dist/gsap.min.js"></script><title>#'
mutant "only known hosts"       's#<title>#<script src="https://example.com/lib@1.2.3.js"></script><title>#'
mutant "exposes renderAt(t)"    's#renderAt#drawAt#g'
# Import maps hide library URLs from an attribute scan (found building a Three.js piece).
cat > "$T/im.html" <<'HTML'
<!doctype html><script type="importmap">{"imports":{"three":"https://cdn.jsdelivr.net/npm/three/build/three.module.js"}}</script>
<script type="module">import * as THREE from "three"; window.renderAt = (t) => {};</script>
HTML
out=$($PYBIN "$C" contract "$T/im.html" 2>&1)
case "$out" in *"FAIL libraries pinned to a version"*) ok "an unpinned library inside an import map is caught" ;; *) no "import-map URL not checked" "$out" ;; esac
sed 's#three/build#three@0.160.0/build#' "$T/im.html" > "$T/im2.html"
$PYBIN "$C" contract "$T/im2.html" >/dev/null 2>&1 && ok "the same import map, pinned, passes" || no "a pinned import map failed"

echo "── seam + pops (Pillow) ──"
if $PYBIN -c 'import PIL' 2>/dev/null; then
  $PYBIN - "$T" <<'EOF'
import os, sys, math
from PIL import Image, ImageDraw
root = sys.argv[1]
def seq(name, n=120, pop=None, broken_seam=False):  # ~2.6 px a step, as at 60 fps
    d = os.path.join(root, name); os.makedirs(d)
    for i in range(n):
        ph = i / n if not broken_seam else i / (n * 0.7)
        im = Image.new("RGB", (160, 160), (14, 15, 18)); dr = ImageDraw.Draw(im)
        x = 80 + 50 * math.cos(2 * math.pi * ph); y = 80 + 50 * math.sin(2 * math.pi * ph)
        if pop is not None and i == pop: x, y = 20, 140
        dr.ellipse([x - 12, y - 12, x + 12, y + 12], fill=(255, 93, 77))
        im.save(os.path.join(d, "frame_%05d.png" % i))
seq("good"); seq("pop", pop=30); seq("seam", broken_seam=True)
d = os.path.join(root, "hold"); os.makedirs(d)   # still for 60 frames, then a smooth 12-frame move, then still
for i in range(100):
    k = min(max(i - 60, 0), 12) / 12.0; x = 40 + 80 * (0.5 - 0.5 * math.cos(math.pi * k))
    im = Image.new("RGB", (160, 160), (14, 15, 18)); ImageDraw.Draw(im).ellipse([x - 12, 68, x + 12, 92], fill=(255, 93, 77))
    im.save(os.path.join(d, "frame_%05d.png" % i))
EOF
  $PYBIN "$C" seam "$T/good" >/dev/null 2>&1 && ok "a whole-cycle loop passes seam" || no "good loop failed seam"
  $PYBIN "$C" seam "$T/seam" >/dev/null 2>&1 && no "a broken seam passed" || ok "a loop that stops short of a whole cycle fails seam"
  $PYBIN "$C" pops "$T/good" >/dev/null 2>&1 && ok "smooth motion passes pops" || no "smooth motion flagged as a pop"
  $PYBIN "$C" pops "$T/hold" >/dev/null 2>&1 && ok "an intentional move out of a still hold is not a pop" || no "a move after stillness was flagged as a pop" "$($PYBIN "$C" pops "$T/hold" 2>&1)"
  out=$($PYBIN "$C" pops "$T/pop" 2>&1) && no "a planted one-frame pop passed" || { case "$out" in *"frame 30"*) ok "the planted pop is found at frame 30" ;; *) no "pop found at the wrong frame" "$out" ;; esac; }
else skip "Pillow not installed"; fi

echo "── audio (ffmpeg) ──"
if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -v error -f lavfi -i "aevalsrc='if(between(t,1.0,1.08),0.5*sin(2*PI*880*t),0)':d=2:s=48000" "$T/beep.wav"
  echo '[{"frame":59}]' > "$T/on.json"; echo '[{"frame":50}]' > "$T/late.json"
  out=$($PYBIN "$C" audio "$T/beep.wav" --events "$T/on.json" --fps 60 2>&1)
  case "$out" in *"PASS hit for frame 59"*) ok "a hit one frame after frame 59 is on time" ;; *) no "on-time hit not found" "$out" ;; esac
  case "$out" in *"integrated loudness"*LUFS*) ok "loudness is measured and reported" ;; *) no "no loudness line" "$out" ;; esac
  out=$($PYBIN "$C" audio "$T/beep.wav" --events "$T/late.json" --fps 60 2>&1)
  case "$out" in *"FAIL hit for frame 50"*) ok "a hit 9 frames late fails" ;; *) no "a late hit passed" "$out" ;; esac
  ffmpeg -v error -f lavfi -i "color=c=black:s=64x64:d=1" -c:v libx264 -pix_fmt yuv420p "$T/mute.mp4"
  $PYBIN "$C" audio "$T/mute.mp4" --silent 2>&1 | grep -q "^N/A  audio  silent by brief" && ok "a silent film under --silent is N/A, not a run failure" || no "--silent did not report N/A"
  $PYBIN "$C" audio "$T/beep.wav" --silent >/dev/null 2>&1 && no "--silent passed a file that has sound" || ok "caught: sound present in a silent brief"
else skip "ffmpeg not installed"; fi

echo "── GIF export keeps the colours of a piece that opens on an empty frame ──"
if $PYBIN -c 'import PIL' 2>/dev/null && command -v ffmpeg >/dev/null 2>&1; then
  cat > "$T/fadein.py" <<'PY'
import os, sys
from PIL import Image, ImageDraw
d = sys.argv[1]; os.makedirs(d)
for i in range(24):
    im = Image.new("RGB", (120, 120), (11, 11, 13))
    if i >= 6: ImageDraw.Draw(im).ellipse([30, 30, 90, 90], fill=(255, 93, 77))
    im.save(os.path.join(d, "frame_%05d.png" % i))
PY
  $PYBIN "$T/fadein.py" "$T/fadein"
  $PYBIN "$R" export "$T/fadein" --fps 24 --out "$T/fadein.mp4" --gif "$T/fadein.gif" --gif-fps 24 >/dev/null 2>&1
  $PYBIN -c 'import sys; from PIL import Image; g=Image.open(sys.argv[1]); g.seek(g.n_frames-1); r,gg,b=g.convert("RGB").getpixel((60,60)); sys.exit(0 if r>200 and gg<140 else 1)' "$T/fadein.gif" \
    && ok "the coral survives in a GIF whose first frame is empty" || no "GIF palette taken from frame 0: later colours lost"
else skip "Pillow or ffmpeg not installed"; fi

echo "── framing: safe margins and a ground that stays ground (Pillow) ──"
if $PYBIN -c 'import PIL' 2>/dev/null; then
  cat > "$T/framing.py" <<'PYF'
import os, sys
from PIL import Image, ImageDraw
out, kind = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
for i in range(30):
    im = Image.new("RGB", (320, 180), (12, 12, 14)); d = ImageDraw.Draw(im)
    if kind == "floor":  d.polygon([(0, 90), (320, 60), (320, 180), (0, 180)], fill=(70, 70, 72))
    x = 100 + i
    d.rectangle([x, 40 if kind != "cut" else 0, x + 90, 140], fill=(200, 200, 205))
    im.save(os.path.join(out, "frame_%05d.png" % i))
PYF
  for k in good cut floor; do $PYBIN "$T/framing.py" "$T/fr-$k" "$k"; done
  $PYBIN "$C" framing "$T/fr-good" >/dev/null 2>&1 && ok "a subject floating inside the margins passes" || no "framing failed a clean frame" "$($PYBIN "$C" framing "$T/fr-good" 2>&1)"
  $PYBIN "$C" framing "$T/fr-cut" 2>&1 | grep -q "FAIL safe margins" && ok "caught: a subject cut by the frame edge" || no "edge cut not caught"
  $PYBIN "$C" framing "$T/fr-floor" 2>&1 | grep -q "FAIL ground stays ground" && ok "caught: a lit floor turning the frame to mid-tone" || no "muddy ground not caught"
  $PYBIN "$C" framing "$T/fr-floor" --bleed >/dev/null 2>&1 && ok "--bleed opts out when full-frame is the intent" || no "--bleed did not skip"
else skip "Pillow not installed"; fi

echo "── the example 6 s loop, end to end (browser) ──"
if $PYBIN -c 'import playwright, PIL' 2>/dev/null && $PYBIN "$R" frames "$EX" --out "$T/probe" --frames 0 --size 64x64 >/dev/null 2>&1; then
  $PYBIN "$R" frames "$EX" --out "$T/f" --all --size 240x240 --fps 30 >/dev/null 2>&1 \
    && [ "$(ls "$T/f" | grep -c '^frame_')" = 180 ] && ok "rendered frames 0..179 (6 s at 30 fps; frame N is never rendered)" || no "frame render failed"
  $PYBIN "$C" seam "$T/f" >/dev/null 2>&1 && ok "seam green" || no "example seam" "$($PYBIN "$C" seam "$T/f" 2>&1)"
  $PYBIN "$C" pops "$T/f" >/dev/null 2>&1 && ok "pops green" || no "example pops" "$($PYBIN "$C" pops "$T/f" 2>&1)"
  $PYBIN "$C" determinism "$EX" --frames 0,84 --size 240x240 --fps 30 >/dev/null 2>&1 && ok "determinism green" || no "example not deterministic"
  printf '[{"frame":0,"expr":"p.phase","expect":0,"tol":1e-9},{"frame":90,"expr":"p.phase","expect":0.5,"tol":1e-9},{"frame":90,"expr":"p.phase - at(0).phase","expect":0.5,"tol":1e-9}]' > "$T/a.json"
  $PYBIN "$C" assert "$EX" "$T/a.json" --fps 30 --size 240x240 >/dev/null 2>&1 && ok "assert green against __probe" || no "assert failed"
  $PYBIN "$R" speed "$EX" --out "$T/speed.png" --size 240x240 --fps 30 >/dev/null 2>&1 && ok "speed: the example has no corners" || no "speed flagged the example" "$($PYBIN "$R" speed "$EX" --out "$T/speed.png" --size 240x240 --fps 30 2>&1)"
  # a value launched from rest at full speed (an ease-out from a standstill) is a corner
  cat > "$T/corner.html" <<'HTMLC'
<!doctype html><html><body><script>
window.__duration = 2; window.__fps = 30;
const outE = (u) => 1 - Math.pow(1 - Math.min(1, Math.max(0, u)), 3);
window.__probe = (t) => ({ x: t < 1 ? 0 : outE((t - 1) / 0.6) });
window.renderAt = (t) => { document.body.style.background = "#111"; };
window.renderAt(0); window.__ready = true;
</script></body></html>
HTMLC
  $PYBIN "$R" speed "$T/corner.html" --out "$T/corner.png" --size 64x64 2>&1 | grep -q "FAIL  corners: x -- 1; first at f31" && ok "caught: a move launched from rest at full speed (f31)" || no "speed corner not caught" "$($PYBIN "$R" speed "$T/corner.html" --out "$T/corner.png" --size 64x64 2>&1)"
  $PYBIN "$R" sheet "$T/f" --out "$T/sheet.png" >/dev/null 2>&1 && [ -s "$T/sheet.png" ] && ok "contact sheet written" || no "sheet failed"
  if command -v ffmpeg >/dev/null 2>&1; then
    $PYBIN "$R" export "$T/f" --fps 30 --out "$T/loop.mp4" --gif "$T/loop.gif" --gif-fps 24 > "$T/x.out" 2>&1 \
      && grep '"gif_ms": 6000' "$T/x.out" >/dev/null && ok "MP4 + 24 fps GIF exported, GIF exactly 6000 ms (no drift)" || no "export" "$(cat "$T/x.out")"
    # no --fps: export must use the fps the frames were rendered at (here 30), not a 60 default
    $PYBIN "$R" export "$T/f" --out "$T/nofps.mp4" > "$T/n.out" 2>&1 \
      && grep '"fps": 30.0' "$T/n.out" >/dev/null \
      && [ "$(ffprobe -v error -select_streams v -show_entries stream=r_frame_rate -of csv=p=0 "$T/nofps.mp4")" = "30/1" ] \
      && ok "export without --fps keeps the rendered 30 fps" || no "export without --fps changed the frame rate" "$(cat "$T/n.out")"
  fi
else skip "no Python Playwright + Chromium here"; fi

echo "── video-watch writes its manifest beside --out, not into the cwd ──"
grep -n 'os.getcwd()' "$ROOT/hooks/media/video-watch.py" | grep -i -E 'manifest|caption-prompt' >/dev/null \
  && no "video-watch.py still writes the manifest into the working directory" || ok "no manifest path built from the cwd"

echo "── RESULT: $PASS passed, $FAIL failed, $SKIP skipped ──"
[ "$FAIL" = 0 ]
