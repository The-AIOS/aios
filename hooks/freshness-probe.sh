#!/usr/bin/env bash
# Moved to hooks/pipeline/freshness-probe.sh (#309). This stub forwards for one release, then goes.
s="$0"; while [ -L "$s" ]; do t=$(readlink "$s"); case "$t" in /*) s="$t" ;; *) s="$(dirname "$s")/$t" ;; esac; done
exec "$(cd "$(dirname "$s")" && pwd)/pipeline/freshness-probe.sh" "$@"
