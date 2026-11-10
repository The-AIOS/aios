"""generate_image passes reference images to the model, before the prompt, and refuses bad paths.

Runs offline: google.genai and mcp are replaced by stand-ins that record the request, so the
test checks what the server SENDS, not what Gemini answers. A control asserts that a call
without references still sends the prompt alone, exactly as before the parameter existed."""
import importlib.util, os, sys, tempfile, types
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sent = {}

class FakePart:
    def __init__(self, data, mime_type): self.data, self.mime_type = data, mime_type
    @classmethod
    def from_bytes(cls, data, mime_type): return cls(data, mime_type)

class FakeModels:
    def generate_content(self, model, contents, config):
        sent["contents"] = contents
        img = types.SimpleNamespace(inline_data=types.SimpleNamespace(data=b"\x89PNG fake"))
        return types.SimpleNamespace(candidates=[types.SimpleNamespace(content=types.SimpleNamespace(parts=[img]))])

genai = types.ModuleType("google.genai")
genai.Client = lambda api_key: types.SimpleNamespace(models=FakeModels())
gtypes = types.ModuleType("google.genai.types")
gtypes.Part = FakePart
gtypes.GenerateContentConfig = lambda **k: k
gtypes.ImageConfig = lambda **k: k
genai.types = gtypes
google = types.ModuleType("google"); google.genai = genai
fastmcp = types.ModuleType("mcp.server.fastmcp")
class FastMCP:
    def __init__(self, name): pass
    def tool(self): return lambda f: f
    def run(self): pass
fastmcp.FastMCP = FastMCP
for name, mod in {"google": google, "google.genai": genai, "google.genai.types": gtypes,
                  "mcp": types.ModuleType("mcp"), "mcp.server": types.ModuleType("mcp.server"),
                  "mcp.server.fastmcp": fastmcp}.items():
    sys.modules[name] = mod
os.environ["GEMINI_API_KEY"] = "test-only"

spec = importlib.util.spec_from_file_location("server", ROOT / "mcps/nano-banana-mcp/server.py")
server = importlib.util.module_from_spec(spec); spec.loader.exec_module(server)

fails = 0
def check(cond, msg):
    global fails
    print(("ok   " if cond else "FAIL ") + msg); fails += 0 if cond else 1

with tempfile.TemporaryDirectory() as d:
    ref = Path(d) / "hero.png"; ref.write_bytes(b"\x89PNG ref")
    out = Path(d) / "out.png"

    # control: no references -> the prompt alone, as before
    r = server.generate_image("a fox", output_path=str(out))
    check(sent["contents"] in ("a fox", ["a fox"]), "without references the request is the prompt alone")
    check(r.get("reference_images") == [], "result reports no references")

    # one reference: image part first, prompt last
    server.generate_image("same fox, now running", output_path=str(out), reference_images=[str(ref)])
    c = sent["contents"]
    check(len(c) == 2 and isinstance(c[0], FakePart) and c[1] == "same fox, now running", "reference image goes before the prompt")
    check(c[0].mime_type == "image/png" and c[0].data == b"\x89PNG ref", "the reference's bytes and type are sent")

    # at most three
    server.generate_image("x", output_path=str(out), reference_images=[str(ref)] * 5)
    check(sum(isinstance(p, FakePart) for p in sent["contents"]) == 3, "no more than three references are sent")

    # refusals
    for bad, why in [(str(Path(d) / "missing.png"), "a missing file"), (str(Path(d) / "notes.txt"), "a non-image type")]:
        if bad.endswith(".txt"): Path(bad).write_text("hello")
        try:
            server.generate_image("x", output_path=str(out), reference_images=[bad]); check(False, f"refuses {why}")
        except ValueError:
            check(True, f"refuses {why}")

sys.exit(1 if fails else 0)
