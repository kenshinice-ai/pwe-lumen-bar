# Product page

The product page (`/lumen`) and the web guide (`/lumen/guide`) live in the tools
site, not here: `PWE Loan Bar/site/public/lumen/`. Edit them there. This repository
used to keep a review copy; it drifted from the live page and was removed on
2026-10-14.

Three things to know before editing them (tools site rules, 2026-10-14):

1. The shared head, header bar and footer of every page are written by
   `PWE Loan Bar/site/chrome.py` between `<!-- chrome:… -->` and `<!-- /chrome -->`.
   Do not edit inside those markers; `deploy.sh` stops if you do. Change
   navigation or footer links in `chrome.py`, then run `python3 site/chrome.py`.
2. Directory links end in a slash (`/lumen/`), single pages do not (`/lumen/guide`).
3. After a deploy, commit the files under `site/public` that the deploy script lists.

The figures come from `docs/images`:

```bash
./scripts/docs-en-figures.py && ./scripts/site-figures.py
```

`site-figures.py` writes straight into `PWE Loan Bar/site/public/lumen/img/`. If a
figure's size changes, update the `width` and `height` on its `<img>` to match.

The disk image is staged by the site's `deploy.sh` from this project's `dist/`
(`./scripts/package.sh --notarize` writes it there). Deploying publishes — it needs
Lee's go.
