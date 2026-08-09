param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[^\r\n]+$')]
    [string]$Password,
    [int]$Port = 5432
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker was not found. Install Docker Desktop or PostgreSQL 16 manually.'
}

$containerName = 'pulse-postgres'
$existing = docker ps -a --filter "name=^/$containerName$" --format '{{.Names}}'
if ($existing -eq $containerName) {
    docker start $containerName | Out-Null
} else {
    docker run -d --name $containerName --restart unless-stopped `
        -e POSTGRES_DB=pulse `
        -e POSTGRES_USER=pulse `
        -e "POSTGRES_PASSWORD=$Password" `
        -p "127.0.0.1:${Port}:5432" `
        -v pulse-postgres-data:/var/lib/postgresql/data `
        postgres:16-alpine | Out-Null
}

$encodedPassword = [Uri]::EscapeDataString($Password)
$databaseUrl = "postgresql://pulse:${encodedPassword}@127.0.0.1:${Port}/pulse"
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
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($envPath, $lines, $utf8WithoutBom)

Write-Host 'PostgreSQL is running and DATABASE_URL was saved to .env.' -ForegroundColor Green
Write-Host 'Stop the backend, then run: .\migrate_sqlite_to_postgresql_windows.ps1'
