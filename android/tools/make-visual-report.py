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
sections = []
for case in cases:
    figures = ''.join(f'<figure><figcaption>{platform}</figcaption><a href="{platform}-{case}.png"><img src="{platform}-{case}.png" alt="{platform} {case}" loading="lazy"></a></figure>' for platform in ['ios', 'android'])
    sections.append(f'<section><h2>{case.replace("-", " ").title()}</h2><div class="pair">{figures}</div></section>')
(args.output / 'index.html').write_text('''<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Unpaged Android / iOS visual review</title>
<style>body{margin:40px auto;max-width:900px;padding:0 20px;background:#eeeae3;color:#252322;font:16px system-ui}h1{font-size:28px}p{line-height:1.6}section{margin:48px 0}.pair{display:flex;gap:24px;align-items:flex-start}figure{margin:0;flex:1;min-width:0}figcaption{text-transform:uppercase;font-size:12px;letter-spacing:2px;padding-bottom:12px}img{display:block;width:100%;height:auto;border-radius:12px}a{color:inherit}@media(max-width:600px){body{margin:24px auto;padding:0 12px}.pair{gap:12px}}</style>
<h1>Unpaged — Android / iOS visual review</h1>
<p>Actual emulator and simulator captures at equal display width. PNG bytes are unchanged; click to inspect full resolution. Matching fixture titles, authors and durations are used. System chrome, fonts and missing Android features remain visible.</p>
<p>This is a human comparison artifact, not an automated pixel-diff pass. See the adjacent validation document for provenance, fixes and outstanding parity gaps.</p>
''' + '\n'.join(sections) + '</html>\n')
print(args.output / 'index.html')
