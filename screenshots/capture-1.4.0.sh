#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
simulator_id=1190AB80-92FA-4D00-A2DE-AC5C998B6B62

# Private (0700, atomically created, owned by us) scratch dir; never a fixed /tmp path.
umask 077
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/shots140.XXXXXXXX")"
chmod 700 "$scratch_dir"
# Credentials must not outlive the run; build output and results stay in scratch_dir.
trap 'rm -f "$scratch_dir/abs.json"' EXIT
echo "Scratch dir: $scratch_dir"

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
# Exclusive create with mode 0600 from the first open; refuse symlinks/existing files.
fd = os.open(sys.argv[2], os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
with os.fdopen(fd, "w") as handle:
    handle.write(json.dumps(credentials))
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
