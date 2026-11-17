# Moved to hooks/install/install-git-hooks.ps1 (#309). This stub forwards for one release, then goes.
& (Join-Path $PSScriptRoot 'install/install-git-hooks.ps1') @args
exit $LASTEXITCODE
