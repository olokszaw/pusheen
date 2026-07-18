$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# Run this in one PowerShell window on the server.
$venvPython = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $venvPython) {
    & $venvPython manage.py migrate
    if ($LASTEXITCODE -ne 0) {
        throw 'Database migrations failed. Backend was not started.'
    }
    & $venvPython -m daphne -b 127.0.0.1 -p 8000 config.asgi:application
} elseif ($pythonCommand) {
    & $pythonCommand.Source manage.py migrate
    if ($LASTEXITCODE -ne 0) {
        throw 'Database migrations failed. Backend was not started.'
    }
    & $pythonCommand.Source -m daphne -b 127.0.0.1 -p 8000 config.asgi:application
} else {
    py manage.py migrate
    if ($LASTEXITCODE -ne 0) {
        throw 'Database migrations failed. Backend was not started.'
    }
    py -m daphne -b 127.0.0.1 -p 8000 config.asgi:application
}
