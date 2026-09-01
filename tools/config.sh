# Shared settings for the selling side. Sourced by tools/issue.sh.

PRODUCT_NAME="PWE Lumen Bar"
VENDOR="PWE Group Pty Ltd"
SUPPORT_EMAIL="lee.liu.melbourne@gmail.com"

# The stable link the site always serves; deploy.sh keeps a versioned copy beside
# it, so an old link in an old licence email never turns into a 404.
DOWNLOAD_URL="https://pwestudio.site/lumen/download/PWE-Lumen-Bar.dmg"

# The licence tier. There is only one today; the field exists so the ledger does
# not have to change shape when there is a second.
TIER="pro"
