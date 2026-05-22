---
tags:
  - template
  - meeting-prep
target: 03 - export/meetings/{YYYY-MM-DD}-{slug}-prep.md
created: '2026-04-23'
updated: '2026-05-09'
---

# Meeting Prep Template

> Copy this file, rename to `{YYYY-MM-DD}-{slug}-prep.md` (date = meeting date, slug = primary contact or company), move to `03 - export/meetings/`, and fill in placeholders. Delete unused sections — not every meeting needs every block.

## Naming convention
- **Date prefix** is the meeting date (not creation date) — so files sort chronologically when scanning "what's next."
- **Slug** is the primary contact or company in lowercase, hyphenated. Disambiguate when needed: `{firstname}-{company}`, `{firstname}-{org}`, `{lastname}-{event}`.
- **Type suffix** — `-prep` for this file. Optional siblings: `-notes.md` (during/after capture), `-followup.md` (if follow-up is a standalone artifact).

## When to use this template
- **Use it** — new prospect, high-stakes discovery, partner intro, forum/community pitch, investor call, board meeting where you need context that isn't in the daily note.
- **Don't use it** — routine team meetings, recurring syncs, quick pings. Those belong in the daily note's Calendar/Rhythm.

---

## Frontmatter to fill in

```yaml
---
tags:
  - meeting-prep
  - prospect              # or: partner / client / investor / speaking / internal
  - {domain-tags}         # e.g. consulting, {venture-name}, {community-name}
created: '{YYYY-MM-DD}'
meeting: '{YYYY-MM-DDTHH:MM:SS±HH:MM}'   # ISO 8601 with tz
duration: {N}min
attendee: {Full Name} — {Role}, {Company}
context: {one-line framing — who they are, why now}
call-link: {meet/zoom/tel URL}
---
```

---

# {Primary Attendee} / {Company} — Meeting Prep

**{Weekday YYYY-MM-DD HH:MM}–{HH:MM} {TZ}** · {duration} · [Call link]({url}) · Event: "{calendar title}"

> ⏱️ **Time budget.** {Duration} is {tight/ample}. This prep is designed so the first {N} minutes unlock what they actually want, the next {N} execute accordingly, and the last {N} close with a clear next step.

---

## Who they are (intel gathered {YYYY-MM-DD})

- **{Name}** — {role}, {company}. Based in {city/country}. {Size signal — HC, revenue, etc.}
- **{Company}** is {what they do — one sentence}. {Key context: industry, stage, recent news}
- {Other signals: how you met, mutual connections, relevant associations (industry forums, peer groups)}
- {What they're looking for, per the meeting request/referral}

## Strategic disambiguation (critical — clarify in the first 3–5 min)

The ask can be {N} different things. Each has a different shape, price, and delivery. **Ask early** — the answer reshapes the rest of the call.

| Scenario | What it means | My shape |
|---|---|---|
| **A — {Scenario 1}** | {When this is true} | {Format, duration, price tier, travel} |
| **B — {Scenario 2}** | {When this is true} | {Format, duration, price tier} |
| **C — {Scenario 3}** | {When this is true — often a channel or recurring play} | {Channel partner pattern / recurring revenue shape} |

**Most likely:** {prior on which scenario}, but don't assume.

> **Opener (first 3 min):** *"{Exact question, in the language of the call, that surfaces which scenario this is}"*

---

## Path A — They're clear on what they want (demo / direct flow)

If they arrive with a specific ask, lead with the relevant artifact. Order of things to show:

### 1. **{Primary demo artifact}** ({N} min)
- What to open: {specific file, URL, dashboard}
- What to say: *"{One-line framing — why this is the right thing for them to see}"*

### 2. **Background / credibility** ({N} min)
- Prepared 90-second version:
  - {Key credential 1}
  - {Key credential 2 — tie to their world}
  - {Recent proof point — what shipped, with whom, at what scale}

### 3. **Offering ladder** ({N} min)
- Show your offerings doc (e.g. `[[your-offerings]]`). Specifically the {tier / offering} that matches their signal.
- Call out precedent: *"Same format delivered to {prior client} at {scale}."*

### 4. **Pricing — live calculator** ({N} min, only if buyer intent is clear)
- Open your pricing calculator (e.g. `[[your-pricing]]`) and calculate live with their numbers:
  - Audience size: {?}
  - Format: {?}
  - Travel: {?}
  - Channel fee: {?}
  - Tier modifier: {?}

**Close:** *"{Explicit next step with timing — proposal by when, decision by whom, follow-up channel}"*

---

## Path B — They're exploring / not clear yet (discovery flow)

If the disambiguation question surfaces "I'm not sure yet — that's why I want to talk," flip to discovery mode. Don't demo; listen.

### Understand the trigger
1. *"What made you think now is the time to bring {topic} into the conversation?"*
2. *"When you say {pain point they hinted at}, can you walk me through a specific example?"*

### Understand their internal context
3. *"{Question that probes current state — tools used, team posture, prior attempts}"*
4. *"{Question that maps decision-makers and sponsors}"*

### Surface the real job-to-be-done
5. *"If this goes perfectly — a month after, what's different? What does 'success' look like?"* _(JTBD anchor — forces outcomes, not activities)_
6. *"{Question about what they've seen work or NOT work in similar efforts}"*

### Budget + decision path (earn the right first)
7. *"How does {their org} decide this type of investment? Is it your call or a committee?"*
8. *"Is there a budget range in mind, so I can calibrate the proposal?"*

**Close:** *"I'll send you within {24h} a {one-pager / short doc} with 2–3 possible formats, pricing, and timelines. You review, discuss with who you need to, and we reconvene {day}. Sound good?"*

---

## Materials to have ready BEFORE the call

- [ ] Tab 1: {primary demo artifact}
- [ ] Tab 2: {supporting demo — e.g. daily note, project dashboard}
- [ ] Tab 3: your offerings doc (e.g. `[[your-offerings]]`)
- [ ] Tab 4: your pricing calculator (e.g. `[[your-pricing]]`)
- [ ] Tab 5: {precedent/proof document — prior proposal, case study, shipped artifact}
- [ ] **Language:** {Spanish / English / Portuguese / other} — based on {their location / previous correspondence}
- [ ] Test the call link {N} minutes before: {url}

---

## Post-call — regardless of path

Within {4 hours} of the call:
- [ ] Create project note `vault/00 - notes/projects/{slug}.md` (status depends on outcome)
- [ ] Add entry to your offerings doc → Engagements (or Channel Partners, or the relevant registry)
- [ ] Send follow-up — {channel}: 1-paragraph recap + concrete next step + Drive folder link if co-creating
- [ ] If channel-partner emerged → create a client folder (e.g. `~/cowork/{your-org}/clients/{slug}/`)
- [ ] Create sibling `{YYYY-MM-DD}-{slug}-notes.md` in this folder with what was actually said (raw notes)

---

## Internal strategy note (don't say this out loud)

**Why this meeting matters more than it looks:**
- {The compound play — why the obvious single engagement is actually a channel / network / precedent multiplier}
- {What "winning" unlocks beyond the immediate scope}
- {Competitive positioning — what's the unfair advantage in THIS room?}

**Biggest risk:**
- {The one thing that could tank this — over-demoing, under-listening, pricing too early, etc.}
- **Discipline:** {the one rule you'll enforce on yourself during the call}

---

## Links
- {your offerings doc} — Engagements, Channel Partners, pricing ladder
- {your pricing calculator} — live calculator
- {relevant precedent project notes}
- {relevant context notes}
