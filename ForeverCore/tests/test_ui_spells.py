import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import ui_spells

ENTRY = '{["key"]="frostbolt",["level"]=8,["cast"]=1.8,["cost"]=35,["resource"]="mana",["base"]=31,["max"]=35,["coef"]=0.489,["id"]=205}'
SPELL = {'level': 8, 'castMs': 1800, 'cooldownMs': 0, 'powers': [{'type': 0, 'cost': 35, 'pct': 0}],
         'effects': [{'type': 2, 'min': 27, 'max': 31, 'spCoef': 0.489, 'apCoef': 0, 'perLevel': 0.3}],
         'baseLevel': 8, 'maxLevel': 12}


class UiSpellTests(unittest.TestCase):
    def test_changed_damage_is_taken_from_the_engine(self):
        changes = []
        entry = ui_spells.refresh_entry(ENTRY, SPELL, changes)
        self.assertIn('["base"]=27', entry)
        self.assertIn('["max"]=31', entry)
        self.assertEqual({c[0] for c in changes}, {'base', 'max'})

    def test_rounding_inside_a_point_is_left_alone(self):
        spell = dict(SPELL, effects=[dict(SPELL['effects'][0], min=31.4, max=34.6)])
        changes = []
        self.assertEqual(ui_spells.refresh_entry(ENTRY, spell, changes), ENTRY)
        self.assertEqual(changes, [])

    def test_row_without_matching_coefficient_keeps_its_numbers(self):
        spell = dict(SPELL, effects=[dict(SPELL['effects'][0], spCoef=0.9)])
        entry = ui_spells.refresh_entry(ENTRY, spell, [])
        self.assertIn('["base"]=31', entry)

    def test_negative_cast_time_is_not_taken(self):
        entry = ui_spells.refresh_entry(ENTRY, dict(SPELL, castMs=-1000), [])
        self.assertIn('["cast"]=1.8', entry)


if __name__ == '__main__':
    unittest.main()


class AlignTests(unittest.TestCase):
    SPELLS = {'10': {'name': 'Curse', 'rank': 1}, '20': {'name': 'Curse', 'rank': 2}}

    @staticmethod
    def block(*rows):
        return '{["curse"]={' + ','.join(rows) + '}}'

    @staticmethod
    def row(i, rank):
        return '{["key"]="curse",["level"]=1,["rank"]=%d,["id"]=%d}' % (rank, i)

    def test_unknown_id_becomes_the_engines_id_for_that_rank(self):
        report = {'removed': [], 'remapped': []}
        out = ui_spells.align_ranks(self.block(self.row(99, 1), self.row(20, 2)), self.SPELLS, report, 'x')
        self.assertIn('["id"]=10', out)
        self.assertEqual(report['remapped'], [('x', 'curse', 99, 10)])

    def test_rank_the_engine_does_not_have_is_removed(self):
        report = {'removed': [], 'remapped': []}
        out = ui_spells.align_ranks(self.block(self.row(10, 1), self.row(20, 2), self.row(77, 3)), self.SPELLS, report, 'x')
        self.assertEqual(out, self.block(self.row(10, 1), self.row(20, 2)))
        self.assertEqual(report['removed'], [('x', 'curse', 77)])
