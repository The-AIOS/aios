#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "google-api-python-client>=2.0",
#     "google-auth>=2.0",
#     "google-auth-httplib2>=0.1",
#     "requests>=2.28",
#     "tzdata>=2024.1",
# ]
# ///
"""
Pipeline Executor — CLI tool for vault-commands (/today, /close-day).

Guarantees external API calls (Calendar, Tasks, Slack) run before Claude
sees the command. Vault file reads stay with Claude (never skipped, fast).

Usage: uv run pipeline-executor.py --command today|close-day
Output: structured markdown to stdout (Claude reads it as Bash output).
Lazy imports: google-auth and googleapiclient are imported inside functions
to avoid ~200ms startup cost when they're not needed.
"""

import sys
import json
import re
from concurrent.futures import ThreadPoolExecutor

# Fix Windows encoding — cp1252 doesn't support emojis in output
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
from datetime import datetime
from pathlib import Path
from threading import Lock
from zoneinfo import ZoneInfo

# --- Config ---
VAULT_PATH = Path.home() / "obsidian" / "vault"
SOURCES_PATH = Path.home() / "obsidian" / "USER.md"
GOOGLE_CREDS_DIR_PRIMARY = Path.home() / ".google_workspace_mcp" / "credentials"
GOOGLE_CREDS_DIR_PERSONAL = Path.home() / ".google_workspace_mcp" / "credentials-personal"
SLACK_TOKENS_PATH = Path.home() / ".slack-mcp-tokens.json"
LOG_PATH = Path.home() / "obsidian" / "hooks" / "pipeline-executor.log"
MAX_LOG_LINES = 500

PIPELINE_COMMANDS = {"today", "close-day"}
MAX_MSG_TEXT_LENGTH = 300  # truncate Slack message text in recap output

# Single global lock for credential file writes — simple, correct
_creds_lock = Lock()


def log(msg):
    """Append to log file with rotation."""
    try:
        with open(LOG_PATH, "a") as f:
            f.write(f"{datetime.now().isoformat()} | {msg}\n")
        # Rotate occasionally (check every call is cheap, rewrite is rare)
        if LOG_PATH.stat().st_size > 100_000:  # ~100KB
            lines = LOG_PATH.read_text().splitlines()
            LOG_PATH.write_text("\n".join(lines[-MAX_LOG_LINES:]) + "\n")
    except Exception:
        pass


def parse_sources():
    """Parse USER.md Sources section for API IDs and configured sources."""
    config = {
        "configured": set(),
        "google_email_primary": None,
        "google_email_personal": None,
        "google_tasks_list": None,
        "timezone": "UTC",  # Universal default — each user sets their timezone in USER.md
        "slack_channels_monitor": [],
        "slack_channels_skip": [],
        "slack_recap_enabled": False,
    }
    if not SOURCES_PATH.exists():
        log(f"USER.md not found at {SOURCES_PATH} — using defaults")
        return config

    content = SOURCES_PATH.read_text()

    if "Google Calendar" in content:
        config["configured"].add("calendar")
        if "Google Calendar (Personal)" in content:
            config["configured"].add("calendar-personal")
    if "Slack" in content and "### Communication" in content:
        config["configured"].add("slack")
    if "Google Tasks" in content:
        config["configured"].add("tasks")
    if "### Dev projects" in content:
        config["configured"].add("dev-projects")

    for line in content.split("\n"):
        for pattern, key in [
            (r'- Google Tasks list: `(.+?)`', "google_tasks_list"),
            (r'- Google email: `(.+?)`', "google_email_primary"),
            (r'- Google email \(Personal\): `(.+?)`', "google_email_personal"),
            (r'- Timezone: `(.+?)`', "timezone"),
        ]:
            m = re.match(pattern, line)
            if m:
                config[key] = m.group(1)

        # Parse channels to monitor
        m = re.match(r'- \*\*Channels to monitor:\*\* (.+)', line)
        if m:
            config["slack_channels_monitor"] = [
                ch.strip().lstrip("#") for ch in m.group(1).split(",")
            ]

        # Parse skip channels
        m = re.match(r'- \*\*Skip:\*\* (.+)', line)
        if m:
            config["slack_channels_skip"] = [
                ch.strip().lstrip("#").split(" ")[0] for ch in m.group(1).split(",")
            ]

        # Parse close-day recap flag
        if "Close-day recap:" in line and "enabled" in line.lower():
            config["slack_recap_enabled"] = True

    return config


def _tz_offset(timezone_name):
    """Compute UTC offset string from timezone name using zoneinfo."""
    try:
        zi = ZoneInfo(timezone_name)
        offset = datetime.now(zi).strftime("%z")
        # Convert +0300 to +03:00
        return f"{offset[:3]}:{offset[3:]}"
    except Exception:
        log(f"Unknown timezone '{timezone_name}', defaulting to +00:00 (UTC)")
        return "+00:00"


def _load_google_creds(creds_path):
    """Load Google OAuth credentials and refresh if expired or unknown."""
    from google.oauth2.credentials import Credentials
    from google.auth.transport.requests import Request

    creds_data = json.loads(creds_path.read_text())
    expiry_str = creds_data.get("expiry")
    expiry = None
    if expiry_str:
        parsed = datetime.fromisoformat(expiry_str)
        # google-auth expects UTC naive datetime
        if parsed.tzinfo is not None:
            from datetime import timezone as _tz
            parsed = parsed.astimezone(_tz.utc).replace(tzinfo=None)
        expiry = parsed

    creds = Credentials(
        token=creds_data["token"],
        refresh_token=creds_data["refresh_token"],
        token_uri=creds_data["token_uri"],
        client_id=creds_data["client_id"],
        client_secret=creds_data["client_secret"],
        scopes=creds_data.get("scopes", []),
        expiry=expiry,
    )
    if not creds.valid and creds.refresh_token:
        creds.refresh(Request())
        _save_refreshed_token(creds, creds_path)
    return creds


def _save_refreshed_token(creds, creds_path):
    """Save refreshed token back to disk (thread-safe, re-reads before writing)."""
    with _creds_lock:
        current = json.loads(creds_path.read_text())
        if creds.token != current["token"]:
            current["token"] = creds.token
            if creds.expiry:
                current["expiry"] = creds.expiry.isoformat()
            if creds.refresh_token and creds.refresh_token != current.get("refresh_token"):
                current["refresh_token"] = creds.refresh_token
            creds_path.write_text(json.dumps(current, indent=2))


def google_calendar_events(creds_path, email, time_min, time_max, detailed=False):
    """Fetch calendar events using Google Calendar API."""
    from googleapiclient.discovery import build

    creds = _load_google_creds(creds_path)
    service = build("calendar", "v3", credentials=creds, cache_discovery=False)
    result = service.events().list(
        calendarId="primary",
        timeMin=time_min,
        timeMax=time_max,
        singleEvents=True,
        orderBy="startTime",
        maxResults=50,
    ).execute()

    events = result.get("items", [])
    lines = []
    for e in events:
        start = e.get("start", {})
        end = e.get("end", {})
        summary = e.get("summary", "(no title)")
        if "date" in start:
            lines.append(f"- All day — {summary}")
        else:
            s = start.get("dateTime", "")[:16].split("T")
            en = end.get("dateTime", "")[:16].split("T")
            s_time = s[1] if len(s) > 1 else ""
            e_time = en[1] if len(en) > 1 else ""
            lines.append(f"- {s_time} – {e_time} — {summary}")

        if detailed:
            desc = e.get("description", "")
            if desc:
                lines.append(f"  Description: {desc[:200]}{'...' if len(desc) > 200 else ''}")
            attachments = e.get("attachments", [])
            for att in attachments:
                title = att.get("title", "untitled")
                mime = att.get("mimeType", "")
                file_id = att.get("fileId", "")
                lines.append(f"  Attachment: {title} ({mime}) [fileId: {file_id}]")

    return "\n".join(lines) if lines else "No events."


def google_tasks_list(creds_path, task_list_id):
    """Fetch open Google Tasks."""
    from googleapiclient.discovery import build

    creds = _load_google_creds(creds_path)
    service = build("tasks", "v1", credentials=creds, cache_discovery=False)
    result = service.tasks().list(
        tasklist=task_list_id,
        showCompleted=False,
        maxResults=100,
    ).execute()

    tasks = result.get("items", [])
    lines = []
    for t in tasks:
        title = t.get("title", "(no title)")
        due = t.get("due", "")[:10] if t.get("due") else "no due date"
        notes = t.get("notes", "")
        suffix = "..." if len(notes) > 80 else ""
        note_preview = f" — {notes[:80]}{suffix}" if notes else ""
        lines.append(f"- {title} (due: {due}){note_preview}")
    return f"{len(tasks)} open tasks:\n" + "\n".join(lines) if tasks else "No open tasks."


def slack_unreads():
    """Fetch Slack unread conversations with batch user name resolution."""
    import requests

    if not SLACK_TOKENS_PATH.exists():
        raise FileNotFoundError(f"Slack tokens not found at {SLACK_TOKENS_PATH}. Run `npx -y @jtalk22/slack-mcp --setup` to configure.")

    tokens = json.loads(SLACK_TOKENS_PATH.read_text())
    token = tokens.get("SLACK_TOKEN", "")
    cookie = tokens.get("SLACK_COOKIE", "")
    headers = {"Authorization": f"Bearer {token}"}
    cookies = {"d": cookie}

    resp = requests.get(
        "https://slack.com/api/conversations.list",
        params={
            "types": "im,mpim,public_channel,private_channel",
            "limit": 200,
            "exclude_archived": "true",
        },
        headers=headers,
        cookies=cookies,
        timeout=10,
    )
    data = resp.json()
    if not data.get("ok"):
        raise RuntimeError(f"Slack API: {data.get('error', 'unknown')}")

    channels = data.get("channels", [])
    unreads = [c for c in channels if c.get("unread_count", 0) > 0]

    if not unreads:
        return "No unread conversations."

    # Batch resolve: fetch all users once instead of N serial calls
    user_ids = {c["user"] for c in unreads if c.get("is_im") and c.get("user")}
    user_names = {}
    if user_ids:
        try:
            uresp = requests.get(
                "https://slack.com/api/users.list",
                params={"limit": 200},
                headers=headers,
                cookies=cookies,
                timeout=10,
            )
            udata = uresp.json()
            if udata.get("ok"):
                for u in udata.get("members", []):
                    if u.get("id") in user_ids:
                        user_names[u["id"]] = u.get("real_name") or u.get("name") or u["id"]
        except Exception as ex:
            log(f"Failed to resolve user names: {ex}")  # Fall back to raw IDs

    lines = []
    for c in sorted(unreads, key=lambda x: x.get("unread_count", 0), reverse=True):
        if c.get("is_im") and c.get("user"):
            name = user_names.get(c["user"], c["user"])
        else:
            name = c.get("name") or c.get("id")
        count = c.get("unread_count", 0)
        lines.append(f"- {name}: {count} unread")
    return f"{len(unreads)} conversations with unreads:\n" + "\n".join(lines)


def slack_daily_recap(channels_skip, timezone_name):
    """Fetch today's messages from monitored channels + active DMs for close-day recap."""
    import requests
    from datetime import timedelta

    if not SLACK_TOKENS_PATH.exists():
        raise FileNotFoundError(f"Slack tokens not found at {SLACK_TOKENS_PATH}")

    tokens = json.loads(SLACK_TOKENS_PATH.read_text())
    token = tokens.get("SLACK_TOKEN", "")
    cookie = tokens.get("SLACK_COOKIE", "")
    headers = {"Authorization": f"Bearer {token}"}
    cookies = {"d": cookie}

    # Calculate today's start in the user's timezone
    zi = ZoneInfo(timezone_name)
    now = datetime.now(zi)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    oldest_ts = str(today_start.timestamp())

    # Get all conversations to map names → IDs
    resp = requests.get(
        "https://slack.com/api/conversations.list",
        params={"types": "im,mpim,public_channel,private_channel", "limit": 200, "exclude_archived": "true"},
        headers=headers, cookies=cookies, timeout=10,
    )
    data = resp.json()
    if not data.get("ok"):
        raise RuntimeError(f"Slack API: {data.get('error', 'unknown')}")

    all_channels = data.get("channels", [])

    # All non-DM channels except skip list
    skip_set = set(channels_skip)
    target_channels = [
        ch for ch in all_channels
        if ch.get("name") and not ch.get("is_im") and ch.get("name") not in skip_set
    ]

    # All DMs (we'll filter by activity after fetching)
    dm_channels = [ch for ch in all_channels if ch.get("is_im")]

    # Resolve all user names in one call
    all_user_names = {}
    try:
        # TODO: paginate for workspaces > 200 users
        uresp = requests.get("https://slack.com/api/users.list", params={"limit": 200},
                             headers=headers, cookies=cookies, timeout=10)
        udata = uresp.json()
        if udata.get("ok"):
            for u in udata.get("members", []):
                all_user_names[u["id"]] = u.get("real_name") or u.get("name") or u["id"]
    except Exception as ex:
        log(f"Failed to fetch user list for recap: {ex}")

    # Cap per channel — 200-user limit on users.list is fine for small teams
    MAX_MSGS = 50

    def _fetch_channel(ch_id, label):
        """Fetch today's messages from a single channel."""
        try:
            hist = requests.get(
                "https://slack.com/api/conversations.history",
                params={"channel": ch_id, "oldest": oldest_ts, "limit": MAX_MSGS},
                headers=headers, cookies=cookies, timeout=5,
            )
            hdata = hist.json()
            if not hdata.get("ok"):
                return None
            msgs = hdata.get("messages", [])
            if not msgs:
                return None
            msg_lines = []
            for m in reversed(msgs):
                user = all_user_names.get(m.get("user", ""), m.get("user", "unknown"))
                text = m.get("text", "")[:MAX_MSG_TEXT_LENGTH]
                if text:
                    msg_lines.append(f"  [{user}] {text}")
            if msg_lines:
                return f"### {label} ({len(msgs)} messages)\n" + "\n".join(msg_lines)
        except Exception as ex:
            log(f"Failed to fetch {label}: {ex}")
        return None

    # Fetch all channels + DMs in parallel
    fetch_futures = {}
    # 10 workers — Slack Tier 3 rate limit is ~50 req/min, stay well under
    with ThreadPoolExecutor(max_workers=10) as fetch_pool:
        for ch in target_channels:
            ch_id = ch["id"]
            ch_name = ch.get("name", ch_id)
            fetch_futures[f"#{ch_name}"] = fetch_pool.submit(_fetch_channel, ch_id, f"#{ch_name}")
        for ch in dm_channels:
            ch_id = ch["id"]
            dm_user = all_user_names.get(ch.get("user", ""), ch.get("user", "unknown"))
            fetch_futures[f"DM:{dm_user}"] = fetch_pool.submit(_fetch_channel, ch_id, f"DM: {dm_user}")

        sections = []
        for label, fut in fetch_futures.items():
            try:
                result = fut.result(timeout=10)
                if result:
                    sections.append(result)
            except Exception as ex:
                log(f"Recap future {label} timed out or failed: {ex}")

    if not sections:
        return "No Slack activity today in monitored channels."

    return "\n\n".join(sections)


def run_pipeline(command_name):
    """Execute the API-only pipeline and return formatted results."""
    start_time = datetime.now()
    sources = parse_sources()
    tz_off = _tz_offset(sources["timezone"])
    log(f"Running pipeline for '{command_name}' | tz={sources['timezone']} ({tz_off})")

    today_str = start_time.strftime("%Y-%m-%d")
    time_min = f"{today_str}T00:00:00{tz_off}"
    time_max = f"{today_str}T23:59:59{tz_off}"

    # close-day needs detailed calendar (attachments) + next 7 days for cross-check
    is_close_day = command_name == "close-day"
    from datetime import timedelta
    next_week_str = (start_time + timedelta(days=7)).strftime("%Y-%m-%d")
    time_max_week = f"{next_week_str}T23:59:59{tz_off}"

    results = {}
    errors = {}
    futures = {}

    with ThreadPoolExecutor(max_workers=7) as pool:
        creds_primary = GOOGLE_CREDS_DIR_PRIMARY / f"{sources['google_email_primary']}.json" if sources["google_email_primary"] else None
        creds_personal = GOOGLE_CREDS_DIR_PERSONAL / f"{sources['google_email_personal']}.json" if sources["google_email_personal"] else None

        if "calendar" in sources["configured"] and creds_primary and creds_primary.exists():
            futures["calendar_primary"] = pool.submit(
                google_calendar_events, creds_primary,
                sources["google_email_primary"], time_min, time_max,
                detailed=is_close_day
            )
            # close-day also needs next 7 days for calendar cross-check
            if is_close_day:
                futures["calendar_next_week"] = pool.submit(
                    google_calendar_events, creds_primary,
                    sources["google_email_primary"], time_min, time_max_week
                )
        if "calendar-personal" in sources["configured"] and creds_personal and creds_personal.exists():
            futures["calendar_personal"] = pool.submit(
                google_calendar_events, creds_personal,
                sources["google_email_personal"], time_min, time_max
            )
        if "tasks" in sources["configured"] and sources["google_tasks_list"] and creds_primary and creds_primary.exists():
            futures["tasks"] = pool.submit(
                google_tasks_list, creds_primary,
                sources["google_tasks_list"]
            )
        if "slack" in sources["configured"]:
            futures["slack"] = pool.submit(slack_unreads)
            # Slack daily recap — both today and close-day if enabled
            if sources["slack_recap_enabled"]:
                futures["slack_recap"] = pool.submit(
                    slack_daily_recap, sources["slack_channels_skip"], sources["timezone"]
                )

        for key, future in futures.items():
            try:
                timeout = 30 if key == "slack_recap" else 15
                results[key] = future.result(timeout=timeout)
            except Exception as ex:
                errors[key] = str(ex)
                log(f"{key} failed: {ex}")

    # Build status
    status = []
    for key in futures:
        if key in results:
            status.append(f"✅ {key}")
        else:
            status.append(f"❌ {key}: {errors.get(key, 'unknown')}")
    for source, mapped in [("calendar", "calendar_primary"), ("calendar-personal", "calendar_personal"), ("tasks", "tasks"), ("slack", "slack")]:
        if mapped not in futures:
            status.append(f"⏭️ {source}: not configured")

    elapsed = (datetime.now() - start_time).total_seconds()

    has_errors = bool(errors)
    lines = [f"# Pre-loaded API Data (pipeline-executor {elapsed:.1f}s)", ""]
    if has_errors:
        failed = ", ".join(errors.keys())
        lines.extend([f"⚠️ **Partial load — {failed} failed.** Tell the user what failed and how to fix it (see details below).", ""])

    # Calendar Primary
    if "calendar_primary" in results:
        lines.extend([f"## Google Calendar — Primary ({sources['google_email_primary']})", results["calendar_primary"], ""])
    elif "calendar_primary" in errors:
        lines.extend([f"## Google Calendar — Primary ({sources['google_email_primary']})",
                       f"❌ FAILED: {errors['calendar_primary']}",
                       "Fix: re-authenticate Google Workspace MCP — open a new session and call any `mcp__google-workspace__*` tool to trigger OAuth refresh.", ""])

    # Calendar next 7 days (close-day only)
    if "calendar_next_week" in results:
        lines.extend(["## Google Calendar — Next 7 days (for cross-check)", results["calendar_next_week"], ""])
    elif "calendar_next_week" in errors:
        lines.extend(["## Google Calendar — Next 7 days",
                       f"❌ FAILED: {errors['calendar_next_week']}",
                       "Fix: same as Calendar Primary.", ""])

    # Calendar Personal
    if "calendar_personal" in results:
        lines.extend([f"## Google Calendar — Personal ({sources['google_email_personal']})", results["calendar_personal"], ""])
    elif "calendar_personal" in errors:
        lines.extend([f"## Google Calendar — Personal ({sources['google_email_personal']})",
                       f"❌ FAILED: {errors['calendar_personal']}",
                       "Fix: re-authenticate Google Workspace Personal MCP — open a new session and call any `mcp__google-workspace-personal__*` tool.", ""])

    # Tasks
    if "tasks" in results:
        lines.extend(["## Google Tasks", results["tasks"], ""])
    elif "tasks" in errors:
        lines.extend(["## Google Tasks",
                       f"❌ FAILED: {errors['tasks']}",
                       "Fix: same as Calendar — re-authenticate Google Workspace MCP (Tasks uses the same credentials).", ""])

    # Slack unreads
    if "slack" in results:
        lines.extend(["## Slack Unreads", results["slack"], ""])
    elif "slack" in errors:
        lines.extend(["## Slack Unreads",
                       f"❌ FAILED: {errors['slack']}",
                       "Fix: Slack browser tokens expired. Run `npx -y @jtalk22/slack-mcp --setup` to re-extract tokens from Chrome.", ""])

    # Slack daily recap (close-day only)
    if "slack_recap" in results:
        lines.extend(["## Slack Daily Recap",
                       "Claude: summarize this activity, identify action items/pendings for the user, and flag anything that needs a response.",
                       "", results["slack_recap"], ""])
    elif "slack_recap" in errors:
        lines.extend(["## Slack Daily Recap",
                       f"❌ FAILED: {errors['slack_recap']}",
                       "Fix: same as Slack Unreads — check tokens.", ""])

    lines.extend(["## Pipeline Status", *status, f"Total: {elapsed:.1f}s"])

    return "\n".join(lines)


def main():
    """CLI entry point — python3 pipeline-executor.py --command today"""
    import argparse
    parser = argparse.ArgumentParser(description="Pipeline executor for vault-commands")
    parser.add_argument("--command", required=True, choices=sorted(PIPELINE_COMMANDS),
                        help="Which command to run the pipeline for")
    args = parser.parse_args()

    try:
        log(f"Pipeline detected: {args.command}")
        context = run_pipeline(args.command)
        log(f"Pipeline complete: {len(context)} chars")
        print(context)
    except Exception as ex:
        log(f"Fatal error: {ex}")
        print(f"# Pre-loaded API Data\n\n❌ Pipeline executor crashed: {ex}")


if __name__ == "__main__":
    main()
