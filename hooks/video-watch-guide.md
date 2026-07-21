---
title: "Adding Video Comprehension to AIOS — a build guide"
audience: AIOS operators (framework-level)
status: shareable
date: 2026-06-20
tags: [aios-infra, video, multimodal, guide, export]
---

# Adding Video Comprehension to AIOS

> **What this gives you:** the ability for AIOS to actually *watch* a video — read the slides, diagrams, code, and on-screen text — not just transcribe the audio. Self-contained guide; copy the one script and you have it.

---

## 1. The problem it solves

AIOS bundles Microsoft's **markitdown** (`hooks/markitdown-convert.py`) to turn any file into Markdown. But markitdown is **blind to the screen**:

- An `.mp4` is routed to the *audio* converter → `exiftool` metadata + speech-to-text. **Every frame is discarded.**
- The YouTube path scrapes page metadata + the existing transcript. **No frames.**
- Images *can* be captioned, but only with an `llm_client` configured — the AIOS wrapper calls bare `MarkItDown()`, so even still images get only metadata.

Net: anything *shown* — slides, diagrams, code, charts, on-screen labels, demonstrations — is invisible to AIOS. The transcript is half the signal; the screen is the other half. This adds the missing half.

## 2. The architecture (and why)

We surveyed how practitioners actually solve this in 2026 (native video models · frame-sampling/scene-detection · frame→VLM captioning · OCR-on-frames · audio-visual fusion · cost). The durable answer the community ships is **a frame pipeline you control**, not handing the raw video to a native model — because native video models (Gemini etc.) sample ~1 fps and **reliably miss/merge/hallucinate dense on-screen text and code**, while the *same frames sent as still images read correctly*.

The key design insight: the "describe the screen" engine and the "transcribe the screen verbatim" engine are **the same pipeline with a different per-frame reader**. So:

```
input (file | YouTube URL)
  ① transcript pass FIRST   → the semantic spine (two-pass anchor — reduces temporal hallucination)
  ② ffmpeg scene-keyframes  → candidate frames (cap 720p, scene-change select)
  ③ phash dedup             → drop near-duplicate slides (pure pillow — biggest cost lever)
  ④ per-frame READER ◄── pluggable
        vlm  = describe (Claude vision via `claude -p`)   → diagrams, structure, layout
        ocr  = transcribe verbatim (Apple Vision)         → code, tables, exact strings
        both = caption + verbatim
  ⑤ merge on a shared timeline → Markdown (+ optional JSON)

ALT FAST PATH (separate engine, stubbed): native one-shot (Gemini) — cheapest, lossy on text.
```

Three design decisions worth copying:

1. **Transcript first, then attach frames to the nearest spoken segment.** Reuse the transcript AIOS already produces; the audio is the spine, the screen annotates it. Cuts temporal hallucination.
2. **Two readers because they're complementary.** OCR gives you the *verbatim payload* (a slide's `6,000 GPUs · ~$2M · 1e24 FLOPS`); a VLM gives you the *structure* (the arrows that say "training = compression"). Neither subsumes the other.
3. **Frame control is cost control.** Scene-change selection + perceptual-hash dedup collapse a static lecture to a few dozen unique frames before you pay any vision tokens. A `--max-frames-per-min` ceiling caps the worst case.

## 3. Why it's dependency-light (and Fortress-clean)

Everything is already on a typical AIOS Mac — **no pip install** for the core:

| Step | Tool | Note |
|---|---|---|
| Download (YouTube) | `yt-dlp` | capped to 720p |
| Frame extraction | `ffmpeg` | `select='gt(scene,T)'` scene-change |
| Dedup | `pillow` | pure-pillow dHash, no opencv/imagehash |
| OCR reader | `swift` + Apple Vision | `hooks/ocr-image.swift`, on-device, **no network** |
| VLM reader | `claude` CLI | `claude -p`, subscription auth — **no `ANTHROPIC_API_KEY`** |
| Transcript (YouTube) | `youtube-transcript-api` | per-machine install on system python (often 3.9) |
| Transcript (local file) | `whisper.cpp` (`whisper-cli`) | on-device, free, Metal-fast; model in `~/.cache/aios/whisper/` |

Both readers and the transcriber are fully local (Fortress-clean) except the optional YouTube download. The VLM path rides the same `claude -p` rail the gmail/housekeeping routines already use, so it works headless in routines without an API key.

## 4. Install

1. Copy **`hooks/video-watch.py`** into your `~/aios/hooks/`.
2. Ensure **`hooks/ocr-image.swift`** supports `--no-correction` (the code-mode flag — disables Apple Vision autocorrect so it doesn't mangle `C001` → "cool"). If yours predates this, add a `noCorrection` arg that sets `req.usesLanguageCorrection = !noCorrection`.
3. Confirm the toolchain: `ffmpeg`, `yt-dlp`, `swift`, `claude`, and `pillow` (`python3 -c "import PIL"`).
4. **YouTube transcripts:** `youtube-transcript-api` on a system python (the script auto-finds an interpreter that has it).
5. **Local-file transcripts (whisper.cpp):** `brew install whisper-cpp`, then fetch a model once:
   ```bash
   mkdir -p ~/.cache/aios/whisper && cd ~/.cache/aios/whisper
   curl -L -o ggml-large-v3-turbo.bin \
     https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
   ```
   (~1.5GB, one-time, **per-machine** — it's not in git. Without it, local files degrade to visual-only; YouTube still works via captions. Override the model with `WHISPER_MODEL`.)

## 5. Use

```bash
python3 hooks/video-watch.py <file-or-youtube-url> [options]

  --reader vlm|ocr|both     per-frame reader (default vlm)
  --engine backbone|gemini  pipeline (default backbone; gemini = stub)
  --transcript PATH         reuse an existing transcript .md
  --no-transcript           visual-only
  --scene-threshold 0.3     LOWER = more frames (slides change little)
  --sample-every 90         periodic-floor seconds (static-video coverage; 0=off)
  --max-frames-per-min 6    per-minute ceiling
  --max-frames 300          absolute hard cap (announced loudly if it bites; 0=∞)
  --phash-threshold 6       dedup aggressiveness (the cost lever)
  --code                    OCR code mode (verbatim, no autocorrect)
  --caption-mode headless|manifest   default headless = one-shot `claude -p`
                            (complete output, no API key); manifest = emit
                            frames + a prompt for the calling session to read
  --json                    also emit a JSON timeline
```

**Routing by content type:**

| Your video is… | Use |
|---|---|
| Talking-head / tutorial where the screen complements speech | `--reader vlm` |
| Slide deck / code / terminal — text *is* the payload | `--reader ocr` (add `--code` for code) |
| Mixed (slides + live demo) | `--reader both` |
| Long, cost-sensitive, text not critical | `--engine gemini` (wire the stub first) |

## 6. Proof it works

On a 5-minute slice of a slide-heavy talk, the OCR reader pulled the slide's quantitative payload (`~10TB of text · 6,000 GPUs for 12 days, ~$2M · ~1e24 FLOPS · ~140GB`) at a timestamp where the **transcript said none of those numbers** — it was narrating a different point. The VLM reader on the same frame additionally recovered the diagram's *structure* (a left→right compression pipeline). That gap — screen carrying signal the audio doesn't — is precisely what markitdown throws away. The headless `claude -p` captioner returned the full diagram (arrows + every number) in ~15s with no API key; whisper.cpp transcribed the same clip locally in ~27s.

## 7. Hardening (worth copying)

This was reviewed with an **Inversion premortem** ("it's 6 months later and it broke — why?"). The fixes are baked in: external calls degrade gracefully on timeout/missing-binary (never crash); a **periodic-floor** sample guarantees coverage of static videos (dedup collapses the redundancy); three cost ceilings (dedup-first → per-minute → absolute `--max-frames`, with a loud log — never silent truncation); and periodic frames use exact `-ss` seeks so timestamps match content (a computed-timestamp bug that only surfaced under test would otherwise break audio-visual alignment — the whole point).

## 8. Extending it

- **Gemini native engine (#1).** Wire `read_gemini(video) -> blocks` behind `--engine gemini`. Use `media_resolution=low` + `fps<1` for static lectures; escalate to the backbone when verbatim text matters. Keep the same input→timeline interface so callers don't branch.
- **PySceneDetect.** v1 uses raw ffmpeg scene-select (zero heavy deps). Swap in PySceneDetect (`detect-adaptive`/`detect-hash`) if you need better motion/animation handling — it costs an `opencv-python` dependency.
- **4th engine — Video-RAG.** Index frames+captions in a vector store and retrieve per query, for "chat with a long video" rather than one-shot. Research-grade; add only when you have the retrieval use case.
- **Where it plugs in.** In this build it's wired into `/study:transcribe` (a "screen matters" row) and `/aios:ingest` (a "watch this video" route). Same pattern works for any command that already owns a transcript.

## 9. Caveats (from the research)

- The "frame+OCR beats native on text" finding is strongly suggested by practitioner reports (screenshots succeed where the video path fails) but not a single rigorous public head-to-head — validate on your own content.
- Native-model pricing/limits move monthly; treat any $/hour figure as order-of-magnitude.
- OCR language correction corrupts code/serials — keep `--code` for those.

---

*Built for AIOS, 2026-06-20. Companion to the operator's project note `infra-video-comprehension`. The capability is one script (`hooks/video-watch.py`) plus the Apple Vision OCR helper.*
