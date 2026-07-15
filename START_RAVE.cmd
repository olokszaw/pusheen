@echo off
setlocal
set "ROOT=%~dp0"
set "PYTHON=%ROOT%backend\.venv_verify\Scripts\python.exe"

if not exist "%PYTHON%" (
  echo Backend environment is missing: %PYTHON%
  echo Create it and install backend\requirements.txt first.
  pause
  exit /b 1
)

where flutter >nul 2>nul
if errorlevel 1 (
  set "FLUTTER=C:\src\flutter\bin\flutter.bat"
) else (
  set "FLUTTER=flutter"
)

start "Rave backend" /D "%ROOT%backend" cmd /k ""%PYTHON%" manage.py runserver 127.0.0.1:8000"
cd /d "%ROOT%flutter_app"
call "%FLUTTER%" run -d edge --web-port 5173
