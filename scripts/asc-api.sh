#!/bin/bash
# Call the App Store Connect API with the owner's key. Prints the JSON body, even for an error.
#
#   scripts/asc-api.sh GET  '/v1/apps/6761081641/appStoreVersions?limit=3'
#   scripts/asc-api.sh PATCH /v1/reviewSubmissions/<id> '{"data":{...}}'
#
# Percent-encode brackets in query strings (filter%5Bversion%5D=126): curl globs bare [ ].
# Exits 1 on an HTTP error after printing Apple's errors array.
#
# Sourced (`. scripts/asc-api.sh`), it defines `api` and `json` and sets TOKEN for the caller.
# Credentials stay outside the repo: ~/.appstoreconnect/issuer_id and
# ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8. Set ASC_KEY_ID to pick a key;
# otherwise the first key that can read the app is used.
set -euo pipefail

APP_ID=6761081641
API=https://api.appstoreconnect.apple.com
KEYS=~/.appstoreconnect/private_keys
ISSUER=$(tr -d '[:space:]' < ~/.appstoreconnect/issuer_id)

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

token() {
  local kid=$1 now header payload der
  now=$(date +%s)
  header=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$kid" | b64url)
  payload=$(printf '{"iss":"%s","iat":%d,"exp":%d,"aud":"appstoreconnect-v1"}' "$ISSUER" "$now" $((now + 1100)) | b64url)
  # ES256 wants raw r||s; openssl emits DER SEQUENCE{INTEGER r, INTEGER s}.
  der=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$KEYS/AuthKey_$kid.p8" | xxd -p | tr -d '\n')
  printf '%s.%s.%s' "$header" "$payload" "$(python3 -I -c '
import base64, sys
d = bytes.fromhex(sys.argv[1]); i = 2 + (d[1] & 0x7f if d[1] & 0x80 else 0)
def integer(i):
    n = d[i + 1]; return d[i + 2:i + 2 + n].lstrip(b"\0").rjust(32, b"\0"), i + 2 + n
r, i = integer(i); s, _ = integer(i)
print(base64.urlsafe_b64encode(r + s).decode().rstrip("="))' "$der")"
}

api() { # api METHOD PATH [BODY]; prints the body, fails on HTTP >= 400
  local args=(-s -X "$1" -H "Authorization: Bearer $TOKEN" -w '\n%{http_code}')
  [ $# -ge 3 ] && args+=(-H 'Content-Type: application/json' -d "$3")
  local out code
  out=$(curl "${args[@]}" "$API$2")
  code=${out##*$'\n'}
  printf '%s\n' "${out%$'\n'*}"
  [ "$code" -lt 400 ] || { echo "HTTP $code from $1 $2" >&2; return 1; }
}

json() { python3 -I -c "import json, os, sys; d = json.load(sys.stdin); $1"; }

TOKEN=""
for path in $KEYS/AuthKey_*.p8; do
  kid=$(basename "$path" .p8); kid=${kid#AuthKey_}
  [ -n "${ASC_KEY_ID:-}" ] && [ "$kid" != "$ASC_KEY_ID" ] && continue
  TOKEN=$(token "$kid")
  api GET "/v1/apps/$APP_ID" >/dev/null 2>&1 && break
  TOKEN=""
done
[ -n "$TOKEN" ] || { echo "No App Store Connect key in $KEYS can read app $APP_ID." >&2; exit 1; }

# Run directly, make one call. Sourced, leave the functions to the caller.
[ "${BASH_SOURCE[0]}" = "$0" ] && api "$@"
true
