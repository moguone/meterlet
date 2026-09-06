#!/usr/bin/env python3
"""Check release metadata. Sparkle additionally verifies feed/archive signatures."""
import argparse
import base64
import pathlib
import re
import xml.etree.ElementTree as ET

NS = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
RELEASES = 'https://github.com/moguone/meterlet/releases'


def validate(path, expected_version, archive=None):
    if not re.fullmatch(r'\d+(?:\.\d+){1,3}', expected_version):
        raise ValueError('Expected a dotted numeric version')
    data = pathlib.Path(path).read_bytes()
    if len(data) > 1_000_000 or b'<!-- sparkle-signatures:\n' not in data:
        raise ValueError('Expected a signed Sparkle feed under 1 MB')
    root = ET.fromstring(data)
    items = root.findall('./channel/item')
    if len(items) != 1:
        raise ValueError('The feed must contain exactly one release')
    item = items[0]
    enclosure = item.find('enclosure')
    if enclosure is None:
        raise ValueError('Missing update archive')
    version = item.findtext(NS + 'version') or enclosure.get(NS + 'version')
    if version != expected_version:
        raise ValueError('Feed version does not match the release')
    filename = f'Meterlet-{version}-macOS-arm64.zip'
    if enclosure.get('url') != f'{RELEASES}/download/v{version}/{filename}':
        raise ValueError('Archive must belong to this exact GitHub release')
    signature = base64.b64decode(enclosure.get(NS + 'edSignature', ''), validate=True)
    if len(signature) != 64:
        raise ValueError('Missing archive signature')
    length = int(enclosure.get('length', '0'))
    if length <= 0:
        raise ValueError('Invalid archive length')
    if archive is not None:
        file = pathlib.Path(archive)
        if file.name != filename or file.stat().st_size != length:
            raise ValueError('Archive filename or size does not match')
    for node in (item.find('link'), item.find(NS + 'fullReleaseNotesLink')):
        if node is not None and node.text != f'{RELEASES}/tag/v{version}':
            raise ValueError('Release information must belong to this exact release')
    return version


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('feed')
    parser.add_argument('version')
    parser.add_argument('--archive')
    args = parser.parse_args()
    validate(args.feed, args.version, args.archive)
    print('Update feed mapping verified.')
