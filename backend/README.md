# Pulse watch-party backend

## Start

```powershell
cd backend
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python manage.py makemigrations watchparty
python manage.py migrate
python manage.py runserver
```

For multi-user WebSockets start Redis locally (Docker is easiest):

```powershell
docker run --rm -p 6379:6379 redis:7-alpine
```

`POST /api/auth/demo-login/` returns a development token. Pass it to the socket as `ws://HOST/ws/rooms/ROOM_ID/?token=TOKEN`.

The room owner alone may issue `playback_command`. All state broadcasts include the server timestamp so clients align to the owner's timeline.
