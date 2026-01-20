param(
    [string]$InstallerPath = "$(Split-Path -Parent $MyInvocation.MyCommand.Path)\install-send-to-stata.ps1",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path $InstallerPath)) { throw "Installer not found at $InstallerPath" }

# Calculate checksums for both executables
$arm64Exe = Join-Path $repoRoot "send-to-stata-arm64.exe"
$x64Exe = Join-Path $repoRoot "send-to-stata-x64.exe"

if (-not (Test-Path $arm64Exe)) { throw "ARM64 executable not found at $arm64Exe" }
if (-not (Test-Path $x64Exe)) { throw "x64 executable not found at $x64Exe" }

$hashArm64 = (Get-FileHash -Path $arm64Exe -Algorithm SHA256).Hash.ToLower()
$hashX64 = (Get-FileHash -Path $x64Exe -Algorithm SHA256).Hash.ToLower()

Write-Host "ARM64 checksum: $hashArm64"
Write-Host "x64 checksum:   $hashX64"

$content = Get-Content -Path $InstallerPath -Raw

# Update ARM64 checksum
$patternArm64 = '(?m)\$expectedChecksumArm64\s*=\s*"[A-Fa-f0-9]{64}"'
if ($content -notmatch $patternArm64) { throw "expectedChecksumArm64 assignment not found in installer" }
$updated = [regex]::Replace($content, $patternArm64, "`$expectedChecksumArm64 = `"$hashArm64`"")

# Update x64 checksum
$patternX64 = '(?m)\$expectedChecksumX64\s*=\s*"[A-Fa-f0-9]{64}"'
if ($updated -notmatch $patternX64) { throw "expectedChecksumX64 assignment not found in installer" }
$updated = [regex]::Replace($updated, $patternX64, "`$expectedChecksumX64 = `"$hashX64`"")

if ($DryRun) {
    Write-Host "Checksums would be updated:"
    Write-Host "  ARM64: $hashArm64"
    Write-Host "  x64:   $hashX64"
    return
}

if ($content -eq $updated) {
    Write-Host "Checksums already up to date."
    return
}

Set-Content -Path $InstallerPath -Value $updated -Encoding UTF8

# Stage and commit
& git add $InstallerPath
& git commit -m "chore: update send-to-stata executable checksums"

Write-Host "Updated checksums and committed."
