#!/usr/bin/env python3
"""Check app identity against the public beta page and downloadable artifact."""
import hashlib
import pathlib
import plistlib
import re

root = pathlib.Path(__file__).resolve().parent.parent
app = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
store = plistlib.loads((root / 'Resources/Info-Store.plist').read_bytes())
for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
    assert app[key] == store[key], f'App plists disagree on {key}'
version, build = app['CFBundleShortVersionString'], app['CFBundleVersion']
site = root / 'marketing/website/dist'
html = (site / 'download/index.html').read_text()
filename = f'Typefield-{version}-beta.dmg'
assert f'class="download-button" href="../assets/{filename}"' in html, 'Stale primary DMG link'
assert f'Version {version} beta 1 (build {build})' in html, 'Stale version/build copy'
assert f'https://github.com/paperplasticmetal/typefield/releases/download/v{version}-beta.1/{filename}' in html, 'Stale GitHub link'
digest = hashlib.sha256((site / 'assets' / filename).read_bytes()).hexdigest()
assert html.count(digest) == 2, 'Download and latest history checksums must match the DMG'
assert f'/assets/{filename}\n  Content-Type: application/x-apple-diskimage' in (site / '_headers').read_text(), 'Missing DMG headers'
print(f'PASS: public downloads, checksum and both app plists match Typefield {version} ({build})')
