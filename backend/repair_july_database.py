"""Run in the deployed backend folder with the server stopped."""
from pathlib import Path
import getpass
import json
import os
import socket
import sys
import zipfile
from datetime import datetime


def main():
    root = Path(__file__).resolve().parent
    os.chdir(root)
    with socket.socket() as probe:
        probe.settimeout(1)
        if probe.connect_ex(('127.0.0.1', 8000)) == 0:
            raise RuntimeError('Stop the backend with Ctrl+C before running this script.')

    from config.environment import load_environment
    # Match the launcher even when the current terminal has stale values.
    selected = {}
    load_environment(root, selected)
    os.environ.update(selected)
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
    import django
    django.setup()
    from django.conf import settings
    from django.contrib.auth import get_user_model
    from django.contrib.auth.password_validation import validate_password
    from django.core.exceptions import ValidationError
    from django.core.management import call_command
    from django.db import connection, transaction
    from watchparty.models import UserProfile, ViewingActivity, CompanionActivity, FriendLink

    users = get_user_model()
    companion = users.objects.get(username__iexact='fuck')
    old = users.objects.filter(username__iexact='july').first()
    if old and (old.is_staff or old.is_superuser):
        raise RuntimeError('july has administrator privileges; refusing to delete it.')
    views_path = root / 'watchparty/views.py'
    views_source = views_path.read_text(encoding='utf-8')
    old_row = 'for name, seconds in sorted(genres.items(), key=lambda item: item[1], reverse=True)[:5]'
    new_row = 'for name, seconds in sorted(((name, seconds) for name, seconds in genres.items() if name != "__unclassified__"), key=lambda item: item[1], reverse=True)[:5]'
    if '__unclassified__' not in views_source and old_row not in views_source:
        raise RuntimeError('Unsupported activity serializer. No accounts were changed.')
    print('Database:', connection.vendor, connection.settings_dict['NAME'])
    print('Users:', users.objects.count(), '| fuck ID:', companion.pk, '| july ID:', old.pk if old else 'new')
    while True:
        password = getpass.getpass('New july password: ')
        repeated = getpass.getpass('Repeat password: ')
        if password != repeated:
            print('Passwords do not match. Try again.')
            continue
        try:
            validate_password(password, users(username='july'))
        except ValidationError as error:
            print('; '.join(error.messages))
            continue
        break

    stamp = datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backups = root / '_database_backups'
    backups.mkdir(exist_ok=True)
    database_url = os.environ.get('DATABASE_URL')
    if not database_url:
        if connection.vendor != 'sqlite':
            raise RuntimeError('DATABASE_URL missing for a non-SQLite database.')
        database_url = 'sqlite:///' + Path(connection.settings_dict['NAME']).resolve().as_posix()
    # Keep the active database in one place; preserve all unrelated settings.
    for filename in ('.env', '.env.local'):
        env_path = root / filename
        original = env_path.read_text(encoding='utf-8-sig') if env_path.exists() else ''
        if env_path.exists():
            (backups / (filename.lstrip('.') + '-before-' + stamp + '.txt')).write_text(original, encoding='utf-8')
        retained = [line for line in original.splitlines()
                    if not ('=' in line and line.split('=', 1)[0].strip() == 'DATABASE_URL')]
        if filename == '.env':
            retained.append('DATABASE_URL=' + database_url)
        if env_path.exists() or filename == '.env':
            env_path.write_text('\n'.join(retained) + '\n', encoding='utf-8')
    snapshot = backups / ('before-july-' + stamp + '.json')
    call_command('dumpdata', output=str(snapshot), indent=2, verbosity=0)
    # Test the completed snapshot before any destructive operation.
    with snapshot.open(encoding='utf-8') as source:
        exported = json.load(source)
    assert any(row['model'] == 'auth.user' and row['pk'] == companion.pk for row in exported)

    if '__unclassified__' not in views_source:
        (backups / ('views-before-' + stamp + '.py')).write_text(views_source, encoding='utf-8')
        views_path.write_text(views_source.replace(old_row, new_row, 1), encoding='utf-8')
    # Reload the serializer after installing support for incomplete genre data.
    import importlib
    from watchparty import views
    importlib.reload(views)

    with transaction.atomic():
        # Lock both accounts before recreating july. The other users remain.
        list(users.objects.select_for_update().filter(pk__in=[companion.pk] + ([old.pk] if old else [])))
        if old:
            old.delete()
        july = users.objects.create_user(username='july', password=password)
        UserProfile.objects.create(user=july, nickname='july')
        ViewingActivity.objects.create(
            user=july, watched_seconds=54000,
            genre_counts={'Другое': 34020, 'Хоррор': 5400, 'Реалити': 4860,
                          'Триллер': 4860, 'Музыка': 1620, '__unclassified__': 3240},
        )
        for owner, friend in ((july, companion), (companion, july)):
            FriendLink.objects.get_or_create(user=owner, friend=friend)
            CompanionActivity.objects.update_or_create(user=owner, companion=friend, defaults={'seconds': 39840})
        from watchparty.views import activity_payload
        payload = activity_payload(july.viewing_activity)
        actual = {row['name']: row['percent'] for row in payload['genres']}
        assert actual == {'Другое': 63, 'Хоррор': 10, 'Реалити': 9, 'Триллер': 9, 'Музыка': 3}, actual
        assert payload['watched_seconds'] == 54000
        assert july.check_password(password)

    # Settings is shared by manage.py and ASGI. Preserve the rest of settings.py.
    settings_path = root / 'config/settings.py'
    source = settings_path.read_text(encoding='utf-8')
    if 'load_environment()' not in source:
        import_line = 'from config.environment import load_environment\nload_environment()\n'
        # Insert after future imports if the deployed settings has any.
        lines = source.splitlines(keepends=True)
        last_future = max((index for index, line in enumerate(lines) if line.startswith('from __future__ import ')), default=-1)
        (backups / ('settings-before-' + stamp + '.py')).write_text(source, encoding='utf-8')
        lines.insert(last_future + 1, import_line)
        settings_path.write_text(''.join(lines), encoding='utf-8')

    # Remove only inactive SQLite files from this backend's root after archiving.
    # Never drop unknown PostgreSQL databases or touch folders outside this root.
    active = Path(connection.settings_dict['NAME']).resolve() if connection.vendor == 'sqlite' else None
    candidates = [path for path in root.iterdir() if path.is_file() and (
        path.name == 'db.sqlite3' or (path.name.startswith('db-before-postgresql-') and path.suffix == '.sqlite3'))
        and path.resolve() != active]
    if candidates:
        archive = backups / ('inactive-sqlite-' + stamp + '.zip')
        archived = []
        with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as output:
            for path in candidates:
                for item in (path, Path(str(path) + '-wal'), Path(str(path) + '-shm')):
                    if item.is_file():
                        assert item.resolve().parent == root
                        output.write(item, arcname=item.name)
                        archived.append(item)
        with zipfile.ZipFile(archive) as check:
            assert check.testzip() is None
        for path in archived:
            path.unlink()
        print('Inactive SQLite files archived and removed:', len(archived))
    print('DONE: july recreated; viewed 15h; together with fuck 11h04m in both profiles.')
    print('Backup:', snapshot)
    print('Use the new password to sign in as july. Start run_backend_windows.ps1.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('ERROR:', str(error), file=sys.stderr)
        sys.exit(1)
