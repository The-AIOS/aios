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

def main():
    if len(sys.argv) < 2:
        print("Usage: markitdown-convert.py <input_file> [output_file]", file=sys.stderr)
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None

    md = MarkItDown()
    result = md.convert(input_file)

    if output_file:
        with open(output_file, 'w') as f:
            f.write(result.text_content)
        print(f"Converted: {input_file} → {output_file}")
    else:
        print(result.text_content)

if __name__ == "__main__":
    main()
