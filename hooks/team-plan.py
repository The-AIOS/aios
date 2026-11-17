#!/usr/bin/env python3
"""Moved to hooks/agents/team-plan.py (#309). This stub forwards for one release, then goes.

Run as a script, it runs the real file with that file's folder first on sys.path (so its own
sibling imports resolve there). Imported as a module, it loads the real module and takes on its
names, running nothing: `import team_plan` from hooks/ must keep meaning the module, never its main().
"""
import importlib.util, os, runpy, sys
_P = os.path.join(os.path.dirname(os.path.realpath(__file__)), "agents", "team-plan.py")
if __name__ == "__main__":
    sys.argv[0] = _P
    sys.path[0] = os.path.dirname(_P)
    runpy.run_path(_P, run_name="__main__")
else:
    _s = importlib.util.spec_from_file_location(__name__ + "_moved", _P)
    _m = importlib.util.module_from_spec(_s)
    _s.loader.exec_module(_m)
    globals().update({k: v for k, v in vars(_m).items() if not k.startswith("__")})
