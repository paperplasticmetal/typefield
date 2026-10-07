#!/usr/bin/env python3
"""Fail a release when the website download and app versions diverge."""
import pathlib
import plistlib
import re

root = pathlib.Path(__file__).resolve().parent.parent
app = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
store = plistlib.loads((root / 'Resources/Info-Store.plist').read_bytes())
for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
    assert app[key] == store[key], f'App plists disagree on {key}'
version, build = app['CFBundleShortVersionString'], app['CFBundleVersion']
html = (root / 'marketing/website/dist/index.html').read_text()
links = re.findall(r'href="([^"]+\.dmg)"', html)
expected = f'https://github.com/paperplasticmetal/typefield-feedback/releases/download/v{version}/Typefield-{version}-beta.dmg'
assert len(links) >= 2 and all(link == expected for link in links), 'Missing, stale or inconsistent DMG links'
assert f'Typefield {version} ({build})' in html, 'Missing version/build copy'
assert 'Coming to Mac' not in html and 'first public release ready' not in html, 'Stale prelaunch copy'
print(f'PASS: website downloads and both app plists match Typefield {version} ({build})')
