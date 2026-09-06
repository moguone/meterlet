#!/usr/bin/env python3
"""Exercise Sparkle against isolated copies; never launches or targets the user's app."""
import argparse
import functools
import http.server
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import threading
import uuid
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT / '.build/artifacts/sparkle/Sparkle/bin'
NS = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
ET.register_namespace('sparkle', NS[1:-1])


def run(args, expected=0, timeout=60):
    result = subprocess.run(list(map(str, args)), capture_output=True, text=True, timeout=timeout)
    if result.returncode != expected:
        raise AssertionError(f'Command failed ({result.returncode}, expected {expected}): {args[0]}\n{result.stdout}\n{result.stderr}')
    return result.stdout


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('app')
    parser.add_argument('--identity', default='-')
    parser.add_argument('--notary-profile')
    args = parser.parse_args()
    source = pathlib.Path(args.app).resolve()
    with (source / 'Contents/Info.plist').open('rb') as file:
        assert plistlib.load(file)['CFBundleIdentifier'] == 'io.github.moguone.meterlet'
    with tempfile.TemporaryDirectory(prefix='update-install-', dir=ROOT / '.build') as directory:
        root = pathlib.Path(directory)
        test_id = 'io.github.moguone.meterlet.update-test.' + uuid.uuid4().hex
        installed = root / 'installed/Meterlet Update Test.app'
        new = root / 'release/Meterlet Update Test.app'
        installed.parent.mkdir()
        new.parent.mkdir()
        for app, version in [(installed, '1.0'), (new, '2.0')]:
            shutil.copytree(source, app, symlinks=True)
            plist_path = app / 'Contents/Info.plist'
            with plist_path.open('rb') as file:
                info = plistlib.load(file)
            info.update(CFBundleIdentifier=test_id, CFBundleName='Meterlet Update Test',
                        CFBundleDisplayName='Meterlet Update Test', CFBundleVersion=version,
                        CFBundleShortVersionString=version)
            with plist_path.open('wb') as file:
                plistlib.dump(info, file)
            sign = ['codesign', '--force', '--options', '0' if args.identity == '-' else 'runtime', '--sign', args.identity]
            if args.identity != '-':
                sign += ['--timestamp']
            run(sign + [app])
        archive = root / 'update.zip'
        run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', new, archive])
        if args.notary_profile:
            run(['xcrun', 'notarytool', 'submit', archive, '--keychain-profile', args.notary_profile, '--wait'], timeout=240)
            run(['xcrun', 'stapler', 'staple', new])
            run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', new, archive])
        signature = run([TOOLS / 'sign_update', '--account', 'meterlet', '-p', archive]).strip()
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(root)))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f'http://127.0.0.1:{server.server_port}'

        def write_feed(name, url='update.zip', version='2.0'):
            rss = ET.Element('rss', version='2.0')
            channel = ET.SubElement(rss, 'channel')
            ET.SubElement(channel, 'title').text = 'Meterlet isolated update tests'
            item = ET.SubElement(channel, 'item')
            ET.SubElement(item, 'title').text = 'Test update'
            ET.SubElement(item, NS + 'version').text = version
            ET.SubElement(item, NS + 'shortVersionString').text = version
            ET.SubElement(item, NS + 'minimumSystemVersion').text = '14.0'
            ET.SubElement(item, 'enclosure', {'url': f'{base}/{url}', NS + 'edSignature': signature,
                          'length': str(archive.stat().st_size), 'type': 'application/octet-stream'})
            path = root / name
            path.write_bytes(ET.tostring(rss, encoding='utf-8', xml_declaration=True))
            run([TOOLS / 'sign_update', '--account', 'meterlet', path])
            return path

        def probe(name, expected):
            return run([ROOT / '.build/update-tests/sparkle-cli', installed, '--probe', '--feed-url',
                        f'{base}/{name}', '--user-agent-name', 'Meterlet-Update-Test', '--verbose'], expected)

        def install(name, expected):
            return run([ROOT / '.build/update-tests/sparkle-cli', installed, '--check-immediately', '--feed-url',
                        f'{base}/{name}', '--user-agent-name', 'Meterlet-Update-Test', '--verbose'], expected)

        def installed_version():
            with (installed / 'Contents/Info.plist').open('rb') as file:
                info = plistlib.load(file)
            assert info['CFBundleIdentifier'] == test_id
            return info['CFBundleVersion']

        try:
            write_feed('available.xml')
            probe('available.xml', 0)
            assert installed_version() == '1.0'
            print('PASS: new update found without installing', flush=True)
            write_feed('current.xml', version='1.0')
            probe('current.xml', 4)
            print('PASS: no update available', flush=True)
            write_feed('older.xml', version='0.9')
            probe('older.xml', 4)
            print('PASS: older release cannot downgrade the app', flush=True)
            probe('missing.xml', 1)
            print('PASS: HTTP failure leaves installed app unchanged', flush=True)
            tampered = write_feed('tampered.xml')
            tampered.write_bytes(tampered.read_bytes().replace(b'Test update', b'Fake update'))
            probe('tampered.xml', 1)
            print('PASS: modified feed signature rejected', flush=True)
            install('available.xml', 0)
            assert installed_version() == '2.0'
            run(['codesign', '--verify', '--deep', '--strict', installed])
            print('PASS: signed update installed, version 1.0 → 2.0', flush=True)
            # Keep the failed installation last: Sparkle's installer exits asynchronously,
            # and a new CLI process can otherwise attach to that unfinished attempt.
            corrupt = bytearray(archive.read_bytes())
            corrupt[100] ^= 1
            (root / 'corrupt.zip').write_bytes(corrupt)
            write_feed('corrupt.xml', url='corrupt.zip', version='3.0')
            install('corrupt.xml', 1)
            assert installed_version() == '2.0'
            print('PASS: modified archive rejected before replacement', flush=True)
        finally:
            server.shutdown()
            server.server_close()
            subprocess.run(['defaults', 'delete', test_id], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == '__main__':
    main()
