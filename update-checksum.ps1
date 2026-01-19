param(
    [string]$InstallerPath = "$(Split-Path -Parent $MyInvocation.MyCommand.Path)\install-send-to-stata.ps1",
    [string]$TargetPath = "$(Split-Path -Parent $MyInvocation.MyCommand.Path)\send-to-stata.ps1",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path $InstallerPath)) { throw "Installer not found at $InstallerPath" }
if (-not (Test-Path $TargetPath)) { throw "Target script not found at $TargetPath" }

$hash = (Get-FileHash -Path $TargetPath -Algorithm SHA256).Hash

$content = Get-Content -Path $InstallerPath -Raw
$pattern = '(?m)\$expectedChecksum\s*=\s*"[A-Fa-f0-9]{64}"'
if ($content -notmatch $pattern) { throw "expectedChecksum assignment not found in installer" }
$updated = [regex]::Replace($content, $pattern, "`$expectedChecksum = `"$hash`"")

if ($DryRun) {
    Write-Host "Checksum would be updated to $hash"
    return
}

Set-Content -Path $InstallerPath -Value $updated -Encoding UTF8

# stage and commit
& git add $InstallerPath
& git commit -m "chore: update send-to-stata.ps1 checksum`n`nCo-Authored-By: Warp <agent@warp.dev>"

Write-Host "Updated checksum to $hash and committed."
