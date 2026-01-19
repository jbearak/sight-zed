param(
    [switch]$SkipBuild,
    [switch]$SkipExtensionInstall,
    [switch]$SkipSendToStata,
    [switch]$Uninstall,

    # If set, setup.ps1 will attempt to install missing build dependencies.
    # This is most useful on a fresh Windows machine.
    [switch]$InstallDependencies,

    # If set alongside -InstallDependencies, setup.ps1 may install the Visual C++ build tools
    # (large download) when a C toolchain is missing.
    [switch]$InstallMSVCBuildTools,
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
    Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File .\\setup.ps1 -Yes -InstallDependencies -InstallMSVCBuildTools"
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

function Install-RustupIfMissing {
    if (Test-CommandExists -Name cargo) {
        return
    }

    if (-not (Confirm-Install -Prompt "Rustup (cargo) is required to build; install via winget now?")) {
        throw "Rust toolchain is required to build. Re-run with -Yes or install Rust (https://rustup.rs/) then re-run."
    }

    if (Test-CommandExists -Name winget) {
        Write-Host "Installing Rustup via winget (Rustlang.Rustup)..."
        & winget install --id Rustlang.Rustup -e --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "winget failed to install Rustup (exit code $LASTEXITCODE)."
        }
        Ensure-UserCargoOnPath
        return
    }

    throw "cargo is required to build the extension, but was not found. Install Rust via rustup (https://rustup.rs/) or install winget and re-run with -InstallDependencies."
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

                $hostArch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
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
        throw "MSVC build tools (cl.exe/link.exe) were not found. Install the 'Desktop development with C++' workload or rerun setup.ps1 with -InstallDependencies -InstallMSVCBuildTools to install via winget."
    }

    Invoke-Command -ScriptBlock $Script
}

function Install-MSVCBuildToolsViaWinget {
    if (-not (Test-CommandExists -Name winget)) {
        throw "MSVC build tools appear to be missing (cl.exe not found), and winget is not available to install them. Install Visual Studio Build Tools (C++ workload) and re-run."
    }

    Write-Host "Installing Visual Studio 2022 Build Tools (C++ workload) via winget... (this can take a while, ~3-4 GB)"
    $wingetArgs = 'install --id Microsoft.VisualStudio.2022.BuildTools -e --accept-package-agreements --accept-source-agreements --override "--add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.ARM64 --includeRecommended --passive --norestart"'
    if (Test-Administrator) {
        & winget $wingetArgs
        $installExit = $LASTEXITCODE
    } else {
        Write-Host "Elevating to install MSVC Build Tools via winget..."
        $installExit = Invoke-ElevatedProcess -FilePath "winget" -ArgumentString $wingetArgs -AllowedExitCodes @(0, -1978335189)
    }
    if ($installExit -eq -1978335189) {
        Write-Host "Visual Studio Build Tools already installed and up to date (winget exit $installExit)."
    } elseif ($installExit -ne 0) {
        throw "winget failed to install Visual Studio Build Tools (exit code $installExit)."
    }
    
    # After installation, we need to ensure the environment is updated or warn the user.
    Write-Host "Installation successful. If cl.exe is still not on PATH, restart your terminal."
}

function Install-MSVCBuildToolsIfRequested {
    if (-not $InstallMSVCBuildTools) { return }
    if (Test-MsvcToolchainPresent) { return }
    if ($script:MsvcInstallAttempted) { return }
    $script:MsvcInstallAttempted = $true
    Install-MSVCBuildToolsViaWinget
}

function Ensure-BuildDependencies {
    if ($InstallMSVCBuildTools -and -not $InstallDependencies) {
        Write-Warning "-InstallMSVCBuildTools has no effect unless -InstallDependencies is also specified. Re-run with both switches to auto-install the toolchain."
    }

    if (-not (Test-MsvcToolchainPresent)) {
        Write-Host "MSVC build tools (cl.exe/link.exe) are required to build the extension."
        # If tools are installed but not on PATH, try importing MSVC env once before prompting.
        $imported = $false
        try {
            Invoke-WithMsvc -Script { Write-Host "MSVC environment imported for current session (pre-install check)." }
            $imported = $true
        } catch {
            Write-Warning "MSVC env import attempt failed: $($_.Exception.Message)"
        }
        if ($imported -and (Test-MsvcToolchainPresent)) {
            return
        }
        if (Test-CommandExists -Name winget) {
            if (Confirm-Install -Prompt "Download and install the Visual Studio Build Tools C++ workload now via winget?") {
                Install-MSVCBuildToolsViaWinget
                # Attempt to proceed in the same session; Invoke-WithMsvc will import vcvars if needed.
                try {
                    Invoke-WithMsvc -Script { Write-Host "MSVC environment imported for current session." }
                } catch {
                    Write-Warning "MSVC build tools remain unavailable after installation: $($_.Exception.Message)"
                    Report-MsvcInstructions
                }
            } else {
                throw "MSVC build tools are required; rerun with -SkipBuild if you only want install/uninstall steps."
            }
        } else {
            throw "MSVC build tools are required (cl.exe/link.exe not found) and winget is unavailable. Install the 'Desktop development with C++' workload of Visual Studio or the standalone Build Tools, then re-run."
        }
    }

    # Only attempt Rust-related installs when explicitly requested.
    if (-not $InstallDependencies) {
        return
    }

    Install-RustupIfMissing
    
    if (-not (Test-MsvcToolchainPresent) -and $InstallMSVCBuildTools) {
        Install-MSVCBuildToolsIfRequested
        if (-not (Test-MsvcToolchainPresent)) {
            Report-MsvcInstructions
        }
    }
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

function Build-Extension {
    Assert-Command -Name cargo -Hint "Install Rust (https://rustup.rs/) and ensure 'cargo' is on your PATH (or re-run setup.ps1 with -InstallDependencies)."
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