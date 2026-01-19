param(
    [switch]$SkipBuild,
    [switch]$SkipExtensionInstall,
    [switch]$SkipSendToStata,
    [switch]$Uninstall,
    [switch]$Yes,

    [string]$ZedExtensionsDir = "$(Join-Path $env:APPDATA 'Zed\extensions\installed')",

    # Forwarded to install-send-to-stata.ps1
    [switch]$RegisterAutomation,
    [switch]$SkipAutomationCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-CommandExists {
    param([Parameter(Mandatory=$true)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}
function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}
function Invoke-ElevatedProcess {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string]$ArgumentString,
        [int[]]$AllowedExitCodes = @(0)
    )
    $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentString -Verb RunAs -Wait -PassThru
    if ($AllowedExitCodes -notcontains $proc.ExitCode) {
        throw "$FilePath exited with code $($proc.ExitCode)"
    }
    return $proc.ExitCode
}
function Get-HostArch {
    try {
        $arch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
        if ($arch) { return $arch.ToString() }
    } catch { }
    $pa = $env:PROCESSOR_ARCHITECTURE
    $pi = $env:PROCESSOR_IDENTIFIER
    if ($pa -match 'ARM64' -or $pi -match '(?i)ARM') { return 'Arm64' }
    if ([Environment]::Is64BitProcess) { return 'X64' }
    return 'X86'
}
function Ensure-Arm64MsvcLibs {
    param([string]$InstallPath)
    if ([string]::IsNullOrWhiteSpace($InstallPath)) { return }
    $arm64Lib = Get-ChildItem -Path (Join-Path $InstallPath "VC\\Tools\\MSVC") -Filter "msvcrt.lib" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like "*\\lib\\arm64\\msvcrt.lib" } | Select-Object -First 1
    if ($arm64Lib) { return }
    $vsInstaller = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\\Installer\\vs_installer.exe"
    if (-not (Test-Path $vsInstaller)) {
        Write-Warning "vs_installer.exe not found; cannot auto-add ARM64 MSVC component."
        return
    }
    $productId = & "$vsInstaller" list --quiet | Select-String "$InstallPath" | ForEach-Object {
        ($_ -split '\s+')[0]
    } | Select-Object -First 1
    $pidArg = if ($productId) { "--productId `"$productId`"" } else { "" }
    $args = "--modify --installPath `"$InstallPath`" $pidArg --add Microsoft.VisualStudio.Component.VC.Tools.ARM64 --quiet --norestart --wait"
    Write-Host "ARM64 MSVC libs missing; adding component via vs_installer..."
    if (Test-Administrator) {
        & $vsInstaller $args
        if ($LASTEXITCODE -ne 0) { throw "vs_installer.exe failed with exit code $LASTEXITCODE" }
    } else {
        Invoke-ElevatedProcess -FilePath $vsInstaller -ArgumentString $args
    }
}
function Confirm-Install {
    param(
        [Parameter(Mandatory=$true)][string]$Prompt
    )
    if ($Yes) { return $true }
    $response = Read-Host "$Prompt (y/N)"
    return $response -match '^[Yy]'
}
function Report-MsvcInstructions {
    Write-Host ""
    Write-Host "MSVC toolchain still unavailable. Please install manually, then re-open a NEW terminal and re-run setup.ps1:"
    Write-Host "  1) Install 'Visual Studio 2022 Build Tools'."
    Write-Host "  2) Select workload: Desktop development with C++."
    Write-Host "  3) Include component: Microsoft.VisualStudio.Component.VC.Tools.ARM64 (for ARM64 host)."
    Write-Host ""
    Write-Host "After installation, close this window, open a fresh terminal, and rerun:"
    Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File .\\setup.ps1 -Yes"
    throw "MSVC toolchain not detected; manual install required."
}

function Assert-Command {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$Hint
    )

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $msg = "Required command not found on PATH: $Name"
        if ($Hint) { $msg += "`n$Hint" }
        throw $msg
    }
}

function Ensure-UserCargoOnPath {
    $cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
    if ($env:PATH -notlike "*$cargoBin*") {
        if (Test-Path $cargoBin) {
            $env:PATH = "$cargoBin;$env:PATH"
        }
    }
}

function Ensure-Chocolatey {
    if (Test-CommandExists -Name choco) {
        Write-Host "Chocolatey already installed" -ForegroundColor Green
        return
    }

    Write-Host "Installing Chocolatey package manager..." -ForegroundColor Yellow
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

    # Refresh PATH to pick up choco
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:PATH = "$machinePath;$userPath"

    if (-not (Test-CommandExists -Name choco)) {
        throw "Chocolatey installation failed - choco command not found after install."
    }
    Write-Host "Chocolatey installed successfully" -ForegroundColor Green
}

function Install-ChocoPackageIfMissing {
    param(
        [Parameter(Mandatory=$true)][string]$Command,
        [Parameter(Mandatory=$true)][string]$Package,
        [string]$PackageParams
    )

    if (Test-CommandExists -Name $Command) {
        Write-Host "$Command already installed" -ForegroundColor Green
        return
    }

    Write-Host "Installing $Package via Chocolatey..." -ForegroundColor Yellow
    if ($PackageParams) {
        & choco install $Package --package-parameters $PackageParams -y
    } else {
        & choco install $Package -y
    }
    if ($LASTEXITCODE -ne 0) {
        throw "choco install $Package failed (exit code $LASTEXITCODE)."
    }
}

function Test-MsvcToolchainPresent {
    # Rust on Windows typically needs a linker/toolchain.
    # Check for cl.exe and verify that 'link' is the MSVC linker, not the one from Git Bash/coreutils.
    if (-not (Test-CommandExists -Name cl)) { return $false }

    $linkPath = Get-Command link -ErrorAction SilentlyContinue
    if ($linkPath) {
        # The MSVC linker typically responds to /? or /LOGO.
        # The Unix-like link utility will fail or show different help.
        $linkHelp = & link /? 2>&1 | Out-String
        if ($linkHelp -notlike "*Microsoft (R) Incremental Linker*") {
            Write-Warning "Found 'link' at $($linkPath.Source), but it does not appear to be the MSVC linker."
            Write-Warning "This is often caused by Git Bash or other Unix-like tools being earlier in your PATH."
            return $false
        }
    } else {
        return $false
    }

    return $true
}

function Invoke-WithMsvc {
    param([scriptblock]$Script)
    $msvcReady = $false

    if (Test-MsvcToolchainPresent) { $msvcReady = $true }

    # Try to find and import vcvarsall.bat with correct host/target arch
    if (-not $msvcReady) {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
        if (-not (Test-Path $vswhere)) {
            $vswhere = "vswhere.exe"
        }

        if (Test-CommandExists -Name $vswhere) {
            $installPath = & $vswhere -latest -products * -requiresAny -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -requires Microsoft.VisualStudio.Component.VC.Tools.ARM64 -property installationPath
            if ([string]::IsNullOrWhiteSpace($installPath)) {
                Write-Warning "vswhere did not return an installation path for MSVC build tools."
            }
            if ($installPath) {
                $vcvarsAll = Join-Path $installPath "VC\\Auxiliary\\Build\\vcvarsall.bat"
                if (-not (Test-Path $vcvarsAll)) {
                    throw "vcvarsall.bat not found under $installPath"
                }

                $hostArch = Get-HostArch
                $preferArm64 = $false
                $rustHost = $null
                if (Test-CommandExists -Name rustc) {
                    $rustHostLine = (& rustc -vV 2>$null | Where-Object { $_ -like "host:*" } | Select-Object -First 1)
                    if ($rustHostLine) {
                        $parts = $rustHostLine -split "\\s+"
                        if ($parts.Count -ge 2) {
                            $rustHost = $parts[1]
                            if ($rustHost -like "*aarch64*") { $preferArm64 = $true }
                        }
                    }
                }

                if ($preferArm64) { Ensure-Arm64MsvcLibs -InstallPath $installPath }
                $vcArgs = @()
                if ($preferArm64 -or $hostArch -eq "Arm64") {
                    $vcArgs = @("arm64", "amd64_arm64")
                } elseif ($hostArch -eq "X86") {
                    $vcArgs = @("x86", "x86_amd64", "x86_arm64")
                } else {
                    $vcArgs = @("amd64", "amd64_arm64")
                }

                foreach ($arg in $vcArgs) {
                    Write-Host "Setting up MSVC environment with vcvarsall.bat $arg ..."
                    $tempFile = [System.IO.Path]::GetTempFileName()
                    cmd /c " `"$vcvarsAll`" $arg > nul && set " > $tempFile
                    if ($LASTEXITCODE -eq 0) {
                        Get-Content $tempFile | ForEach-Object {
                            if ($_ -match "^(.*?)=(.*)$") {
                                $name = $matches[1]
                                $value = $matches[2]
                                if ($name -ieq "PATH") {
                                    $env:PATH = "$value;$env:PATH"
                                } else {
                                    Set-Item -Path "env:$name" -Value $value
                                }
                            }
                        }
                        $libArch = if ($arg -like "*arm64*") { "arm64" } elseif ($arg -like "*x86*") { "x86" } else { "x64" }
                        $msvcrtDirs = Get-ChildItem -Path (Join-Path $installPath "VC\Tools\MSVC") -Filter "msvcrt.lib" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match "\\lib\\$libArch\\" } | Select-Object -ExpandProperty DirectoryName -Unique
                        if ($msvcrtDirs) {
                            $existingLib = $env:LIB
                            $libPrefix = ($msvcrtDirs -join ";")
                            if ($existingLib) {
                                $env:LIB = "$libPrefix;$existingLib"
                            } else {
                                $env:LIB = $libPrefix
                            }
                        }
                        Remove-Item $tempFile -ErrorAction SilentlyContinue
                        if (Test-MsvcToolchainPresent) {
                            $msvcReady = $true
                            break
                        } else {
                            Write-Warning "MSVC env via '$arg' did not expose cl.exe/link.exe; trying next option..."
                        }
                    } else {
                        Remove-Item $tempFile -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }

    if (-not $msvcReady) {
        throw "MSVC build tools (cl.exe/link.exe) were not found. Install the 'Desktop development with C++' workload or rerun setup.ps1 to install via winget."
    }

    Invoke-Command -ScriptBlock $Script
}

function Install-MSVCBuildToolsViaChocolatey {
    Write-Host "Installing Visual Studio 2022 Build Tools (C++ workload) via Chocolatey... (this can take a while, ~3-4 GB)" -ForegroundColor Yellow
    $params = '"--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --includeOptional --passive"'
    & choco install visualstudio2022buildtools --package-parameters $params -y
    if ($LASTEXITCODE -ne 0) {
        throw "choco install visualstudio2022buildtools failed (exit code $LASTEXITCODE)."
    }
    Write-Host "Installation successful. If cl.exe is still not on PATH, restart your terminal." -ForegroundColor Green
}

function Install-WasiSdk {
    $wasiSdkVersion = "24"
    $hostArch = Get-HostArch
    if ($hostArch -eq "Arm64") {
        $wasiSdkUrl = "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${wasiSdkVersion}/wasi-sdk-${wasiSdkVersion}.0-arm64-windows.tar.gz"
    } else {
        $wasiSdkUrl = "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${wasiSdkVersion}/wasi-sdk-${wasiSdkVersion}.0-x86_64-windows.tar.gz"
    }
    $wasiSdkPath = "C:\wasi-sdk"

    if (Test-Path $wasiSdkPath) {
        Write-Host "WASI SDK already installed at $wasiSdkPath" -ForegroundColor Green
        return
    }

    Write-Host "Installing WASI SDK..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $wasiSdkPath -Force | Out-Null
    $downloadPath = "$env:TEMP\wasi-sdk.tar.gz"

    Write-Host "Downloading WASI SDK from GitHub..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $wasiSdkUrl -OutFile $downloadPath

    Write-Host "Extracting WASI SDK..." -ForegroundColor Yellow
    tar -xzf $downloadPath -C $wasiSdkPath --strip-components=1
    Remove-Item $downloadPath -ErrorAction SilentlyContinue

    # Add to PATH
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($currentPath -notlike "*$wasiSdkPath\bin*") {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$wasiSdkPath\bin", "Machine")
        Write-Host "Added WASI SDK to system PATH" -ForegroundColor Green
    }

    Write-Host "WASI SDK installed at $wasiSdkPath" -ForegroundColor Green
}

function Install-TreeSitterBuildTools {
    # These tools are required by Zed to compile Tree-sitter grammars
    Install-ChocoPackageIfMissing -Command "git" -Package "git"
    Install-ChocoPackageIfMissing -Command "cmake" -Package "cmake" -PackageParams "'ADD_CMAKE_TO_PATH=System'"
    Install-ChocoPackageIfMissing -Command "ninja" -Package "ninja"
    Install-ChocoPackageIfMissing -Command "python" -Package "python"
    Install-ChocoPackageIfMissing -Command "clang" -Package "llvm"
}

function Ensure-BuildDependencies {
    # Check if we need to install anything that requires admin
    $needsAdmin = $false
    if (-not (Test-CommandExists -Name choco)) { $needsAdmin = $true }
    if (-not (Test-CommandExists -Name cargo)) { $needsAdmin = $true }
    if (-not (Test-CommandExists -Name git)) { $needsAdmin = $true }
    if (-not (Test-CommandExists -Name cmake)) { $needsAdmin = $true }
    if (-not (Test-CommandExists -Name ninja)) { $needsAdmin = $true }
    if (-not (Test-CommandExists -Name python)) { $needsAdmin = $true }
    if (-not (Test-CommandExists -Name clang)) { $needsAdmin = $true }
    if (-not (Test-WasiSdkPresent)) { $needsAdmin = $true }

    # Check MSVC
    $msvcPresent = $false
    if (Test-MsvcToolchainPresent) {
        $msvcPresent = $true
    } else {
        # Try importing vcvars
        try {
            Invoke-WithMsvc -Script { }
            $msvcPresent = Test-MsvcToolchainPresent
        } catch { }
    }
    if (-not $msvcPresent) { $needsAdmin = $true }

    if ($needsAdmin -and -not (Test-Administrator)) {
        if (-not (Confirm-Install -Prompt "Some build dependencies are missing and require administrator privileges to install. Elevate now?")) {
            throw "Build dependencies are required. Re-run with -Yes or install manually."
        }

        # Re-launch this script elevated
        $scriptPath = $PSCommandPath
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        if ($SkipBuild) { $argList += " -SkipBuild" }
        if ($SkipExtensionInstall) { $argList += " -SkipExtensionInstall" }
        if ($SkipSendToStata) { $argList += " -SkipSendToStata" }
        if ($Yes) { $argList += " -Yes" }
        if ($RegisterAutomation) { $argList += " -RegisterAutomation" }
        if ($SkipAutomationCheck) { $argList += " -SkipAutomationCheck" }
        $argList += " -ZedExtensionsDir `"$ZedExtensionsDir`""

        Write-Host "Elevating to install dependencies..."
        $exitCode = Invoke-ElevatedProcess -FilePath "powershell.exe" -ArgumentString $argList
        exit $exitCode
    }

    # Install Chocolatey first (needed for other installs)
    Ensure-Chocolatey

    # Install Rust
    if (-not (Test-CommandExists -Name cargo)) {
        Install-ChocoPackageIfMissing -Command "rustc" -Package "rust"
        Ensure-UserCargoOnPath
    } else {
        Write-Host "Rust already installed" -ForegroundColor Green
    }

    # Install MSVC build tools if needed
    if (-not $msvcPresent) {
        Write-Host "MSVC build tools (cl.exe/link.exe) are required to build the extension."
        # Check again after potential Chocolatey installs
        $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
        $hasVs = (Test-Path $vswhere) -and (& $vswhere -latest -property installationPath)
        if (-not $hasVs) {
            Install-MSVCBuildToolsViaChocolatey
        }
        # Try to import MSVC env
        try {
            Invoke-WithMsvc -Script { Write-Host "MSVC environment imported for current session." }
        } catch {
            Write-Warning "MSVC build tools installed but environment import failed: $($_.Exception.Message)"
            Report-MsvcInstructions
        }
    }

    # Install Tree-sitter build tools (Git, CMake, Ninja, Python, LLVM)
    Install-TreeSitterBuildTools

    # Install WASI SDK
    if (-not (Test-WasiSdkPresent)) {
        Install-WasiSdk
        # Refresh PATH
        $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $env:PATH = "$machinePath;$userPath"
        $env:WASI_SDK_PATH = "C:\wasi-sdk"
    } else {
        Write-Host "WASI SDK already installed" -ForegroundColor Green
    }

    # Refresh environment after all installs
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:PATH = "$machinePath;$userPath"
}

function Test-WasiSdkPresent {
    if ($env:WASI_SDK_PATH -and (Test-Path (Join-Path $env:WASI_SDK_PATH 'bin\clang.exe'))) { return $true }
    $paths = $env:PATH -split ';'
    foreach ($p in $paths) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $clang = Join-Path $p 'clang.exe'
        if (Test-Path $clang) {
            # Heuristic: check for accompanying sysroot in sibling share directory
            $root = Split-Path $p -Parent
            if (Test-Path (Join-Path $root 'share\\wasi-sysroot')) { return $true }
        }
    }
    return $false
}

function Ensure-WasmTarget {
    # wasm32-wasip1 is required to build Zed extensions.
    $rustup = Get-Command rustup -ErrorAction SilentlyContinue
    if (-not $rustup) {
        Write-Warning "rustup not found; cannot auto-install wasm32-wasip1 target. Assuming it is already installed."
        return
    }

    $targets = & rustup target list --installed
    if ($LASTEXITCODE -ne 0) { throw "Failed to list installed Rust targets (rustup target list --installed)." }

    if ($targets -notcontains 'wasm32-wasip1') {
        if (Confirm-Install -Prompt "Rust target wasm32-wasip1 is required; install now?") {
            Write-Host "Adding Rust target wasm32-wasip1..."
            & rustup target add wasm32-wasip1
            if ($LASTEXITCODE -ne 0) { throw "Failed to add Rust target wasm32-wasip1 (rustup target add wasm32-wasip1)." }
        } else {
            throw "wasm32-wasip1 target is required to build. Re-run with -Yes or install it manually via 'rustup target add wasm32-wasip1'."
        }
    }
}

function Download-TreeSitterGrammar {
    # Zed cannot compile tree-sitter grammars to WASM on Windows, so we download
    # a pre-built WASM from the tree-sitter-stata releases.

    $grammarUrl = "https://github.com/jbearak/tree-sitter-stata/releases/download/v0.1.0/tree-sitter-stata.wasm"

    $grammarsDir = Join-Path $PSScriptRoot 'grammars'
    if (-not (Test-Path $grammarsDir)) {
        New-Item -ItemType Directory -Path $grammarsDir -Force | Out-Null
    }

    $destWasm = Join-Path $grammarsDir 'stata.wasm'

    Write-Host "Downloading pre-built tree-sitter-stata grammar..."
    Invoke-WebRequest -Uri $grammarUrl -OutFile $destWasm

    if (-not (Test-Path $destWasm)) {
        throw "Failed to download grammar WASM"
    }

    $size = (Get-Item $destWasm).Length
    Write-Host "Downloaded grammar: grammars\stata.wasm ($size bytes)" -ForegroundColor Green

    # Remove grammar source directory if it exists.
    # If grammars/stata/ exists, Zed will try to compile it and fail on Windows.
    $grammarSrcDir = Join-Path $grammarsDir 'stata'
    if (Test-Path $grammarSrcDir) {
        Remove-Item -Path $grammarSrcDir -Recurse -Force
        Write-Host "Removed grammar source directory: grammars\stata\" -ForegroundColor Yellow
    }
}

function Build-Extension {
    Assert-Command -Name cargo -Hint "Install Rust (https://rustup.rs/) and ensure 'cargo' is on your PATH."
    Ensure-WasmTarget

    Write-Host "Building Zed extension (wasm32-wasip1, release)..."
    Invoke-WithMsvc -Script {
        & cargo build --release --target wasm32-wasip1
    }
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed." }

    $builtWasm = Join-Path $PSScriptRoot 'target\wasm32-wasip1\release\sight_extension.wasm'
    if (-not (Test-Path $builtWasm)) {
        throw "Expected build output not found: $builtWasm"
    }

    $destWasm = Join-Path $PSScriptRoot 'extension.wasm'
    Copy-Item -Path $builtWasm -Destination $destWasm -Force

    $size = (Get-Item $destWasm).Length
    Write-Host "Wrote extension.wasm ($size bytes)"

    # Download pre-built tree-sitter grammar WASM (Zed can't compile grammars on Windows)
    Download-TreeSitterGrammar
}

function Install-ZedExtension {
    param([string]$InstallRoot)

    if (-not $env:APPDATA) {
        throw "APPDATA is not set; cannot locate Zed configuration directory."
    }

    $dest = Join-Path $InstallRoot 'sight'
    if (-not (Test-Path $InstallRoot)) {
        New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
    }

    if (Test-Path $dest) {
        Remove-Item -Path $dest -Recurse -Force
    }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    # Copy the runtime files Zed needs for a locally-installed extension.
    $itemsToCopy = @(
        'extension.toml',
        'extension.wasm',
        'languages',
        'LICENSE',
        'README.md'
    )

    foreach ($item in $itemsToCopy) {
        $src = Join-Path $PSScriptRoot $item
        if (Test-Path $src) {
            Copy-Item -Path $src -Destination $dest -Recurse -Force
        }
    }

    # Copy only the pre-built grammar WASM, not the source directory.
    # If we copy grammars/stata/ (the source), Zed will try to compile it and fail on Windows.
    $grammarWasm = Join-Path $PSScriptRoot 'grammars\stata.wasm'
    if (Test-Path $grammarWasm) {
        $destGrammars = Join-Path $dest 'grammars'
        New-Item -ItemType Directory -Path $destGrammars -Force | Out-Null
        Copy-Item -Path $grammarWasm -Destination $destGrammars -Force
    }

    Write-Host "Installed extension files to: $dest"
    Write-Host "In Zed, restart or reload window to ensure the extension is picked up."
}

function Uninstall-ZedExtension {
    param([string]$InstallRoot)

    $dest = Join-Path $InstallRoot 'sight'
    if (Test-Path $dest) {
        Remove-Item -Path $dest -Recurse -Force
        Write-Host "Removed extension directory: $dest"
    } else {
        Write-Host "Extension directory not found (already removed): $dest"
    }
}

function Install-SendToStata {
    $installer = Join-Path $PSScriptRoot 'install-send-to-stata.ps1'
    if (-not (Test-Path $installer)) {
        throw "Installer not found: $installer"
    }

    $args = @()
    if ($RegisterAutomation) { $args += '-RegisterAutomation' }
    if ($Yes) { $args += '-RegisterAutomation' }
    if ($SkipAutomationCheck) { $args += '-SkipAutomationCheck' }

    Write-Host "Installing send-to-stata integration..."
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer @args
    if ($LASTEXITCODE -ne 0) { throw "install-send-to-stata.ps1 failed with exit code $LASTEXITCODE" }
}

function Uninstall-SendToStata {
    $installer = Join-Path $PSScriptRoot 'install-send-to-stata.ps1'
    if (-not (Test-Path $installer)) {
        throw "Installer not found: $installer"
    }

    Write-Host "Uninstalling send-to-stata integration..."
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Uninstall
    if ($LASTEXITCODE -ne 0) { throw "install-send-to-stata.ps1 -Uninstall failed with exit code $LASTEXITCODE" }
}

# Main
if ($Uninstall) {
    if (-not $SkipSendToStata) {
        Uninstall-SendToStata
    }
    if (-not $SkipExtensionInstall) {
        Uninstall-ZedExtension -InstallRoot $ZedExtensionsDir
    }
    Write-Host "Done."
    exit 0
}

if (-not $SkipBuild) {
    Ensure-BuildDependencies
    Ensure-UserCargoOnPath
    Build-Extension
}

if (-not $SkipExtensionInstall) {
    Install-ZedExtension -InstallRoot $ZedExtensionsDir
}

if (-not $SkipSendToStata) {
    Install-SendToStata
}

Write-Host "Done."
