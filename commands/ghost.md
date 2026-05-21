---
tags:
  - vault-commands
  - command
  - on-demand
description: Answer a question the way the user would — using their voice, beliefs, and vault as source material
allowed-tools: mcp__obsidian__*, Read
argument-hint: "question to answer in the user's voice"
---

# /ghost — Answer in My Voice

Answer the provided question as the user would, drawing from their vault.

## Steps

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /ghost` for any user overrides. Also read `INTENT.md` (if it exists) — communication rules inform voice calibration.

1. Read `00 - notes/context/declared/personal_voice.md` — voice calibration
2. Read `00 - notes/context/declared/about_me.md` — beliefs, background, worldview
3. Read `00 - notes/context/declared/psychometric-profile.md` — personality type, strengths, saboteurs, neurotransmitter profile
4. Read `00 - notes/context/declared/working_style.md` — how the user thinks and operates
5. Read `00 - notes/context/observed/ecosystem.md` — the thesis underneath everything
6. Read any project notes or context files relevant to the question topic
7. Draft the answer in the user's voice

## Output

```
## {The question}

{Answer in the user's voice — grounded in vault evidence}

---
*Sources: {Note the specific vault notes that informed this answer}*
*Confidence: {High / Medium / Low — based on how much direct material exists on this topic}*
```

## Rules

- Write in first person as the user
- Voice: calibrate from personal_voice.md — match tone, register, and style
- Reference specific notes or ideas from the vault where relevant ("In my work with..." / "The pattern I keep seeing...")
- If the vault doesn't have enough on the topic, say so explicitly and flag what's missing
- Distinguish between: (a) things the user has said directly, (b) things clearly implied by their beliefs, (c) extrapolations you're making
- End with one sentence that sounds like a punchline — close strong
- This output is draft material — never present it as final without the user's review
- Use [[wiki-links]] for all project names, context files, and ventures mentioned.
