# PowerShell Script to Install WASI Compilation Tools on Windows
# Run as Administrator

#Requires -RunAsAdministrator

Write-Host "=== WASI Compilation Tools Installer for Windows ===" -ForegroundColor Cyan
Write-Host ""

# Function to check if a command exists
function Test-CommandExists {
    param($command)
    $null = Get-Command $command -ErrorAction SilentlyContinue
    return $?
}

# Install Chocolatey if not present
if (-not (Test-CommandExists choco)) {
    Write-Host "Installing Chocolatey package manager..." -ForegroundColor Yellow
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    refreshenv
} else {
    Write-Host "Chocolatey already installed" -ForegroundColor Green
}

# Install Git
if (-not (Test-CommandExists git)) {
    Write-Host "Installing Git..." -ForegroundColor Yellow
    choco install git -y
} else {
    Write-Host "Git already installed" -ForegroundColor Green
}

# Install CMake
if (-not (Test-CommandExists cmake)) {
    Write-Host "Installing CMake..." -ForegroundColor Yellow
    choco install cmake --installargs 'ADD_CMAKE_TO_PATH=System' -y
} else {
    Write-Host "CMake already installed" -ForegroundColor Green
}

# Install Ninja build system
if (-not (Test-CommandExists ninja)) {
    Write-Host "Installing Ninja..." -ForegroundColor Yellow
    choco install ninja -y
} else {
    Write-Host "Ninja already installed" -ForegroundColor Green
}

# Install Python (needed for LLVM build scripts)
if (-not (Test-CommandExists python)) {
    Write-Host "Installing Python..." -ForegroundColor Yellow
    choco install python -y
} else {
    Write-Host "Python already installed" -ForegroundColor Green
}

# Install LLVM/Clang
if (-not (Test-CommandExists clang)) {
    Write-Host "Installing LLVM with Clang..." -ForegroundColor Yellow
    choco install llvm -y
} else {
    Write-Host "LLVM/Clang already installed" -ForegroundColor Green
}

# Install Visual Studio Build Tools (for C/C++ compilation)
Write-Host "Checking for Visual Studio Build Tools..." -ForegroundColor Yellow
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vsWhere) {
    $vsInstall = & $vsWhere -latest -property installationPath
    if ($vsInstall) {
        Write-Host "Visual Studio Build Tools found" -ForegroundColor Green
    } else {
        Write-Host "Installing Visual Studio Build Tools..." -ForegroundColor Yellow
        choco install visualstudio2022buildtools --package-parameters "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --includeOptional --passive" -y
    }
} else {
    Write-Host "Installing Visual Studio Build Tools..." -ForegroundColor Yellow
    choco install visualstudio2022buildtools --package-parameters "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --includeOptional --passive" -y
}

# Install Rust (optional but useful for some WASI tooling)
if (-not (Test-CommandExists rustc)) {
    Write-Host "Installing Rust..." -ForegroundColor Yellow
    choco install rust -y
} else {
    Write-Host "Rust already installed" -ForegroundColor Green
}

# Install wasi-sdk (pre-built WASI toolchain)
Write-Host "Installing WASI SDK..." -ForegroundColor Yellow
$wasiSdkVersion = "24"
$wasiSdkUrl = "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${wasiSdkVersion}/wasi-sdk-${wasiSdkVersion}.0-x86_64-windows.tar.gz"
$wasiSdkPath = "C:\wasi-sdk"

if (-not (Test-Path $wasiSdkPath)) {
    New-Item -ItemType Directory -Path $wasiSdkPath -Force | Out-Null
    $downloadPath = "$env:TEMP\wasi-sdk.tar.gz"

    Write-Host "Downloading WASI SDK from GitHub..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $wasiSdkUrl -OutFile $downloadPath

    Write-Host "Extracting WASI SDK..." -ForegroundColor Yellow
    tar -xzf $downloadPath -C $wasiSdkPath --strip-components=1
    Remove-Item $downloadPath

    # Add to PATH
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($currentPath -notlike "*$wasiSdkPath\bin*") {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$wasiSdkPath\bin", "Machine")
        Write-Host "Added WASI SDK to system PATH" -ForegroundColor Green
    }
} else {
    Write-Host "WASI SDK already installed" -ForegroundColor Green
}

# Refresh environment
refreshenv

Write-Host ""
Write-Host "=== Installation Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Installed tools:" -ForegroundColor Yellow
Write-Host "  - Chocolatey (package manager)"
Write-Host "  - Git"
Write-Host "  - CMake"
Write-Host "  - Ninja"
Write-Host "  - Python"
Write-Host "  - LLVM/Clang"
Write-Host "  - Visual Studio Build Tools"
Write-Host "  - Rust"
Write-Host "  - WASI SDK"
Write-Host ""
Write-Host "WASI SDK installed at: $wasiSdkPath" -ForegroundColor Green
Write-Host ""
Write-Host "IMPORTANT: Please restart your terminal or run 'refreshenv' to update your PATH" -ForegroundColor Yellow
Write-Host ""
Write-Host "To compile a C file to WASI:" -ForegroundColor Cyan
Write-Host "  clang --target=wasm32-wasi -o output.wasm input.c" -ForegroundColor White
Write-Host ""
Write-Host "Or using WASI SDK:" -ForegroundColor Cyan
Write-Host '  $wasiSdkPath\bin\clang -o output.wasm input.c' -ForegroundColor White
