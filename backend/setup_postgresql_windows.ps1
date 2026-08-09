param(
    # This is the password chosen during the normal PostgreSQL Windows installer.
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[^\r\n]+$')]
    [string]$Password,
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,62}$')]
    [string]$DatabaseName = 'pulse',
    [string]$DatabaseUser = 'postgres',
    [string]$DbHost = '127.0.0.1',
    [ValidateRange(1, 65535)]
    [int]$Port = 5432
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# PostgreSQL's Windows installer normally puts psql here.  Prefer PATH if the
# user has already added it, then fall back to every installed major version.
$psqlCommand = Get-Command psql.exe -ErrorAction SilentlyContinue
$psql = if ($psqlCommand) { $psqlCommand.Source } else {
    Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe' -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $psql) {
    throw 'PostgreSQL was not found. Install PostgreSQL for Windows first, then run this script again.'
}

$env:PGPASSWORD = $Password
try {
    & $psql -X -v ON_ERROR_STOP=1 -h $DbHost -p $Port -U $DatabaseUser -d postgres -c 'SELECT 1;' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not connect to PostgreSQL. Check the installer password and that the PostgreSQL service is running.' }

    $existsOutput = @(& $psql -X -h $DbHost -p $Port -U $DatabaseUser -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$DatabaseName';")
    if ($LASTEXITCODE -ne 0) { throw 'Could not check whether the PostgreSQL database exists.' }
    # psql returns no rows for a new database.  Convert the array explicitly so
    # a valid empty response never becomes a null .Trim() call in PowerShell.
    $exists = [string]::Join("`n", [string[]]$existsOutput).Trim()
    if ($exists -ne '1') {
        & $psql -X -v ON_ERROR_STOP=1 -h $DbHost -p $Port -U $DatabaseUser -d postgres -c "CREATE DATABASE `"$DatabaseName`";" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the PostgreSQL database.' }
    }
} finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}

$encodedUser = [Uri]::EscapeDataString($DatabaseUser)
$encodedPassword = [Uri]::EscapeDataString($Password)
$databaseUrl = "postgresql://${encodedUser}:${encodedPassword}@${DbHost}:${Port}/${DatabaseName}"
$envPath = Join-Path $PSScriptRoot '.env'
$lines = if (Test-Path -LiteralPath $envPath) { @(Get-Content -LiteralPath $envPath) } else { @() }
$updated = $false
$lines = @($lines | ForEach-Object {
    if ($_ -match '^DATABASE_URL=') {
        $updated = $true
        "DATABASE_URL=$databaseUrl"
    } else { $_ }
})
if (-not $updated) { $lines += "DATABASE_URL=$databaseUrl" }
[System.IO.File]::WriteAllLines($envPath, $lines, (New-Object System.Text.UTF8Encoding($false)))

Write-Host 'PostgreSQL is ready and DATABASE_URL was written to .env.' -ForegroundColor Green
Write-Host 'Next: run .\migrate_sqlite_to_postgresql_windows.ps1'
