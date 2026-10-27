---
name: aios-avatar
description: >-
  Make the operator an AIOS avatar: the AIOS ant (the logo is its head) wearing a hat for what they do, or
  their initial behind it, ready to upload as a Discord or other profile picture. The seeds, the agent-to-hat
  map and a generator live at https://www.the-aios.com/avatar-seeds, so the result matches the community set.
  Use when the operator says "make me my AIOS avatar", "AIOS profile picture", "give me an ant avatar",
  "avatar for the Discord", "change my hat", or asks for a version of an existing AIOS avatar in another
  colour or with a new hat. NOT for logos, brand marks or slides (the ant is a community avatar, not a
  brand asset to restyle).
---

# Make an AIOS avatar

The AIOS ant is the logo with antennae. A member's avatar is that ant with **one** thing that is theirs: a hat for what they do, or their initial behind it. Everything stays in one visual family, so a member list reads as a colony, not a pile of unrelated pictures. The whole set is public and free, and so is anything this skill makes.

## Where everything is

- Gallery and copy-paste prompt: `https://www.the-aios.com/avatar-seeds`
- `https://www.the-aios.com/avatar-seeds/manifest.json`: every bundled agent with its hat, its bundle colour and a ready PNG; the named initial palette; the default colour for a new hat; the rules.
- `https://www.the-aios.com/avatar-seeds/generator.py`: renders an agent's hat, a hat by name, a new custom hat, or an initial. Every render also writes a 40 px preview (`*-40.png`), and every hat render is checked against Discord's circle crop. Needs `pymupdf` and `pillow`. Initials download the JetBrains Mono font (OFL) from github.com on first use if it is not installed.

Fetch the manifest and the generator into a fresh temp folder before using them. Read the generator's docstring: it is the spec for a new hat. For scale, open one existing hat SVG from `hats/` before drawing.

## The flow

1. **Ask one question:** a hat for what you do, or your initial? Do not ask for colours, styles or sizes up front.
2. **Hat:**
   - Map what they do onto the closest agent in `manifest.json` (a lawyer → `lawyer`, a founder → `technical-cofounder`'s crown, a writer → `content-writer`). Say which one you chose, and why, in one line.
   - **Two or more roles:** a hat carries one. Pick the one they named first or seem proudest of, say which, and offer the other as a second avatar. Do not merge two hats into one.
   - A close match is the default. Draw a new hat only when nothing in the manifest fits what they told you.
   - **A new hat** follows the docstring exactly: drawn in the hat box, `fill="#fff"` for the hat, `BG` for cut-out details, flat shapes only. Render it with `generator.py hat --hat-svg <file> --name <role> --colour <hex>`. If it prints a circle-crop warning, make the hat smaller and render again. Never hand over a warned render.
   - Colour: an existing hat uses its agent's bundle colour. A new hat uses the bundle colour of the agent closest to the work, or slate `#334155` if none is close (`new_hat_colour` in the manifest). Offer a change only if they ask.
3. **Initial:** use the first letter of the name they go by. The palette in the manifest is named (gold, blue, pink, slate…), so map a wish like "something pink-ish" to a name; if they gave no wish, pick one and say they can change it. Render with `generator.py initial <LETTER> --colour <hex>`. Initials have fixed, crop-safe geometry, so there is no circle check to run.
4. **Look before you hand it over.** Open the PNG and its `-40.png` preview. If the hat does not read at 40 px, simplify it and render again.
5. **Deliver:** save the PNG to their Downloads folder and give the absolute path. Then one line on where it goes, for example in Discord: *User Settings → Edit Profiles → avatar → Upload Image*. You cannot set a profile picture for them; they upload it.

## Rules that keep the family together

- **Coral `#ff5d4d` is kept for the AIOS team.** Do not give it to a member's hat or initial, even on request; offer the nearest palette colour.
- One flat background colour, a white ant, a white hat. No text, gradients, faces, photos or extra colours.
- Never reshape the head or the antennae. The ant is the constant; only the hat or the letter changes.
- Nothing is exclusive. If an operator wants a one-of-a-kind hat, make it, and tell them anyone may make the same.

## If the site is unreachable

Say so, and offer to retry later. Do not reconstruct the generator from memory: an ant drawn freehand drifts from the set, and the drift is the thing this skill exists to prevent.
