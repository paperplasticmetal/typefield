#!/usr/bin/env python3
"""Sign a verified release DMG and publishable feed using the dedicated Keychain key."""
import argparse
import datetime
import email.utils
import os
import plistlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from appcast import (ACCOUNT, FEED_URL, ROOT, bundle_manifest, decode_base64, download_url,
                     load_configuration, require, sparkle, validate_feed, version_tuple)


def verify_packaged_app(app, dmg):
    require(app.name == 'Typefield.app', 'The canonical bundle must be named Typefield.app')
    require((app / 'Contents/Frameworks/Sparkle.framework').is_dir(), 'App is missing Sparkle.framework')
    require((app / 'Contents/Resources/Sparkle-LICENSE.txt').is_file(), 'App is missing the Sparkle license')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    subprocess.run(['hdiutil', 'verify', str(dmg)], check=True, stdout=subprocess.DEVNULL)
    with tempfile.TemporaryDirectory(prefix='typefield-update-dmg-') as directory:
        mount = Path(directory) / 'volume'
        mount.mkdir()
        subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen',
                        '-mountpoint', str(mount), str(dmg)], check=True, stdout=subprocess.DEVNULL)
        try:
            packaged_app = mount / 'Typefield.app'
            require(packaged_app.is_dir(), 'DMG does not contain Typefield.app at its root')
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(packaged_app)], check=True)
            require(bundle_manifest(packaged_app) == bundle_manifest(app),
                    'Packaged Typefield.app does not exactly match the verified built application')
        finally:
            subprocess.run(['hdiutil', 'detach', str(mount)], check=True, stdout=subprocess.DEVNULL)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--dmg', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--previous-feed', type=Path, help='Preserve this signed feed; defaults to existing output')
    parser.add_argument('--published-at', help='ISO-8601 timestamp for reproducible output (defaults to current UTC)')
    parser.add_argument('--notes', type=Path, help='Plain text release notes to embed in the signed feed')
    args = parser.parse_args()
    app, dmg, output = args.app.resolve(), args.dmg.resolve(), args.output.resolve()
    info = load_configuration(app / 'Contents/Info.plist')
    version = info['CFBundleShortVersionString']
    require(dmg.name == f'Typefield-{version}-beta.dmg', 'DMG filename must match the built app version')
    verify_packaged_app(app, dmg)
    tools = Path(subprocess.check_output(['bash', str(ROOT / 'scripts/updater/prepare-sparkle.sh')], text=True).strip()) / 'bin'
    # -p only reads the existing public key. This script never creates or exports a key.
    public_key = subprocess.check_output([str(tools / 'generate_keys'), '--account', ACCOUNT, '-p'], text=True).strip()
    require(public_key == info['SUPublicEDKey'], 'The existing release key does not match the built app public key')
    previous = args.previous_feed.resolve() if args.previous_feed else (output if output.exists() else None)
    if previous:
        root, items = validate_feed(previous, info, require_current=False)
        latest = items[0].findtext(sparkle('version'))
        if latest == info['CFBundleVersion']:
            validate_feed(previous, info, dmg)
            if previous != output:
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(previous.read_bytes())
            print(f'Already signed and verified: {output}')
            return
        require(version_tuple(info['CFBundleVersion']) > version_tuple(latest), 'Refusing to publish a non-increasing build number')
        channel = root.find('channel')
    else:
        root = ET.Element('rss', {'version': '2.0'})
        channel = ET.SubElement(root, 'channel')
        ET.SubElement(channel, 'title').text = 'Typefield Updates'
        ET.SubElement(channel, 'link').text = FEED_URL
        ET.SubElement(channel, 'description').text = 'Signed public beta updates for Typefield.'
        ET.SubElement(channel, 'language').text = 'en'
    signature = subprocess.check_output([str(tools / 'sign_update'), '--account', ACCOUNT, '-p', str(dmg)], text=True).strip()
    decode_base64(signature, 64, 'archive signature')
    item = ET.Element('item')
    ET.SubElement(item, 'title').text = f'Typefield {version}'
    ET.SubElement(item, 'link').text = 'https://typefield.app/download/'
    ET.SubElement(item, sparkle('version')).text = info['CFBundleVersion']
    ET.SubElement(item, sparkle('shortVersionString')).text = version
    ET.SubElement(item, sparkle('minimumSystemVersion')).text = info['LSMinimumSystemVersion']
    ET.SubElement(item, sparkle('hardwareRequirements')).text = 'arm64'
    published = datetime.datetime.fromisoformat(args.published_at.replace('Z', '+00:00')) if args.published_at else datetime.datetime.now(datetime.timezone.utc)
    require(published.tzinfo is not None, '--published-at must include a timezone')
    ET.SubElement(item, 'pubDate').text = email.utils.format_datetime(published.astimezone(datetime.timezone.utc))
    if args.notes:
        ET.SubElement(item, 'description', {sparkle('format'): 'plain-text'}).text = args.notes.read_text()
    ET.SubElement(item, 'enclosure', {'url': download_url(version), 'length': str(dmg.stat().st_size),
                                    'type': 'application/octet-stream', sparkle('edSignature'): signature})
    first_item = channel.find('item')
    channel.insert(list(channel).index(first_item) if first_item is not None else len(channel), item)
    ET.indent(root, space='  ')
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix='.appcast-', suffix='.xml', dir=output.parent)
    os.close(descriptor)
    temporary = Path(temporary)
    try:
        ET.ElementTree(root).write(temporary, encoding='utf-8', xml_declaration=True)
        subprocess.run([str(tools / 'sign_update'), '--account', ACCOUNT, '--disable-signing-warning', str(temporary)], check=True)
        subprocess.run([str(tools / 'sign_update'), '--account', ACCOUNT, '--verify', str(temporary)], check=True)
        validate_feed(temporary, info, dmg)
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    print(f'Signed and verified Typefield {version} ({info["CFBundleVersion"]}): {output}')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, ET.ParseError) as error:
        sys.exit(f'Appcast generation failed: {error}')
