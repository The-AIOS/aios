#!/usr/bin/env python3
"""Moved to hooks/context/context-rungs.py (#309). This stub forwards for one release, then goes."""
import os, runpy, sys
p = os.path.join(os.path.dirname(os.path.realpath(__file__)), "context", "context-rungs.py")
sys.argv[0] = p
runpy.run_path(p, run_name="__main__")
