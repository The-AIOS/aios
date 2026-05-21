#!/usr/bin/env python3
"""
Claude Code Context Monitor
Real-time context usage monitoring with visual indicators, session analytics,
cumulative monthly cost tracking, and people-equivalent productivity metric.
"""

import json
import sys
import os
import re
import subprocess
from datetime import datetime


# === CONFIGURATION ===
MONTHLY_PLAN_COST = 200       # Your subscription cost in USD
COST_TRACKER_FILE = os.path.expanduser("~/.claude/monthly-cost-tracker.json")

# People-equivalent baselines: how many actions/hour a human does per role
# Conservative estimates — a focused human doing ONLY that role
ROLE_BASELINES = {
    "engineering":   8,   # edits, writes, bash commands, git ops per hour
    "research":      4,   # web searches, fetches, deep reads per hour
    "ops":           6,   # calendar, tasks, slack, monday actions per hour
    "knowledge":     5,   # vault reads, writes, patches, searches per hour
    "content":       3,   # doc creation, presentations, PDF generation per hour
}

# Map tool names to roles
TOOL_ROLE_MAP = {
    # Engineering
    "Edit": "engineering", "Write": "engineering", "Bash": "engineering",
    "Grep": "engineering", "Glob": "engineering",
    # Research
    "WebSearch": "research", "WebFetch": "research", "Read": "research",
    "Agent": "research",
    # Ops (calendar, tasks, slack, monday, jira, gmail)
    "mcp__google-workspace__get_events": "ops",
    "mcp__google-workspace__list_tasks": "ops",
    "mcp__google-workspace__manage_event": "ops",
    "mcp__google-workspace__manage_task": "ops",
    "mcp__claude_ai_Slack__": "ops",
    "mcp__claude_ai_monday_com__": "ops",
    "mcp__claude_ai_Atlassian__": "ops",
    "mcp__claude_ai_Gmail__": "ops",
    "TaskCreate": "ops", "TaskUpdate": "ops",
    "Skill": "ops",
    # Knowledge management (obsidian vault)
    "mcp__obsidian__": "knowledge",
    # Content (google docs, slides, sheets, pdf)
    "mcp__google-workspace__get_doc": "content",
    "mcp__google-workspace__batch_update": "content",
    "mcp__google-workspace__create_": "content",
    "mcp__google-workspace__modify_": "content",
    "mcp__google-workspace__insert_": "content",
    "mcp__google-workspace__update_": "content",
    "mcp__google-workspace__get_presentation": "content",
    "mcp__google-workspace__get_spreadsheet": "content",
    "NotebookEdit": "content",
}


def get_git_status():
    """Get git branch and change count for statusline."""
    try:
        subprocess.check_output(
            ["git", "rev-parse", "--git-dir"], stderr=subprocess.DEVNULL
        )
        branch = (
            subprocess.check_output(
                ["git", "branch", "--show-current"], stderr=subprocess.DEVNULL
            )
            .decode()
            .strip()
        )
        if not branch:
            return ""
        changes = (
            subprocess.check_output(
                ["git", "status", "--porcelain"], stderr=subprocess.DEVNULL
            )
            .decode()
            .splitlines()
        )
        change_count = len(changes)
        if change_count > 0:
            color = "\033[31m"
            suffix = f" ({change_count})"
        else:
            color = "\033[32m"
            suffix = ""
        return f" \033[90m|\033[0m {color}🌿 {branch}{suffix}\033[0m"
    except Exception:
        return ""


def get_context_window(model_name=""):
    """Return context window size based on model. Defaults to 200K for unknown models."""
    if "1M" in model_name or "1m" in model_name:
        return 1_000_000
    elif "opus" in model_name.lower() or "sonnet" in model_name.lower():
        return 200_000
    return 200_000


def classify_tool(tool_name):
    """Classify a tool call into a role category."""
    # Exact match first
    if tool_name in TOOL_ROLE_MAP:
        return TOOL_ROLE_MAP[tool_name]
    # Prefix match for MCP tools
    for prefix, role in TOOL_ROLE_MAP.items():
        if tool_name.startswith(prefix):
            return role
    # Skip meta-tools that don't represent work
    if tool_name in ("ToolSearch",):
        return None
    return None


def parse_transcript(transcript_path, context_window=200_000):
    """Parse transcript for context usage AND tool call counts by role."""
    result = {
        "context": None,
        "role_counts": {},
        "total_tools": 0,
    }

    if not transcript_path or not os.path.exists(transcript_path):
        return result

    try:
        with open(transcript_path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except (FileNotFoundError, PermissionError):
        return result

    # Count ALL tool calls across the full transcript
    role_counts = {}
    total_tools = 0

    for line in lines:
        try:
            data = json.loads(line.strip())
            if data.get("type") == "assistant":
                message = data.get("message", {})
                content = message.get("content", [])
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "tool_use":
                        tool_name = block.get("name", "")
                        role = classify_tool(tool_name)
                        if role:
                            role_counts[role] = role_counts.get(role, 0) + 1
                            total_tools += 1
        except (json.JSONDecodeError, KeyError, ValueError):
            continue

    result["role_counts"] = role_counts
    result["total_tools"] = total_tools

    # Parse context from recent lines (same as before)
    recent_lines = lines[-15:] if len(lines) > 15 else lines
    for line in reversed(recent_lines):
        try:
            data = json.loads(line.strip())
            if data.get("type") == "assistant":
                message = data.get("message", {})
                usage = message.get("usage", {})
                if usage:
                    input_tokens = usage.get("input_tokens", 0)
                    cache_read = usage.get("cache_read_input_tokens", 0)
                    cache_creation = usage.get("cache_creation_input_tokens", 0)
                    total_tokens = input_tokens + cache_read + cache_creation
                    if total_tokens > 0:
                        percent_used = min(100, (total_tokens / context_window) * 100)
                        result["context"] = {
                            "percent": percent_used,
                            "tokens": total_tokens,
                            "method": "usage",
                        }
                        break
            elif data.get("type") == "system_message":
                content = data.get("content", "")
                match = re.search(
                    r"Context left until auto-compact: (\d+)%", content
                )
                if match:
                    percent_left = int(match.group(1))
                    result["context"] = {
                        "percent": 100 - percent_left,
                        "warning": "auto-compact",
                        "method": "system",
                    }
                    break
                match = re.search(r"Context low \((\d+)% remaining\)", content)
                if match:
                    percent_left = int(match.group(1))
                    result["context"] = {
                        "percent": 100 - percent_left,
                        "warning": "low",
                        "method": "system",
                    }
                    break
        except (json.JSONDecodeError, KeyError, ValueError):
            continue

    return result


def get_context_display(context_info):
    """Generate context display with visual indicators."""
    if not context_info:
        return "🔵 ???"

    percent = context_info.get("percent", 0)
    warning = context_info.get("warning")

    # Color + icon only — the text labels ("COMPACT SOON", "HIGH", etc.)
    # stole too much statusline real estate. The color/icon carries the
    # signal fine; only the genuinely-terminal states ("AUTO-COMPACT!",
    # "LOW!") keep their text because those require immediate action.
    if percent >= 95:
        icon, color = "🚨", "\033[31;1m"
        alert = ""
    elif percent >= 90:
        icon, color = "🔴", "\033[31m"
        alert = ""
    elif percent >= 75:
        icon, color = "🟠", "\033[91m"
        alert = ""
    elif percent >= 50:
        icon, color = "🟡", "\033[33m"
        alert = ""
    else:
        icon, color = "🟢", "\033[32m"
        alert = ""

    if warning == "auto-compact":
        alert = "AUTO-COMPACT!"
    elif warning == "low":
        alert = "LOW!"

    segments = 6
    filled = int((percent / 100) * segments)
    bar = "▓" * filled + "░" * (segments - filled)

    reset = "\033[0m"
    alert_str = f" ⚠ {alert}" if alert else ""

    return f"{icon} {color}{percent:.0f}% {bar}{alert_str}{reset}"


def get_people_display(role_counts, duration_ms):
    """Calculate and display people-equivalent metric."""
    if not role_counts or duration_ms <= 0:
        return ""

    hours = duration_ms / 3_600_000
    if hours <= 0:
        return ""

    reset = "\033[0m"
    total_people = 0.0
    role_abbrev = {
        "engineering": "eng",
        "research": "res",
        "ops": "ops",
        "knowledge": "kb",
        "content": "con",
    }

    for role, count in role_counts.items():
        baseline = ROLE_BASELINES.get(role, 5)
        # How many person-hours this work represents
        person_hours = count / baseline
        # How many people working in parallel for this session duration
        people = person_hours / hours
        total_people += people

    if total_people < 0.5:
        return ""

    # Color based on multiplier
    if total_people >= 8:
        color = "\033[94;1m"  # Bold bright blue — exceptional
    elif total_people >= 5:
        color = "\033[94m"    # Bright blue — strong
    elif total_people >= 3:
        color = "\033[36m"    # Cyan — good
    elif total_people >= 1.5:
        color = "\033[36m"    # Cyan — solid
    else:
        color = "\033[90m"    # Gray — warming up

    total_actions = sum(role_counts.values())
    return (
        f" \033[90m·{reset} "
        f"{color}👤 {total_people:.1f} people{reset}"
        f" \033[90m·{reset} "
        f"\033[36m⚡{total_actions} tasks{reset}"
    )


def get_directory_display(workspace_data):
    """Get directory display name."""
    current_dir = workspace_data.get("current_dir", "")
    project_dir = workspace_data.get("project_dir", "")
    if current_dir and project_dir:
        if current_dir.startswith(project_dir):
            rel_path = current_dir[len(project_dir):].lstrip("/")
            return rel_path or os.path.basename(project_dir)
        else:
            return os.path.basename(current_dir)
    elif project_dir:
        return os.path.basename(project_dir)
    elif current_dir:
        return os.path.basename(current_dir)
    else:
        return "unknown"


def load_monthly_tracker():
    """Load or initialize the monthly cost tracker."""
    current_month = datetime.now().strftime("%Y-%m")
    try:
        if os.path.exists(COST_TRACKER_FILE):
            with open(COST_TRACKER_FILE, "r") as f:
                tracker = json.load(f)
            if tracker.get("month") != current_month:
                tracker = {
                    "month": current_month,
                    "total_cost": 0.0,
                    "session_costs": {},
                }
            return tracker
    except (json.JSONDecodeError, KeyError):
        pass
    return {"month": current_month, "total_cost": 0.0, "session_costs": {}}


def save_monthly_tracker(tracker):
    """Save the monthly cost tracker."""
    try:
        os.makedirs(os.path.dirname(COST_TRACKER_FILE), exist_ok=True)
        with open(COST_TRACKER_FILE, "w") as f:
            json.dump(tracker, f, indent=2)
    except (PermissionError, OSError):
        pass


def get_cost_display(cost_data, transcript_path=""):
    """Get cost display: session cost · monthly total / plan."""
    if not cost_data:
        return ""

    session_cost = cost_data.get("total_cost_usd", 0)
    if session_cost <= 0:
        return ""

    # --- Update monthly tracker ---
    session_id = transcript_path or "unknown"
    tracker = load_monthly_tracker()
    session_costs = tracker.get("session_costs", {})

    old_cost = session_costs.get(session_id, 0.0)
    cost_diff = session_cost - old_cost

    if cost_diff > 0:
        tracker["total_cost"] = tracker.get("total_cost", 0.0) + cost_diff
        session_costs[session_id] = session_cost
        tracker["session_costs"] = session_costs
        save_monthly_tracker(tracker)

    monthly_total = tracker.get("total_cost", 0.0)

    # --- Session cost color ---
    if session_cost >= 0.50:
        sc = "\033[31m"
    elif session_cost >= 0.10:
        sc = "\033[33m"
    else:
        sc = "\033[32m"

    # --- Monthly total vs plan ---
    reset = "\033[0m"
    if monthly_total >= MONTHLY_PLAN_COST:
        savings = monthly_total - MONTHLY_PLAN_COST
        monthly_str = (
            f"\033[32;1m${monthly_total:.2f}{reset} / ${MONTHLY_PLAN_COST} "
            f"\033[32;1m🔥 +${savings:.2f} saved!{reset}"
        )
    elif monthly_total >= MONTHLY_PLAN_COST * 0.75:
        monthly_str = f"\033[33m${monthly_total:.2f}{reset} / ${MONTHLY_PLAN_COST}"
    elif monthly_total >= MONTHLY_PLAN_COST * 0.50:
        monthly_str = f"\033[32m${monthly_total:.2f}{reset} / ${MONTHLY_PLAN_COST}"
    else:
        monthly_str = f"\033[90m${monthly_total:.2f}{reset} / ${MONTHLY_PLAN_COST}"

    # --- Session duration ---
    duration_str = ""
    duration_ms = cost_data.get("total_duration_ms", 0)
    if duration_ms > 0:
        minutes = duration_ms / 60000
        if minutes < 1:
            duration_str = f" \033[90m·{reset} ⏱ {duration_ms // 1000}s"
        else:
            duration_str = f" \033[90m·{reset} ⏱ {minutes:.0f}m"

    return (
        f" \033[90m|{reset} "
        f"{sc}💰 ${session_cost:.2f} session{reset}"
        f" \033[90m·{reset} {monthly_str}"
        f"{duration_str}"
    )


def get_rate_limit_display(rate_limits):
    """Display 5-hour and 7-day rate limit usage with color coding."""
    if not rate_limits:
        return ""

    reset = "\033[0m"
    parts = []

    for key, label in [("five_hour", "5h"), ("seven_day", "7d")]:
        period = rate_limits.get(key, {})
        pct = period.get("used_percentage", 0)
        resets_at = period.get("resets_at")

        if pct <= 0:
            continue

        # Color: green → yellow → red
        if pct >= 90:
            color = "\033[31m"
        elif pct >= 70:
            color = "\033[33m"
        else:
            color = "\033[32m"

        # Reset time
        reset_str = ""
        if resets_at:
            try:
                reset_time = datetime.fromtimestamp(resets_at)
                now = datetime.now()
                diff = reset_time - now
                mins = int(diff.total_seconds() / 60)
                if mins > 0:
                    if mins >= 60:
                        reset_str = f" ↻{mins // 60}h{mins % 60:02d}m"
                    else:
                        reset_str = f" ↻{mins}m"
            except (OSError, ValueError):
                pass

        parts.append(f"{color}{label}:{pct:.0f}%{reset_str}{reset}")

    if not parts:
        return ""

    return f" \033[90m|{reset} ⚡ " + f" \033[90m·{reset} ".join(parts)


def get_account_display():
    """Show the active Anthropic account's local-part (before @) so you can
    tell at a glance whether you're on j@ or cc@ after an auto-swap.
    Cheap — reads ~/.claude.json once per statusline refresh."""
    try:
        with open(os.path.expanduser("~/.claude.json")) as f:
            d = json.load(f)
        email = d.get("oauthAccount", {}).get("emailAddress", "")
        if not email:
            return ""
        label = email.split("@")[0]
        # Green by default — colored red if we couldn't match an Anthropic account
        return f" \033[90m|\033[0m \033[36m👤 {label}\033[0m"
    except Exception:
        return ""


def main():
    # Force UTF-8 stdout so emoji render on Windows (where the default
    # console code page is cp1252 and json/print would crash on 📁🌿🟢).
    # Safe on macOS/Linux where stdout is already UTF-8.
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

    try:
        data = json.load(sys.stdin)
        model_name = data.get("model", {}).get("display_name", "Claude")
        workspace = data.get("workspace", {})
        transcript_path = data.get("transcript_path", "")
        cost_data = data.get("cost", {})
        rate_limits = data.get("rate_limits", {})
        duration_ms = cost_data.get("total_duration_ms", 0) if cost_data else 0

        context_window = get_context_window(model_name)
        parsed = parse_transcript(transcript_path, context_window)

        context_info = parsed["context"]
        context_display = get_context_display(context_info)
        people_display = get_people_display(parsed["role_counts"], duration_ms)
        directory = get_directory_display(workspace)
        # cost_display = get_cost_display(cost_data, transcript_path)
        rate_display = get_rate_limit_display(rate_limits)
        account_display = get_account_display()
        git_status = get_git_status()

        # Shorten model name: "Opus 4.6 (1M context)" → "Opus 4.6 (1M)"
        model_name = model_name.replace(" context", "")

        # Model color based on context usage
        if context_info:
            percent = context_info.get("percent", 0)
            if percent >= 90:
                model_color = "\033[31m"
            elif percent >= 75:
                model_color = "\033[33m"
            else:
                model_color = "\033[32m"
            model_display = f"{model_color}[{model_name}]\033[0m"
        else:
            model_display = f"\033[94m[{model_name}]\033[0m"

        status_line = (
            f"{model_display} "
            f"\033[93m📁 {directory}\033[0m"
            f"{git_status} "
            f"\033[90m|\033[0m {context_display}"
            # f"{people_display}"  # people-equivalent metric hidden — enable if you want it back
            f"{rate_display}"
            f"{account_display}"
        )

        print(status_line)

    except Exception as e:
        print(
            f"\033[94m[Claude]\033[0m \033[93m📁 {os.path.basename(os.getcwd())}\033[0m "
            f"\033[31m[Error: {str(e)[:20]}]\033[0m"
        )


if __name__ == "__main__":
    main()
