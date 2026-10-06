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
parser.add_argument('--playback-only', action='store_true', help='Require the four playback light captures; include dark captures as source-derived galleries')
parser.add_argument("--cases", nargs="+", help="Generate a focused report, e.g. --cases shelves-light shelves-dark")
args = parser.parse_args()
parity_references = {
    'eq-light': '08-eq-light.png',
    'onboarding-light': '00-launch.png',
    'activity-light': '01-favorites-light.png',
    'activity-dark': '22-favorites-dark.png',
    'player-light': '06-player-light.png',
    'chapters-light': '07-chapters-light.png',
    'library-miniplayer-light': '11-library-miniplayer-light.png',
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
    playback_cases = ['player-light', 'chapters-light', 'detail-miniplayer-light', 'library-miniplayer-light']
    if args.cases:
        if any(case not in parity_references for case in args.cases):
            parser.error('Unknown case; choose from ' + ', '.join(parity_references))
        cases = args.cases
    else:
        cases = playback_cases if args.playback_only else [case for case in parity_references
            if case not in playback_cases or (args.android_captures / f'{case}.png').is_file()
            or case == 'detail-miniplayer-light']
    sources = [(platform, case, root / (parity_references[case] if platform == 'ios' else ('detail-light.png' if case == 'detail-miniplayer-light' and not (root / f'{case}.png').is_file() and not args.playback_only else f'{case}.png')))
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
for case in ['player-dark', 'chapters-dark', 'detail-miniplayer-dark', 'library-miniplayer-dark',
             *[f'abs-{screen}-{theme}' for screen in ['connect', 'browse', 'detail', 'library'] for theme in ['light', 'dark']],
             'shelves-detail-light', 'shelves-detail-dark', 'shelves-collection-light', 'shelves-collection-dark',
             'review-light', 'review-dark', 'empty-light', 'empty-dark', 'detail-moments-empty-light',
             'moment-filters-light', 'moment-filters-dark', 'eq-dark', 'moments-light', 'moments-dark',
             'save-moment-light', 'edit-moment-dark',
             'onboarding-dark', 'stats-light', 'stats-dark', 'stats-sections-light',
             *[f'onboarding-{page}-{theme}' for page in ['permissions', 'playback', 'year', 'moments', 'storage', 'done'] for theme in ['light', 'dark']]]:
    source = args.android_captures / f'{case}.png'
    if source.is_file():
        name = f'android-{case}.png'
        shutil.copyfile(source, args.output / name)
        manifest[name] = hashlib.sha256(source.read_bytes()).hexdigest()
        sections.append(f'<section><h2>{case.replace("-", " ").title()}</h2><p>No matching iOS reference was supplied for this state. Review against the supplied related layouts and SwiftUI source; this is not a verified screenshot pair.</p><figure><a href="{name}"><img src="{name}" alt="{case}" loading="lazy"></a></figure></section>')
(args.output / 'sha256.json').write_text(json.dumps(manifest, indent=2) + '\n')
(args.output / 'index.html').write_text('''<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Unpaged Android / iOS visual review</title>
<style>body{margin:40px auto;max-width:900px;padding:0 20px;background:#eeeae3;color:#252322;font:16px system-ui}h1{font-size:28px}p{line-height:1.6}section{margin:48px 0}.pair{display:flex;gap:24px;align-items:flex-start}figure{margin:0;flex:1;min-width:0}figcaption{text-transform:uppercase;font-size:12px;letter-spacing:2px;padding-bottom:12px}img{display:block;width:100%;height:auto;border-radius:12px}a{color:inherit}@media(max-width:600px){body{margin:24px auto;padding:0 12px}.pair{gap:12px}}</style>
<h1>Unpaged — Android / iOS visual review</h1>
<p>Actual emulator and simulator captures at equal display width. PNG bytes are unchanged; click to inspect full resolution. Matching fixture titles, authors and durations are used. System chrome, fonts and missing Android features remain visible. Plus, purchases and Apple sync stay excluded. Playback captures come from real imported tracks and live Media3 state; Shelves uses the debug fixture catalog, which fixes hero and chart order. Settings references include excluded rows, so section positions differ.</p>
<p>This is a human comparison artifact, not an automated pixel-diff pass. See the adjacent validation document for provenance, fixes and outstanding parity gaps.</p>
''' + '\n'.join(sections) + '</html>\n')
print(args.output / 'index.html')
