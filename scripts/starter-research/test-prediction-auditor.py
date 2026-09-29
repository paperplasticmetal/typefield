#!/usr/bin/env python3
"""Check audit input rejection and the complete missing-letter denominator."""
import argparse
import copy
import json
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--binary', type=Path, required=True)
args = parser.parse_args()
names = ['Helvetica', 'Times-Roman', 'Courier', 'Menlo-Regular', 'Avenir-Book',
         'ChalkboardSE-Regular', 'Noteworthy-Light', 'MarkerFelt-Wide', 'SnellRoundhand',
         'Georgia', 'Verdana', 'TrebuchetMS', 'Baskerville', 'Cochin', 'AmericanTypewriter',
         'ComicSansMS', 'BradleyHandITCTT-Bold', 'Zapfino']
empty = [{'name': name, 'glyphs': []} for name in names]
with tempfile.TemporaryDirectory(prefix='typefield-audit-tests-') as directory:
    path = Path(directory)/'predictions.json'
    def run(label, payload, expected, extra=(), contains=None):
        path.write_text(json.dumps(payload, allow_nan=False))
        result = subprocess.run([str(args.binary.resolve()), '--audit-frozen-predictions', str(path), *extra],
                                capture_output=True, text=True, timeout=45)
        if result.returncode != expected or (contains and contains not in result.stdout):
            raise AssertionError(f'{label}: exit {result.returncode}\n{result.stdout}\n{result.stderr}')
        print(f'PASS: {label}')
    run('missing face set', [], 1)
    repeated = copy.deepcopy(empty); repeated[0]['name'] = repeated[-1]['name']
    run('duplicate face', repeated, 1)
    duplicate = copy.deepcopy(empty)
    duplicate[0]['glyphs'] = [{'character': 'A', 'contours': []}]*2
    run('duplicate target', duplicate, 1)
    reference = copy.deepcopy(empty)
    reference[0]['glyphs'] = [{'character': 'H', 'contours': []}]
    run('supplied reference excluded from target score', reference, 1)
    run('unsupported sampling grid', empty, 1, ('--prediction-grid-scale', '3'))
    run('all absent predictions count as zero', empty, 0,
        contains='846 targets; 846 rejected at zero; 0 exported faces')
    invalid = copy.deepcopy(empty)
    invalid[0]['glyphs'] = [{'character': 'A', 'contours': [[[99, 0], [100, .1], [99, .2]]]}]
    run('invalid geometry counts as zero', invalid, 0,
        contains='846 targets; 846 rejected at zero; 0 exported faces')
    late_ink = copy.deepcopy(empty)
    late_ink[0]['glyphs'] = [{'character': 'A', 'contours': [[[1.1, .3], [1.2, .3], [1.15, .4]]]}]
    run('late ink remains representable within the fixed frame', late_ink, 0,
        contains='846 targets; 845 rejected at zero; 1 exported faces')
print('PASS: frozen prediction audit guards and denominator')
