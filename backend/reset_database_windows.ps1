$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# The restored backend used these temporary migration branches. They conflict
# with the current canonical migration and must not remain after an upgrade.
$legacyMigrations = @(
    'watchparty\migrations\0002_roommember_active_connections_chatmessage_and_more.py',
    'watchparty\migrations\0003_clientidentity_avatar_data_url.py',
    'watchparty\migrations\0004_merge_20260716_1440.py'
)

foreach ($migration in $legacyMigrations) {
    if (Test-Path -LiteralPath $migration) {
        Remove-Item -LiteralPath $migration -Force
    }
}

$migrationCache = 'watchparty\migrations\__pycache__'
if (Test-Path -LiteralPath $migrationCache) {
    Remove-Item -LiteralPath $migrationCache -Recurse -Force
}

if (Test-Path -LiteralPath 'db.sqlite3') {
    Remove-Item -LiteralPath 'db.sqlite3' -Force
}

$venvPython = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (Test-Path -LiteralPath $venvPython) {
    & $venvPython manage.py migrate
} else {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCommand) {
        & $pythonCommand.Source manage.py migrate
    } else {
        py manage.py migrate
    }
}

if ($LASTEXITCODE -ne 0) {
    throw 'Fresh database migration failed. Database was not initialized.'
}

Write-Host ''
Write-Host 'Fresh database created successfully.' -ForegroundColor Green
Write-Host 'Optional next command: .\.venv\Scripts\python.exe manage.py createsuperuser'
