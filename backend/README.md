# Pulse watch-party backend

## Start

### Updating the Windows server (gallery upload build)

Stop the current backend with Ctrl+C, then extract the new backend ZIP into
`C:\PulseBackend`. Keep the existing `.env`, `.env.local`, `.venv`, database
and `media` directory. The distribution archive excludes these user files.

```powershell
Set-Location C:\PulseBackend
& .\.venv\Scripts\python.exe -m pip install -r requirements.txt
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_backend_windows.ps1
```

The start script loads the server environment and applies pending migrations
before starting Daphne. This includes migration 0022 for owner-clock sync.
Keep using the existing Caddy process. Daphne binds to `127.0.0.1:8000`;
the HTTPS proxy header is trusted only with this loopback deployment.

Gallery videos use `GET /api/rooms/<id>/upload/` to read the size limit and
`POST` on the same route for multipart upload. The default limit is 2 GiB;
`MAX_ROOM_VIDEO_UPLOAD_BYTES` in `.env` overrides it. Supported containers:
MP4, MOV, M4V. The server preserves the original file; it does not transcode.
Keep the app open while sending. The percentage measures bytes sent from
the phone; completion is shown only after the server confirms saving.

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

The production app uses `https://pulse.izanagi.online`. The existing Caddy
process proxies that hostname to Daphne at `127.0.0.1:8000`; Cloudflare Tunnel
is not required.

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
