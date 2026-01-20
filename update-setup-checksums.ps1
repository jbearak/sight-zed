<#
.SYNOPSIS
    Updates the SHA-256 checksums in setup.ps1 for downloaded dependencies.

.DESCRIPTION
    Downloads the current versions of WASI SDK, tree-sitter-stata grammar, and
    Sight language server, calculates their checksums, and updates setup.ps1.

.PARAMETER DryRun
    Show what checksums would be updated without modifying files.

.EXAMPLE
    .\update-setup-checksums.ps1
    .\update-setup-checksums.ps1 -DryRun
#>

param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$setupPath = Join-Path $PSScriptRoot "setup.ps1"
if (-not (Test-Path $setupPath)) {
    throw "setup.ps1 not found at $setupPath"
}

Write-Host "Calculating checksums for setup.ps1 dependencies..." -ForegroundColor Cyan
Write-Host ""

# Temporary directory for downloads
$tempDir = Join-Path $env:TEMP "setup-checksum-update"
if (Test-Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    # WASI SDK x86_64 Windows
    $wasiSdkVersion = "24"
    $wasiSdkUrl = "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${wasiSdkVersion}/wasi-sdk-${wasiSdkVersion}.0-x86_64-windows.tar.gz"
    $wasiSdkPath = Join-Path $tempDir "wasi-sdk.tar.gz"
    
    Write-Host "Downloading WASI SDK ${wasiSdkVersion}..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $wasiSdkUrl -OutFile $wasiSdkPath
    $wasiSdkHash = (Get-FileHash -Path $wasiSdkPath -Algorithm SHA256).Hash.ToLower()
    Write-Host "  WASI SDK x64: $wasiSdkHash" -ForegroundColor Green

    # Tree-sitter-stata grammar
    $grammarUrl = "https://github.com/jbearak/tree-sitter-stata/releases/download/v0.1.0/tree-sitter-stata.wasm"
    $grammarPath = Join-Path $tempDir "stata.wasm"
    
    Write-Host "Downloading tree-sitter-stata grammar..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $grammarUrl -OutFile $grammarPath
    $grammarHash = (Get-FileHash -Path $grammarPath -Algorithm SHA256).Hash.ToLower()
    Write-Host "  Grammar: $grammarHash" -ForegroundColor Green

    # Sight language server (read version from setup.ps1)
    $setupContent = Get-Content -Path $setupPath -Raw
    if ($setupContent -match '\$serverVersion\s*=\s*"(v[\d.]+)"') {
        $serverVersion = $matches[1]
    } else {
        $serverVersion = "v0.1.11"  # fallback
    }
    $serverUrl = "https://github.com/jbearak/sight/releases/download/$serverVersion/sight-server.js"
    $serverPath = Join-Path $tempDir "sight-server.js"
    
    Write-Host "Downloading Sight language server $serverVersion..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $serverUrl -OutFile $serverPath
    $serverHash = (Get-FileHash -Path $serverPath -Algorithm SHA256).Hash.ToLower()
    Write-Host "  Sight server: $serverHash" -ForegroundColor Green

    Write-Host ""

    if ($DryRun) {
        Write-Host "DRY RUN - Would update setup.ps1 with:" -ForegroundColor Cyan
        Write-Host "  WasiSdkX64 = `"$wasiSdkHash`""
        Write-Host "  TreeSitterGrammar = `"$grammarHash`""
        Write-Host "  SightServer = `"$serverHash`""
        return
    }

    # Update setup.ps1
    $content = Get-Content -Path $setupPath -Raw

    # Update WASI SDK checksum (case-insensitive for robustness)
    $pattern = '(?i)(WasiSdkX64\s*=\s*")[a-f0-9]{64}(")'
    if ($content -notmatch $pattern) {
        throw "WasiSdkX64 checksum not found in setup.ps1"
    }
    $updated = [regex]::Replace($content, $pattern, "`${1}$wasiSdkHash`${2}")

    # Update grammar checksum
    $pattern = '(?i)(TreeSitterGrammar\s*=\s*")[a-f0-9]{64}(")'
    if ($updated -notmatch $pattern) {
        throw "TreeSitterGrammar checksum not found in setup.ps1"
    }
    $updated = [regex]::Replace($updated, $pattern, "`${1}$grammarHash`${2}")

    # Update server checksum
    $pattern = '(?i)(SightServer\s*=\s*")[a-f0-9]{64}(")'
    if ($updated -notmatch $pattern) {
        throw "SightServer checksum not found in setup.ps1"
    }
    $updated = [regex]::Replace($updated, $pattern, "`${1}$serverHash`${2}")

    if ($content -eq $updated) {
        Write-Host "No changes, skipping update." -ForegroundColor Cyan
        return
    }

    Set-Content -Path $setupPath -Value $updated -Encoding UTF8

    Write-Host "Updated checksums in setup.ps1" -ForegroundColor Green

    # Stage and commit
    & git add $setupPath
    if ($LASTEXITCODE -ne 0) {
        Write-Error "git add failed with exit code $LASTEXITCODE"
        exit 1
    }
    & git commit -m "chore: update setup.ps1 dependency checksums"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "git commit failed with exit code $LASTEXITCODE"
        exit 1
    }

    Write-Host "Committed changes." -ForegroundColor Green

} finally {
    # Cleanup
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
