$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# Load the environment file created by install_windows.ps1. Without this,
# process-only values disappear when the backend is started in a new window.
$environmentFiles = @('.env', '.env.local')
foreach ($environmentFile in $environmentFiles) {
    $envFile = Join-Path $PSScriptRoot $environmentFile
    if (Test-Path -LiteralPath $envFile) {
        foreach ($line in Get-Content -LiteralPath $envFile) {
            $trimmed = $line.Trim()
            if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
            $parts = $trimmed.Split('=', 2)
            if ($parts.Count -eq 2) {
                [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1], 'Process')
            }
        }
    }
}

# Run this in one PowerShell window on the server.
$venvPython = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $venvPython) {
    & (Join-Path $PSScriptRoot 'ensure_youtube_runtime_windows.ps1') -PythonExecutable $venvPython
    & $venvPython manage.py migrate
    if ($LASTEXITCODE -ne 0) {
        throw 'Database migrations failed. Backend was not started.'
    }
    & $venvPython -m daphne -b 127.0.0.1 -p 8000 config.asgi:application
} elseif ($pythonCommand) {
    & (Join-Path $PSScriptRoot 'ensure_youtube_runtime_windows.ps1') -PythonExecutable $pythonCommand.Source
    & $pythonCommand.Source manage.py migrate
    if ($LASTEXITCODE -ne 0) {
        throw 'Database migrations failed. Backend was not started.'
    }
    & $pythonCommand.Source -m daphne -b 127.0.0.1 -p 8000 config.asgi:application
} else {
    $pyLauncher = (Get-Command py -ErrorAction Stop).Source
    & (Join-Path $PSScriptRoot 'ensure_youtube_runtime_windows.ps1') -PythonExecutable $pyLauncher
    & $pyLauncher manage.py migrate
    if ($LASTEXITCODE -ne 0) {
        throw 'Database migrations failed. Backend was not started.'
    }
    & $pyLauncher -m daphne -b 127.0.0.1 -p 8000 config.asgi:application
}
