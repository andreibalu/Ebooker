#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
: "${E2E_SIMULATOR_UDID:?Set E2E_SIMULATOR_UDID to a dedicated Unpaged e2e simulator}"
# Refuse existing personal simulators even when an explicit UDID was supplied.
simulator_name="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; uid=sys.argv[1]; print(next((d["name"] for devices in json.load(sys.stdin)["devices"].values() for d in devices if d["udid"] == uid),""))' "$E2E_SIMULATOR_UDID")"
[[ "$simulator_name" == 'Unpaged e2e'* ]] || { echo 'Refusing simulator whose name does not start with Unpaged e2e' >&2; exit 2; }
scratch_dir="${E2E_BUILD_DIR:-$(mktemp -d /private/tmp/unpaged-e2e-build.XXXXXX)}"
mkdir -p "$scratch_dir"
xcrun simctl boot "$E2E_SIMULATOR_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$E2E_SIMULATOR_UDID" -b
xcodebuild -project "$repo_root/Pageless.xcodeproj" -scheme Pageless \
  -destination "platform=iOS Simulator,id=$E2E_SIMULATOR_UDID" \
  -configuration Debug -derivedDataPath "$scratch_dir/dd" build-for-testing \
  > "$scratch_dir/build.log" 2>&1 &
build_pid=$!
echo "Building in $scratch_dir (log: $scratch_dir/build.log)"
if ! wait "$build_pid"; then tail -80 "$scratch_dir/build.log"; exit 1; fi
app_path="$scratch_dir/dd/Build/Products/Debug-iphonesimulator/Pageless.app"
xcrun simctl install "$E2E_SIMULATOR_UDID" "$app_path"
echo "Installed $app_path on $simulator_name ($E2E_SIMULATOR_UDID)"
# build-for-testing also produces the hosted unit-test bundle; tests/purchases.e2e.ts runs one
# hosted test from it to clear the local StoreKit ledger. Point E2E_BUILD_DIR here to reuse it.
echo "E2E_BUILD_DIR=$scratch_dir"
