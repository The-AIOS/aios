# install-git-hooks.ps1 — Windows sibling of install-git-hooks.sh.
# Wires a concurrently-written AIOS repo to the attribution guard (hooks/git/pre-commit).
# The guard scripts themselves are bash + run under Git Bash (Git for Windows always ships
# it; git runs hooks through sh on every platform) — so there is no PowerShell rewrite of the
# LOGIC, only of the per-machine install (git config is not version-controlled).
# Usage:  pwsh -File hooks/install-git-hooks.ps1 [repoPath]   (default: $HOME\aios)
param([string]$Repo = (Join-Path $HOME 'aios'))

$HooksDir = Split-Path -Parent $MyInvocation.MyCommand.Path       # ...\hooks
if (-not (Test-Path (Join-Path $Repo '.git'))) {
  Write-Host "install-git-hooks: $Repo is not a git repo - skipped"; exit 0
}

# core.hooksPath relative to the repo root -> each repo uses its own hooks/git copy
git -C $Repo config core.hooksPath "hooks/git"

# put aios-commit on PATH for callers that use the bare name (idempotent .cmd shim in ~/bin).
# aios-commit is a bash script -> invoke through Git Bash. The full-path calls in the ritual
# commands (~/aios/hooks/aios-commit) resolve under Git Bash without any PATH change.
$Bin = Join-Path $HOME 'bin'; New-Item -ItemType Directory -Force -Path $Bin | Out-Null
$acPath = ($HooksDir -replace '\\','/') + '/aios-commit'
"@echo off`r`nbash `"$acPath`" %*" | Set-Content -Encoding ASCII (Join-Path $Bin 'aios-commit.cmd')

Write-Host "aios git-hooks installed on $Repo -> core.hooksPath = hooks/git"
Write-Host "  raw 'git commit' is now guarded (runs via Git Bash); commit via  aios-commit -m ... <paths>"
Write-Host "  (an aios-commit.cmd shim was written to $Bin; ensure it is on PATH)"
