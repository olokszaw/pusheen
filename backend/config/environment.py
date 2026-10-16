"""Load the same local configuration for management commands and ASGI."""
import os
from pathlib import Path


def load_environment(base_dir=None, environ=None):
    target = os.environ if environ is None else environ
    root = Path(base_dir) if base_dir is not None else Path(__file__).resolve().parent.parent
    values = {}
    for name in ('.env', '.env.local'):
        path = root / name
        if not path.is_file():
            continue
        for line in path.read_text(encoding='utf-8-sig').splitlines():
            text = line.strip()
            if not text or text.startswith('#') or '=' not in text:
                continue
            key, value = text.split('=', 1)
            key = key.strip()
            if key:
                values[key] = value
    for key, value in values.items():
        # Explicit process configuration is needed by migration commands and CI.
        target.setdefault(key, value)
