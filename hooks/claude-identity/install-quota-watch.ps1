# install-quota-watch.ps1 -- Windows sibling of com.aios.claude-quota-watch.plist
# (launchd, macOS) and aios-claude-quota-watch.timer (systemd user, Linux).
#
# Registers a per-user Scheduled Task that runs `claude-identity.sh watch` as the
# SAFETY NET for account rotation. Real-time detection is not this: it lives in
# _cache.py, which the statusLine pipe drives several times per turn. This task
# exists for sessions where that pipe is broken or absent.
#
# Mapping of the three schedulers, so a change to one can be mirrored:
#
#   launchd (plist)          systemd (timer)        Task Scheduler (here)
#   -----------------------  ---------------------  ------------------------------
#   StartInterval 1800       OnUnitActiveSec=30min  Repetition Interval PT30M
#   RunAtLoad true           OnStartupSec=1min      StartWhenAvailable (see below)
#   (implicit on wake)       Persistent=true        StartWhenAvailable true
#   user agent, not root     systemd --user         InteractiveToken/LeastPrivilege
#
# The RunAtLoad / OnStartupSec row is the one that does not map cleanly. A
# <LogonTrigger> is the exact analogue and it is the ONE element Task Scheduler
# refuses to register without elevation -- bisected element by element: a task
# with only a logon trigger fails "Acceso denegado" while the identical task with
# a repeating TimeTrigger registers fine. Rather than make every Windows operator
# open an elevated shell for a per-user watcher, the default leans on
# StartWhenAvailable with a StartBoundary already in the past: if the machine was
# off or asleep when a run was due, the scheduler fires one as soon as it can
# after resume. That is systemd's Persistent=true, and it covers the same gap the
# logon trigger covered. Pass -WithLogonTrigger from an ELEVATED shell if you want
# literal launchd parity.
#
# Why 30 minutes and not 60 seconds: on macOS a 60s interval pinned the machine
# awake through constant DarkWake cycles. Windows would block modern standby the
# same way, and the conclusion is identical -- this is the net, not the detector.
#
# WHY schtasks.exe AND NOT Register-ScheduledTask
# -----------------------------------------------
# The ScheduledTasks cmdlets go through the CIM provider, which on a default
# Windows 11 install refuses to create a task from a non-elevated shell:
#   Register-ScheduledTask : Acceso denegado.  (HRESULT 0x80070005)
# That happens with OR without an explicit -Principal, so it is not a principal
# problem -- and asking every Windows operator to run an elevated shell to install
# a per-user quota watcher is the wrong trade for a tool whose whole point is that
# it stays inside the user's own session. `schtasks.exe /Create /XML` registers the
# identical task definition unelevated. Verified on Windows 11 Home 26200 in a
# normal (IsInRole Administrator = False) shell.
#
# The watcher LOGIC is bash and stays bash: it is the same script macOS and Linux
# run, and Git for Windows always ships bash. Only the per-machine registration is
# PowerShell, exactly like install-git-hooks.ps1 does for the git hooks. Do not
# rewrite claude-identity.sh in PowerShell -- a second copy of a credential swapper
# is a drift hazard, not parity.
#
# Usage:
#   pwsh -File hooks/claude-identity/install-quota-watch.ps1            # install
#   pwsh -File hooks/claude-identity/install-quota-watch.ps1 -Uninstall
#   pwsh -File hooks/claude-identity/install-quota-watch.ps1 -RunNow    # trigger once
#
# Verify:  schtasks /Query /TN 'AIOS Claude Quota Watch' /V /FO LIST
# Logs:    ~\.claude\quota-watch.log        (the script's own log)
#          ~\.claude\quota-watch-task.log   (stdout/stderr of the task)

param(
  [switch]$Uninstall,
  [switch]$RunNow,
  # Literal launchd RunAtLoad parity. REQUIRES an elevated shell -- see the header.
  [switch]$WithLogonTrigger,
  [string]$Repo = (Join-Path $HOME 'aios'),
  [int]$IntervalMinutes = 30
)

$ErrorActionPreference = 'Stop'
$TaskName = 'AIOS Claude Quota Watch'

function Test-TaskPresent {
  # schtasks returns non-zero AND writes to stderr when the task is absent. In
  # PowerShell 5.1, redirecting a native executable's stderr *inside PowerShell*
  # wraps each line in a NativeCommandError ErrorRecord -- which, under the
  # 'Stop' preference set above, turns "the task simply does not exist" into a
  # terminating error and takes -Uninstall down with it. Let cmd own the
  # redirection so PowerShell never sees the stream, and read the exit code.
  cmd /c "schtasks /Query /TN ""$TaskName"" >nul 2>nul"
  return ($LASTEXITCODE -eq 0)
}

if ($Uninstall) {
  if (-not (Test-TaskPresent)) { Write-Host "not installed - nothing to remove"; exit 0 }
  cmd /c "schtasks /Delete /TN ""$TaskName"" /F >nul 2>nul"   # redirection inside cmd; see Test-TaskPresent
  if (Test-TaskPresent) { Write-Host "FAILED: '$TaskName' is still registered"; exit 1 }
  Write-Host "removed scheduled task '$TaskName'"
  exit 0
}

if ($RunNow) {
  if (-not (Test-TaskPresent)) { Write-Host "not installed yet - run without -RunNow first"; exit 1 }
  schtasks /Run /TN $TaskName | Out-Null
  Write-Host "triggered '$TaskName' - check $HOME\.claude\quota-watch-task.log"
  exit 0
}

# --- locate the watcher script -------------------------------------------------
$Watcher = Join-Path $Repo 'hooks\claude-identity\claude-identity.sh'
if (-not (Test-Path $Watcher)) {
  Write-Host "claude-identity.sh not found at $Watcher"
  Write-Host "  pass -Repo <path> if your vault is not at $HOME\aios"
  exit 1
}

# --- locate Git Bash -----------------------------------------------------------
# The task must invoke bash, not PowerShell. Resolve it from the installed git
# rather than hardcoding Program Files, so scoop/winget/portable installs work.
$Bash = $null
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($null -ne $gitCmd) {
  $gitRoot = Split-Path -Parent (Split-Path -Parent $gitCmd.Source)   # ...\Git\cmd\git.exe -> ...\Git
  foreach ($rel in @('bin\bash.exe', 'usr\bin\bash.exe')) {
    $cand = Join-Path $gitRoot $rel
    if (Test-Path $cand) { $Bash = $cand; break }
  }
}
if ($null -eq $Bash) {
  foreach ($cand in @("$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe")) {
    if (Test-Path $cand) { $Bash = $cand; break }
  }
}
if ($null -eq $Bash) {
  Write-Host "Git Bash (bash.exe) not found. Install Git for Windows, then re-run."
  exit 1
}

# --- build the bash command ----------------------------------------------------
# Give bash a POSIX-form path: it is bash's own argument, not Windows'. Redirect
# both streams to a log, mirroring the plist's StandardOut/StandardErrorPath.
$posixWatcher = '/' + ($Watcher -replace ':', '' -replace '\\', '/')
$posixWatcher = $posixWatcher.Substring(0, 2).ToLower() + $posixWatcher.Substring(2)
$bashCmd  = "-lc '`"$posixWatcher`" watch >> `$HOME/.claude/quota-watch-task.log 2>&1'"

# --- task definition XML -------------------------------------------------------
# Written as XML rather than schtasks' flag syntax because /Create's flags cannot
# express repetition-with-duration, StartWhenAvailable and a logon trigger at once.
# Every value below has a named counterpart in the mapping table at the top.
# StartBoundary deliberately in the PAST (today 00:01). Combined with
# StartWhenAvailable that is what produces a prompt catch-up run after the machine
# has been off or asleep -- the stand-in for the logon trigger. A boundary in the
# future would make the operator wait for it before anything ran at all.
$startBoundary = (Get-Date).Date.AddMinutes(1).ToString('yyyy-MM-ddTHH:mm:ss')
$logonTriggerXml = ''
if ($WithLogonTrigger) {
  $logonTriggerXml = @"

    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT1M</Delay>
    </LogonTrigger>
"@
}
$xmlCmd  = [System.Security.SecurityElement]::Escape($Bash)
$xmlArgs = [System.Security.SecurityElement]::Escape($bashCmd)
$xmlDesc = [System.Security.SecurityElement]::Escape(
  "AIOS: safety-net Claude Code quota watcher (rotates Anthropic accounts at threshold). " +
  "Sibling of the macOS launchd agent and the Linux systemd user timer. " +
  "Logic lives in hooks/claude-identity/claude-identity.sh.")

$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>$xmlDesc</Description>
    <URI>\$TaskName</URI>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <StartBoundary>$startBoundary</StartBoundary>
      <Enabled>true</Enabled>
      <Repetition>
        <Interval>PT${IntervalMinutes}M</Interval>
        <Duration>P3650D</Duration>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
    </TimeTrigger>$logonTriggerXml
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$xmlCmd</Command>
      <Arguments>$xmlArgs</Arguments>
    </Exec>
  </Actions>
</Task>
"@

# schtasks requires UTF-16 for /XML; the declaration above says so and the bytes
# have to agree with it or registration fails with a parse error.
$xmlFile = Join-Path $env:TEMP 'aios-quota-watch.xml'
[System.IO.File]::WriteAllText($xmlFile, $xml, [System.Text.Encoding]::Unicode)

schtasks /Create /TN $TaskName /XML $xmlFile /F 2>&1 | ForEach-Object { "  schtasks: $_" }
Remove-Item $xmlFile -ErrorAction SilentlyContinue

# Verify against the scheduler, not against the call. A create that prints a
# success line is not evidence the task is there -- the CIM path taught that the
# hard way, printing "registered" over a rejected definition.
if (-not (Test-TaskPresent)) {
  Write-Host "FAILED: '$TaskName' is not registered after the call returned."
  if ($WithLogonTrigger) {
    Write-Host "  -WithLogonTrigger needs an ELEVATED shell. Re-run without it, or as admin."
  }
  exit 1
}

$catchUp = if ($WithLogonTrigger) { "+ once at logon, 1 min delay" } else { "+ catch-up run after downtime (StartWhenAvailable)" }
Write-Host ""
Write-Host "registered scheduled task '$TaskName' (verified present)"
Write-Host "  every       : $IntervalMinutes minutes $catchUp"
Write-Host "  runs        : $Bash $bashCmd"
Write-Host "  task log    : $HOME\.claude\quota-watch-task.log"
Write-Host "  script log  : $HOME\.claude\quota-watch.log"
Write-Host ""
Write-Host "Verify now :  pwsh -File hooks/claude-identity/install-quota-watch.ps1 -RunNow"
Write-Host "Inspect    :  schtasks /Query /TN '$TaskName' /V /FO LIST"
Write-Host "Remove     :  pwsh -File hooks/claude-identity/install-quota-watch.ps1 -Uninstall"
Write-Host ""
Write-Host "NOTE: rotation only fires once at least two accounts are listed in USER.md"
Write-Host "      under '## Anthropic accounts' AND each has been captured with"
Write-Host "      'claude-switch --capture'. Until then the watcher logs and does nothing."
