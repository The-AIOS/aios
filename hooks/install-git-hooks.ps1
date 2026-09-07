# install-git-hooks.ps1 -- Windows sibling of install-git-hooks.sh.
# Wires a concurrently-written AIOS repo to the attribution guard (hooks/git/pre-commit).
# The guard scripts themselves are bash + run under Git Bash (Git for Windows always ships
# it; git runs hooks through sh on every platform) -- so there is no PowerShell rewrite of the
# LOGIC, only of the per-machine install (git config is not version-controlled).
# Usage:  pwsh -File hooks/install-git-hooks.ps1 [repoPath]   (default: $HOME\aios)
param([string]$Repo = (Join-Path $HOME 'aios'))

$HooksDir = Split-Path -Parent $MyInvocation.MyCommand.Path       # ...\hooks
if (-not (Test-Path (Join-Path $Repo '.git'))) {
  Write-Host "install-git-hooks: $Repo is not a git repo - skipped"; exit 0
}

# core.hooksPath relative to the repo root -> each repo uses its own hooks/git copy
git -C $Repo config core.hooksPath "hooks/git"

# Normalize CRLF -> LF on the hook scripts. THIS PLATFORM IS THE ONE THAT NEEDS IT:
# core.autocrlf=true is the Git-for-Windows default, so it rewrites LF -> CRLF on checkout,
# and git then runs these bash hooks through sh -- where a trailing \r makes the shebang
# unresolvable (measured: "env: bash\r: No such file or directory", exit 127). git reads any
# non-zero pre-commit/pre-push exit as a refusal, so the operator cannot commit or push at
# all, with an error naming neither AIOS nor the cause.
# .gitattributes does carry `text eol=lf` for these paths, but it is Tier-0 -- it never
# reaches an operator vault through /aios:update, and a fork's copy freezes at fork time.
# The installer is the only surface that reaches every operator.
# Byte-level on purpose: Set-Content re-encodes and can add a BOM, which breaks a shebang
# just as thoroughly as the \r did. Only a CR that precedes LF is dropped.
$hookFiles = @()
$gitHookDir = Join-Path $HooksDir 'git'
if (Test-Path $gitHookDir) {
  $hookFiles += Get-ChildItem -File $gitHookDir | Where-Object { $_.Extension -ne '.md' }
}
$ac = Join-Path $HooksDir 'aios-commit'
if (Test-Path $ac) { $hookFiles += Get-Item $ac }
foreach ($f in $hookFiles) {
  try {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($bytes -notcontains 13) { continue }
    $out = [System.Collections.Generic.List[byte]]::new()
    for ($i = 0; $i -lt $bytes.Length; $i++) {
      if ($bytes[$i] -eq 13 -and ($i + 1) -lt $bytes.Length -and $bytes[$i + 1] -eq 10) { continue }
      $out.Add($bytes[$i])
    }
    [System.IO.File]::WriteAllBytes($f.FullName, $out.ToArray())
    Write-Host "  normalized CRLF -> LF: $($f.Name)"
  } catch {
    Write-Host "  WARNING: could not normalize line endings in $($f.FullName) - the hook may not run"
  }
}

# put aios-commit on PATH for callers that use the bare name (idempotent .cmd shim in ~/bin).
# aios-commit is a bash script -> invoke through Git Bash. The full-path calls in the ritual
# commands (~/aios/hooks/aios-commit) resolve under Git Bash without any PATH change.
$Bin = Join-Path $HOME 'bin'; New-Item -ItemType Directory -Force -Path $Bin | Out-Null
$acPath = ($HooksDir -replace '\\','/') + '/aios-commit'
"@echo off`r`nbash `"$acPath`" %*" | Set-Content -Encoding ASCII (Join-Path $Bin 'aios-commit.cmd')

Write-Host "aios git-hooks installed on $Repo -> core.hooksPath = hooks/git"
Write-Host "  raw 'git commit' is now guarded (runs via Git Bash); commit via  aios-commit -m ... <paths>"
Write-Host "  pre-push refuses off-limits remote owners - inert until you set them:"
Write-Host "      git config --global aios.blockedRemoteOwners ""AcmeCorp anotherorg"""
Write-Host "  (an aios-commit.cmd shim was written to $Bin; ensure it is on PATH)"
