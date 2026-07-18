$ErrorActionPreference = 'Stop'

# Run this in a second PowerShell window after run_backend_windows.ps1.
$cloudflared = 'C:\Cloudflared\cloudflared.exe'
if (Test-Path -LiteralPath $cloudflared) {
    & $cloudflared tunnel --url http://127.0.0.1:8000
} else {
    cloudflared tunnel --url http://127.0.0.1:8000
}
