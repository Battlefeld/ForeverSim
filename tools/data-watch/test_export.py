import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parent))
spec = importlib.util.spec_from_file_location('run_export', Path(__file__).with_name('run_export.py'))
export = importlib.util.module_from_spec(spec)
spec.loader.exec_module(export)


class ExportCacheTests(unittest.TestCase):
    def test_product_cache_is_selected_without_using_other_clients(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            retail = root / '_retail_' / 'Cache'
            retail.mkdir(parents=True)
            self.assertIsNone(export.product_cache_folder(root, 'wowf'))
            forever = root / '_forever_' / 'Cache'
            forever.mkdir(parents=True)
            self.assertEqual(export.product_cache_folder(root, 'wowf'), forever)
            self.assertIsNone(export.product_cache_folder(root, 'wow_classic_beta'))
            beta = root / '_classic_beta_' / 'Cache'
            beta.mkdir(parents=True)
            self.assertEqual(export.product_cache_folder(root, 'wow_classic_beta'), beta)

    def test_direct_product_folder_and_absent_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertIsNone(export.product_cache_folder(root, 'wowf'))
            cache = root / 'Cache'
            cache.mkdir()
            self.assertEqual(export.product_cache_folder(root, 'wowf'), cache)


if __name__ == '__main__': unittest.main()
