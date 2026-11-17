import importlib.util, sys
s = importlib.util.spec_from_file_location("tp", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
R = "’"
q = m.ps_quote("x" + R + "; Remove-Item ~ ; " + R + " and 'y'")
assert q == "'x" + R + R + "; Remove-Item ~ ; " + R + R + " and ''y'''", q
