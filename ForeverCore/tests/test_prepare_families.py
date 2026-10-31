"""creature-families.json from client CreatureFamily exports (no network)."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

CORE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CORE))
import prepare_families  # noqa: E402

EN = 'ID,Name_lang,MinScale\n1,Wolf,1\n2,Cat,1\n27,Wind Serpent,1\n'
DE = 'ID,Name_lang,MinScale\n1,Wolf,1\n2,Katze,1\n27,Windnatter,1\n'


class PrepareFamilies(unittest.TestCase):
    def test_names_per_locale(self):
        out = prepare_families.build('1.60.1.70425', {'enUS': (EN, 'en'), 'deDE': (DE, 'de')})
        by_id = {f['id']: f for f in out['families']}
        self.assertEqual(by_id[27]['name'], 'Wind Serpent')
        self.assertEqual(by_id[2]['names']['deDE'], 'Katze')
        self.assertEqual(out['clientBuild'], '1.60.1.70425')

    def test_english_required(self):
        with self.assertRaises(ValueError):
            prepare_families.build('x', {'deDE': (DE, 'de')})

    def test_wrong_columns_rejected(self):
        with self.assertRaises(ValueError):
            prepare_families.parse('ID,Name\n1,Wolf\n')

    def test_cli_from_directory(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / 'CreatureFamily-enUS.csv').write_text(EN)
            (d / 'CreatureFamily-deDE.csv').write_text(DE)
            subprocess.run([sys.executable, str(CORE / 'prepare_families.py'), 'b', str(d / 'out.json'), '--from-dir', str(d)],
                           check=True, capture_output=True)
            out = json.loads((d / 'out.json').read_text(encoding='utf-8'))
            self.assertEqual(len(out['families']), 3)


class EngineHunterTables(unittest.TestCase):
    """The manifest tables are read from the engine source; they must line up with each other."""
    ENGINE = CORE.parent / 'deps/engine'

    def test_hunter_options_from_engine_source(self):
        if not (self.ENGINE / 'proto/hunter.proto').exists():
            self.skipTest('engine checkout not present')
        import re
        src = (CORE / 'prepare_engine.py').read_text()
        ns = {'re': re}
        exec(src[src.index('def armor_mitigation'):src.index("out['armorMitigation']")], ns)
        # the committed manifest's hunter tables against the engine source it was read from
        h = json.loads((CORE / 'engine-data.json').read_text())['hunter']
        families = re.findall(r'^\t"(\w+)":\s*\{Name:\s*"([^"]+)"', (self.ENGINE / 'sim/hunter/pet_families_auto_gen.go').read_text(), re.M)
        self.assertIn('Cat', h['petTypes'])
        self.assertTrue(set(h['petTypes']) <= {name for _, name in families})
        self.assertTrue(all(q['hastePct'] > 0 for q in h['quiver']))
        self.assertGreater(h['petLevel60Damage']['max'], h['petLevel60Damage']['min'])
        self.assertEqual(h['petAttackSpeeds'][0]['seconds'], 2.0)
        armor = ns['armor_mitigation'](self.ENGINE)
        self.assertGreater(armor['perLevel'], 0)


if __name__ == '__main__':
    unittest.main()
