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

# The hero: the panel alone, on a Studio Display.
#
# It is built from the guide's own sheet rather than drawn again, so the hero and
# the manual cannot drift apart. Three things change on the way:
#
#   · the display becomes a Studio Display — an Apple panel is what most people
#     picture on a Mac desk, and it is what this machine actually drives;
#   · the contrast row goes, because an Apple display answers no DDC and the app
#     therefore does not draw that row at all. Renaming without removing it would
#     be a screenshot of something the software never shows;
#   · everything below closes the gap, and the popover gets 31px shorter.
#
# The annotated sheet keeps its third-party monitor: that figure has to teach
# what DDC gives you, and the callout numbering belongs to it.
HERO = [
    ("guide-menu.svg", "panel.svg", {
        "Philips 27B1U3900": "Studio Display",
        ">DDC<": ">系统<",
        ">27B1U3900<": ">Studio Display<",
        "已把 2 块屏对齐到 27B1U3900 的 60%": "已把 2 块屏对齐到 Studio Display 的 60%",
    }),
    ("guide-menu-en.svg", "panel-en.svg", {
        "Philips 27B1U3900": "Studio Display",
        ">DDC<": ">System<",
        ">27B1U3900<": ">Studio Display<",
        "Matched 2 displays to the 27B1U3900's 60%": "Matched 2 displays to the Studio Display's 60%",
    }),
]

SHIFT = 31          # the height the contrast row occupied
CARD_HEIGHT = 285   # of card 1, before the row was removed

OUT.mkdir(parents=True, exist_ok=True)

for name in COPY:
    source = IMAGES / name
    if not source.exists():
        sys.exit(f"missing {source} — run ./scripts/docs-en-figures.py first")
    (OUT / name).write_text(source.read_text())
print(f"  copied {len(COPY)} figures")

def section(text: str, start: str, end: str) -> tuple:
    """The slice between two of the drawing's own comments."""
    a, b = text.index(start), text.index(end)
    return a, b


for name, out_name, swaps in HERO:
    text = (IMAGES / name).read_text()

    for old, new in swaps.items():
        if old not in text:
            sys.exit(f"{name}: nothing to swap for {old!r}")
        text = text.replace(old, new)

    # Drop the contrast row, and pull the four rows under it up into its place.
    a, b = section(text, "  <!-- contrast -->", "  <!-- warmth -->")
    text = text[:a] + text[b:]
    a, b = section(text, "  <!-- warmth -->", "  <!-- status bar -->")
    text = (text[:a] + f'  <g transform="translate(0,-{SHIFT})">\n' + text[a:b]
            + "  </g>\n" + text[b:])

    # The status bar and the footer come up with them, and the card and popover
    # lose the same height.
    a, b = section(text, "  <!-- status bar -->", "  <!-- ===================== card 2")
    text = (text[:a] + f'  <g transform="translate(0,-{SHIFT})">\n' + text[a:b]
            + "  </g>\n" + text[b:])
    text = text.replace(f'<rect x="113" y="178" width="354" height="{CARD_HEIGHT}" rx="13"',
                        f'<rect x="113" y="178" width="354" height="{CARD_HEIGHT - SHIFT}" rx="13"')

    # Card 2 and the callouts belong to the manual, not to a hero.
    text = text[:text.index("  <!-- ===================== card 2")] + "</svg>\n"

    box = f"104 76 372 {476 - SHIFT}"
    width, height = box.split()[2:]
    text, count = re.subn(r'viewBox="[^"]*"( width="[^"]*")?( height="[^"]*")?',
                          f'viewBox="{box}" width="{width}" height="{height}"',
                          text, count=1)
    if not count:
        sys.exit(f"{name}: no viewBox to crop")
    (OUT / out_name).write_text(text)
    print(f"  {out_name}  ({box})")
