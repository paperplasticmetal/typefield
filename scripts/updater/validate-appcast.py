#!/usr/bin/env python3
"""Validate release metadata and both Ed25519 signatures without a private key."""
import argparse
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from appcast import load_configuration, validate_feed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--plist', type=Path)
    group.add_argument('--app', type=Path)
    parser.add_argument('--feed', type=Path, required=True)
    parser.add_argument('--dmg', type=Path, required=True)
    args = parser.parse_args()
    plist = args.plist or args.app / 'Contents/Info.plist'
    info = load_configuration(plist)
    validate_feed(args.feed, info, args.dmg)
    print(f"Verified signed Typefield {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}) feed and DMG")


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, ET.ParseError) as error:
        sys.exit(f'Appcast validation failed: {error}')
