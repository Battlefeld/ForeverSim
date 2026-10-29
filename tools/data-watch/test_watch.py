import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('watch', Path(__file__).with_name('watch.py'))
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)

class DataWatchTests(unittest.TestCase):
    def test_official_product_channels_are_kept_separate(self):
        def response(url):
            build = '70658' if '/wowf/' in url else '70532'
            return ('Region!STRING:0|BuildConfig!HEX:16|CDNConfig!HEX:16|VersionsName!String:0\n## seqn = 1\neu|' + 'a'*32 + '|' + 'b'*32 + '|1.60.1.' + build + '\n').encode()
        with patch.object(w, 'fetch', side_effect=response):
            found = w.discover('eu')
        self.assertEqual(found['wowf']['row']['VersionsName'], '1.60.1.70658')
        self.assertEqual(found['wow_classic_beta']['row']['VersionsName'], '1.60.1.70532')

    def test_same_build_hotfix_is_detected_without_patch_notes(self):
        before = w.parse_csv(b'ID,EffectBasePoints,Value\n2618,9,unchanged\n')
        after = w.parse_csv(b'ID,EffectBasePoints,Value\n2618,15,unchanged\n')
        self.assertEqual(w.diff(before, after), [{'id': '2618', 'kind': 'modified', 'fields': {'EffectBasePoints': {'before': '9', 'after': '15'}}}])

    def test_additions_deletions_and_multiline_strings(self):
        before = w.parse_csv(b'ID,Name\n1,"line1\nline2"\n')
        after = w.parse_csv(b'ID,Name\n2,new\n')
        self.assertEqual([c['kind'] for c in w.diff(before, after)], ['removed', 'added'])
        self.assertEqual(before['1']['Name'], 'line1\nline2')

    def test_bad_or_partial_exports_cannot_become_baselines(self):
        for raw in (b'<html>error</html>', b'ID,Value\n1\n', b'ID,Value\n1,a\n1,b\n', b'ID,Value\n', b'ID,Value,Value\n1,a,b\n'):
            with self.subTest(raw=raw):
                with self.assertRaises(ValueError): w.parse_csv(raw)

    def test_local_cache_absence_is_not_proof_of_no_hotfixes(self):
        self.assertEqual(w.cache_facts(None), [])
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory) / 'DBCache.bin'
            p.write_bytes(b'first')
            old = w.cache_facts(directory)[0]['sha256']
            p.write_bytes(b'updated')
            self.assertNotEqual(old, w.cache_facts(directory)[0]['sha256'])

    def test_new_same_build_cache_requires_export_without_erasing_effective_data(self):
        import gzip
        import json
        import sys
        import hotfix_cache
        products = {p: {'row': {'VersionsName': '1.60.1.70685'}} for p in w.PRODUCTS}
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            common = ['watch.py', '--output', str(root/'first'), '--raidbots']
            with patch.object(w, 'discover', return_value=products), patch.object(w, 'export_table', return_value=({'1': {'Value': 'old'}}, 'csvhash')), patch.object(hotfix_cache, 'download', return_value={'status':'available','sha256':'oldcache'}), patch.object(sys, 'argv', common+['--exporter','http://localhost:5089','--build','1.60.1.70685']):
                w.main()
            with patch.object(w, 'discover', return_value=products), patch.object(hotfix_cache, 'download', return_value={'status':'available','sha256':'newcache'}), patch.object(sys, 'argv', ['watch.py','--output',str(root/'second'),'--previous',str(root/'first/state.json.gz'),'--raidbots']):
                w.main()
            state = w.read_state(root/'second/state.json.gz')
            report = json.loads((root/'second/report.json').read_text())
            self.assertTrue(report['extractionRequired'])
            self.assertEqual(state['exportedCacheSHA256'], 'oldcache')
            self.assertEqual(state['tables']['SpellEffect']['effective']['1']['Value'], 'old')
            self.assertEqual(report['hotfixCoverage'], 'downloaded_not_applied')

if __name__ == '__main__': unittest.main()
