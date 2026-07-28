---
name: watch-video
description: >-
  Actually watch or listen to a video/audio source and hold it in context so you can answer questions about it,
  summarise it, pull quotes, or act on what it says — a QUICK COMPREHENSION action, not a filing pipeline.
  Covers the local media hooks Claude cannot otherwise discover: hooks/transcribe.py (long-form audio → text,
  on-device) and hooks/video-watch.py (the VISUAL channel — slides, code, diagrams, terminal, on-screen text
  that a transcript throws away). Use when the operator shares a video, recording, talk, screencast, demo,
  lecture, meeting capture or YouTube URL and wants you to engage with its CONTENT — "watch this", "what does
  this video say", "does he mention X", "summarise this talk", "is this worth my time", "listen to this
  recording", "transcribe this", "what's on the slides", "pull the code from this screencast". Also the
  reference for which tool to reach for: documents → MarkItDown or the document-skills · long audio →
  transcribe.py · video where the SCREEN carries signal → video-watch.py on top of the transcript. NOT for
  filing a source into the vault as a permanent note — that is /aios:ingest, and this skill hands off to it
  rather than duplicating it.
---

# Watch a video — comprehension, not ingestion

Someone shares a video and asks you about it. Two hooks make that possible, and **neither is discoverable on its own** — hooks have no semantic match, so a session asked to "watch this" finds nothing and improvises. That gap is the whole reason this skill exists.

## The boundary — read this first

> **This skill WATCHES. It does not FILE.** Its output is *understanding held in the session*, not a vault artifact. No note, no frontmatter, no cross-links, no `_index` update, no action-item routing. Working files go to a scratch path (`/tmp`), never to `vault/`.
>
> **`/aios:ingest` is the filing pipeline** — it exists precisely so that turning a source into a permanent, wired-up vault note is a deliberate act with conventions. If the operator wants that, **hand off** (*"want me to `/aios:ingest` this so it lands in `reflections/ingests/` with the cross-links?"*) — do not half-implement it here. Two paths, one boundary, no overlap.

So the shape of a run is: **get it into context → do what was asked → offer, don't assume.** If the ask was open-ended (*"watch this"* with no question), watch it, then say what it is in two or three lines and ask what they want from it. Don't manufacture a deliverable nobody requested.

## Which tool — the actual decision

| The source | Reach for | Why |
|---|---|---|
| Document (PDF, docx, deck, sheet) | MarkItDown or the `document-skills` | Not this skill's job; those already match semantically |
| **Long audio/video, audio is enough** | `hooks/transcribe.py` | MarkItDown single-shots audio to Google Web Speech — fine for a sentence, useless for a 49-minute interview |
| **YouTube, audio is enough** | MarkItDown captions **first** | Far faster than transcribing; fall back to `transcribe.py` when captions are absent or garbage |
| **The SCREEN carries signal** | `hooks/video-watch.py` **on top of** the transcript | A transcript discards every frame: slides, code, diagrams, terminal, charts, on-screen text |

**The screen carries signal when** the source is a talk with slides, a screencast, a code walkthrough, a tool demo, a lecture with diagrams, or anything where *"as you can see here"* would leave you blind. When in doubt, ask — the visual pass costs real time.

### The commands

```bash
# transcript spine (on-device: ffmpeg → mlx-whisper large-v3-turbo, arbitrary length)
python3 ~/aios/hooks/transcribe.py <file-or-URL> /tmp/watch-transcript.txt

# visual channel, layered on the transcript — NEVER instead of it
python3 ~/aios/hooks/video-watch.py <file-or-URL> \
  --transcript /tmp/watch-transcript.txt --reader ocr --code
```

**Reader choice is the one real flag decision:**
- `--reader ocr` — verbatim on-screen text via Apple Vision. **Default for slides, code, terminals, anything you need to quote exactly.** Add `--code` when frames contain code.
- `--reader vlm` — Claude vision *describes* each frame. For diagrams, charts, architecture, UI — structure over literal text.
- `--reader both` — when you need the exact words *and* what the picture means. Roughly doubles the per-frame cost.

Everything else (`--scene-threshold`, `--max-frames`, `--sample-every`, `--max-width`, `--phash-threshold`) has a sane default. Touch them only when the first pass is visibly too sparse or too noisy; `--help` lists them.

## Platform reality — state it, don't hit it

Both hooks are **macOS / Apple Silicon** (`mlx-whisper`, Apple Vision via `hooks/ocr-image.swift`). On Linux or Windows, say so and fall back to **MarkItDown**, which handles YouTube captions and short audio cross-platform. Don't let an operator watch a command fail to learn this.

## Set expectations before you burn the time

Transcribing a long recording and reading its frames is **minutes, not seconds** — a 45-minute talk with a visual pass is the heaviest thing in this skill. Say the estimate up front and confirm, especially for the visual pass. Two cheap moves that usually beat brute force:

- **Transcript first, always.** It's the semantic spine, it's faster, and it often answers the question outright — at which point the visual pass is unnecessary.
- **If the ask is narrow** (*"does she mention pricing?"*), search the transcript rather than reading the whole thing back.

## Failure modes worth knowing

- **A transcript is not the video.** If the operator asks about something *shown*, a clean transcript that never mentions it is not evidence of absence — it's the wrong instrument. Run the visual pass or say you can't answer yet.
- **YouTube captions can be auto-generated and wrong** (names, jargon, numbers). If a quote matters, verify against `transcribe.py` before attributing it.
- **Don't quote what you didn't read.** Frames are sampled on scene-change and de-duplicated, so the visual pass is a *sample*, not a full record. If a claim rests on one frame, say which timestamp it came from.
- **Scratch files are scratch.** Clean up `/tmp/watch-*` when done, or say where you left them. Never write them into `vault/`.

## Handing off

When the material turns out to be worth keeping:

- **File it properly** → `/aios:ingest` (lands in `reflections/ingests/`, `{source}-{slug}` naming, frontmatter, cross-links, action items routed to project to-dos).
- **It changed a project's state** → say so and offer to update that project note.
- **It produced a durable insight** → that belongs in the vault via the normal close-session path, not as a side effect of watching something.

Watching is cheap and repeatable. Filing is a decision. Keep them separate.
