# UserPromptSubmit hook (PowerShell port) -- inject current system date/time into Claude's context.
#
# Hook event: UserPromptSubmit (runs after user submits prompt, before Claude reads it).
# stdout from this hook is appended to Claude's view of the prompt as additional context.
#
# Eliminates the failure mode: Claude infers time-of-day from conversational context
# instead of checking the system clock. Ref: antifragile.md 2026-05-18.
#
# Cross-platform sibling of inject-datetime.sh -- same output format.
# Encoding: ASCII-only (avoid CP1252 reinterpretation on Windows PowerShell 5.1).

$ErrorActionPreference = "Stop"

$now = Get-Date
$weekday = $now.ToString("dddd", [System.Globalization.CultureInfo]::InvariantCulture)
$date = $now.ToString("yyyy-MM-dd")
$time = $now.ToString("HH:mm:ss")

# Timezone: short ID + UTC offset (e.g. "EST (-0500)" or "ART (-0300)")
$tzInfo = [System.TimeZoneInfo]::Local
$tzName = $tzInfo.StandardName
$offset = $tzInfo.GetUtcOffset($now)
$offsetSign = if ($offset.TotalMinutes -ge 0) { "+" } else { "-" }
$offsetStr = "{0}{1:00}{2:00}" -f $offsetSign, [math]::Abs($offset.Hours), [math]::Abs($offset.Minutes)

$unix = [int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())

@"
<system-time>
weekday: $weekday
date: $date
time: $time
timezone: $tzName ($offsetStr)
unix: $unix
</system-time>
"@
