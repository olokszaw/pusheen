param([Parameter(Mandatory = $true)][string]$PythonExecutable)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$toolsDirectory = Join-Path $PSScriptRoot '.tools'
$denoExecutable = Join-Path $toolsDirectory 'deno.exe'
$readyMarker = Join-Path $toolsDirectory 'youtube-runtime-v1.ready'

if (-not (Test-Path -LiteralPath $readyMarker)) {
    & $PythonExecutable -m pip install --upgrade 'yt-dlp[default]'
    if ($LASTEXITCODE -ne 0) { throw 'Failed to update yt-dlp with YouTube EJS support.' }

    if (-not (Test-Path -LiteralPath $denoExecutable)) {
        New-Item -ItemType Directory -Force -Path $toolsDirectory | Out-Null
        $denoArchive = Join-Path $env:TEMP 'pulse-deno-x86_64.zip'
        Invoke-WebRequest `
            -Uri 'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip' `
            -OutFile $denoArchive `
            -UseBasicParsing
        Expand-Archive -LiteralPath $denoArchive -DestinationPath $toolsDirectory -Force
        Remove-Item -LiteralPath $denoArchive -Force
    }

    & $denoExecutable --version
    if ($LASTEXITCODE -ne 0) { throw 'Deno runtime validation failed.' }
    [System.IO.File]::WriteAllText($readyMarker, "ready`n", (New-Object System.Text.UTF8Encoding($false)))
}
