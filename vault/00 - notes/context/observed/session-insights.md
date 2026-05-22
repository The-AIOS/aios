---
tags: [context, claude-observed, session-insights]
created: ""
updated: ""
type: claude-context
---

# Session Insights — Observation Buffer

> This file is a distillation buffer, not a log. Observations enter as **Emerging** (single session), get **Reinforced** when seen again, then get **routed** to their target observed file and removed. Session summaries live in daily notes — this file holds only pattern-level observations waiting to be confirmed.
>
> **Lifecycle:** Emerging → Reinforced → routed to target file → removed from here.
> **Gardening rule:** Adding forces reviewing. Every time close-session adds a new observation, scan what's already here — reinforce matches, drop stale items, make room. Keep Emerging ≤10, Reinforced ≤5.
> **Snapshot rule:** Only snapshot when the document actually changes (insight added, moved, or routed). Not every session.

---

## Reinforced
<!-- 2+ sessions of evidence — ready to route to target observed file -->
<!-- When routed: remove from here, note "→ routed to {file}" in commit message -->

_First reinforced insight will appear after an Emerging observation is confirmed in a second session._

## Emerging
<!-- Single-session observations — persist here until reinforced or expired -->

_First entry will appear after your first `/close-session` or `/close-day` run._

---

**See also:** [[patterns]] · [[preferences]] · [[growth]] · [[antifragile]]
