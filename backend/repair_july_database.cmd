@echo off
cd /d "%~dp0"
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8
".venv\Scripts\python.exe" repair_july_database.py
if errorlevel 1 (
  echo Repair failed. Read the error above.
  pause
  exit /b 1
)
echo Repair completed. You can start the backend now.
pause
