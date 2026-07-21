#!/usr/bin/env python3
"""
transcribe.py — local audio/video → text transcription (custom hook, Chuy-only).

A self-contained sibling to hooks/markitdown-convert.py. markitdown handles
DOCUMENTS; this handles MEDIA. markitdown's audio path is unusable for long-form
(its deps aren't installed, and even equipped it single-shots the whole file to
Google's Web Speech API — fine for a sentence, useless for a 49-min interview).

This does the path that actually works on Apple Silicon:
    download (if URL) → ffmpeg extract to 16kHz mono → mlx-whisper (large-v3-turbo)

Why mlx-whisper: fast on Apple Silicon, arbitrary length, high accuracy on
names/jargon, fully local (no third party, no rate limit).

**Platform: macOS/Apple-Silicon only (mlx).** This is a bundled *macOS enhancement*
to /aios:ingest — the command's routing calls it only on macOS, and MarkItDown
remains the cross-platform default for every format (including YouTube captions
and short audio). On non-Mac, MarkItDown handles transcription (the long-form
local-audio gap is MarkItDown's own, unchanged); a cross-platform build would
swap mlx-whisper for faster-whisper (CPU/CUDA) — not yet wired. The script
self-checks its deps and exits with a clear install hint if mlx is absent, so a
mis-route on non-Mac fails loudly, never silently.

Usage:
    python3 hooks/custom/transcribe.py <input> [output.txt]
    python3 hooks/custom/transcribe.py video.mp4                 # → stdout
    python3 hooks/custom/transcribe.py video.mp4 out.txt         # → file
    python3 hooks/custom/transcribe.py "https://.../clip.mp4"    # URL → stdout
    python3 hooks/custom/transcribe.py pod.mp3 --language es

<input> may be a local media file (mp4/mov/webm/mkv/m4a/mp3/wav/...) OR a direct
media URL (it will be downloaded first). Note: a tweet/article PAGE url won't
work — pass the direct media file URL (e.g. video.twimg.com/.../*.mp4); the
page itself often 402s/blocks.

Requires: ffmpeg on PATH + mlx-whisper in the hooks venv
(`~/aios/hooks/.venv/bin/mlx_whisper`; install once with
`~/aios/hooks/.venv/bin/pip install mlx-whisper`).
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

DEFAULT_MODEL = "mlx-community/whisper-large-v3-turbo"
HOOKS_DIR = os.path.dirname(os.path.abspath(__file__))  # this file lives in hooks/ (canonical); venv is hooks/.venv
VENV_DIR = os.path.join(HOOKS_DIR, ".venv")
MLX_WHISPER_BIN = os.path.join(VENV_DIR, "bin", "mlx_whisper")


def _die(msg):
    print(f"transcribe.py: {msg}", file=sys.stderr)
    sys.exit(1)


def _check_deps():
    if shutil.which("ffmpeg") is None:
        _die("ffmpeg not found on PATH. Install with `brew install ffmpeg`.")
    if not os.path.exists(MLX_WHISPER_BIN):
        _die(
            "mlx-whisper not found in the hooks venv. Install once with:\n"
            f"    {os.path.join(VENV_DIR, 'bin', 'pip')} install mlx-whisper"
        )


def _download(url, dest_dir):
    """Download a direct media URL to a local file via curl."""
    dest = os.path.join(dest_dir, "source_media")
    print(f"transcribe.py: downloading {url} ...", file=sys.stderr)
    rc = subprocess.run(
        ["curl", "-sL", "-A", "Mozilla/5.0", url, "-o", dest]
    ).returncode
    if rc != 0 or not os.path.exists(dest) or os.path.getsize(dest) == 0:
        _die(f"download failed for {url} (curl rc={rc}). Pass a direct media URL, not a page URL.")
    return dest


def _extract_audio(src, dest_dir):
    """Normalize any audio/video to 16kHz mono mp3 (whisper-native, small)."""
    audio = os.path.join(dest_dir, "audio.mp3")
    print("transcribe.py: extracting audio (ffmpeg, 16kHz mono) ...", file=sys.stderr)
    rc = subprocess.run(
        ["ffmpeg", "-y", "-i", src, "-vn", "-ac", "1", "-ar", "16000",
         "-c:a", "libmp3lame", "-q:a", "5", audio],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode
    if rc != 0 or not os.path.exists(audio):
        _die("ffmpeg failed to extract audio. Is the input a valid media file?")
    return audio


def _transcribe(audio, dest_dir, model, language):
    """Run mlx-whisper. --condition-on-previous-text False is mandatory: without
    it the decoder falls into a repetition loop on trailing silence/outro and
    drops the back half of the file."""
    print(f"transcribe.py: transcribing with {model} (this can take a few min) ...", file=sys.stderr)
    cmd = [
        MLX_WHISPER_BIN, "--model", model,
        "--condition-on-previous-text", "False",
        "--output-format", "txt", "--output-name", "transcript",
        "--output-dir", dest_dir, "--verbose", "False",
    ]
    if language:
        cmd += ["--language", language]
    cmd.append(audio)
    # Send mlx-whisper's own stdout to stderr so this script's stdout carries
    # ONLY the transcript (the result is read from the .txt file below).
    rc = subprocess.run(cmd, stdout=sys.stderr).returncode
    out_txt = os.path.join(dest_dir, "transcript.txt")
    if rc != 0 or not os.path.exists(out_txt):
        _die(f"mlx-whisper failed (rc={rc}).")
    with open(out_txt, "r") as f:
        return f.read()


def main():
    ap = argparse.ArgumentParser(
        description="Local audio/video → text (ffmpeg + mlx-whisper). Mac-only, Chuy custom hook.",
    )
    ap.add_argument("input", help="media file path OR direct media URL")
    ap.add_argument("output", nargs="?", default=None, help="output .txt path (omit → stdout)")
    ap.add_argument("--language", default=None, help="language code (e.g. en, es). Omit → auto-detect.")
    ap.add_argument("--model", default=DEFAULT_MODEL, help=f"mlx-whisper model (default: {DEFAULT_MODEL})")
    ap.add_argument("--keep-audio", action="store_true", help="don't delete the extracted audio (debug)")
    args = ap.parse_args()

    _check_deps()
    work = tempfile.mkdtemp(prefix="transcribe-")
    try:
        src = args.input
        if src.startswith("http://") or src.startswith("https://"):
            src = _download(src, work)
        elif not os.path.exists(src):
            _die(f"input not found: {src}")
        audio = _extract_audio(src, work)
        text = _transcribe(audio, work, args.model, args.language)
        if args.keep_audio:
            kept = os.path.join(os.getcwd(), "transcribe-audio.mp3")
            shutil.copy(audio, kept)
            print(f"transcribe.py: kept audio at {kept}", file=sys.stderr)
        if args.output:
            with open(args.output, "w") as f:
                f.write(text)
            print(f"transcribe.py: {args.input} → {args.output} ({len(text.split())} words)", file=sys.stderr)
        else:
            sys.stdout.write(text)
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
