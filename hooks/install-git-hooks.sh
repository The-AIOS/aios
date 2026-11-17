#!/usr/bin/env bash
# Moved to hooks/install/install-git-hooks.sh (#309). This stub forwards for one release, then goes.
s="$0"; while [ -L "$s" ]; do t=$(readlink "$s"); case "$t" in /*) s="$t" ;; *) s="$(dirname "$s")/$t" ;; esac; done
exec "$(cd "$(dirname "$s")" && pwd)/install/install-git-hooks.sh" "$@"
