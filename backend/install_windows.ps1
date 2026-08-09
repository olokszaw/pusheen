$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Invoke-Checked {
    param([string]$FilePath, [string[]]$Arguments)
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $FilePath $($Arguments -join ' ')"
    }
}

if (-not (Test-Path ".venv\Scripts\python.exe") -and -not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "Python is not installed or is not available in PATH. Install Python 3.12 and reopen PowerShell."
}

if (-not (Test-Path ".venv\Scripts\python.exe")) {
    python -m venv .venv
    if ($LASTEXITCODE -ne 0) { throw "Failed to create Python virtual environment." }
}

$venvPython = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"
Invoke-Checked $venvPython @("--version")
Invoke-Checked $venvPython @("-m", "pip", "install", "--upgrade", "pip")
Invoke-Checked $venvPython @("-m", "pip", "install", "-r", "requirements.txt")

if (-not (Test-Path ".env")) {
    $secret = & $venvPython -c "import secrets; print(secrets.token_urlsafe(64))"
    if ($LASTEXITCODE -ne 0) { throw "Failed to generate DJANGO_SECRET_KEY." }
    $environmentLines = @(
        "DJANGO_SECRET_KEY=$secret"
        "DJANGO_DEBUG=0"
        "DJANGO_ALLOWED_HOSTS=*"
        "USE_REDIS=0"
        "TELEGRAM_BOT_TOKEN="
    )
    [System.IO.File]::WriteAllLines(
        (Join-Path $PSScriptRoot ".env"),
        $environmentLines,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

foreach ($line in Get-Content ".env") {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
    $parts = $trimmed.Split("=", 2)
    if ($parts.Count -eq 2) {
        [Environment]::SetEnvironmentVariable($parts[0], $parts[1], "Process")
    }
}

Invoke-Checked $venvPython @("manage.py", "migrate", "--noinput")
Invoke-Checked $venvPython @("manage.py", "collectstatic", "--noinput")
Invoke-Checked $venvPython @("manage.py", "check", "--deploy")

Write-Host ""
Write-Host "Pulse backend installed successfully." -ForegroundColor Green
Write-Host "Next command: .\run_backend_windows.ps1"
