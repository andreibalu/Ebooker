#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
scratch_dir=/tmp/shots140
simulator_id=1190AB80-92FA-4D00-A2DE-AC5C998B6B62

mkdir -p "$scratch_dir"
python3 - "$HOME/abs-test/README.md" "$scratch_dir/abs.json" <<'PY'
import json
import os
import pathlib
import re
import sys

readme = pathlib.Path(sys.argv[1]).read_text()
patterns = {
    "url": r"URL\s+(\S+)",
    "username": r"username\s+(\S+)",
    "password": r"password\s+(\S+)",
}
credentials = {key: re.search(pattern, readme).group(1) for key, pattern in patterns.items()}
target = pathlib.Path(sys.argv[2])
target.write_text(json.dumps(credentials))
os.chmod(target, 0o600)
PY

xcrun simctl status_bar "$simulator_id" override \
  --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3

cd "$repo_dir"
xcodebuild test -project Pageless.xcodeproj -scheme Pageless \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -configuration Debug -derivedDataPath "$scratch_dir/dd" \
  -parallel-testing-enabled NO \
  -only-testing:PagelessUITests/PagelessUITests/testCaptureMarketingScreenshots \
  -resultBundlePath "$scratch_dir/results-$(date +%s).xcresult"
