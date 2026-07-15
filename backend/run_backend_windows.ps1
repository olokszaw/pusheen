$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".env")) {
    throw "Missing .env. Run .\install_windows.ps1 first."
}

foreach ($line in Get-Content ".env") {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
    $parts = $trimmed.Split("=", 2)
    if ($parts.Count -eq 2) {
        [Environment]::SetEnvironmentVariable($parts[0], $parts[1], "Process")
    }
}

$python = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"
& $python manage.py migrate --noinput
if ($LASTEXITCODE -ne 0) { throw "Database migration failed." }
& .\.venv\Scripts\daphne.exe -b 127.0.0.1 -p 8000 config.asgi:application
