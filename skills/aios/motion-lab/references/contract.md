# The render contract

Paste these lines under every motion prompt. `hooks/media/motion-check.py contract` lints a page against the
rules 1–6 (and that the page exposes `renderAt`); rule 7 is checked by `seam`.

1. **One self-contained file.** HTML, CSS and JS inline; assets as data URIs or files beside it.
2. **Only pinned libraries**, from a known CDN, with an exact version in the URL (`three@0.160.0`).
3. **No network** at render time except web fonts and those libraries. No `fetch`, no XHR, no sockets.
4. **Every frame is a pure function of t.** Rendering frame 84 alone gives the same pixels as reaching it
   from frame 0.
5. **`window.renderAt(t)`** draws the frame at t seconds if JS drives any motion. CSS animations are
   frozen through `document.getAnimations()`; JS animation is not, unless it reads t.
6. **No clock, no timers, no unseeded randomness.** No `Date.now`, `performance.now`, `setTimeout`,
   `setInterval`, `requestAnimationFrame` loops, or bare `Math.random`. Use a seeded PRNG.
7. **Loops render frames 0..N−1 only**, and frame N is frame 0: rendering both puts a stutter at the
   seam. A cyclic loop is built from `phase = frame / N` with whole cycles; a **story loop** (beats,
   then a reset beat) instead returns every value to frame 0's by its last frame, asserted with
   `at(0)` within a tolerance.

Also expose, when they apply: `window.__duration` and `window.__fps` (so the renderer needs no flags),
`window.__ready` (set when assets are loaded), `window.__probe(t)` returning the numbers the brief sets
(scale, position, opacity) so `assert` and `speed` can read them, and `?t=` in the URL to freeze any frame
in a normal browser.

**Opened directly, it must not look blank.** With no `?t=`, the page renders its **hero frame** (the resolved hold, or the most telling moment of a loop), never frame 0 of a piece that opens on an empty ground. Someone double-clicking the file sees the piece, not a black page; the renderer always sets t itself, so this changes no frame it captures.

## BANNED (seed)

Defaults a model reaches for when nothing stops it. Paste the list under every prompt; the house copy
grows by name each time a render surprises you.

- a floor plane, a lit sweep, a grey table under the subject (unless asked)
- a static camera in 3D when no one asked for one
- primitive stand-ins: a plain cylinder for a cup, a box for a phone, a blob for a lid
- particles, lens flares, glow halos, bokeh dust, light leaks
- a spinning turntable, a camera shake, a whip pan
- an invented logo, company name, tagline, price, statistic or claim
- real-world marks: the contactless-payment symbol, card-network or app-store marks, a recognisable phone's camera layout or a brand's product silhouette (generic enough: a single lens or a plain bump, no signature arrangement, no brand-specific button, notch or colour)
- a row of objects front-on across a wide empty frame (a catalogue shot)
- a square cut made by cropping the wide one
- an ease-out launched from rest, a move that stops instead of landing

## Fixes table (each line is a failure that will happen to you)

| Symptom | Cause | Fix |
|---|---|---|
| First frames blank or white | the browser had not painted yet | the renderer warms up until two shots agree; if a piece loads assets, set `__ready` after they load |
| Frame differs between renders | a clock, a timer or `Math.random` | contract rules 4 and 6; `determinism` finds it |
| Hiccup where the loop wraps | rendered frame N, or a cycle that is not whole | rule 7; `seam` finds it |
| One frame jumps | a branch at an exact t, an easing evaluated outside 0..1 | clamp; `pops` names the frame |
| Text reflows mid-shot | the web font arrived after frame 0 | the renderer waits for `document.fonts.ready`; preload fonts |
| GIF runs 4% slow | 41.67 ms delays rounded to 40 | export at 25 fps, or 24 fps with the 40/40/40/40/40/50 ms pattern (`export --gif-fps 24`) |
| Hits feel late | sound files peak after their start | measure with `audio --events`; shift each hit to land 1 frame after its picture |
| The frame reads as mid-grey mud | a lit floor or sweep fills the frame | float the subject on the dark ground; a contact shadow only; `framing` finds it |
| The subject is cut by the edge | the camera framed the hero beat, not the widest moment | frame the widest moment inside 3%; `framing` names the frame it found (it samples about 24 frames across the piece, so check your beat frames with `frames --frames` too) |
| A move looks like it jumps, then slows | an ease-out launched from rest | start in-out or on a spring; `speed` names the corner frame |
| The square cut loses half the subject | cropped from the wide render | a second render with its own layout (`?aspect=1`): camera and, where needed, object positions |
| The event is too small to see | the camera frames every object at once | frame the beat's actors; the rest out of frame or soft behind; assert the hero's share via `__probe` |

*Add a row every time a fix works. The house copy of this file is the one that grows.*
