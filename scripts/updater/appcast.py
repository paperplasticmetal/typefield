"""Shared, fail-closed validation for Typefield's signed public update feed."""
import base64
import hashlib
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPARKLE_NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
FEED_URL = 'https://typefield.app/updates/appcast.xml'
ACCOUNT = 'typefield-updates'
SIGNATURE_TRAILER = re.compile(
    rb'<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/]+={0,2})\nlength: ([0-9]+)\n-->\n?\Z')
ET.register_namespace('sparkle', SPARKLE_NS)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sparkle(name):
    return '{' + SPARKLE_NS + '}' + name


def version_tuple(value):
    require(isinstance(value, str) and re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', value),
            f'Invalid numerical bundle version: {value!r}')
    parts = tuple(int(part) for part in value.split('.'))
    return parts + (0,) * (3 - len(parts))


def decode_base64(value, size, label):
    try:
        data = base64.b64decode(value, validate=True)
    except (ValueError, TypeError):
        raise ValueError(f'Missing or malformed {label}') from None
    require(len(data) == size, f'{label} must decode to {size} bytes')
    return data


def load_configuration(plist):
    with Path(plist).open('rb') as stream:
        info = plistlib.load(stream)
    require(info.get('CFBundleIdentifier') == 'local.typefield.app', 'Unexpected application bundle identifier')
    version_tuple(info.get('CFBundleVersion'))
    version_tuple(info.get('CFBundleShortVersionString'))
    require(info.get('SUFeedURL') == FEED_URL, 'App must use the canonical HTTPS update feed')
    decode_base64(info.get('SUPublicEDKey'), 32, 'app update public key')
    require(info.get('SURequireSignedFeed') is True, 'App must require signed update feeds')
    require(info.get('SUVerifyUpdateBeforeExtraction') is True, 'App must verify archives before extraction')
    require(info.get('SUSignedFeedFailureExpirationInterval') == 0, 'App must fail closed on invalid feed signatures')
    version_tuple(info.get('LSMinimumSystemVersion'))
    return info


def download_url(version):
    version_tuple(version)
    return f'https://github.com/paperplasticmetal/typefield/releases/download/v{version}-beta.1/Typefield-{version}-beta.dmg'


def signed_feed_parts(data):
    match = SIGNATURE_TRAILER.search(data)
    require(match is not None, 'Feed is missing its Sparkle Ed25519 signature trailer')
    signature = match.group(1).decode('ascii')
    decode_base64(signature, 64, 'feed signature')
    length = int(match.group(2))
    require(length == match.start(), 'Feed signature length does not cover the complete XML payload')
    return signature, length


def verifier_binary():
    source = ROOT / 'scripts/updater/verify-signature.swift'
    directory = ROOT / '.build/updater-tools'
    directory.mkdir(parents=True, exist_ok=True)
    executable = directory / 'verify-signature'
    if not executable.exists() or executable.stat().st_mtime_ns < source.stat().st_mtime_ns:
        subprocess.run(['swiftc', '-O', '-module-cache-path', str(ROOT / '.build/module-cache'),
                        str(source), '-o', str(executable)], check=True)
    return executable


def verify_signature(public_key, signature, path, length):
    decode_base64(public_key, 32, 'app update public key')
    decode_base64(signature, 64, 'Ed25519 signature')
    subprocess.run([str(verifier_binary()), public_key, signature, str(path), str(length)], check=True)


def validate_feed_metadata(data, info, require_current=True):
    signed_feed_parts(data)
    root = ET.fromstring(data)
    require(root.tag == 'rss' and root.get('version') == '2.0', 'Expected an RSS 2.0 appcast')
    channels = root.findall('channel')
    require(len(channels) == 1, 'Feed must have exactly one channel')
    channel = channels[0]
    require(channel.findtext('link') == FEED_URL, 'Feed channel URL must match the app')
    items = channel.findall('item')
    require(bool(items), 'Feed has no releases')
    prior_version = None
    for item in items:
        build = item.findtext(sparkle('version'))
        version = item.findtext(sparkle('shortVersionString'))
        parsed_build = version_tuple(build)
        version_tuple(version)
        if prior_version is not None:
            require(parsed_build < prior_version, 'Feed builds must be unique and strictly newest first')
        prior_version = parsed_build
        require(item.find(sparkle('channel')) is None, 'Public beta releases must use the default update channel')
        require(item.find(sparkle('releaseNotesLink')) is None, 'Release notes must be embedded in the signed feed')
        require(item.findtext(sparkle('hardwareRequirements')) == 'arm64', 'Update must declare Apple silicon requirement')
        version_tuple(item.findtext(sparkle('minimumSystemVersion')))
        enclosures = item.findall('enclosure')
        require(len(enclosures) == 1, 'Each release needs exactly one update archive')
        enclosure = enclosures[0]
        require(enclosure.get('url') == download_url(version), 'Update archive must use its exact public GitHub beta asset')
        require(enclosure.get('type') == 'application/octet-stream', 'Unexpected update archive type')
        require(re.fullmatch(r'[1-9][0-9]*', enclosure.get('length', '')) is not None, 'Missing or invalid archive size')
        decode_base64(enclosure.get(sparkle('edSignature')), 64, 'archive signature')
    if require_current:
        latest = items[0]
        require(latest.findtext(sparkle('version')) == info['CFBundleVersion'], 'Latest feed build does not match the app')
        require(latest.findtext(sparkle('shortVersionString')) == info['CFBundleShortVersionString'], 'Latest feed version does not match the app')
        require(version_tuple(latest.findtext(sparkle('minimumSystemVersion'))) == version_tuple(info['LSMinimumSystemVersion']),
                'Latest feed macOS requirement does not match the app')
    return root, items


def validate_feed(feed, info, dmg=None, require_current=True):
    feed = Path(feed)
    data = feed.read_bytes()
    root, items = validate_feed_metadata(data, info, require_current)
    signature, length = signed_feed_parts(data)
    verify_signature(info['SUPublicEDKey'], signature, feed, length)
    if dmg is not None:
        dmg = Path(dmg)
        expected_name = f"Typefield-{info['CFBundleShortVersionString']}-beta.dmg"
        require(dmg.name == expected_name, 'DMG filename does not match the current version')
        enclosure = items[0].find('enclosure')
        require(dmg.stat().st_size == int(enclosure.get('length')), 'DMG size does not match the signed feed')
        verify_signature(info['SUPublicEDKey'], enclosure.get(sparkle('edSignature')), dmg, dmg.stat().st_size)
    return root, items


def bundle_manifest(app):
    entries = {}
    for path in sorted(Path(app).rglob('*')):
        if path.is_symlink():
            entries[str(path.relative_to(app))] = ('link', str(path.readlink()))
        elif path.is_file():
            digest = hashlib.sha256()
            with path.open('rb') as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
            entries[str(path.relative_to(app))] = ('file', digest.hexdigest(), path.stat().st_mode & 0o111)
    return entries
