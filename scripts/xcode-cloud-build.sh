#!/bin/bash
# Start an Xcode Cloud build on demand. Pushes no longer start builds.
#
#   scripts/xcode-cloud-build.sh                 # list workflows and their manual branches
#   scripts/xcode-cloud-build.sh External        # test + archive main, App Store eligible (TestFlight/App Store)
#   scripts/xcode-cloud-build.sh Internal        # archive dev, internal TestFlight only
#
# Credentials and key choice: see scripts/asc-api.sh.
set -euo pipefail

# Signs the JWT and defines api and json.
. "$(dirname "$0")/asc-api.sh"

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
