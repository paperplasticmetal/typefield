#!/usr/bin/env python3
"""Disposable signed fixtures; no Keychain, installed app, user data or release key."""
import base64
import copy
import plistlib
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from appcast import (FEED_URL, ROOT, download_url, load_configuration, signed_feed_parts,
                     sparkle, validate_feed, validate_feed_metadata, verifier_binary)


class AppcastTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='typefield-appcast-tests-')
        cls.directory = Path(cls.temporary.name)
        cls.signer = cls.directory / 'fixture-sign'
        subprocess.run(['swiftc', '-O', '-module-cache-path', str(ROOT / '.build/module-cache'),
                        str(ROOT / 'scripts/updater/test-fixture-sign.swift'), '-o', str(cls.signer)], check=True)
        verifier_binary()
        cls.dmg = cls.directory / 'Typefield-1.2.3-beta.dmg'
        cls.dmg.write_bytes(b'Disposable archive signature test fixture\n')
        key, signature = subprocess.check_output([str(cls.signer), str(cls.dmg)], text=True).splitlines()
        cls.info = {'CFBundleIdentifier': 'local.typefield.app', 'CFBundleVersion': '123',
                    'CFBundleShortVersionString': '1.2.3', 'LSMinimumSystemVersion': '13.0',
                    'SUFeedURL': FEED_URL, 'SUPublicEDKey': key,
                    'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True,
                    'SUSignedFeedFailureExpirationInterval': 0}
        cls.xml = ET.Element('rss', {'version': '2.0'})
        channel = ET.SubElement(cls.xml, 'channel')
        ET.SubElement(channel, 'link').text = FEED_URL
        item = ET.SubElement(channel, 'item')
        for name, value in [('version', '123'), ('shortVersionString', '1.2.3'),
                            ('minimumSystemVersion', '13.0'), ('hardwareRequirements', 'arm64')]:
            ET.SubElement(item, sparkle(name)).text = value
        ET.SubElement(item, 'enclosure', {'url': download_url('1.2.3'), 'length': str(cls.dmg.stat().st_size),
                                        'type': 'application/octet-stream', sparkle('edSignature'): signature})

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def signed(self, root=None):
        path = self.directory / 'appcast.xml'
        payload = ET.tostring(root if root is not None else self.xml, encoding='utf-8', xml_declaration=True)
        path.write_bytes(payload)
        _, signature = subprocess.check_output([str(self.signer), str(path)], text=True).splitlines()
        path.write_bytes(payload + f'<!-- sparkle-signatures:\nedSignature: {signature}\nlength: {len(payload)}\n-->\n'.encode())
        return path

    def test_valid_public_verification(self):
        validate_feed(self.signed(), self.info, self.dmg)

    def test_app_settings_fail_closed(self):
        for field, value in [('SUPublicEDKey', ''), ('SUFeedURL', 'https://example.com/appcast.xml'),
                             ('SURequireSignedFeed', False), ('SUVerifyUpdateBeforeExtraction', False),
                             ('SUSignedFeedFailureExpirationInterval', 604800),
                             ('CFBundleVersion', 'beta'), ('CFBundleIdentifier', 'other.app')]:
            with self.subTest(field=field):
                info = dict(self.info, **{field: value})
                plist = self.directory / 'Info.plist'
                plist.write_bytes(plistlib.dumps(info))
                with self.assertRaises(ValueError):
                    load_configuration(plist)

    def test_feed_metadata_mismatches(self):
        for field, value in [('version', '122'), ('shortVersionString', '1.2.2'),
                             ('hardwareRequirements', 'x86_64'), ('minimumSystemVersion', '14.0')]:
            with self.subTest(field=field):
                root = copy.deepcopy(self.xml)
                root.find('channel/item/' + sparkle(field)).text = value
                with self.assertRaises(ValueError):
                    validate_feed_metadata(self.signed(root).read_bytes(), self.info)

    def test_archive_metadata_mismatches(self):
        for field, value in [('url', 'https://example.com/fake.dmg'), ('length', '0'),
                             (sparkle('edSignature'), ''), ('type', 'text/plain')]:
            with self.subTest(field=field):
                root = copy.deepcopy(self.xml)
                root.find('channel/item/enclosure').set(field, value)
                with self.assertRaises(ValueError):
                    validate_feed_metadata(self.signed(root).read_bytes(), self.info)

    def test_missing_signature(self):
        with self.assertRaises(ValueError):
            validate_feed_metadata(ET.tostring(self.xml), self.info)

    def test_missing_version(self):
        root = copy.deepcopy(self.xml)
        item = root.find('channel/item')
        item.remove(item.find(sparkle('version')))
        with self.assertRaises(ValueError):
            validate_feed_metadata(self.signed(root).read_bytes(), self.info)

    def test_duplicate_release(self):
        root = copy.deepcopy(self.xml)
        root.find('channel').append(copy.deepcopy(root.find('channel/item')))
        with self.assertRaises(ValueError):
            validate_feed_metadata(self.signed(root).read_bytes(), self.info)

    def test_unsigned_trailing_content(self):
        data = self.signed().read_bytes() + b'<!-- unsigned -->'
        with self.assertRaises(ValueError):
            signed_feed_parts(data)

    def test_signed_length_mismatch(self):
        data = self.signed().read_bytes()
        _, length = signed_feed_parts(data)
        with self.assertRaises(ValueError):
            signed_feed_parts(data.replace(f'length: {length}'.encode(), f'length: {length - 1}'.encode()))

    def test_feed_tampering(self):
        path = self.signed()
        path.write_bytes(path.read_bytes().replace(b'<channel>', b'<channel >'))
        with self.assertRaises(ValueError):
            validate_feed(path, self.info, self.dmg)
        path = self.signed()
        path.write_bytes(path.read_bytes().replace(b'13.0', b'13.1'))
        adjusted_info = dict(self.info, LSMinimumSystemVersion='13.1')
        with self.assertRaises(subprocess.CalledProcessError):
            validate_feed(path, adjusted_info, self.dmg)

    def test_dmg_tampering(self):
        path = self.signed()
        original = self.dmg.read_bytes()
        self.dmg.write_bytes(b'X' + original[1:])
        try:
            with self.assertRaises(subprocess.CalledProcessError):
                validate_feed(path, self.info, self.dmg)
        finally:
            self.dmg.write_bytes(original)

    def test_dmg_size_mismatch(self):
        path = self.signed()
        original = self.dmg.read_bytes()
        self.dmg.write_bytes(original + b'X')
        try:
            with self.assertRaises(ValueError):
                validate_feed(path, self.info, self.dmg)
        finally:
            self.dmg.write_bytes(original)

    def test_sparkle_signature_format_compatibility(self):
        signer = ROOT / '.build/sparkle/2.10.0/bin/sign_update'
        if not signer.exists():
            self.skipTest('Run prepare-sparkle.sh to enable pinned Sparkle compatibility coverage')
        # The public RFC 8032 test vector, never a generated or production key.
        seed = bytes.fromhex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60')
        key_file = self.directory / 'public-test-vector.txt'
        key_file.write_bytes(base64.b64encode(seed))
        path = self.directory / 'official-appcast.xml'
        path.write_bytes(ET.tostring(self.xml, encoding='utf-8', xml_declaration=True))
        subprocess.run([str(signer), '--ed-key-file', str(key_file), '--disable-signing-warning', str(path)],
                       check=True, stdout=subprocess.DEVNULL)
        validate_feed(path, self.info, self.dmg)

    def test_wrong_public_key(self):
        info = dict(self.info, SUPublicEDKey=base64.b64encode(bytes(32)).decode())
        with self.assertRaises(subprocess.CalledProcessError):
            validate_feed(self.signed(), info, self.dmg)


if __name__ == '__main__':
    unittest.main()
