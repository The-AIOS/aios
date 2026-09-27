#!/usr/bin/env python3
"""guard-outward-action.py — PreToolUse hook: nothing leaves on the operator's behalf unless they asked.

WHY. A Claude Code user reported that, told to "push a project further", the agent pulled a
contract PDF from Gmail, placed a signature image on it and was about to send it
(https://news.ycombinator.com/item?id=49798257). The shape is general: an irreversible outward
action (a send, a share, a publish) reached as a way to finish a vague goal. INTENT.md already says
"stop and ask" for external comms and legal — but prose is read by the model, and a model finishing
a vague goal is exactly the reader that skips it. An `ask` permission rule does not prompt in auto
mode either. So the rule is enforced here, mechanically.

RULE
  1. A gated tool (send / reply / forward / share / publish) is allowed only when the operator's
     MOST RECENT instruction explicitly asks for that kind of action: their last typed message, or
     an AskUserQuestion answer given after it. "Check this", "draft it", "look at" do not count.
     Verbs are matched as whole words (EN / IT / ES). A bare approval ("yes", "go ahead") counts only
     as an AskUserQuestion answer or a short reply (<= 12 words), i.e. when it answers a proposal.
  2. A contract-shaped PDF attachment (contract, agreement, mandate, NDA, signed…) is ALWAYS blocked,
     whatever was said: signatures and contracts go out by the operator's own hand.
  3. No human record (an unattended `claude -p` routine, whose prompt is recorded as `sdk`) = nobody
     to ask = BLOCK, unless the launcher names the tool in $AIOS_OUTWARD_OK (comma-separated) because
     the operator ruled that routine may send.

WHOSE WORDS COUNT — identified by STRUCTURE, never by wording. Many transcript entries of type
"user" are not the operator: subagent hand-backs and peer messages (`origin.kind: "peer"`,
`isMeta: true`), task notifications, tool output, headless prompts (`promptSource: "sdk"`). Only
`origin.kind == "human"` and an AskUserQuestion result (`toolUseResult.answers` — the CHOSEN values,
never the question text, which the model wrote) count. A version that read "the latest user text"
let a send through on a subagent's report that contained the word "send": permission laundering by
construction.

FAIL-OPEN vs FAIL-CLOSED — deliberately split, unlike guard-venture-mount.py:
  - FAIL-OPEN on a malformed HOOK PAYLOAD (unparseable stdin, a tool this hook does not gate): a
    broken guardrail must not brick every tool call.
  - FAIL-CLOSED on the question the hook exists to answer: no transcript, an unreadable transcript,
    or no human record in it → BLOCK. "I could not find the operator asking" is not "the operator
    asked". A wrongly blocked send costs one re-ask; a wrongly allowed one cannot be recalled.

Contract (Claude Code PreToolUse):
  stdin  = JSON {tool_name, tool_input, transcript_path, ...}
  exit 0 = allow (silent)
  exit 2 = BLOCK; stderr is fed back to Claude as the reason

ESCAPE HATCHES (deliberate, loud, logged):
  - AIOS_ALLOW_OUTWARD=1 in the environment for one call.
  - `touch ~/aios/hooks/.outward-gate-off` to disable (every use is logged).
EXTENDING: AIOS_OUTWARD_EXTRA="tool_name:send,other_tool:publish" gates more tools (e.g. a
scheduler or ads MCP you installed) without editing this file.
Log: ~/aios/hooks/outward-gate.log. Guard: tests/outward-action-gate.test.sh. Wire per SETUP §10 Hook D.
"""
import datetime
import json
import os
import re
import sys

for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        try:
            _stream.reconfigure(encoding="utf-8", errors="replace")
        except (ValueError, OSError):
            pass

LOG = os.path.expanduser("~/aios/hooks/outward-gate.log")
KILL = os.path.expanduser("~/aios/hooks/.outward-gate-off")

# Gated tool -> the kind of action it performs (decides which words authorise it).
GATED = {
    # mail and chat
    "mcp__google-workspace__send_gmail_message": "send",
    "mcp__claude_ai_Gmail__send_message": "send",
    "mcp__claude_ai_Gmail__reply": "send",
    "mcp__claude_ai_Gmail__forward": "send",
    "mcp__claude_ai_Microsoft_365__outlook_send_mail": "send",
    "mcp__claude_ai_Microsoft_365__outlook_send_draft": "send",
    "mcp__claude_ai_Microsoft_365__outlook_forward_mail": "send",
    "mcp__claude_ai_Microsoft_365__teams_send_chat_message": "send",
    "mcp__claude_ai_Microsoft_365__teams_send_channel_message": "send",
    "mcp__claude_ai_Microsoft_365__teams_reply_channel_message": "send",
    "mcp__slack__slack_send_message": "send",
    # sharing
    "mcp__claude_ai_Google_Drive__share_file": "share",
    "mcp__google-workspace__manage_drive_access": "share",
    "mcp__google-workspace__set_drive_file_permissions": "share",
    "mcp__google-workspace__set_publish_settings": "share",
}

WORDS = {
    "send": r"send|sent|reply|respond|forward|email it|mail it|invia|inviala|invialo|manda|mandala|mandalo|rispondi|inoltra|envía|envia|enviar|responde|reenvía",
    "share": r"share|shared|give access|grant access|condividi|condividila|condividilo|comparte|compartir",
    "publish": r"publish|post|schedule|go live|activate|launch|boost|pubblica|posta|programma|attiva|publica|programa|activa",
}
APPROVAL = r"yes|yep|ok|okay|go|go ahead|approved?|confirm(ed)?|do it|sì|si|vai|procedi|dale|adelante"
CONTRACT_NAME = re.compile(
    r"contract|agreement|mandate|mandat|\bnda\b|encargo|contrato|contratto|accordo|signed|firmad|firmat|signature",
    re.I,
)


def gated():
    g = dict(GATED)
    for pair in os.environ.get("AIOS_OUTWARD_EXTRA", "").split(","):
        if ":" in pair:
            name, kind = (x.strip() for x in pair.split(":", 1))
            if name and kind in WORDS:
                g[name] = kind
    return g


def log(msg):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(f"{datetime.datetime.now().isoformat(timespec='seconds')}  {msg}\n")
    except OSError:
        pass


def block(reason):
    log("BLOCK " + reason)
    sys.stderr.write(
        "outward-action gate: " + reason + "\n"
        "Nothing was sent, shared or published. Show the operator exactly what would go out and to "
        "whom, and act only on their explicit instruction.\n"
    )
    sys.exit(2)


def last_instruction(transcript_path):
    """(text, is_answer) for the operator's most recent instruction, or (None, False)."""
    try:
        with open(transcript_path, encoding="utf-8") as f:
            lines = f.readlines()
    except OSError:
        return None, False
    for raw in reversed(lines):
        try:
            e = json.loads(raw)
        except ValueError:
            continue
        tur = e.get("toolUseResult")
        if isinstance(tur, dict) and isinstance(tur.get("answers"), dict):
            parts = [str(v) for v in tur["answers"].values()]
            for a in (tur.get("annotations") or {}).values():
                if isinstance(a, dict) and a.get("notes"):
                    parts.append(str(a["notes"]))
            return " | ".join(parts), True
        if e.get("type") != "user" or e.get("isMeta"):
            continue
        if (e.get("origin") or {}).get("kind") != "human":
            continue
        content = (e.get("message") or {}).get("content")
        if isinstance(content, str):
            return content, False
        if isinstance(content, list):
            texts = [c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text"]
            if any(texts):
                return "\n".join(texts), False
    return None, False


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        sys.exit(0)                      # fail-open: not a payload this hook can judge
    tool = data.get("tool_name", "")
    table = gated()
    if tool not in table:
        sys.exit(0)
    kind = table[tool]
    ti = data.get("tool_input") or {}

    if os.environ.get("AIOS_ALLOW_OUTWARD") == "1":
        log(f"ESCAPE (AIOS_ALLOW_OUTWARD) allowed {tool}")
        sys.exit(0)
    if os.path.exists(KILL):
        log(f"KILL-SWITCH allowed {tool}")
        sys.exit(0)

    blob = json.dumps(ti, ensure_ascii=False)
    for m in re.finditer(r"[\w\-. ]{1,120}\.pdf", blob, re.I):
        if CONTRACT_NAME.search(m.group(0)):
            block(f"{tool} carries a contract-shaped PDF ({m.group(0).strip()}). Contracts and "
                  "signatures go out by the operator's own hand.")

    ok_env = {t.strip() for t in os.environ.get("AIOS_OUTWARD_OK", "").split(",") if t.strip()}
    tp = data.get("transcript_path")
    text, is_answer = (last_instruction(tp) if tp and os.path.exists(tp) else (None, False))
    # A "typed" record may be the spawn inbox typing on someone else's behalf: a scheduled routine,
    # a dispatch from another session, a spawned worker's first prompt. The surfaces deliver by
    # typing into the terminal, so the transcript records it exactly like the operator. bus_log.py
    # fingerprints every request at write time; the "(HH:MM, launchd)" shape is refused as a floor
    # for any writer the log missed.
    if text and not is_answer:
        try:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            import bus_log
            bus = bus_log.is_bus_prompt(text)
        except Exception:
            bus = False
        if bus or re.search(r"\(\d{1,2}:\d{2},\s*launchd\)", text):
            block(f"{tool}: the latest 'typed' message came through the spawn inbox "
                  f"(\"{text.strip()[:80]}\"), not from the operator.")
    if not text:
        if tool in ok_env:
            log(f"ALLOW (AIOS_OUTWARD_OK) {tool}")
            sys.exit(0)
        block(f"{tool} with no operator instruction on record (an unattended run, or none found). "
              "A routine the operator allowed to send must name the tool in AIOS_OUTWARD_OK.")

    t = text.lower()
    if re.search(r"\b(" + WORDS[kind] + r")\b", t):
        log(f"ALLOW {tool} ({kind} asked)")
        sys.exit(0)
    if (is_answer or len(t.split()) <= 12) and re.search(r"\b(" + APPROVAL + r")\b", t):
        log(f"ALLOW {tool} (approval)")
        sys.exit(0)
    block(f"{tool}: the operator's latest instruction does not ask to {kind} anything "
          f"(\"{text.strip()[:120]}\").")


if __name__ == "__main__":
    main()
