param(
    [string]$DatabaseUrl = '',
    [switch]$AllowNonEmpty
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (Get-NetTCPConnection -State Listen -LocalPort 8000 -ErrorAction SilentlyContinue) {
    throw 'Stop the backend on port 8000 before migrating the SQLite database.'
}

$envPath = Join-Path $PSScriptRoot '.env'
if (-not $DatabaseUrl -and (Test-Path -LiteralPath $envPath)) {
    $databaseLine = Get-Content -LiteralPath $envPath | Where-Object { $_ -match '^DATABASE_URL=' } | Select-Object -Last 1
    if ($databaseLine) { $DatabaseUrl = $databaseLine.Substring('DATABASE_URL='.Length).Trim() }
}
if (-not $DatabaseUrl -or $DatabaseUrl -notmatch '^postgres(?:ql)?://') {
    throw 'PostgreSQL DATABASE_URL is missing. Run start_postgresql_docker_windows.ps1 first.'
}

$venvPython = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $venvPython)) {
    throw '.venv was not found. Run install_windows.ps1 first.'
}
$sqlitePath = Join-Path $PSScriptRoot 'db.sqlite3'
if (-not (Test-Path -LiteralPath $sqlitePath)) {
    throw 'db.sqlite3 was not found.'
}

$backupDirectory = Join-Path $PSScriptRoot '_database_backups'
New-Item -ItemType Directory -Force -Path $backupDirectory | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$sqliteBackup = Join-Path $backupDirectory "db-before-postgresql-$stamp.sqlite3"
$fixture = Join-Path $backupDirectory "sqlite-export-$stamp.json"
Copy-Item -LiteralPath $sqlitePath -Destination $sqliteBackup

$sqliteUrl = 'sqlite:///' + ($sqlitePath -replace '\\', '/')
try {
    $env:DATABASE_URL = $sqliteUrl
    & $venvPython manage.py dumpdata `
        --natural-foreign --natural-primary `
        --exclude contenttypes --exclude auth.permission --exclude admin.logentry `
        --indent 2 --output $fixture
    if ($LASTEXITCODE -ne 0) { throw 'SQLite export failed.' }

    $env:DATABASE_URL = $DatabaseUrl
    & $venvPython manage.py migrate --noinput
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL migrations failed.' }

    $existingUsers = & $venvPython manage.py shell -c "from django.contrib.auth import get_user_model; print(get_user_model().objects.count())"
    $existingCount = [int]($existingUsers | Select-Object -Last 1)
    if ($existingCount -gt 0 -and -not $AllowNonEmpty) {
        throw 'PostgreSQL already contains users. Use -AllowNonEmpty only for an intentional merge.'
    }

    & $venvPython manage.py loaddata $fixture
    if ($LASTEXITCODE -ne 0) { throw 'Loading data into PostgreSQL failed.' }
    & $venvPython manage.py check
    if ($LASTEXITCODE -ne 0) { throw 'Backend check failed after migration.' }
} finally {
    $env:DATABASE_URL = $DatabaseUrl
}

Write-Host 'PostgreSQL migration completed.' -ForegroundColor Green
Write-Host "SQLite backup: $sqliteBackup"
Write-Host "Data export: $fixture"
Write-Host 'The old db.sqlite3 was preserved. Start run_backend_windows.ps1.'
