#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
scratch_dir=/tmp/wrap
simulator_id=1190AB80-92FA-4D00-A2DE-AC5C998B6B62
reference_dir=/Users/andreibalu/Developer/Ebooker/.worktrees/release/site/src/assets/screens
result_bundle="$scratch_dir/site-$(date +%s).xcresult"
attachment_dir="$scratch_dir/attachments"
output_dir="$scratch_dir/screens"

mkdir -p "$scratch_dir" "$output_dir"
rm -rf "$attachment_dir"
if ! xcrun simctl boot "$simulator_id" 2>/dev/null; then
  echo "Simulator was already booted; continuing."
fi
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl ui "$simulator_id" appearance light
xcrun simctl status_bar "$simulator_id" override \
  --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3

cd "$repo_dir"
xcodebuild test -project Pageless.xcodeproj -scheme Pageless \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -configuration Debug -derivedDataPath "$scratch_dir/dd" \
  -parallel-testing-enabled NO \
  -only-testing:PagelessUITests/PagelessUITests/testCaptureSiteScreenshots \
  -resultBundlePath "$result_bundle"

xcrun xcresulttool export attachments \
  --path "$result_bundle" --output-path "$attachment_dir"

node - "$attachment_dir" "$reference_dir" "$output_dir" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('/tmp/pw/node_modules/sharp');

const [attachmentDir, referenceDir, outputDir] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(path.join(attachmentDir, 'manifest.json'), 'utf8'));
const shots = ['recordings', 'recap', 'stats'];

function findAttachment(value, name) {
  if (Array.isArray(value)) {
    for (const entry of value) {
      const found = findAttachment(entry, name);
      if (found) return found;
    }
  } else if (value && typeof value === 'object') {
    const label = value.suggestedHumanReadableName ?? value.name;
    const filename = value.exportedFileName ?? value.fileName;
    if (label === name && typeof filename === 'string') return filename;
    for (const entry of Object.values(value)) {
      const found = findAttachment(entry, name);
      if (found) return found;
    }
  }
  return null;
}

(async () => {
  for (const name of shots) {
    const filename = findAttachment(manifest, name);
    if (!filename) throw new Error(`No ${name} attachment in xcresult manifest`);
    const input = path.join(attachmentDir, filename);
    const reference = path.join(referenceDir, `${name}.webp`);
    const { width, height } = await sharp(reference).metadata();
    if (!width || !height) throw new Error(`Could not read size of ${reference}`);
    const output = path.join(outputDir, `${name}.webp`);
    await sharp(input)
      .resize(width, height, { fit: 'cover', position: 'north' })
      .webp({ quality: 90 })
      .toFile(output);
    console.log(`${output}: ${width}x${height}`);
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
JS
