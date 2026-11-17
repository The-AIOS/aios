# Moved to hooks/install/install-git-hooks.ps1 (#309). This stub forwards for one release, then goes.
# Re-run through -File in the same PowerShell edition, so named switches (-Decline, -Json)
# bind as parameters: splatting @args would hand them over as plain strings.
$t = Join-Path $PSScriptRoot 'install/install-git-hooks.ps1'
& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $t @args
exit $LASTEXITCODE
