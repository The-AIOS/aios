---
name: motion-lab
description: 'Use when making motion that will be rendered to video or GIF — starting from a one-line ask like "make me a 3D animation of X": it first interviews the operator element by element (goal, story, time, hero move, look, camera, motion, banned, engine, QA, output), each with a recommended answer, then renders. For a loop, a logo sting, a title card, a product shot, a launch film, an explainer film, a deck component exported for social. Code-drawn motion where every frame is a pure function of t: the render contract, the eleven-line directed brief (the same elements the interview proposes), the numbers (easing, springs as damping ratio, stagger, beat grid, holds), and the render → look → fix loop run on hooks/media/motion-render.py and hooks/media/motion-check.py. NOT for reading someone else''s video (watch-video) and NOT for live UI motion inside a product.'
---

# Motion Lab

**Direction is numbers, and review is measurement.** Every adjective left in a brief is a decision handed back to the model's default look; every check left to "watching it" is a check that does not happen, because the model sees only the frames it is shown and cannot hear. Measured in public: the same model given 27 words of adjectives and 448 words of numbers for the same subject came back with its stock look for the first and the brief for the second.

The engine is plain: **one self-contained HTML file whose every frame is a pure function of t**, frozen frame by frame in a headless browser (`hooks/media/motion-render.py`), checked by instruments (`hooks/media/motion-check.py`), stitched by ffmpeg. Frames are reproducible, an edit is one number and a re-render, and the model can look at its own work.

## The bar, by default

**Every piece aims at the house bar unless the operator says otherwise**, and a lower bar is written into the brief by name (*"rough draft, one round"*), never drifted into. The bar, as things that can be checked:

- **The subject floats on a dark ground.** No floor plane, no lit sweep, no grey table, unless asked: a lit surface turns the whole frame to mid-tone and nothing reads as the hero. `framing` fails it.
- **Nothing touches the frame edge** (3% safe margin), and **the hero fills at least a third of the frame height** at its beat. `framing` measures the margins; the hero's own share is a number the page reports through `__probe` (in 3D, the `screenHeight` helper in `references/three-d.md`; flat, the element's box height over the frame height) and `assert` checks.
- **Frame the event, not the inventory.** It applies to **every** beat, not only the payoff: the tap, the swap, the click is an event too, so the camera comes in on it (or the layout brings the actors close and large) and goes back out after. At each beat the frame is about what that beat is about: what acts is large, the rest is out of frame, dimmed or behind. A row of objects front-on across a wide empty frame reads as a catalogue shot, and the event happens too small to see. In 3D, a three-quarter view (15–35° off front) with the objects at different depths; flat, the same idea as scale and contrast (the active word bright and large, the rest receding).
- **The camera moves on purpose** (3D): one named move (a push-in, a short orbit), eased in-out, never locked off by accident. In a loop the move is a closed path: it breathes in and out, or orbits back to where it began. Flat pieces may hold still; their motion is in the type and shapes.
- **Objects are built with detail on every surface the camera sees** (in 3D, to real proportions in metres): a screen shows a real interface state, a product has its parts. A cylinder with a blob on top is a placeholder, not a piece. Flat: real type (a set family and weight, kerned), never a default system label.
- **Every move lands**: from rest, a move starts in-out or on a spring; ease-out only for something already moving. `speed` fails a corner.
- **Every check is green**, and the receipts say which ones did not apply.

## Who calls this

The **GOAL belongs to the caller**: `explainer` (rung 3: the reader understands one step), a launch (the viewer wants the product), a deck (`animation-composer`, for a component exported as a clip). Take the GOAL from them. A standalone piece with no caller (a sting, a loop) has the operator as its caller: ask for the GOAL.

> **Promotion rule.** If this skill is loaded three times for standalone pieces with no explainer, launch or deck purpose, the orphan domain is real: propose a `motion-designer` agent that owns `03 - export/motion/` and the house contract. Until then, no agent.

## Step 0 — interview for the brief (always, for any short ask)

A one-line ask (*"make me a 3D animation of X"*) is never rendered as given: the model fills every gap with its default look. **Your first reply is the whole brief, proposed**: eleven elements, each with a recommended answer derived from the session's context (the purpose, the venture's `design.md`, the house contract and BANNED list) and a few words of why. Mark as questions only what the operator alone can answer: usually the goal, the story beats, and anything about their brand or claims (a logo, a price, a figure). Keep it to about three questions in all, whichever elements they sit in; everything else is a recommendation they can wave through. They answer once ("yes", or edits by element); read the final brief back; render nothing before a yes. Save it as `{slug}.brief.md`. How to recommend each element, and what a finished brief looks like: **`references/brief-interview.md`** and **`references/example-brief.md`**. Nobody present → use the recommendations and mark each one `assumed` in the receipts.

## Before the first frame

1. **The brief from Step 0 is the eleven-line template** (`references/prompt-template.md`), same elements, same order. **GOAL first**, one sentence: what the viewer should feel or do. If nobody can say it, stop and ask; no easing curve rescues a missing GOAL. **TIME second**: every other number hangs off the frame count. One hero move per shot.
2. **Append the house contract and BANNED list.** They live in the vault at `03 - export/motion/_contract.md`; if it does not exist, seed it from `references/contract.md`. Working outside a vault, or told not to touch it: seed `_contract.md` beside the piece, add your new lines to it, and list them in the receipts too so they can be carried into the house copy. The contract is the lab's memory: every line is a failure you no longer have to see.
3. **Pick the engine by the rule.** One idea under 10 s → plain HTML + canvas/SVG/CSS. Anything 3D → Three.js, pinned to a version, built from **`references/three-d.md`** (the plumbing, lights, objects without models, text on screens, and the faults the first contact sheet shows). Name it in OUTPUT with its numbers. Take numbers from `references/numbers.md`, never adjectives.
4. **Start from the example**, `examples/loop-6s.html`: it already has `__duration`, `__fps`, a closed-form spring, a seeded PRNG, `renderAt(t)`, `__probe(t)` and `?t=`.

## The loop

```bash
R(){ python3 "$HOME/aios/hooks/media/motion-render.py" "$@"; }   # functions, not strings: zsh does not
C(){ python3 "$HOME/aios/hooks/media/motion-check.py" "$@"; }    # word-split "$R", and ~ does not expand in quotes
C contract piece.html                                     # lint against the contract first
R frames piece.html --out frames --frames 0,120,240,360   # stills at YOUR beat frames (these are an example)
R frames piece.html --out frames --all                    # then every frame (a loop renders 0..N-1)
R sheet frames --out sheet.png                            # 12 frames on one page: READ it
C seam frames                                             # loops only: the cut back to frame 0 (a piece that ends: N/A)
C pops frames                                             # one-frame glitches
C framing frames                                          # safe margins, ground stays ground, hero height
C determinism piece.html --frames 0,120,360              # your beat frames, all < N: same frame twice, same pixels?
C assert piece.html checks.json                           # the brief's numbers, against __probe(t):
                                                          # [{"frame":330,"expr":"p.ring","expect":1,"tol":0.001},
                                                          #  {"frame":599,"expr":"p.x - at(0).x","expect":0,"tol":0.001}]
R onion frames --range 80:92 --out onion.png              # things that TRAVEL: spacing should tighten near the keys
                                                          # (a look: write "tightens: yes/no"; for growth in place, read speed.csv)
R speed piece.html --out speed.png                        # FAILs on a corner (a launch from rest, a stop); lives in
                                                          # motion-render because it renders, but it is a check
R export frames --out piece.mp4 [--audio score.wav] [--gif piece.gif --gif-fps 24]
C audio piece.mp4 --events hits.json                      # loudness, true peak, hits 1 frame late
C audio piece.mp4 --silent                                # a silent brief: prints N/A; FAILs if sound slipped in
```

**Look, then write notes that name frames** ("at f84 the ring overshoots past 1.08"), one or two per round; fix; re-render only what changed. Turn feelings into numbers before acting ("make it pop" → scale 1.0 → 1.08 → 1.0 over 6 frames, peak on the beat). Give notes as the problem plus the result you want, not the fix. **Two to four rounds is normal; report the count.**

Sizes default to **1920×1080**. A **square cut is a second render with its own layout** (the page reads `?aspect=1` and moves the camera and, where needed, the objects), never a crop of the wide one: a crop cuts the subject and breaks the margins. Pass the page as a URL to every tool that renders (`R frames "file://$PWD/piece.html?aspect=1" --size 1080x1080 …`, the same for `determinism`, `assert` and `speed`), give `assert` its own `checks-square.json` where positions differ, and run `framing` on its frames. `contract` lints the file once.

**A loop for social is seamless**: whole cycles, frames 0..N−1, and `seam` must pass. "Social", "feed", "autoplay" in the ask mean a loop unless the operator says it ends. **A story still has its payoff in a loop:** give it a hold (≥ 1 s) and then a **reset beat** (1–1.5 s) that returns every value to frame 0's, on springs, with the camera closing its path. Assert that frame N−1 and frame 0 probe the same values (`at(0)`), **within a tolerance of 0.001**: a spring approaches its target and never reaches it exactly, so an exact-equality assert fails on a piece that is visually at rest. `seam` passing alone cannot tell a reset from a frozen ending.

**Sound is last**, scored from frame numbers (each hit one frame after its picture), synthesized or from licensed files, and checked by `audio`, never by "listening": the model cannot hear.

**Every check says PASS or FAIL with its numbers.** A check that could not run exits 2 and says why; never report it as passed. A check that does not apply (no `audio` on a silent piece, no `seam` on a piece that ends) is reported as **N/A, with the reason**, never as PASS.

## After

- **When a fix works, append its line to the house contract.** When the first render used a default you did not want, add it to BANNED **by name**.
- **Ship the receipts:** the prompt and every follow-up go beside the piece as `{slug}.receipts.md`, with the round count and the final check output.
- **Where it lands** (CLAUDE.md § File Placement Router): audience-facing pieces in `03 - export/motion/` (or the venture's export folder); frames and scratch renders in a temp directory, never the vault. Under a sandboxed shell, `$TMPDIR` can name a different folder inside and outside the sandbox: pick one absolute path for the frames and use it in every command.

## References

- `references/contract.md` — the render contract + the fixes table (seed of the house contract)
- `references/numbers.md` — easings, the closed-form spring, damping ratios, durations, stagger, beat grid, holds, accessibility limits, loudness targets
- `references/brief-interview.md` — Step 0: turning a one-line ask into a full brief with the operator, with a worked exchange
- `references/example-brief.md` — a finished brief for a fictional product, at the level of detail to aim for
- `references/three-d.md` — Three.js that renders deterministically: plumbing, lights, objects, text, first faults
- `references/prompt-template.md` — the eleven-line brief, how to fill it, a worked example
- `references/launch-film.md` — what is specific to a product launch film
- `references/explainer-film.md` — the silent, captioned film rung of `explainer`
