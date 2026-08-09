# Pulse watch-party backend

## Start

```powershell
cd C:\Users\luiin\OneDrive\Desktop\rave\backend
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python manage.py migrate
.\run_backend_windows.ps1
```

Add the BotFather token once to `.env`:

```env
TELEGRAM_BOT_TOKEN=123456789:your-bot-token
```

`run_backend_windows.ps1` loads `.env` on every start, so the token survives
backend restarts and new PowerShell windows.

`TELEGRAM_BOT_TOKEN` нужен только серверу для официальных Bot API методов
`getStickerSet`/`getFile`. Не добавляйте его в Swift-код, Info.plist или IPA.

## PostgreSQL на Windows

SQLite оставлен только для локального одиночного запуска. Для нескольких
пользователей используйте PostgreSQL: он допускает параллельные записи и не
создаёт `database is locked` при presence, сообщениях и комнатах.

Самый короткий вариант через Docker Desktop:

```powershell
cd C:\PulseBackend
.\start_postgresql_docker_windows.ps1 -Password 'СЛОЖНЫЙ_ПАРОЛЬ'
# Остановите старое окно backend, затем:
.\migrate_sqlite_to_postgresql_windows.ps1
.\run_backend_windows.ps1
```

Сценарий переноса сохраняет пользователей, токены, друзей, комнаты, сообщения,
активность и стикеры. Перед переносом он создаёт резервную копию `db.sqlite3` и
JSON-экспорт в `_database_backups`. Старую SQLite-базу он не удаляет.

Если PostgreSQL уже установлен без Docker, добавьте в `.env` строку:

```env
DATABASE_URL=postgresql://pulse:password@127.0.0.1:5432/pulse
```

и запустите `migrate_sqlite_to_postgresql_windows.ps1`.

For the public Cloudflare quick tunnel, leave the backend running and open a
second PowerShell window:

```powershell
cd C:\Users\luiin\OneDrive\Desktop\rave\backend
.\run_tunnel_windows.ps1
```

The app is configured for `bradford-advice-convinced-manager.trycloudflare.com`.
Quick Tunnel URLs change after a restart; rebuild the Flutter app with
`--dart-define=API_BASE_URL=https://NEW-URL.trycloudflare.com` when Cloudflare
prints a different address.

For multi-user WebSockets start Redis locally (Docker is easiest):

```powershell
docker run --rm -p 6379:6379 redis:7-alpine
```

`POST /api/auth/demo-login/` returns a development token. Pass it to the socket as `ws://HOST/ws/rooms/ROOM_ID/?token=TOKEN`.

The room owner alone may issue `playback_command`. All state broadcasts include the server timestamp so clients align to the owner's timeline.

## Media providers

- `VK` links use the dedicated `resolve_vk_stream` pipeline.
- Other public HTTP(S) pages use the separate `resolve_web_stream` pipeline.
- The WEB pipeline extracts the main direct MP4/HLS stream when the site exposes one. The Flutter client may use its isolated embedded-page fallback for unsupported public pages.
- Localhost, private IPs and local network URLs are rejected.

No database migration is required for this provider split. The existing
`vk_video_url` database column is retained for compatibility; API clients use
the provider-neutral `media_url` and `source_type` fields.
