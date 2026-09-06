#!/usr/bin/env python3
import base64
import importlib.util
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('verify_appcast', pathlib.Path(__file__).with_name('verify-appcast.py'))
feed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feed)


def fixture(version='0.2.0', url=None, signature=None):
    signature = signature or base64.b64encode(bytes(64)).decode()
    url = url or f'{feed.RELEASES}/download/v{version}/Meterlet-{version}-macOS-arm64.zip'
    return f'''<?xml version="1.0"?><rss xmlns:sparkle="{feed.NS[1:-1]}"><channel><item>
<sparkle:version>{version}</sparkle:version><enclosure url="{url}" length="12" sparkle:edSignature="{signature}"/>
</item></channel></rss>\n<!-- sparkle-signatures:\nedSignature: placeholder\nlength: 0\n-->'''


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.candidate = self.root / 'candidate.xml'

    def tearDown(self):
        self.temp.cleanup()

    def write(self, **kwargs):
        self.candidate.write_text(fixture(**kwargs))
        return self.candidate

    def test_accepts_matching_release(self):
        self.assertEqual(feed.validate(self.write(), '0.2.0'), '0.2.0')

    def test_rejects_external_downloads(self):
        with self.assertRaises(ValueError):
            feed.validate(self.write(url='https://example.com/app.zip'), '0.2.0')

    def test_rejects_different_release(self):
        with self.assertRaises(ValueError):
            feed.validate(self.write(), '0.3.0')

    def test_rejects_missing_archive_signature(self):
        with self.assertRaises(ValueError):
            feed.validate(self.write(signature='AA=='), '0.2.0')

    def test_rejects_unsigned_feed(self):
        self.candidate.write_text(fixture().split('<!-- sparkle-signatures:')[0])
        with self.assertRaises(ValueError):
            feed.validate(self.candidate, '0.2.0')

    def test_checks_archive_size(self):
        archive = self.root / 'Meterlet-0.2.0-macOS-arm64.zip'
        archive.write_bytes(bytes(11))
        with self.assertRaises(ValueError):
            feed.validate(self.write(), '0.2.0', archive)
        archive.write_bytes(bytes(12))
        feed.validate(self.candidate, '0.2.0', archive)


if __name__ == '__main__':
    unittest.main()
