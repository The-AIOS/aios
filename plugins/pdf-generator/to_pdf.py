#!/usr/bin/env python3
"""
Convert Sovra-branded HTML to PDF using WeasyPrint.

Usage:
    python to_pdf.py input.html                    # -> input.pdf
    python to_pdf.py input.html output.pdf         # -> output.pdf

Programmatic:
    from to_pdf import html_to_pdf
    html_to_pdf("<html>...</html>", "output.pdf")

Styles are inline in the HTML (same approach as web-site repo).
No external CSS needed.
"""

import os
import sys

PLUGIN_DIR = os.path.dirname(os.path.abspath(__file__))


def html_to_pdf(html, output_path):
    """
    Convert an HTML string to PDF.
    Styles should be inline in the HTML (inside <style> tags).
    """
    from weasyprint import HTML

    if '<html' not in html.lower():
        html = f"""<!DOCTYPE html>
<html lang="es">
<head><meta charset="utf-8"></head>
<body>{html}</body>
</html>"""

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    doc = HTML(string=html, base_url=PLUGIN_DIR)
    doc.write_pdf(output_path)
    print(f"PDF generated: {output_path}")


def file_to_pdf(input_path, output_path=None):
    """Convert an HTML file to PDF."""
    from weasyprint import HTML

    if output_path is None:
        output_path = os.path.splitext(input_path)[0] + '.pdf'

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    doc = HTML(filename=input_path, base_url=os.path.dirname(os.path.abspath(input_path)))
    doc.write_pdf(output_path)
    print(f"PDF generated: {output_path}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python to_pdf.py input.html [output.pdf]")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None
    file_to_pdf(input_file, output_file)
