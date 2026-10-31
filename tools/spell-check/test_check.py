import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check

FROSTFIRE = {'id': 401502, 'name': 'Frostfire Bolt', 'rank': 'Rank 1', 'spellLevel': 40, 'castMs': 3000, 'durationMs': 9000,
             'effects': [{'index': 0, 'type': 6, 'aura': 33, 'base': -40, 'ppl': 0, 'variance': 0, 'spCoef': 0, 'periodMs': 0},
                         {'index': 1, 'type': 2, 'aura': 0, 'base': 100, 'ppl': 1.3, 'variance': 0.1534, 'spCoef': 0.814, 'periodMs': 0},
                         {'index': 2, 'type': 6, 'aura': 3, 'base': 9, 'ppl': 0, 'variance': 0, 'spCoef': 0, 'periodMs': 3000}]}
TEXT = ("Launches a bolt of frostfire at the enemy, causing 92 to 108 Frostfire damage, slowing movement speed by 40% and "
        "causing an additional 27 Frostfire damage over 9 sec.")


class Values(unittest.TestCase):
    def test_tooltip_of_the_api_matches_the_engine_values(self):
        self.assertEqual(check.check_values(FROSTFIRE, TEXT), [])

    def test_a_changed_base_is_found(self):
        problems = check.check_values(FROSTFIRE, TEXT.replace('92 to 108', '97 to 114'))
        self.assertEqual(len(problems), 1)
        self.assertTrue(problems[0].startswith('direct'))

    def test_a_changed_tick_total_is_found(self):
        problems = check.check_values(FROSTFIRE, TEXT.replace('27 Frostfire', '36 Frostfire'))
        self.assertEqual(len(problems), 1)
        self.assertTrue(problems[0].startswith('periodic'))

    def test_one_number_and_the_base_plus_one_form(self):
        heal = {'durationMs': 0, 'effects': [{'type': check.E_HEAL, 'aura': 0, 'base': 69, 'variance': 0, 'periodMs': 0}]}
        self.assertEqual(check.check_values(heal, 'Heals a friendly target for 70 health.'), [])
        self.assertEqual(check.check_values(heal, 'Heals a friendly target for 69 health.'), [])
        self.assertEqual(len(check.check_values(heal, 'Heals a friendly target for 80 health.')), 1)

    def test_other_effects_are_not_guessed(self):
        buff = {'durationMs': 1000, 'effects': [{'type': check.E_APPLY_AURA, 'aura': 33, 'base': -40, 'variance': 0, 'periodMs': 0}]}
        self.assertEqual(check.expected_values(buff), [])


class Run(unittest.TestCase):
    def test_report_lists_missing_level_and_value_findings(self):
        engine = [FROSTFIRE, {**FROSTFIRE, 'id': 5, 'name': 'Other', 'rank': '', 'spellLevel': 10, 'effects': []}]
        classes = {'mage': {'abilities': [
            {'name': 'Frostfire Bolt', 'ranks': [{'spellId': 401502, 'rank': 'Rank 1', 'level': 40}]},
            {'name': 'Other', 'ranks': [{'spellId': 5, 'rank': '', 'level': 12}]},
            {'name': 'Gone', 'ranks': [{'spellId': 99, 'rank': '', 'level': 1}]}]}}

        class Fake:
            def __init__(self, *a):
                self.calls = 0

            def get(self, path):
                self.calls += 1
                if path.startswith('/classes/'):
                    return classes.get(path.rsplit('/', 1)[1])
                return {'description': TEXT.replace('92 to 108', '97 to 114')}

        with tempfile.TemporaryDirectory() as d:
            dump = Path(d) / 'spells.json'
            dump.write_text(json.dumps(engine))
            out = Path(d) / 'report'
            with mock.patch.object(check, 'Api', Fake), mock.patch.dict(os.environ, {'FOREVERDB_API_KEY': 'x'}):
                with mock.patch.object(sys, 'argv', ['check', '--dump', str(dump), '--out', str(out), '--max-level', '45', '--classes', 'mage,hunter']):
                    self.assertEqual(check.main(), 0)
            report = json.loads(Path(str(out) + '.json').read_text())
            kinds = sorted(f['kind'] for f in report['findings'])
            self.assertEqual(kinds, ['class', 'level', 'missing', 'value'])
            self.assertIn('ForeverDB.net', Path(str(out) + '.md').read_text())

    def test_no_key_is_an_error(self):
        with mock.patch.dict(os.environ, {}, clear=True), mock.patch.object(sys, 'argv', ['check', '--dump', 'x', '--out', 'y']):
            self.assertEqual(check.main(), 2)


if __name__ == '__main__':
    unittest.main()
