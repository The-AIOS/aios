#!/usr/bin/env python3
"""
MarkItDown wrapper — converts any file to Markdown.
Usage: python3 hooks/markitdown-convert.py <input_file> [output_file]

If output_file is omitted, prints to stdout.
Supports: PDF, Word, Excel, PowerPoint, images, audio, HTML, CSV, JSON, XML, ZIP, YouTube URLs, EPUB.
"""
import sys
import os

# Use the hooks venv
venv_path = os.path.join(os.path.dirname(__file__), '.venv')
if os.path.exists(venv_path):
    sys.path.insert(0, os.path.join(venv_path, 'lib', f'python{sys.version_info.major}.{sys.version_info.minor}', 'site-packages'))

from markitdown import MarkItDown

# Windows consoles default to cp1252, which cannot encode the em dashes and
# symbols this script prints — so on Windows the report raised
# UnicodeEncodeError and aborted instead of printing. Already guarded this way
# in pipeline-executor.py, route-insight.py and claude-identity/context-monitor.py;
# these callers were simply missed. Safe on macOS/Linux, where stdout is UTF-8.
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")


def main():
    if len(sys.argv) < 2:
        print("Usage: markitdown-convert.py <input_file> [output_file]", file=sys.stderr)
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None

    md = MarkItDown()
    result = md.convert(input_file)
    text = result.text_content or ""

    # No text is a failure, not an empty success. A scanned, image-only PDF has no
    # text layer, and MarkItDown returns nothing for it. Writing an empty file and
    # printing "Converted" let /aios:ingest go on to ingest nothing while looking
    # successful (#283). Exit 2, write no file, and say what to try instead.
    if not text.strip():
        print(f"No text extracted from {input_file}: nothing was written.\n"
              "  A scanned or image-only PDF has no text layer, so there is nothing to convert.\n"
              "  Read the file directly (Claude can read PDFs and images), or run OCR first.",
              file=sys.stderr)
        sys.exit(2)

    if output_file:
        with open(output_file, 'w', encoding="utf-8") as f:
            f.write(text)
        print(f"Converted: {input_file} → {output_file}")
    else:
        print(text)

if __name__ == "__main__":
    main()
