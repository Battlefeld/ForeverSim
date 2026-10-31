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


class CheckoutPreparationTests(unittest.TestCase):
    def test_default_preparation_generates_proto(self):
        with patch.dict(update.os.environ, {}, clear=True), patch.object(update, 'protoc') as protoc:
            update.prepare_checkout(Path('/engine'))
            protoc.assert_called_once_with(Path('/engine'))

    def test_custom_preparation_is_used(self):
        with patch.dict(update.os.environ, {'FOREVERCORE_PREPARE': 'custom-build'}), patch.object(update, 'sh') as sh, patch.object(update, 'protoc') as protoc:
            update.prepare_checkout(Path('/engine'))
            sh.assert_called_once_with('bash', '-c', 'custom-build', cwd=Path('/engine'))
            protoc.assert_not_called()

    def test_main_prepares_go_before_level_extraction(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            work = root / 'work'
            report = root / 'report.json'
            prepared = set()
            def checkout(repo, base, dest):
                (dest / 'assets/db_inputs').mkdir(parents=True)
                (dest / 'assets/db_inputs/forever_client_build.txt').write_text('1.60.1.70425')
            def extract(*cmd, **kw):
                if str(cmd[1]).endswith('prepare_leveling.py'):
                    self.assertEqual(prepared, {work/'upstream', work/'parity', work/'overlay'})
                    raise update.UpdateError('test reached prepared extractor')
                return 0
            args = ['engine_update.py', '--work', str(work), '--report', str(report)]
            with patch.object(sys, 'argv', args), patch.object(update, 'fetch_upstream'), patch.object(update, 'pick_base', return_value=('mythicsim/test', 'abc', True)), patch.object(update, 'settle_patches', return_value=([], [])), patch.object(update, 'checkout', side_effect=checkout), patch.object(update, 'apply_patches'), patch.object(update, 'prepare_checkout', side_effect=lambda p: prepared.add(p)), patch.object(update, 'client_table', return_value=root/'table.sqlite'), patch.object(update, 'sh', side_effect=extract):
                with self.assertRaises(SystemExit):
                    update.main()
            self.assertIn('test reached prepared extractor', json.loads(report.read_text())['error'])


if __name__ == '__main__':
    unittest.main()


class CalculationChangeTests(unittest.TestCase):
    """Only a change of the calculation makes an engine update necessary."""

    def test_calculation_files(self):
        import engine_update as e
        for path in ('sim/mage/frostfire_bolt.go', 'sim/core/spell.go', 'proto/common.proto', 'go.mod',
                     'sim/core/spelldata/spelldata.go', 'tools/database/gen_spelldata/main.go'):
            self.assertTrue(e.is_calculation_file(path), path)

    def test_data_files(self):
        import engine_update as e
        for path in ('sim/mage/spell_data_auto_gen.go', 'sim/core/spelldata/spells_auto_gen.go', 'sim/mage/frostfire_bolt_test.go',
                     'assets/database/db.json', 'ui/app/Sim.tsx', 'docs/readme.md', 'sim/mage/testdata/x.results'):
            self.assertFalse(e.is_calculation_file(path), path)
