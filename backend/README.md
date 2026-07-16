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

For the public Cloudflare quick tunnel, leave the backend running and open a
second PowerShell window:

```powershell
cd C:\Users\luiin\OneDrive\Desktop\rave\backend
.\run_tunnel_windows.ps1
```

The app is configured for `trio-anderson-istanbul-definition.trycloudflare.com`.
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
