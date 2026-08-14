<#
.SYNOPSIS
  aios-star-check -- the in-product star ask, as a verdict. No UI, no prompt, no nag.

.DESCRIPTION
  Windows sibling of hooks/aios-star-check. Same four verdicts, same fail-closed rule, same
  fixed repo allowlist, same three-state decline record in .aios-update.

  WHY A SECOND IMPLEMENTATION EXISTS AT ALL -- and why this one is defensible where others
  were refused. The porting doctrine in this repo is deliberately narrow: secret-scan.sh was
  NOT ported because git invokes hooks through `sh`, and a second secret scanner is a drift
  hazard with a security blast radius. The consumer here is different. On Windows the callers
  are the App (Electron) and Glass (a Node extension host), and neither can assume Git Bash
  is on PATH -- a desktop-app user has no reason to have installed Git. A caller that cannot
  invoke the script is not served by the script existing.

  The drift hazard is real anyway, and the header of the bash version says out loud not to
  duplicate this logic. So it is guarded mechanically rather than by intention:
  `.github/workflows/validate.yml` asserts that both implementations name the same repos and
  the same four verdicts, and fails the build when they diverge. If you change one, the CI
  tells you about the other. That check is the only reason this file is acceptable.

.PARAMETER Decline
  Record the decline, once, forever.

.PARAMETER Star
  One or more repos to PUT. Reports each individually; exits non-zero if any failed.

.PARAMETER Json
  Emit JSON instead of key=value lines (for the TypeScript surfaces).
#>
[CmdletBinding()]
param(
  [switch]$Decline,
  [string[]]$Star,
  [switch]$Json
)

$ErrorActionPreference = 'Continue'

$HomeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
$Tracker = if ($env:AIOS_TRACKER) { $env:AIOS_TRACKER } else { Join-Path $HomeDir 'aios\.aios-update' }

# -- The repo allowlist is FIXED and every entry is verified public --------------------
# Kept in lockstep with the bash version by a CI parity check. See that file's comment for
# why `forum` is never listed (private: invisible to strangers, and its GET 404 is
# indistinguishable from "not starred", so the tool would offer and fail forever) and why
# site/org/company-template are not (stars concentrate or they are worth nothing).
$CanonicalRepo = 'The-AIOS/aios'

function Write-Verdict {
  param([string]$Verdict, [string[]]$Repos, [string]$Reason)
  if (-not $Repos) { $Repos = @() }
  if ($Json) {
    [pscustomobject]@{ verdict = $Verdict; repos = $Repos; reason = $Reason } |
      ConvertTo-Json -Compress
  } else {
    # Shell-quoted to match the bash sibling byte-for-byte in shape: its documented caller is
    # `eval "$(aios-star-check)"`, and an unquoted sentence in reason= gets EXECUTED. Keeping
    # both emitters identical means a caller cannot be written against one and break on the
    # other -- the divergence class the CI parity check exists to prevent.
    # POSIX-shell escaping ('\''), NOT PowerShell's doubled-quote convention. The consumer of
    # key=value output is a shell `eval`, so the escape has to be the one a shell understands;
    # emitting PowerShell's would produce a string that only PowerShell can read back, from a
    # format that exists specifically for shells.
    $q = { param($s) "'" + ($s -replace "'", "'\''") + "'" }
    "verdict=$(& $q $Verdict)"
    "repos=$(& $q ($Repos -join ' '))"
    "reason=$(& $q $Reason)"
  }
  exit 0
}

# -- Surface detection ------------------------------------------------------------
# PRIMARY is the surface's own announcement, not an install directory: Glass runs inside
# whatever IDE the operator uses, and no hardcoded list survives them switching editors.
function Test-SurfaceInstalled {
  param([string]$Surface)
  if (Test-Path (Join-Path $HomeDir ".aios\surfaces\$Surface.json")) { return $true }
  switch ($Surface) {
    'glass' {
      # PLAIN foreach, deliberately. `return $true` inside a ForEach-Object scriptblock
      # returns from the SCRIPTBLOCK, not the function -- the loop keeps going and the
      # function falls through to `return $false`, so Glass would read as not-installed on
      # every machine. It is the kind of defect that looks correct in review and is invisible
      # without a Windows box to run it on.
      foreach ($dir in (Get-ChildItem -Path $HomeDir -Directory -Force -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -like '.*' })) {
        $ext = Join-Path $dir.FullName 'extensions'
        if (Test-Path $ext) {
          $hit = Get-ChildItem $ext -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match 'aios-glass' }
          if ($hit) { return $true }
        }
      }
      return $false
    }
    'app' {
      foreach ($p in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\AIOS'),
        (Join-Path $env:PROGRAMFILES  'AIOS'),
        (Join-Path $HomeDir 'AppData\Local\Programs\AIOS')
      )) { if ($p -and (Test-Path $p)) { return $true } }
      return $false
    }
  }
  return $false
}

function Get-CandidateRepos {
  $out = @($CanonicalRepo)
  if (Test-SurfaceInstalled 'glass') { $out += 'The-AIOS/aios-glass' }
  if (Test-SurfaceInstalled 'app')   { $out += 'The-AIOS/aios-app' }
  return $out
}

# -- Decline record: THREE-STATE -- 0 declined - 1 not declined - 2 CANNOT TELL --------
# "Cannot tell" must never collapse into "not declined": an unreadable tracker hides a prior
# decline, and asking again is the nag the three-state design exists to prevent.
function Get-DeclineState {
  if (-not (Test-Path $Tracker)) { return 2 }
  try { $c = Get-Content $Tracker -ErrorAction Stop } catch { return 2 }
  if ($c | Where-Object { $_ -match '^star-ask=declined' }) { return 0 }
  return 1
}

function Set-Decline {
  if (-not (Test-Path $Tracker)) {
    Write-Error "aios-star-check: no tracker at $Tracker -- nothing recorded"; exit 0
  }
  if ((Get-DeclineState) -eq 0) { 'already recorded'; exit 0 }
  # Writes ONLY the star-ask= line; never hash=, synced= or repo=. /aios:update owns hash=,
  # and hand-bumping it past un-pulled commits is what permanently orphans content.
  $kept = Get-Content $Tracker | Where-Object { $_ -notmatch '^star-ask=' }
  $kept += "star-ask=declined:$(Get-Date -Format 'yyyy-MM-dd')"
  Set-Content -Path $Tracker -Value $kept -Encoding UTF8
  'recorded: star-ask=declined -- this will not be asked again'
  exit 0
}

function Invoke-StarPut {
  param([string[]]$Repos)
  $ok = 0; $bad = 0
  foreach ($r in $Repos) {
    $code = $null
    try {
      $raw = & gh api -X PUT "user/starred/$r" -i 2>$null
      if ($raw) { $code = ($raw | Select-Object -First 1) -split '\s+' | Select-Object -Index 1 }
    } catch { $code = $null }
    if ($code -eq '204') { "starred=$r"; $ok++ }
    else { "failed=$r:$(if ($code) { $code } else { 'no-response' })"; $bad++ }
  }
  "summary=$ok starred, $bad failed"
  if ($bad -gt 0) { exit 1 }
  exit 0
}

# -- Dispatch ------------------------------------------------------------
if ($Decline) { Set-Decline }

if ($Star) {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { 'failed=all:no-gh'; exit 1 }
  Invoke-StarPut -Repos $Star
}

if ($env:AIOS_STAR_ASK -eq 'never') {
  Write-Verdict 'unknown' @() 'AIOS_STAR_ASK=never -- automated context'
}
switch (Get-DeclineState) {
  0 { Write-Verdict 'declined' @() 'decline on file in .aios-update' }
  2 { Write-Verdict 'unknown'  @() "tracker unreadable at $Tracker -- a prior decline would be invisible" }
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  Write-Verdict 'unknown' @() 'gh not installed'
}
& gh auth status *> $null
if ($LASTEXITCODE -ne 0) { Write-Verdict 'unknown' @() 'gh not authenticated' }

$unstarred = @()
foreach ($repo in (Get-CandidateRepos)) {
  $code = $null
  try {
    $raw = & gh api -X GET "user/starred/$repo" -i 2>$null
    if ($raw) { $code = ($raw | Select-Object -First 1) -split '\s+' | Select-Object -Index 1 }
  } catch { $code = $null }
  switch ($code) {
    '204' { }
    '404' { $unstarred += $repo }
    default {
      Write-Verdict 'unknown' @() "inconclusive check on $repo (HTTP $(if ($code) { $code } else { 'no-response' }))"
    }
  }
}

if ($unstarred.Count -eq 0) { Write-Verdict 'starred' @() 'all candidate repos already starred' }
Write-Verdict 'unstarred' $unstarred 'not starred, never asked'
