#!/bin/bash
#
# Issue a PWE Lumen Bar Pro licence.
#
# Run it with no arguments and it asks for what it needs. Everything sensitive —
# the signing key, the ledger, every issued licence — lives in
# ~/.pwe-lumenbar-signing, so that one folder is the only thing to back up.
#
#   ./tools/issue.sh                                   ask
#   ./tools/issue.sh --email jo@example.com --name Jo
#   ./tools/issue.sh --email jo@example.com --cn       write the email in Chinese
#   ./tools/issue.sh --list                            every licence issued so far
#   ./tools/issue.sh --reissue 1004                    re-send an existing one
#
# It writes the customer email and puts it on the clipboard. It never sends
# anything by itself.
#
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_DIR="$PWD"
source "$PROJECT_DIR/tools/config.sh"

VAULT="$HOME/.pwe-lumenbar-signing"
LICENSES="$VAULT/licenses"
LEDGER="$VAULT/ledger.csv"
SIGNING_KEY="$VAULT/signing-key"
SIGNER="$PROJECT_DIR/tools/sign-license.swift"

BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; OFF=$'\033[0m'

mkdir -p "$LICENSES"
chmod 700 "$VAULT"

# ---------------------------------------------------------------- the key
#
# Older checkouts kept the signing key in the repository root. It is git-ignored
# there, but "git-ignored" and "not in the backup you just shared" are different
# properties — move it into the vault the first time this runs.
if [[ ! -f "$SIGNING_KEY" && -f "$PROJECT_DIR/.license-signing-key" ]]; then
  mv "$PROJECT_DIR/.license-signing-key" "$SIGNING_KEY"
  chmod 600 "$SIGNING_KEY"
  echo "  Moved the signing key out of the repository and into $VAULT"
fi

if [[ ! -f "$SIGNING_KEY" ]]; then
  cat <<KEY
  ✗ No signing key at $SIGNING_KEY

    Without it no licence can be issued, and the public half embedded in the app
    only verifies keys made with this exact private half. If you have a backup,
    restore it there. If it is genuinely lost, a new pair has to be generated and
    LicenseStore.publicKeyBase64 updated — which invalidates every key already
    sold.
KEY
  exit 1
fi

# ---------------------------------------------------------------- ledger

if [[ ! -f "$LEDGER" ]]; then
  echo "order,date,email,name,tier,file" > "$LEDGER"
  chmod 600 "$LEDGER"
fi

show_ledger() {
  local count
  count=$(( $(wc -l < "$LEDGER") - 1 ))
  echo
  if [[ "$count" -le 0 ]]; then
    echo "  No licences issued yet."
  else
    echo "  ${BOLD}$count licence(s)${OFF}"
    echo
    column -s, -t < "$LEDGER" | sed 's/^/  /'
  fi
  echo
  echo "  ${DIM}Ledger: $LEDGER${OFF}"
  echo
}

# ---------------------------------------------------------------- arguments

EMAIL=""; NAME=""; ORDER=""; CHINESE=0; REISSUE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --email)   EMAIL="$2"; shift 2 ;;
    --name)    NAME="$2"; shift 2 ;;
    --order)   ORDER="$2"; shift 2 ;;
    --reissue) REISSUE="$2"; shift 2 ;;
    --cn)      CHINESE=1; shift ;;
    --list)    show_ledger; exit 0 ;;
    --help|-h) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "✗ unknown option: $1"; exit 1 ;;
  esac
done

if [[ -n "$REISSUE" ]]; then
  ROW=$(awk -F, -v o="$REISSUE" '$1 == o' "$LEDGER" | head -1)
  [[ -n "$ROW" ]] || { echo "  ✗ Order $REISSUE is not in the ledger. Try --list"; exit 1; }
  ORDER="$REISSUE"
  EMAIL=$(echo "$ROW" | cut -d, -f3)
  NAME=$(echo "$ROW" | cut -d, -f4)
  echo "  Re-issuing order $ORDER, first issued $(echo "$ROW" | cut -d, -f2)"
fi

if [[ -z "$EMAIL" ]]; then
  printf "  Buyer's email: "
  read -r EMAIL
fi
[[ "$EMAIL" == *@* ]] || { echo "  ✗ That does not look like an email address."; exit 1; }
if [[ -z "$NAME" && -z "$REISSUE" ]]; then
  printf "  Their name (enter to skip): "
  read -r NAME
fi

EMAIL="$(echo "$EMAIL" | tr '[:upper:]' '[:lower:]' | xargs)"

# ---------------------------------------------------------------- order number

if [[ -z "$ORDER" ]]; then
  LAST=$(tail -n +2 "$LEDGER" | cut -d, -f1 | sort -n | tail -1)
  ORDER=$(( ${LAST:-1000} + 1 ))
fi

# ---------------------------------------------------------------- sign

KEY="$(swift "$SIGNER" --email "$EMAIL" --key-file "$SIGNING_KEY")"
[[ -n "$KEY" ]] || { echo "  ✗ Signing produced nothing."; exit 1; }

SAFE_EMAIL="$(printf '%s' "$EMAIL" | tr -c 'a-zA-Z0-9@._-' '_')"
KEY_FILE="$LICENSES/$ORDER-$SAFE_EMAIL.txt"

# Grouped for the buyer's benefit; the app strips whitespace before checking.
GROUPED="$(echo "$KEY" | fold -w 22)"

{
  echo "PWE Lumen Bar Pro licence"
  echo "order $ORDER · $(date +%Y-%m-%d) · $EMAIL"
  echo
  echo "-----BEGIN PWE LUMEN BAR LICENCE-----"
  echo "$GROUPED"
  echo "-----END PWE LUMEN BAR LICENCE-----"
} > "$KEY_FILE"
chmod 600 "$KEY_FILE"

if [[ -z "$REISSUE" ]]; then
  # Plain CSV with no quoting, so a comma inside a field would shear the row.
  printf "%s,%s,%s,%s,%s,%s\n" \
    "$ORDER" "$(date +%Y-%m-%d)" "$EMAIL" "${NAME//,/ }" "$TIER" "$KEY_FILE" >> "$LEDGER"
fi

# ---------------------------------------------------------------- the email

# Written as a plain branch, not a `$(... && echo ...)`: under `set -e` a command
# substitution that ends in a false test takes the whole assignment down with it.
if [[ "$CHINESE" == "1" ]]; then
  TEMPLATE="$PROJECT_DIR/tools/templates/customer-email-cn.txt"
else
  TEMPLATE="$PROJECT_DIR/tools/templates/customer-email.txt"
fi
[[ -f "$TEMPLATE" ]] || { echo "  ✗ Missing template $TEMPLATE"; exit 1; }

FIRST_NAME="${NAME%% *}"
if [[ -z "$FIRST_NAME" ]]; then
  if [[ "$CHINESE" == "1" ]]; then FIRST_NAME="你好"; else FIRST_NAME="there"; fi
fi

# The one-click link the app answers on pwelumen://activate.
urlencode() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }
LINK="pwelumen://activate?email=$(urlencode "$EMAIL")&key=$(urlencode "$KEY")"

if [[ -n "$DOWNLOAD_URL" ]]; then
  DOWNLOAD_LINE="$DOWNLOAD_URL"
elif [[ "$CHINESE" == "1" ]]; then
  DOWNLOAD_LINE="（安装包随本邮件附上）"
else
  DOWNLOAD_LINE="(the installer is attached to this email)"
fi

EMAIL_FILE="$LICENSES/$ORDER-email.txt"
export PWE_FIRST_NAME="$FIRST_NAME" PWE_EMAIL="$EMAIL" PWE_ORDER="$ORDER"
export PWE_GROUPED="$GROUPED" PWE_LINK="$LINK" PWE_DOWNLOAD="$DOWNLOAD_LINE"
export PWE_SUPPORT="$SUPPORT_EMAIL"
python3 - "$TEMPLATE" "$EMAIL_FILE" <<'PY'
import os, sys
template, out = sys.argv[1], sys.argv[2]
text = open(template, encoding="utf-8").read()
for token, value in {
    "{{first_name}}": os.environ["PWE_FIRST_NAME"],
    "{{email}}":      os.environ["PWE_EMAIL"],
    "{{order}}":      os.environ["PWE_ORDER"],
    "{{key}}":        os.environ["PWE_GROUPED"],
    "{{link}}":       os.environ["PWE_LINK"],
    "{{download}}":   os.environ["PWE_DOWNLOAD"],
    "{{support}}":    os.environ["PWE_SUPPORT"],
}.items():
    text = text.replace(token, value)
open(out, "w", encoding="utf-8").write(text)
PY

pbcopy < "$EMAIL_FILE" 2>/dev/null || true

echo
echo "  ${GREEN}${BOLD}Licence $ORDER issued${OFF}"
echo "    Email    $EMAIL"
echo "    Key      $KEY_FILE"
echo "    Message  $EMAIL_FILE   ${DIM}(now on your clipboard)${OFF}"
echo "    ${DIM}Ledger   $LEDGER${OFF}"
echo
if [[ "$CHINESE" == "1" ]]; then
  echo "    Subject: 您的 PWE Lumen Bar Pro 授权码（订单 $ORDER）"
else
  echo "    Subject: Your PWE Lumen Bar Pro licence (order $ORDER)"
fi
echo
