import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import subprocess

CORE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CORE))
import engine_update as update
from engine_identity import build_identity, leveling_digest


class IdentityTests(unittest.TestCase):
    def test_overlay_and_level_data_change_identity(self):
        a = build_identity('base', [], 'overlay-a', 'levels-a')
        self.assertNotEqual(a, build_identity('base', [], 'overlay-b', 'levels-a'))
        self.assertNotEqual(a, build_identity('base', [], 'overlay-a', 'levels-b'))
        self.assertNotEqual(a, build_identity('base', [{'sha256': '11'*32}], 'overlay-a', 'levels-a'))

    def test_derived_revision_is_not_hashed_but_stats_are(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'levels.json'
            p.write_text(json.dumps(dict(engineRevision='old', classes={'mage': {'20': {'mana': 100}}})))
            before = leveling_digest(p)
            data = json.loads(p.read_text()); data['engineRevision'] = 'new'
            p.write_text(json.dumps(data)); self.assertEqual(before, leveling_digest(p))
            data['classes']['mage']['20']['mana'] = 101
            p.write_text(json.dumps(data)); self.assertNotEqual(before, leveling_digest(p))

    def test_committed_inputs_match_lock(self):
        from engine_source import read_lock
        lock = read_lock()
        self.assertEqual(lock['buildIdentity'], json.loads((CORE/'engine-data.json').read_text())['engineRevision'])


class UpdateGateTests(unittest.TestCase):
    def test_incomplete_or_missing_results_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            original = Path(d)/'TestFake.results'
            tmp = Path(str(original)+'.tmp')
            for content in (None, '', 'key: "wrong"\nvalue: { dps: 1 }', 'key: "expected"\nvalue: { dps: nan }'):
                if content is not None: tmp.write_text(content)
                with self.assertRaises(update.UpdateError):
                    update.validate_level_golden(original, tmp, b'key: "expected"\nvalue: { dps: 1 }')

    def test_spell_rank_changes_do_not_look_like_missing_suite_cases(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)/'TestRanks.results'; tmp = Path(str(p)+'.tmp')
            original = ' key: "TestRanks-Casts"\n value: {\n  casts: {\n   key: "spell_id: 25307"\n   value: 1\n  }\n }'
            tmp.write_text(original.replace('25307', '686'))
            update.validate_level_golden(p, tmp, original.encode())

    def test_failed_tests_cannot_pass_without_results(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            golden = root/'TestFake.results'
            golden.write_text('key: "TestFake-Settings-LongSingleTarget"\nvalue: {\ndps: 1\n}\n')
            with patch.object(update, 'sh', return_value=''), patch.object(update, 'packages', return_value=['fake/spec']), patch.object(update, 'golden_suites', return_value=['TestFake']), patch.object(update, 'touched_packages', return_value=set()), patch.object(update, 'build_cli'), patch.object(update, 'spell_levels', return_value={}), patch.object(update, 'REFERENCE_REQUESTS', []), patch.object(update.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, stdout='FAIL fake/spec [build failed]', stderr='compile error')):
                with self.assertRaises(update.UpdateError):
                    update.checks(root, root, root, [], root, {})

    def test_real_assertion_failure_survives_level_golden_refresh(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); golden = root/'TestFake.results'
            content = 'key: "TestFake-Settings-LongSingleTarget"\nvalue: {\ndps: 1\n}\n'
            golden.write_text(content)
            def collect(*args, **kwargs):
                Path(str(golden)+'.tmp').write_text(content)
                return subprocess.CompletedProcess([], 1, stdout='FAIL assertion', stderr='')
            def sh(*args, **kwargs):
                if kwargs.get('env', {}).get('FOREVERCORE_LEVEL'):
                    raise update.UpdateError('assertion still fails')
                return ''
            with patch.object(update, 'sh', side_effect=sh), patch.object(update, 'packages', return_value=['fake/spec']), patch.object(update, 'golden_suites', return_value=['TestFake']), patch.object(update, 'touched_packages', return_value=set()), patch.object(update, 'build_cli'), patch.object(update, 'spell_levels', return_value={}), patch.object(update, 'REFERENCE_REQUESTS', []), patch.object(update.subprocess, 'run', side_effect=collect):
                with self.assertRaisesRegex(update.UpdateError, 'assertion still fails'):
                    update.checks(root, root, root, [], root, {})
            self.assertEqual(content, golden.read_text(), 'upstream goldens must be restored')


if __name__ == '__main__':
    unittest.main()
