#!/usr/bin/env python3
"""Copy unmodified platform captures into a reviewable, side-by-side HTML report."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('android_captures', type=Path)
parser.add_argument('ios_captures', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
parity_references = {
    'favorites-light': '01-favorites-light.png',
    'library-light': '02-library-light.png',
    'detail-light': '04-detail-light.png',
    'detail-miniplayer-light': '10-detail-miniplayer-light.png',
    'shelves-light': '03-shelves-light.png',
    'shelves-dark': '23-shelves-dark.png',
    'detail-expanded-light': '05-detail-expanded-light.png',
    'settings-light': '12-settings-light.png',
    'settings2-light': '13-settings2-light.png',
    'settings3-light': '14-settings3-light.png',
    'library-dark': '21-library-dark.png',
    'favorites-dark': '22-favorites-dark.png',
    'settings-dark': '25-settings-dark.png',
    'detail-dark': '26-detail-dark.png',
}
if (args.ios_captures / '02-library-light.png').is_file():
    cases = list(parity_references)
    sources = [(platform, case, root / (parity_references[case] if platform == 'ios' else ('detail-light.png' if case == 'detail-miniplayer-light' else f'{case}.png')))
               for case in cases for platform, root in [('ios', args.ios_captures), ('android', args.android_captures)]]
else:
    cases = ['empty-light', 'empty-dark', 'library-light', 'library-dark',
             'detail-light', 'detail-dark', 'review-light', 'review-dark']
    sources = [(platform, case, root / (f'ios-{case.replace("review", "import")}.png'
               if platform == 'ios' else f'{case}.png'))
               for case in cases for platform, root in [('ios', args.ios_captures), ('android', args.android_captures)]]
for _, _, source in sources:
    if not source.is_file():
        parser.error(f'Missing capture: {source}')
args.output.mkdir(parents=True, exist_ok=True)
manifest = {}
for platform, case, source in sources:
    name = f'{platform}-{case}.png'
    shutil.copyfile(source, args.output / name)
    manifest[name] = hashlib.sha256(source.read_bytes()).hexdigest()
(args.output / 'sha256.json').write_text(json.dumps(manifest, indent=2) + '\n')
duplicate_dark_reference = (
    (args.ios_captures / '26-detail-dark.png').is_file()
    and (args.ios_captures / '21-library-dark.png').is_file()
    and (args.ios_captures / '26-detail-dark.png').read_bytes()
        == (args.ios_captures / '21-library-dark.png').read_bytes()
)
sections = []
for case in cases:
    figures = ''.join(f'<figure><figcaption>{platform}</figcaption><a href="{platform}-{case}.png"><img src="{platform}-{case}.png" alt="{platform} {case}" loading="lazy"></a></figure>' for platform in ['ios', 'android'])
    note = '<p>Supplied 26-detail-dark.png is identical to 21-library-dark.png and shows Library. A matching iOS dark-detail reference is unavailable; this pair is not a detail parity verification.</p>' if case == 'detail-dark' and duplicate_dark_reference else ''
    sections.append(f'<section><h2>{case.replace("-", " ").title()}</h2>{note}<div class="pair">{figures}</div></section>')
(args.output / 'index.html').write_text('''<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Unpaged Android / iOS visual review</title>
<style>body{margin:40px auto;max-width:900px;padding:0 20px;background:#eeeae3;color:#252322;font:16px system-ui}h1{font-size:28px}p{line-height:1.6}section{margin:48px 0}.pair{display:flex;gap:24px;align-items:flex-start}figure{margin:0;flex:1;min-width:0}figcaption{text-transform:uppercase;font-size:12px;letter-spacing:2px;padding-bottom:12px}img{display:block;width:100%;height:auto;border-radius:12px}a{color:inherit}@media(max-width:600px){body{margin:24px auto;padding:0 12px}.pair{gap:12px}}</style>
<h1>Unpaged — Android / iOS visual review</h1>
<p>Actual emulator and simulator captures at equal display width. PNG bytes are unchanged; click to inspect full resolution. Matching fixture titles, authors and durations are used. System chrome, fonts and missing Android features remain visible. Slice 1 intentionally omits Plus, Sources, Reset Onboarding, reading activity and the mini player. Shelves is a placeholder awaiting its source slice. The mini-player reference reuses the unloaded Android detail capture to make that boundary visible. Imported Android fixtures have no moments until moment creation is implemented. Settings references include those excluded rows, so section positions differ.</p>
<p>This is a human comparison artifact, not an automated pixel-diff pass. See the adjacent validation document for provenance, fixes and outstanding parity gaps.</p>
''' + '\n'.join(sections) + '</html>\n')
print(args.output / 'index.html')
