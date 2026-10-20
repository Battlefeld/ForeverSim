"""Talent builds and gear sets read from an engine checkout (no network, synthetic files in the upstream shape)."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

CORE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CORE))
import engine_presets  # noqa: E402

PRESETS_TS = """
import * as PresetUtils from '../../core/preset_utils';
import { SavedTalents } from '../../core/proto/ui';
import PreBisGear from './gear_sets/pre_bis.gear.json';
import P1Gear from './gear_sets/p1.gear.json';

export const PRE_BIS = PresetUtils.makePresetGear('Pre-BiS', PreBisGear);
export const P1 = PresetUtils.makePresetGear("Phase 1", P1Gear);

export const FireTalents = {
	name: 'Fire DPS',
	data: SavedTalents.create({
		talentsString: '05002252000003-23550000130135031-',
	}),
};
export const ShortFire = {
	name: 'Fire 0/35/16',
	data: SavedTalents.create({
		talentsString: '-2355000013013503',
	}),
};
export const FIRE_BUILD = PresetUtils.makePresetBuild('Fire', {
	talents: FireTalents,
	gear: PRE_BIS,
	rotation: SomeRotation,
});
export const OtherDefaults = { distanceFromTarget: 20 };
"""


def make_engine(root, presets=PRESETS_TS, gear=None):
    spec = Path(root) / 'ui' / 'specs' / 'mage' / 'dps'
    (spec / 'gear_sets').mkdir(parents=True)
    (spec / 'presets.ts').write_text(presets)
    gear = gear if gear is not None else {
        'pre_bis.gear.json': {'items': [{'id': 647, 'enchant': 1}, {}, {'id': 720}]},
        'p1.gear.json': {'items': [{'id': 727}]},
        'extra.gear.json': {'items': [{'id': 744}]},
    }
    for name, data in gear.items():
        (spec / 'gear_sets' / name).write_text(json.dumps(data))
    return Path(root)


class Presets(unittest.TestCase):
    def test_talent_and_gear_names_and_builds(self):
        with tempfile.TemporaryDirectory() as d:
            got = engine_presets.read_spec_presets(make_engine(d), 'mage/dps')
        self.assertEqual([t['name'] for t in got['talents']], ['Fire DPS', 'Fire 0/35/16'])
        self.assertEqual(got['talents'][0]['talentsString'], '05002252000003-23550000130135031-')
        self.assertEqual([g['name'] for g in got['gear']], ['Pre-BiS', 'Phase 1', 'extra'])
        self.assertEqual(got['gear'][0]['items'][0]['id'], 647)
        self.assertEqual(got['builds'], [{'name': 'Fire', 'talents': 'Fire DPS', 'gear': 'Pre-BiS'}])

    def test_current_upstream_talent_factory(self):
        text = "export const Fire = PresetUtils.makePresetTalents('Fire DPS', SavedTalents.create({ talentsString: '05002252000003-23550000130135031-' }));"
        got = engine_presets.parse_talent_presets(text)
        self.assertEqual(got, [{'var': 'Fire', 'name': 'Fire DPS', 'talentsString': '05002252000003-23550000130135031-'}])

    def test_shipped_manifest_has_class_presets_and_rank_families(self):
        manifest = json.loads((CORE / 'engine-data.json').read_text())
        for cl in manifest['classes']:
            self.assertTrue(manifest['presets'][cl]['talents'], cl)
            self.assertTrue(manifest['presets'][cl]['gear'], cl)
            self.assertTrue(manifest['spellRankFamilies'][cl], cl)

    def test_shared_names_keep_each_specs_talents_and_gear(self):
        with tempfile.TemporaryDirectory() as d:
            engine = make_engine(d)
            import shutil
            shutil.copytree(engine/'ui/specs/mage/dps', engine/'ui/specs/mage/other')
            presets, _ = engine_presets.collect_presets(engine, {'mage': ('mage', 'mage/dps'), 'otherMage': ('mage', 'mage/other')}, {'647': True, '720': True, '727': True, '744': True})
        cls = presets['mage']
        self.assertEqual(len(cls['talents']), 4)
        self.assertEqual(len(cls['gear']), 6)
        other = cls['builds'][1]
        self.assertEqual(other['talents'], 'Fire DPS [otherMage]')
        self.assertEqual(other['gear'], 'Pre-BiS [otherMage]')

    def test_missing_or_unknown_files_give_empty_lists(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(engine_presets.read_spec_presets(d, 'nope/dps'), {'talents': [], 'gear': [], 'builds': []})
            make_engine(Path(d) / 'e', presets='export const nothing = 1;', gear={})
            got = engine_presets.read_spec_presets(Path(d) / 'e', 'mage/dps')
            self.assertEqual(got, {'talents': [], 'gear': [], 'builds': []})

    def test_collect_merges_specs_and_drops_unknown_items(self):
        with tempfile.TemporaryDirectory() as d:
            engine = make_engine(d)
            known = {'647': True, '720': True, '727': True}   # 744 is not in the engine database
            presets, report = engine_presets.collect_presets(engine, {'mage': ('mage', 'mage/dps'), 'other': ('mage', 'none/x')}, known)
        mage = presets['mage']
        self.assertEqual([g['name'] for g in mage['gear']], ['Pre-BiS', 'Phase 1'])
        self.assertTrue(all(t['spec'] == 'mage' for t in mage['talents']))
        self.assertTrue(any('unbekannte Items 744' in r for r in report))
        self.assertTrue(any('none/x' in r and 'keine Talentvorlagen' in r for r in report))
        json.dumps(presets)


if __name__ == '__main__':
    unittest.main()
