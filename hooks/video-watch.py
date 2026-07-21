#!/usr/bin/env python3
"""
video-watch.py — give AIOS the VISUAL channel of video, not just the transcript.

markitdown (bundled) discards every frame: an .mp4 is routed to the audio
converter (exiftool + speech-to-text) and the screen — slides, diagrams, code,
on-screen text, demonstrations — is thrown away. This is the missing half.

ARCHITECTURE (see vault: projects/infra-video-comprehension.md)
---------------------------------------------------------------
One BACKBONE, a pluggable per-frame READER, and an alternative fast path:

    input (file | YouTube URL)
      ① transcript pass FIRST   → the semantic spine (two-pass anchor)
      ② ffmpeg scene-keyframes  → candidate frames (cap 720p, scene-change)
      ③ phash dedup             → drop near-duplicate slides (pure pillow)
      ④ per-frame READER        → pluggable:
            vlm  = Claude vision caption (describe)   [headless via `claude -p`]
            ocr  = Apple Vision verbatim (transcribe) [hooks/ocr-image.swift]
            both = caption + verbatim
      ⑤ merge on a shared timeline → Markdown (+ optional JSON)

The Gemini-native one-shot path (--engine gemini) is a SEPARATE engine — it
samples frames internally and is cheap-but-lossy on dense text; stubbed here.

DEPENDENCY-LIGHT BY DESIGN: ffmpeg + yt-dlp + pillow + the `swift` Apple Vision
script + the `claude` CLI — all already on the machine. No pip install for v1.

USAGE
    python3 hooks/video-watch.py <file-or-youtube-url> [options]

OPTIONS
    --reader vlm|ocr|both     per-frame reader (default: vlm)
    --engine backbone|gemini  pipeline (default: backbone; gemini = stub)
    --transcript PATH         reuse an existing transcript .md (skip fetch)
    --no-transcript           visual-only (no spine)
    --scene-threshold FLOAT   ffmpeg scene-change sensitivity (default 0.3;
                              LOWER = more frames — slides change little)
    --sample-every INT        periodic-floor seconds for static videos
                              (default 90; 0=off) — coverage guarantee
    --max-frames-per-min INT  per-minute ceiling; subsample if exceeded (def 6)
    --max-frames INT          absolute hard cap on frames read (default 300;
                              0=unlimited) — announced loudly if it bites
    --max-width INT           downscale cap for extraction (default 1280)
    --phash-threshold INT     Hamming distance for dedup (default 6; 0=keep all)
    --code                    OCR code mode: disable language correction
    --caption-mode MODE       headless | manifest (default: headless)
                                headless = invoke `claude -p` to caption — one
                                           shot, complete output, no API key
                                manifest = emit frame manifest + ready prompt
                                           (let the calling session do the read)
    --out PATH                output .md (default: alongside input)
    --json                    also write a .json timeline next to the .md
    --workdir PATH            frame extraction dir (default: temp, auto-clean)
    --keep-frames             keep extracted frames (implied if --workdir given)
    -v, --verbose             progress to stderr

EXIT CODES: 0 ok · 1 usage · 2 no transcript · 3 extraction error · 4 reader error
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HOOKS = os.path.dirname(os.path.abspath(__file__))
OCR_SWIFT = os.path.join(HOOKS, "ocr-image.swift")
YT_TRANSCRIPT = os.path.join(HOOKS, "custom", "youtube-transcript.py")

# Local transcription = whisper.cpp (whisper-cli): on-device, free, Metal-fast,
# Fortress-clean. Models live in the established AIOS cache, preferred by power.
WHISPER_DIR = os.path.expanduser("~/.cache/aios/whisper")
WHISPER_PREFERENCE = ["large-v3-turbo", "large-v3", "large-v2", "medium",
                      "small", "base"]


def whisper_model_path():
    """Env override, else the most powerful model present in the AIOS cache."""
    env = os.environ.get("WHISPER_MODEL")
    if env and os.path.exists(env):
        return env
    for name in WHISPER_PREFERENCE:
        p = os.path.join(WHISPER_DIR, f"ggml-{name}.bin")
        if os.path.exists(p):
            return p
    return None


def transcript_python():
    """youtube-transcript-api is a per-machine install, usually on system 3.9
    (see memory: study-transcript-puller-dep) — not necessarily on the python
    running this script. Pick the first interpreter that actually has it."""
    candidates = [sys.executable, "/usr/bin/python3",
                  shutil.which("python3.9"), shutil.which("python3")]
    for py in candidates:
        if not py:
            continue
        r = subprocess.run([py, "-c", "import youtube_transcript_api"],
                           capture_output=True)
        if r.returncode == 0:
            return py
    return sys.executable  # let it fail loudly downstream

YT_RE = re.compile(r"(?:youtube\.com|youtu\.be)", re.I)
TS_LINE_RE = re.compile(r"`\[(?:(\d+):)?(\d+):(\d+)\]`\s*(.*)")  # `[hh:mm:ss]` or `[mm:ss]`


def log(msg, *, verbose):
    if verbose:
        print(f"[video-watch] {msg}", file=sys.stderr)


def run(cmd, timeout=None, **kw):
    """Subprocess wrapper that never raises on timeout or a missing binary —
    returns a CompletedProcess with a non-zero code so callers degrade
    gracefully (visual-only, empty captions) instead of crashing the run."""
    try:
        return subprocess.run(cmd, capture_output=True, text=True,
                              timeout=timeout, **kw)
    except subprocess.TimeoutExpired as e:
        return subprocess.CompletedProcess(
            cmd, 124, e.stdout or "", (e.stderr or "") + f"\n[timed out after {timeout}s]")
    except (FileNotFoundError, OSError) as e:
        return subprocess.CompletedProcess(cmd, 127, "", f"[exec failed: {e}]")


# ───────────────────────── ① transcript (the spine) ─────────────────────────

def fetch_transcript(src, is_url, transcript_path, video, workdir, verbose):
    """Return a list of {start, text} segments (start in seconds), or [].

    Priority: explicit --transcript > YouTube captions (URLs) > local
    whisper.cpp transcription (local files) > visual-only.
    """
    if transcript_path:
        log(f"reusing transcript: {transcript_path}", verbose=verbose)
        with open(transcript_path) as f:
            return parse_timestamped_md(f.read())

    if is_url:
        py = transcript_python()
        log(f"fetching YouTube transcript via youtube-transcript.py ({py})", verbose=verbose)
        r = run([py, YT_TRANSCRIPT, src, "--timestamps"])
        if r.returncode == 0:
            segs = parse_timestamped_md(r.stdout)
            if segs:
                return segs
        log("no YouTube captions — falling back to local whisper", verbose=verbose)

    # Local file (or a caption-less URL we've already downloaded to `video`).
    return transcribe_local(video, workdir, verbose)


def transcribe_local(video, workdir, verbose):
    """Transcribe a local video with whisper.cpp (whisper-cli). Returns
    [{start, text}] or [] (visual-only) if the binary/model is unavailable."""
    cli = shutil.which("whisper-cli")
    model = whisper_model_path()
    if not cli or not model:
        log(f"whisper unavailable (cli={bool(cli)} model={bool(model)}) — visual-only",
            verbose=verbose)
        return []
    wav = os.path.join(workdir, "audio.wav")
    log("extracting 16kHz mono audio for whisper", verbose=verbose)
    ar = run(["ffmpeg", "-hide_banner", "-y", "-i", video, "-vn",
              "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", wav], timeout=1800)
    if ar.returncode != 0 or not os.path.exists(wav):
        log("audio extraction failed — visual-only", verbose=verbose)
        return []
    prefix = os.path.join(workdir, "transcript")
    log(f"whisper.cpp transcribing ({os.path.basename(model)})", verbose=verbose)
    wr = run([cli, "-m", model, "-f", wav, "-oj", "-of", prefix, "-nt"],
             timeout=7200)
    jpath = prefix + ".json"
    if wr.returncode != 0 or not os.path.exists(jpath):
        log(f"whisper failed: {wr.stderr.strip()[-300:]}", verbose=verbose)
        return []
    try:
        data = json.load(open(jpath))
    except Exception:
        return []
    segs = []
    for seg in data.get("transcription", []):
        ms = (seg.get("offsets") or {}).get("from")
        txt = (seg.get("text") or "").strip()
        if ms is not None and txt:
            segs.append({"start": ms / 1000.0, "text": txt})
    log(f"whisper produced {len(segs)} segments", verbose=verbose)
    return segs


def parse_timestamped_md(text):
    segs = []
    for line in text.splitlines():
        m = TS_LINE_RE.match(line.strip())
        if not m:
            continue
        hh, mm, ss, body = m.groups()
        start = int(mm) * 60 + int(ss) + (int(hh) * 3600 if hh else 0)
        if body.strip():
            segs.append({"start": start, "text": body.strip()})
    return segs


# ───────────────── resolve a YouTube URL to a local video file ───────────────

def download_video(url, workdir, max_width, verbose):
    out = os.path.join(workdir, "source.mp4")
    log(f"downloading (≤{max_width}px) via yt-dlp", verbose=verbose)
    fmt = f"bestvideo[height<=720]+bestaudio/best[height<=720]/best"
    r = run(["yt-dlp", "-f", fmt, "--merge-output-format", "mp4",
             "-o", out, "--no-playlist", "--quiet", url], timeout=1800)
    if r.returncode != 0 or not os.path.exists(out):
        raise RuntimeError(f"yt-dlp failed: {r.stderr.strip() or r.stdout.strip()}")
    return out


# ─────────────────── ② ffmpeg scene-change keyframe extract ──────────────────

def extract_keyframes(video, workdir, scene_threshold, max_width, sample_every,
                      verbose):
    """Extract scene-change frames + an explicit t=0 frame + a periodic floor.
    The periodic floor guarantees coverage of *static* videos (one slide held
    for an hour fires zero scene changes); dedup later collapses the redundant
    ones, so the cost is near-zero. Returns [{time, path}] ordered by time."""
    frames_dir = os.path.join(workdir, "frames")
    os.makedirs(frames_dir, exist_ok=True)

    # t=0 opening frame (scene-detect never fires on frame 0).
    first = os.path.join(frames_dir, "f_0000.jpg")
    run(["ffmpeg", "-hide_banner", "-y", "-ss", "0", "-i", video,
         "-frames:v", "1", "-vf", f"scale='min({max_width},iw)':-2",
         "-q:v", "3", first], timeout=300)
    frames = [{"time": 0.0, "path": first}] if os.path.exists(first) else []

    # Scene-change pass: select + showinfo prints pts_time per kept frame, in order.
    vf = (f"select='gt(scene,{scene_threshold})',"
          f"scale='min({max_width},iw)':-2,showinfo")
    pat = os.path.join(frames_dir, "f_%04d.jpg")
    log(f"ffmpeg scene-detect (threshold={scene_threshold})", verbose=verbose)
    r = run(["ffmpeg", "-hide_banner", "-y", "-i", video, "-vf", vf,
             "-fps_mode", "vfr", "-start_number", "1", "-q:v", "3", pat],
            timeout=1800)
    if r.returncode != 0 and not os.listdir(frames_dir):
        raise RuntimeError(f"ffmpeg extraction failed: {r.stderr.strip()[-500:]}")

    times = [float(m) for m in re.findall(r"pts_time:([0-9.]+)", r.stderr)]
    extracted = sorted(p for p in os.listdir(frames_dir)
                       if p.startswith("f_") and p != "f_0000.jpg")
    for i, name in enumerate(extracted):
        t = times[i] if i < len(times) else 0.0
        frames.append({"time": round(t, 2), "path": os.path.join(frames_dir, name)})
    log(f"scene-detect: {len(frames)} frames", verbose=verbose)

    # Periodic floor — coverage guarantee for static / slow videos. Seek to each
    # known time with -ss so the timestamp is EXACT by construction (the fps
    # filter rewrites pts, which would mislabel frames and break A/V alignment).
    dur = video_duration(video)
    if sample_every and sample_every > 0 and dur > 0:
        added = 0
        t = float(sample_every)  # t=0 is already covered by f_0000
        while t < dur:
            name = os.path.join(frames_dir, f"p_{int(t):06d}.jpg")
            pr = run(["ffmpeg", "-hide_banner", "-y", "-ss", f"{t}", "-i", video,
                      "-frames:v", "1", "-vf", f"scale='min({max_width},iw)':-2",
                      "-q:v", "3", name], timeout=120)
            if pr.returncode == 0 and os.path.exists(name):
                frames.append({"time": round(t, 2), "path": name})
                added += 1
            t += sample_every
        log(f"periodic floor (every {sample_every}s): +{added} frames",
            verbose=verbose)

    frames.sort(key=lambda f: f["time"])
    log(f"extracted {len(frames)} candidate frames total", verbose=verbose)
    return frames


def enforce_fpm_ceiling(frames, video_seconds, max_fpm, verbose):
    """If frames exceed the per-minute ceiling, evenly subsample (keep t=0)."""
    if max_fpm <= 0 or video_seconds <= 0:
        return frames
    cap = max(1, int(max_fpm * (video_seconds / 60.0)))
    if len(frames) <= cap:
        return frames
    step = len(frames) / cap
    kept = [frames[0]] + [frames[int(i * step)] for i in range(1, cap)]
    # de-dup by path while preserving order
    seen, out = set(), []
    for f in kept:
        if f["path"] not in seen:
            seen.add(f["path"]); out.append(f)
    log(f"fpm ceiling {max_fpm}/min → {len(frames)}→{len(out)} frames", verbose=verbose)
    return out


def enforce_absolute_cap(frames, max_frames, reader):
    """Hard ceiling on frames sent to a paid/slow reader. Evenly subsample and
    announce it LOUDLY (no silent truncation — CLAUDE.md: 'no silent caps')."""
    if max_frames <= 0 or len(frames) <= max_frames:
        return frames
    step = len(frames) / max_frames
    kept = [frames[0]] + [frames[int(i * step)] for i in range(1, max_frames)]
    seen, out = set(), []
    for f in kept:
        if f["path"] not in seen:
            seen.add(f["path"]); out.append(f)
    print(f"⚠️  capped {len(frames)}→{len(out)} frames (--max-frames {max_frames}, "
          f"reader={reader}). Raise --max-frames or tighten --phash-threshold to "
          f"cover more.", file=sys.stderr)
    return out


# ───────────────────── ③ perceptual-hash dedup (pillow) ──────────────────────

def dhash(path, size=8):
    """64-bit difference hash. Pure pillow; no imagehash/opencv needed.
    Uses tobytes() (getdata() is deprecated, removed in Pillow 14)."""
    from PIL import Image
    img = Image.open(path).convert("L").resize((size + 1, size), Image.LANCZOS)
    px = img.tobytes()  # row-major bytes, one per pixel for an 'L' image
    bits = 0
    w = size + 1
    for row in range(size):
        for col in range(size):
            left = px[row * w + col]
            right = px[row * w + col + 1]
            bits = (bits << 1) | (1 if left > right else 0)
    return bits


def hamming(a, b):
    return bin(a ^ b).count("1")


def dedup_frames(frames, threshold, verbose):
    if threshold <= 0 or len(frames) <= 1:
        return frames
    kept, hashes = [], []
    for f in frames:
        try:
            h = dhash(f["path"])
        except Exception as e:
            log(f"dhash failed on {f['path']}: {e}", verbose=verbose)
            kept.append(f); continue
        if any(hamming(h, kh) <= threshold for kh in hashes):
            continue  # near-duplicate of a frame we already kept
        hashes.append(h); kept.append(f)
    log(f"phash dedup (≤{threshold}) → {len(frames)}→{len(kept)} unique frames", verbose=verbose)
    return kept


# ───────────────────────── ④ per-frame readers ──────────────────────────────

def read_ocr(path, code_mode, verbose):
    """Apple Vision OCR (verbatim) via the bundled swift script. macOS-only."""
    if sys.platform != "darwin":
        log("ocr reader requires macOS (Apple Vision). Use --reader vlm off-Mac "
            "(claude -p is cross-platform).", verbose=True)
        return ""
    cmd = ["swift", OCR_SWIFT, path]
    if code_mode:
        cmd.append("--no-correction")
    r = run(cmd, timeout=120)
    if r.returncode != 0:
        log(f"ocr failed on {path}: {r.stderr.strip()}", verbose=verbose)
        return ""
    return r.stdout.strip()


def read_vlm_headless(frames, segments, verbose):
    """Caption each frame with `claude -p` (subscription auth — no API key).
    Returns {path: caption}. Production path for the vlm reader."""
    claude = shutil.which("claude") or os.path.expanduser("~/.local/bin/claude")
    manifest = [{"index": i, "path": f["path"], "time": f["time"]} for i, f in enumerate(frames)]
    prompt = build_caption_prompt(manifest, segments)
    log(f"captioning {len(frames)} frames via claude -p (headless)", verbose=verbose)
    r = run([claude, "-p", prompt, "--allowedTools", "Read"], timeout=1200)
    if r.returncode != 0:
        log(f"claude -p failed: {r.stderr.strip()[-400:]}", verbose=verbose)
        return {}
    return parse_caption_json(r.stdout, frames)


def build_caption_prompt(manifest, segments):
    spine = "\n".join(f"[{int(s['start'])//60:02d}:{int(s['start'])%60:02d}] {s['text']}"
                      for s in segments[:400]) or "(no transcript)"
    frames_block = "\n".join(f"{m['index']}\t{m['time']}s\t{m['path']}" for m in manifest)
    return (
        "You are the VISUAL READER for a video-comprehension pipeline. Read each "
        "keyframe image with the Read tool and describe what is ON SCREEN that the "
        "spoken transcript does NOT capture: slide titles, bullet text, diagrams, "
        "code, charts, on-screen labels. Be concise and factual — transcribe "
        "visible text verbatim where it carries the payload; do not restate the "
        "narration.\n\n"
        "Return ONLY a JSON array, one object per frame:\n"
        '[{"index": 0, "caption": "..."}, ...]\n\n'
        f"=== TRANSCRIPT (the audio spine, for context) ===\n{spine}\n\n"
        f"=== FRAMES (index, time, path — Read each path) ===\n{frames_block}\n"
    )


def parse_caption_json(stdout, frames):
    m = re.search(r"\[\s*{.*}\s*\]", stdout, re.S)
    if not m:
        return {}
    try:
        arr = json.loads(m.group(0))
    except Exception:
        return {}
    out = {}
    for obj in arr:
        i = obj.get("index")
        if isinstance(i, int) and 0 <= i < len(frames):
            out[frames[i]["path"]] = (obj.get("caption") or "").strip()
    return out


# ───────────────────────── ⑤ timeline merge → Markdown ──────────────────────

def fmt_ts(sec):
    sec = int(sec)
    h, m, s = sec // 3600, (sec % 3600) // 60, sec % 60
    return f"{h:02d}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"


def nearest_transcript(segments, t, window_back):
    """Transcript text spoken in (t-window_back, t]."""
    lo = t - window_back
    chunk = [s["text"] for s in segments if lo < s["start"] <= t + 1]
    return " ".join(chunk).strip()


def merge_timeline(frames, segments, screen_text, reader, title, src, meta):
    blocks = []
    times = [f["time"] for f in frames]
    for i, f in enumerate(frames):
        prev = times[i - 1] if i else 0.0
        said = nearest_transcript(segments, f["time"], max(8.0, f["time"] - prev))
        screen = screen_text.get(f["path"], "").strip()
        blocks.append({
            "time": f["time"], "ts": fmt_ts(f["time"]),
            "screen": screen, "said": said,
            "frame": f["path"],
        })

    lines = [f"# {title}", f"> source: {src} · reader={reader} · {meta}", ""]
    lines.append("> **Screen = what the visual channel adds; Said = the spoken transcript window.**\n")
    for b in blocks:
        lines.append(f"## `[{b['ts']}]`")
        if b["screen"]:
            label = "Screen (verbatim)" if reader == "ocr" else "Screen"
            lines.append(f"**{label}:** {b['screen']}")
        if b["said"]:
            lines.append(f"**Said:** {b['said']}")
        lines.append(f"`{os.path.basename(b['frame'])}`")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n", blocks


# ───────────────────────── gemini-native stub (engine #1) ────────────────────

def engine_gemini_stub(src):
    sys.stderr.write(
        "─── ENGINE: gemini-native (STUB) ───────────────────────────────\n"
        "Not yet implemented. Design (research-backed):\n"
        "  • One-shot: hand the whole video to Gemini 2.5/3 (native frames+audio).\n"
        "  • Cheapest in $ (~$0.11–0.45/hr low-res) but LOSSY on dense on-screen\n"
        "    text/code — escalate to --engine backbone when verbatim text matters.\n"
        "  • Knobs: media_resolution=low, fps<1 for static lectures, context cache.\n"
        "  • Interface: same (input → timeline Markdown) so callers don't branch.\n"
        "  • Needs: GEMINI_API_KEY + google-genai. Wire as read_gemini(video)->blocks.\n"
        f"  • Input was: {src}\n"
        "────────────────────────────────────────────────────────────────\n")
    return 0


# ───────────────────────────────── main ─────────────────────────────────────

def video_duration(video):
    r = run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=nokey=1:noprint_wrappers=1", video])
    try:
        return float(r.stdout.strip())
    except Exception:
        return 0.0


def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("input", nargs="?")
    ap.add_argument("--reader", choices=["vlm", "ocr", "both"], default="vlm")
    ap.add_argument("--engine", choices=["backbone", "gemini"], default="backbone")
    ap.add_argument("--transcript")
    ap.add_argument("--no-transcript", action="store_true")
    ap.add_argument("--scene-threshold", type=float, default=0.3)
    ap.add_argument("--sample-every", type=int, default=90,
                    help="periodic-floor seconds for static videos (0=off)")
    ap.add_argument("--max-frames-per-min", type=int, default=6)
    ap.add_argument("--max-frames", type=int, default=300,
                    help="absolute hard cap on frames read (0=unlimited)")
    ap.add_argument("--max-width", type=int, default=1280)
    ap.add_argument("--phash-threshold", type=int, default=6)
    ap.add_argument("--code", action="store_true")
    ap.add_argument("--caption-mode", choices=["headless", "manifest"], default="headless")
    ap.add_argument("--out")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--workdir")
    ap.add_argument("--keep-frames", action="store_true")
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("-h", "--help", action="store_true")
    a = ap.parse_args()

    if a.help or not a.input:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(0 if a.help else 1)

    v = a.verbose
    src = a.input
    is_url = bool(YT_RE.search(src))

    if a.engine == "gemini":
        sys.exit(engine_gemini_stub(src))

    # workdir: explicit (kept) or temp (auto-clean unless --keep-frames)
    cleanup = False
    if a.workdir:
        workdir = a.workdir; os.makedirs(workdir, exist_ok=True); a.keep_frames = True
    else:
        workdir = tempfile.mkdtemp(prefix="video-watch-"); cleanup = not a.keep_frames

    try:
        # resolve to a local video for frame extraction (+ whisper fallback)
        video = download_video(src, workdir, a.max_width, v) if is_url else src
        if not os.path.exists(video):
            print(f"input not found: {video}", file=sys.stderr); sys.exit(3)
        dur = video_duration(video)

        # ① transcript spine (explicit > YouTube captions > local whisper)
        segments = [] if a.no_transcript else fetch_transcript(
            src, is_url, a.transcript, video, workdir, v)

        # ② extract → ③ dedup (cheapest reducer first) → fpm ceiling → hard cap
        frames = extract_keyframes(video, workdir, a.scene_threshold,
                                   a.max_width, a.sample_every, v)
        frames = dedup_frames(frames, a.phash_threshold, v)
        frames = enforce_fpm_ceiling(frames, dur, a.max_frames_per_min, v)
        frames = enforce_absolute_cap(frames, a.max_frames, a.reader)
        if not frames:
            print("no frames extracted", file=sys.stderr); sys.exit(3)

        # ④ per-frame reader(s)
        screen_text = {}
        title = (os.path.splitext(os.path.basename(video))[0]
                 if not is_url else src)

        if a.reader in ("ocr", "both"):
            log("reader: OCR (Apple Vision)", verbose=v)
            for f in frames:
                txt = read_ocr(f["path"], a.code, v)
                if txt:
                    screen_text[f["path"]] = txt

        if a.reader in ("vlm", "both"):
            if a.caption_mode == "headless":
                caps = read_vlm_headless(frames, segments, v)
                for p, c in caps.items():
                    screen_text[p] = (screen_text.get(p, "") + ("\n" if p in screen_text else "") + c).strip()
            else:
                # manifest mode: emit the frames + a ready prompt for an
                # interactive session (or me) to act as the vision reader.
                emit_manifest(frames, segments, workdir, a, v)

        # ⑤ merge
        meta = f"{len(frames)} keyframes · {fmt_ts(dur)} · scene>{a.scene_threshold} · phash≤{a.phash_threshold}"
        md, blocks = merge_timeline(frames, segments, screen_text, a.reader, title, src, meta)

        out = a.out or (os.path.splitext(video)[0] + ".watch.md"
                        if not is_url else os.path.join(os.getcwd(), "video-watch-output.md"))
        with open(out, "w") as f:
            f.write(md)
        print(f"✓ wrote {out}  ({len(frames)} keyframes, reader={a.reader})")

        if a.json:
            jout = os.path.splitext(out)[0] + ".json"
            with open(jout, "w") as f:
                json.dump({"source": src, "reader": a.reader, "duration": dur,
                           "blocks": blocks}, f, indent=2)
            print(f"✓ wrote {jout}")

        if a.keep_frames:
            print(f"  frames kept in: {os.path.join(workdir, 'frames')}")

    finally:
        if cleanup and os.path.isdir(workdir):
            shutil.rmtree(workdir, ignore_errors=True)


def emit_manifest(frames, segments, workdir, a, verbose):
    """Manifest mode: write the deduped frame list + a ready-to-run caption
    prompt so an interactive Claude session can act as the vision reader."""
    manifest = [{"index": i, "time": f["time"], "path": f["path"]} for i, f in enumerate(frames)]
    mpath = os.path.join(os.getcwd(), "video-watch-manifest.json")
    with open(mpath, "w") as f:
        json.dump({"frames": manifest, "segments": segments}, f, indent=2)
    ppath = os.path.join(os.getcwd(), "video-watch-caption-prompt.txt")
    with open(ppath, "w") as f:
        f.write(build_caption_prompt(manifest, segments))
    print(f"  manifest mode → {mpath}\n  caption prompt → {ppath}")
    print("  (an interactive session Reads each frame path and returns the JSON;")
    print("   or re-run with --caption-mode headless to invoke `claude -p`.)")
    log("manifest emitted; screen captions deferred to interactive reader", verbose=verbose)


if __name__ == "__main__":
    main()
