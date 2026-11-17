#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "google-api-python-client>=2.0",
#     "google-auth>=2.0",
#     "google-auth-httplib2>=0.1",
#     "requests>=2.28",
#     "tzdata>=2024.1",
# ]
# ///
# The block above is copied from the moved file: `uv run` reads it from THIS file to build the
# environment, so without it the forwarded script runs with none of its dependencies.
"""Moved to hooks/pipeline/pipeline-executor.py (#309). This stub forwards for one release, then goes."""
import os, runpy, sys
p = os.path.join(os.path.dirname(os.path.realpath(__file__)), "pipeline", "pipeline-executor.py")
sys.argv[0] = p
runpy.run_path(p, run_name="__main__")
