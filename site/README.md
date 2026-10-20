# Product page

The product page (`/lumen`) and the web guide (`/lumen/guide`) live in the tools
site, not here: `PWE Loan Bar/site/public/lumen/`. Edit them there. This repository
used to keep a review copy; it drifted from the live page and was removed on
2026-10-14.

Rules for editing them. The full text is in the tools site's own `site/README.md`
("Shared page parts", "Layout and rhythm"); this is the part Lumen needs (2026-10-21).

1. The site is called PWE Tools. The header, the product bar (Overview · Guide · Specs,
   plus Download), "Recent updates" and the footer are written by
   `PWE Loan Bar/site/chrome.py` between `<!-- chrome:… -->` and `<!-- /chrome -->`.
   Do not edit inside those markers; `deploy.sh` stops if you do. Change them in
   `chrome.py` (`SUBNAV`, `ACTION`), then run `python3 site/chrome.py`.
2. "Recent updates" on `/lumen/` reads the `lumenbar` entry in
   `PWE Loan Bar/site/functions/_release.js`. A release updates it there.
3. Layout: one 980px column, one left edge, body text at most 38em. The second hero
   action is a text link with › (`.more`), not a second button. Amber is a signal only.
4. Directory links end in a slash (`/lumen/`); single pages do not (`/lumen/guide`,
   `/support`, `/help`). Help questions go to `/help`; `/support` is only about
   supporting PWE.
5. Tell the "PWE Tools AI 设计" session before changing anything under `lumen/`.
   Several sessions deploy from the same working tree.

The figures come from `docs/images`:

```bash
./scripts/docs-en-figures.py && ./scripts/site-figures.py
```

`site-figures.py` writes straight into `PWE Loan Bar/site/public/lumen/img/`.
Commit what it changed there straight away: another session may deploy from that
working tree at any time, and uncommitted figures go live with it. If a figure's
size changes, update the `width` and `height` on its `<img>` to match.

Edit the figures in `docs/images`, never on the site: the script overwrites the
site's copies. (`hidpi-explained.svg` was fixed on the site on 2026-10-21 and copied
back here the same day.)

The disk image is staged by the site's `deploy.sh` from this project's `dist/`
(`./scripts/package.sh --notarize` writes it there). Deploying publishes — it needs
Lee's go.
