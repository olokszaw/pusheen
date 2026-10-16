import tempfile
import unittest
from pathlib import Path
from .environment import load_environment


class EnvironmentTests(unittest.TestCase):
    def test_local_overrides_base_and_preserves_explicit_database(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '.env').write_text('DATABASE_URL=base\nNAME=base\n', encoding='utf-8')
            (root / '.env.local').write_text('DATABASE_URL=local\nNAME=local\n', encoding='utf-8')
            values = {}
            load_environment(root, values)
            self.assertEqual(values, {'DATABASE_URL': 'local', 'NAME': 'local'})
            values = {'DATABASE_URL': 'migration-target'}
            load_environment(root, values)
            self.assertEqual(values['DATABASE_URL'], 'migration-target')
            self.assertEqual(values['NAME'], 'local')

    def test_bom_comments_and_equals_in_value(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '.env').write_text('# comment\n\nTOKEN=a=b\ninvalid\n', encoding='utf-8-sig')
            values = {}
            load_environment(root, values)
            self.assertEqual(values, {'TOKEN': 'a=b'})

    def test_missing_files(self):
        with tempfile.TemporaryDirectory() as directory:
            values = {}
            load_environment(directory, values)
            self.assertEqual(values, {})
