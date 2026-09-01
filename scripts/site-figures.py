#!/usr/bin/env python3
"""Stage the documentation figures the website uses.

    ./scripts/docs-en-figures.py && ./scripts/site-figures.py

`docs/images` is the source of truth for every figure; this copies the ones the
product page and the web guide reference into `site/public/lumen/img/`, and
crops the panel out of its annotated sheet for the hero.

The crop is a viewBox change, nothing else — the artwork is vector, so the hero
is the same drawing at full sharpness with the callouts left outside the frame.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
IMAGES = ROOT / "docs" / "images"
OUT = ROOT / "site" / "public" / "lumen" / "img"

# Copied as they are. Each Chinese figure is paired with its English twin, except
# hidpi-explained, which was drawn bilingual.
COPY = [
    "hidpi-explained.svg",
    "guide-menubar.svg", "guide-menubar-en.svg",
    "guide-menu.svg", "guide-menu-en.svg",
    "guide-pro.svg", "guide-pro-en.svg",
    "guide-settings.svg", "guide-settings-en.svg",
    "guide-actions-menu.svg", "guide-actions-menu-en.svg",
]

# The panel alone, lifted out of the annotated sheet for the hero.
# (source, output, viewBox)
CROP = [
    ("guide-menu.svg", "panel.svg", "104 76 372 476"),
    ("guide-menu-en.svg", "panel-en.svg", "104 76 372 476"),
]

OUT.mkdir(parents=True, exist_ok=True)

for name in COPY:
    source = IMAGES / name
    if not source.exists():
        sys.exit(f"missing {source} — run ./scripts/docs-en-figures.py first")
    (OUT / name).write_text(source.read_text())
print(f"  copied {len(COPY)} figures")

for name, out_name, box in CROP:
    text = (IMAGES / name).read_text()
    width, height = box.split()[2:]
    text, count = re.subn(r'viewBox="[^"]*"( width="[^"]*")?( height="[^"]*")?',
                          f'viewBox="{box}" width="{width}" height="{height}"',
                          text, count=1)
    if not count:
        sys.exit(f"{name}: no viewBox to crop")
    (OUT / out_name).write_text(text)
    print(f"  {out_name}  ({box})")
