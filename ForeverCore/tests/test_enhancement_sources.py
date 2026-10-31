import json
import sys
import unittest
from pathlib import Path

CORE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CORE))
from enhancement_sources import food_entry, recipe_rows


class EnhancementSourceTests(unittest.TestCase):
    def test_tooltip_wins_over_article_and_duplicates(self):
        row = food_entry(1, [('1', '200', '+14 Spell Damage'), ('1', '225', '+22 Spell Damage')],
                         {'name': 'Test', 'tooltip': 'Requires Level 25. well fed and gain 14 Spell Damage for 15 min. experience gained from kills is increased by 5%.'})
        self.assertEqual(row['stats'], {'StatSpellDamage': 14})
        self.assertEqual((row['minLevel'], row['duration'], row['xpKillPct']), (25, 900, 5))

    def test_ambiguous_crit_is_not_guessed(self):
        row = food_entry(1, [('1', '1', '+1% Critical Strike Chance')],
                         {'tooltip': 'well fed and gain 1% Critical Strike chance for 15 min.'})
        self.assertFalse(row['supported'])

    def test_recipe_js_is_parsed_without_eval(self):
        text = 'var listviewitems = [{"id":42,"skill":300,firstseenpatch: 0,popularity:55}];\nnew Listview({});'
        self.assertEqual(recipe_rows(text)[0]['id'], 42)

    def test_catalog_identity_and_coverage(self):
        c = json.loads((CORE / 'enhancements-data.json').read_text())
        lock = json.loads((CORE / 'engine.lock.json').read_text())
        self.assertEqual(c['upstreamRevision'], lock['commit'])
        foods = [e for e in c['entries'] if e['kind'] == 'food']
        enchants = [e for e in c['entries'] if e['kind'] == 'enchant']
        self.assertEqual(len({e['itemId'] for e in foods}), 100)
        self.assertEqual(len({e['itemId'] for e in enchants}), 172)
        self.assertEqual(sum(e['supported'] for e in foods), 89)
        self.assertEqual(sum(e["supported"] for e in enchants), 108)
        for row in enchants:
            if row['supported']:
                self.assertIn(str(row['effectId']), c['engineEnchants'])
