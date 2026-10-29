import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from hotfix_cache import validate, download


def sample(build=70685, value=b'one'):
    return (struct.pack('<4sii', b'XFTH', 9, build) + bytes(32)
            + struct.pack('<4siiiIii4B', b'XFTH', 91, 1, 1, 123, 4, len(value), 1, 0, 0, 0) + value)


class CacheTests(unittest.TestCase):
    def test_same_build_content_changes_have_different_identity(self):
        self.assertNotEqual(validate(sample(), 70685)['sha256'], validate(sample(value=b'two'), 70685)['sha256'])

    def test_mismatch_truncation_and_unknown_format_are_rejected(self):
        for raw in (sample(70532), sample()[:-1], sample() + b'x', sample().replace(b'XFTH', b'HTML', 1), sample().replace(b'\x09\x00\x00\x00', b'\x0a\x00\x00\x00', 1)):
            with self.subTest(raw=raw[:12]), self.assertRaises(ValueError):
                validate(raw, 70685)

    def test_bad_download_cannot_replace_valid_cache(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'DBCache.bin'
            path.write_bytes(sample())
            with patch('hotfix_cache.fetch', return_value=sample()[:-1]), self.assertRaises(ValueError):
                download(70685, folder)
            self.assertEqual(path.read_bytes(), sample())
