#!/bin/bash
# Start an Xcode Cloud build on demand. Pushes no longer start builds.
#
#   scripts/xcode-cloud-build.sh                 # list workflows and their manual branches
#   scripts/xcode-cloud-build.sh External        # test + archive main, App Store eligible (TestFlight/App Store)
#   scripts/xcode-cloud-build.sh Internal        # archive dev, internal TestFlight only
#
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

api() { # api METHOD PATH [BODY]
  local args=(-sf -X "$1" -H "Authorization: Bearer $TOKEN")
  [ $# -ge 3 ] && args+=(-H 'Content-Type: application/json' -d "$3")
  curl "${args[@]}" "$API$2"
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

PRODUCT=$(api GET "/v1/apps/$APP_ID/ciProduct" | json 'print(d["data"]["id"])')
WORKFLOWS=$(api GET "/v1/ciProducts/$PRODUCT/workflows")

if [ $# -eq 0 ]; then
  echo "$WORKFLOWS" | json '
for w in d["data"]:
    a = w["attributes"]; m = a.get("manualBranchStartCondition") or {}
    branches = [p["pattern"] for p in (m.get("source") or {}).get("patterns", [])]
    auto = "starts on push" if a.get("branchStartCondition") else "manual only"
    actions = [x["name"] for x in a["actions"]]
    print(a["name"].ljust(10), auto.ljust(15), "branches=%s actions=%s" % (branches, actions))'
  exit 0
fi

read -r WORKFLOW BRANCH < <(echo "$WORKFLOWS" | NAME="$1" json '
w = next((w for w in d["data"] if w["attributes"]["name"] == os.environ["NAME"]), None)
if not w: sys.exit("No workflow named " + os.environ["NAME"])
m = w["attributes"]["manualBranchStartCondition"]["source"]["patterns"][0]["pattern"]
print(w["id"], m)')

REPO=$(api GET "/v1/ciProducts/$PRODUCT/primaryRepositories" | json 'print(d["data"][0]["id"])')
REF=$(api GET "/v1/scmRepositories/$REPO/gitReferences?limit=200" | BRANCH="$BRANCH" json '
print(next(r["id"] for r in d["data"] if r["attributes"]["canonicalName"] == "refs/heads/" + os.environ["BRANCH"]))')

BODY=$(printf '{"data":{"type":"ciBuildRuns","relationships":{"workflow":{"data":{"type":"ciWorkflows","id":"%s"}},"sourceBranchOrTag":{"data":{"type":"scmGitReferences","id":"%s"}}}}}' "$WORKFLOW" "$REF")
api POST /v1/ciBuildRuns "$BODY" | BRANCH="$BRANCH" json '
a = d["data"]["attributes"]
print("Started Xcode Cloud build %s (%s) on %s: %s" % (a["number"], d["data"]["id"], os.environ["BRANCH"], a["executionProgress"]))'
