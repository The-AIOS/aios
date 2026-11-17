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
"""Moved to hooks/pipeline/pipeline-executor.py (#309). This stub forwards for one release, then goes.

Run as a script, it runs the real file with that file's folder first on sys.path. Imported as a
module, it loads the real module and takes on its names, running nothing.
"""
import importlib.util, os, runpy, sys
_P = os.path.join(os.path.dirname(os.path.realpath(__file__)), "pipeline", "pipeline-executor.py")
if __name__ == "__main__":
    sys.argv[0] = _P
    sys.path[0] = os.path.dirname(_P)
    runpy.run_path(_P, run_name="__main__")
else:
    _s = importlib.util.spec_from_file_location(__name__ + "_moved", _P)
    _m = importlib.util.module_from_spec(_s)
    _s.loader.exec_module(_m)
    globals().update({k: v for k, v in vars(_m).items() if not k.startswith("__")})
