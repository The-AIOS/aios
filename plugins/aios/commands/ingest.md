---
tags:
  - aios
  - command
  - on-demand
description: Process a source into the vault — extract, file, cross-reference, log
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, mcp__obsidian__read_note, mcp__obsidian__write_note, mcp__obsidian__patch_note, mcp__obsidian__search_notes, mcp__obsidian__list_directory, WebFetch, WebSearch
argument-hint: "<path-or-url-or-pasted-text>"
---

# /ingest — Process a Source Into the Vault

You are ingesting a new source into the vault. The source can be anything: an article, a PDF, a video transcript, a voice memo, meeting notes, a report, a Slack thread, a research paper, or a URL. Your job: read it, extract the key information, and integrate it into the existing vault — updating project notes, context files, reflections, and cross-references.

Read `USER.md` → `### /ingest` for command personalizations.

## When to use

When you find a source worth keeping — article, PDF, video transcript, voice memo, meeting notes, report, Slack thread, research paper, URL. The command reads it, extracts the key information, integrates it into the existing vault, and cross-references aggressively. A single source might touch 5-15 vault files — the bookkeeping is the LLM's job.


## The Principle

> "Instead of just retrieving from raw documents at query time, the LLM incrementally builds and maintains a persistent wiki. When you add a new source, the LLM doesn't just index it for later retrieval. It reads it, extracts the key information, and integrates it into the existing wiki — updating entity pages, revising topic summaries, noting where new data contradicts old claims." — Karpathy, LLM Wiki

A single source might touch 5-15 vault files. That's the point — the bookkeeping is the LLM's job.

## Steps

### 1. Receive the source

The user provides one of:
- A file path (any format — PDF, Word, Excel, PowerPoint, images, audio, EPUB, CSV, JSON, XML, ZIP)
- A URL (article, video, repo, YouTube)
- Pasted text (Slack thread, meeting notes, email)
- A reference ("ingest Karpathy's LLM Wiki post")

**File conversion (MarkItDown):**
For non-markdown files, convert first using the MarkItDown wrapper:
```bash
python3 ~/aios/hooks/markitdown-convert.py <input_file> /tmp/ingest-source.md
```
Then read the converted markdown. Supported formats: PDF, Word (.docx), Excel (.xlsx), PowerPoint (.pptx), images (with OCR), audio (with transcription), HTML, CSV, JSON, XML, ZIP, YouTube URLs, EPUB.

**Routing by source type:**
- URL → `WebFetch` to retrieve content
- PDF/Word/Excel/PowerPoint/EPUB → MarkItDown conversion → read markdown
- Image → MarkItDown (OCR + EXIF) → read markdown
- YouTube URL → MarkItDown (`_youtube_converter` — caption extraction, fast, cross-platform) → read markdown
- Short audio → MarkItDown (transcription) → read markdown
- **Long-form audio/video, or a video whose SCREEN carries signal** → see **Media enhancements** below
- Markdown/text → read directly
- Pasted text → process directly

**Media enhancements (macOS — optional local upgrades; MarkItDown stays the cross-platform default).**
MarkItDown is the universal converter and remains **primary for every format above** — documents, images, YouTube captions, and short audio all go through it, on every platform. Two *macOS-only* enhancements handle the exact two things MarkItDown can't; neither demotes it:

1. **Long-form transcription — `hooks/transcribe.py` (macOS · mlx-whisper).** MarkItDown's audio path single-shots the whole file to Google Web Speech — fine for a sentence, useless for a 49-min talk. **On macOS**, route *long-form* local audio/video through the local transcriber instead:
   ```bash
   python3 ~/aios/hooks/transcribe.py <media-file-or-direct-URL> /tmp/ingest-transcript.txt
   ```
   `ffmpeg → mlx-whisper (large-v3-turbo)`, on-device, arbitrary length, no third party. **YouTube still goes through MarkItDown captions first** (faster); fall back to `transcribe.py` only if captions yield nothing. **Non-macOS:** MarkItDown handles it — the long-form-local-audio gap is MarkItDown's own, unchanged (a `faster-whisper` cross-platform build is future work).

2. **Video screen-comprehension — `hooks/video-watch.py` (macOS · opt-in).** A transcript is audio-only — it discards everything *shown* (slides, code, diagrams, terminal, charts). When a video's on-screen content carries signal the narration doesn't, layer the frame reader **on top of** the transcript (from MarkItDown captions OR `transcribe.py`):
   ```bash
   python3 ~/aios/hooks/video-watch.py <file-or-URL> --transcript /tmp/ingest-transcript.txt --reader ocr --code
   ```
   `ffmpeg` scene-keyframes → pHash dedup → per-frame reader (`ocr` = verbatim via Apple Vision · `vlm` = structure via `claude -p` · `both`) → merged timeline. Ingest the **merged** Markdown instead of the transcript alone. Fortress-clean (on-device OCR + `claude -p`, no API key). **Opt-in** — trigger only when the request signals the screen matters (*"read the slides," "there's code on screen," "watch this tutorial"*) or the content is slide/code/whiteboard-heavy; a plain talking-head stays audio-only. **Non-macOS:** the `vlm` reader (`claude -p`) is cross-platform and works; the `ocr` reader needs Apple Vision — use `--reader vlm` off-Mac (the script says so + degrades, never crashes). Guide: `hooks/video-watch-guide.md`.

**Standalone MarkItDown usage (outside /ingest):**
```bash
# Convert any file to markdown
python3 hooks/markitdown-convert.py input.pdf                    # prints to stdout
python3 hooks/markitdown-convert.py input.pdf output.md          # saves to file
python3 hooks/markitdown-convert.py presentation.pptx slides.md  # PowerPoint → markdown
python3 hooks/markitdown-convert.py recording.mp3 transcript.md  # audio → transcript
```

### 2. Read and extract

Read the full source. Extract:
- **Key claims** — what does this source assert?
- **Entities** — people, companies, products, concepts mentioned
- **Actions** — anything the user should do, consider, or follow up on
- **Connections** — which existing vault projects, ventures, or context files relate?
- **Contradictions** — does anything here conflict with existing vault knowledge?

### 3. Discuss with the user

Before filing, present a brief summary:

```
## Ingest: {source title}

**Key takeaways:**
1. {takeaway}
2. {takeaway}
3. {takeaway}

**Vault connections I see:**
- [[project-name]] — {how it connects}
- [[context-file]] — {what to update}

**Contradictions flagged:**
- {existing claim} vs {new claim from source} — needs resolution

**Where I'd file this:**
- Summary → `00 - notes/reflections/ingests/{slug}.md`
- Action items → [[project-name]] to-dos
- Context update → `context/observed/{file}.md` (if pattern-level)

Proceed? Or redirect?
```

Wait for the user to confirm, redirect, or add context before filing.

### 4. File into the vault

After confirmation:

**a. Write the summary page**
- Default location: `00 - notes/reflections/ingests/{slug}.md` (for knowledge/research metabolized from external sources)
- Alternative: `00 - notes/ideas/{slug}.md` (for half-formed thoughts)
- Alternative: directly into a project note's session notes (for project-specific sources)
- Include frontmatter: `title`, `type: ingest`, `source`, `source-date`, `ingested-by`, `created`, `tags`
- Include a `## Source` section with link/path to the raw source
- Use `[[wiki-links]]` for all vault connections

**b. Update related project notes**
- For each connected project: add relevant to-dos, update session notes, or update status
- Follow the rule: update project note FIRST, then cascade to `_index.md`

**c. Update context files (if warranted)**
- Only update observed context if the source reveals a pattern (2+ sessions of evidence)
- Update `business.md` if it's a strategic insight about a venture
- Update `ecosystem.md` if it changes how ventures connect
- Snapshot before editing (mandatory per CLAUDE.md rules)

**d. Flag contradictions**
- If the source contradicts existing vault content, add a `> ⚠️ Contradiction:` callout in the relevant file
- Don't auto-resolve — flag for the user to decide

**e. Update indexes**
- Add the new reflection/idea to the relevant `_index.md`
- Update the reflections or ideas index

### 5. Log the ingest

Append to today's daily note (if it exists) or note for `/close-day`:

```
### Ingested: {source title}
- Source: {URL/path}
- Filed to: [[reflection-slug]] + {N} project notes updated
- Contradictions: {none / listed}
- Action items: {count} added to project notes
```

### 6. Optional — visual infographic

After logging, offer the user a one-page visual summary:

> Want a visual infographic of this ingest? A themed, self-contained HTML one-pager. → invokes `aios/infographic-builder`.

If accepted, invoke the **[`aios/infographic-builder`](../../../skills/aios/infographic-builder/SKILL.md)** skill against the reflection file just written. Default output: `03 - export/infographics/{YYYY-MM-DD}-{slug}.html`. The skill handles theme matching (brand-first → `awesome-design-md` fallback), IA distillation, and rendering — `/ingest` just makes the offer.

Skip silently if the user declines, or if the source is too thin to merit an infographic (single tweet, sub-page note, half-formed idea).

## Output

- **Summary page** at `00 - notes/reflections/ingests/{slug}.md` (or `00 - notes/ideas/{slug}.md` for half-formed thoughts, or directly into a project note for project-specific sources)
- **Updated project notes** with to-dos, session-note entries, or status updates based on connections found
- **Updated context files** (`business.md`, `ecosystem.md`, observed context) when warranted — pattern-level only
- **Contradictions flagged** as `> ⚠️ Contradiction:` callouts in the relevant files (don't auto-resolve — flag for user decision)
- **Updated `_index.md`** in the destination folder
- **Daily-note log entry** under "Ingested:" so the day's close-day picks it up
- **Optional infographic** (if the user accepts the Step-6 offer) — themed self-contained HTML at `03 - export/infographics/{YYYY-MM-DD}-{slug}.html`, via `aios/infographic-builder`


## Rules

- **Never modify raw sources.** The source is immutable. The vault pages are the LLM's layer.
- **Always discuss before filing.** Show the user what you extracted and where you'd put it. Don't silently update 15 files.
- **Cross-reference aggressively.** Use `[[wiki-links]]` everywhere. The connections between pages are as valuable as the pages themselves.
- **Flag contradictions, don't resolve them.** The user decides what's current.
- **One source at a time.** Stay involved per source. Batch ingestion is possible but the user should opt into it.
- **Update project notes first, then index.** Source of truth → derived artifact. Always. (Antifragile #12)
