#!/usr/bin/env python3
"""Put the Paradise wing into the documentation mockups.

The mockups draw the app's own interface, and the app's interface now opens with
the wing. Rather than redraw it — the brand standard forbids that — the five
feather paths are lifted straight out of `01 BRAND ASSETS/logo/symbol-amber.svg`
and placed with a transform, so the mark in the diagrams is the same geometry as
the mark in the app.

Idempotent: it replaces a marked group if one is already there.

    ./scripts/docs-wing.py
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SYMBOL = ROOT.parent.parent / "01 BRAND ASSETS" / "logo" / "symbol-amber.svg"

svg = SYMBOL.read_text()
box = [float(v) for v in re.search(r'viewBox="([^"]+)"', svg).group(1).split()]
paths = re.findall(r'<path d="([^"]+)"', svg)
if len(paths) != 5:
    sys.exit(f"expected 5 feathers in {SYMBOL}, found {len(paths)}")

ASPECT = box[2] / box[3]


def wing(x: float, y: float, height: float, colour: str) -> str:
    """The mark, its own aspect preserved, with (x, y) as the top-left corner."""
    scale = height / box[3]
    tx = x - box[0] * scale
    ty = y - box[1] * scale
    body = "".join(f'<path d="{d}"/>' for d in paths)
    return (f'<g class="pp-wing" fill="{colour}" '
            f'transform="translate({tx:.3f},{ty:.3f}) scale({scale:.5f})">{body}</g>')


# Each entry replaces one block of hand-drawn glyph with the mark.
# (file, what to replace, x, y, height, colour)
EDITS = [
    ("guide-menu.svg",
     '<rect x="115" y="90" width="12" height="9" rx="1.6" fill="none" stroke="#0A84FF" stroke-width="1.4"/>\n'
     '  <rect x="118" y="100" width="6" height="1.6" rx="0.8" fill="#0A84FF"/>',
     113, 92, 11, "#A16207"),
    ("guide-welcome.svg",
     '<rect x="95" y="130" width="30" height="22" rx="3" fill="none" stroke="#0A84FF" stroke-width="1.8"/>\n'
     '  <rect x="104" y="155" width="12" height="2.4" rx="1" fill="#0A84FF"/>\n'
     '  <path d="M 118 126 L 120.4 132 L 126 134.4 L 120.4 136.8 L 118 142.6 L 115.6 136.8 L 110 134.4 L 115.6 132 Z" fill="#0A84FF" stroke="#FFFFFF" stroke-width="1.2"/>',
     93, 124, 26, "#A16207"),
]

for name, old, x, y, height, colour in EDITS:
    path = ROOT / "docs" / "images" / name
    text = path.read_text()
    marked = re.search(r'<g class="pp-wing".*?</g>', text, re.S)
    if marked:
        text = text[:marked.start()] + wing(x, y, height, colour) + text[marked.end():]
    elif old in text:
        text = text.replace(old, wing(x, y, height, colour))
    else:
        sys.exit(f"{name}: the block to replace is no longer there — check the file")
    path.write_text(text)
    print(f"  {name}: wing at ({x}, {y}), {height}px")
