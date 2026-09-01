# Product page

`public/lumenbar/` is the deliverable: one page, both languages, toggled the way every
other page on the group site toggles.

It belongs in the group site, which lives in the PWE Loan Bar project and deploys to
Cloudflare Pages:

```bash
cp -R site/public/lumenbar "../PWE Loan Bar/site/public/"
cd "../PWE Loan Bar/site" && ./deploy.sh        # publishes — ask first
```

`style.css`, `wing-amber.svg`, `wing-navy.svg` and `favicon.svg` in `public/` are **copies
of the group site's own assets**, here only so the page can be opened and reviewed
locally. Do not edit them here — the originals are in `PWE Loan Bar/site/public/`.

Before it goes up:

- `public/lumenbar/download/PWE-Lumen-Bar.dmg` — put the notarised disk image there
  (`./scripts/package.sh --notarize` writes it into `dist/`).
- The Pro section has no price. It links to email instead, and carries a 🔴 comment
  marking where the price goes once it is decided.
