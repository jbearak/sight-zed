# install-jupyter-stata.ps1 - Install stata_kernel for Zed Jupyter integration on Windows
#
# Requirements:
#   - PowerShell 7+ (pwsh). Windows PowerShell 5.1 may fail to parse this script.
#     Install from: https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows
#
# Usage:
#   pwsh -File .\install-jupyter-stata.ps1                         Install stata_kernel
#   pwsh -File .\install-jupyter-stata.ps1 -Uninstall              Remove installation
#   pwsh -File .\install-jupyter-stata.ps1 -Uninstall -RemoveConfig  Remove including config

param (
    [switch]$uninstall,
    [switch]$removeConfig
)

# ============================================================================
# PowerShell 7+ Check
# ============================================================================
# This script requires PowerShell 7+ due to syntax and module compatibility.
# If running in Windows PowerShell 5.1, attempt to re-launch with pwsh.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $scriptPath = $MyInvocation.MyCommand.Path
    $pwshPath = Get-Command pwsh -ErrorAction SilentlyContinue
    
    if ($pwshPath) {
        Write-Host "Re-launching with PowerShell 7..." -ForegroundColor Yellow
        
        if ($scriptPath) {
            # Running from a file - re-invoke with pwsh
            $scriptArgs = @()
            if ($uninstall) { $scriptArgs += '-Uninstall' }
            if ($removeConfig) { $scriptArgs += '-RemoveConfig' }
            & pwsh -File $scriptPath @scriptArgs
            exit $LASTEXITCODE
        } else {
            # Piped via irm | iex - re-fetch and pipe to pwsh
            $scriptArgs = ""
            if ($uninstall) { $scriptArgs += " -Uninstall" }
            if ($removeConfig) { $scriptArgs += " -RemoveConfig" }
            $url = "https://raw.githubusercontent.com/jbearak/sight-zed/main/install-jupyter-stata.ps1"
            & pwsh -NoProfile -ExecutionPolicy Bypass -Command "irm '$url' | iex$scriptArgs"
            exit $LASTEXITCODE
        }
    }
    
    Write-Host "ERROR: This script requires PowerShell 7+." -ForegroundColor Red
    Write-Host ""
    Write-Host "You're running Windows PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Install PowerShell 7:" -ForegroundColor Cyan
    Write-Host "  winget install Microsoft.PowerShell"
    Write-Host ""
    Write-Host "Then run:" -ForegroundColor Cyan
    Write-Host "  pwsh -c `"irm https://raw.githubusercontent.com/jbearak/sight-zed/main/install-jupyter-stata.ps1 | iex`""
    exit 1
}

# ============================================================================
# Configuration Constants
# ============================================================================
$VENV_DIR = "$env:LOCALAPPDATA\stata_kernel\venv"
$CONFIG_FILE = "$env:USERPROFILE\.stata_kernel.conf"

# Preferred Python version for stata_kernel on Windows.
# stata_kernel is most stable on Python 3.9–3.11; Python 3.12+ has caused repeated dependency and kernelspec issues.
$PREFERRED_PYTHON_MAJOR = 3
$PREFERRED_PYTHON_MINOR = 11

# Zed kernel discovery on Windows is most reliable when kernels are installed under:
#   %APPDATA%\jupyter\kernels\...
# Microsoft Store Python often redirects Jupyter's data dir to:
#   ...\LocalCache\Roaming\jupyter
# which Zed may not scan. We force installs into %APPDATA%.
$KERNEL_INSTALL_PREFIX = $env:APPDATA
$script:KERNEL_DIR = $null
$script:WORKSPACE_KERNEL_DIR = $null

# ============================================================================
# Zed Compatibility Pins
# ============================================================================
# Zed's REPL currently has known issues with ipykernel 7.x on Windows (e.g. iopub
# status messages including "starting"). Pin to a Zed-compatible version.
$IPYKERNEL_VERSION = "6.28.0"

# ============================================================================
# Output Helpers
# ============================================================================

function Write-ErrorMessage {
    param ([string]$message)
    Write-Host "Error: $message" -ForegroundColor Red
}

function Write-SuccessMessage {
    param ([string]$message)
    Write-Host "✓ $message" -ForegroundColor Green
}

function Write-WarningMessage {
    param ([string]$message)
    Write-Host "Warning: $message" -ForegroundColor Yellow
}

function Write-InfoMessage {
    param ([string]$message)
    Write-Host $message
}

# ============================================================================
# Prerequisite Checks
# ============================================================================

function Check-Windows {
    if (-not ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)) {
        Write-ErrorMessage "This script requires Windows"
        exit 1
    }
}

function Check-Python3 {
    $pythonPath = $null

    function Get-PythonVersion {
        param([string]$path)
        try {
            $v = & $path -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')" 2>$null
            if (-not $v) { return $null }
            $parts = $v.Trim().Split('.')
            if ($parts.Count -lt 2) { return $null }
            return @{
                Major = [int]$parts[0]
                Minor = [int]$parts[1]
                Micro = if ($parts.Count -ge 3) { [int]$parts[2] } else { 0 }
                Raw = $v.Trim()
            }
        } catch {
            return $null
        }
    }

    function Is-MicrosoftStorePython {
        param([string]$path)
        if (-not $path) { return $false }
        return ($path -match "\\WindowsApps\\") -or ($path -match "\\Program Files\\WindowsApps\\") -or ($path -match "\\Local\\Microsoft\\WindowsApps\\")
    }

    function Is-PreferredPython {
        param($ver)
        if (-not $ver) { return $false }
        return ($ver.Major -eq $PREFERRED_PYTHON_MAJOR -and $ver.Minor -eq $PREFERRED_PYTHON_MINOR)
    }

    function Find-PreferredPythonPath {
        # Try common python.org install locations first (per-user install)
        $candidates = @()

        if ($env:LOCALAPPDATA) {
            $candidates += Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\python.exe"
            $candidates += Join-Path $env:LOCALAPPDATA "Programs\Python\Python311-64\python.exe"
        }

        # Try py launcher if present
        try {
            $py = (Get-Command py -ErrorAction Stop).Source
            if ($py) {
                $candidates += $py
            }
        } catch {}

        foreach ($c in $candidates) {
            if (-not (Test-Path -Path $c)) { continue }

            if ($c -like "*\py.exe") {
                # Use py launcher to resolve 3.11
                try {
                    $ver = & $c -3.11 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')" 2>$null
                    if ($ver -match "^3\.11\.\d+$") {
                        return "$c -3.11"
                    }
                } catch {}
                continue
            }

            $verInfo = Get-PythonVersion $c
            if (Is-PreferredPython $verInfo) {
                return $c
            }
        }

        return $null
    }

    # Prefer Python 3.11 when possible
    $preferred = Find-PreferredPythonPath
    if ($preferred) {
        if ($preferred -like "*\py.exe -3.11") {
            Write-InfoMessage "Found preferred Python via py launcher: $preferred"
            return $preferred
        }

        Write-InfoMessage "Found preferred Python at: $preferred"
        $pythonPath = $preferred
    } else {
        # Fall back to whatever `python` / `python3` resolves to, but avoid Microsoft Store Python if possible.
        try {
            $pythonPath = (Get-Command python -ErrorAction Stop).Source
            Write-InfoMessage "Found Python at: $pythonPath"
        } catch {
            try {
                $pythonPath = (Get-Command python3 -ErrorAction Stop).Source
                Write-InfoMessage "Found Python3 at: $pythonPath"
            } catch {
                $pythonPath = $null
            }
        }

        if (-not $pythonPath -or (Is-MicrosoftStorePython $pythonPath)) {
            Write-WarningMessage "Python not found or Microsoft Store Python detected. Attempting to install Python $PREFERRED_PYTHON_MAJOR.$PREFERRED_PYTHON_MINOR automatically..."
            $pythonPath = Install-PythonAutomatically
            if (-not $pythonPath) {
                Write-ErrorMessage "Python installation failed"
                Write-Host ""
                Write-Host "Please install Python manually from: https://www.python.org/downloads/"
                Write-Host "Make sure to:"
                Write-Host "  1. Download Python $PREFERRED_PYTHON_MAJOR.$PREFERRED_PYTHON_MINOR (recommended for stata_kernel)"
                Write-Host "  2. Check 'Add Python to PATH' during installation"
                Write-Host "  3. Run this script again after installation"
                Write-Host ""
                exit 1
            }
        }
    }

    # If we got "py -3.11" as a command string, skip venv probe here (handled later by Create-Venv).
    if ($pythonPath -like "*\py.exe -3.11") {
        Write-InfoMessage "Using Python $PREFERRED_PYTHON_MAJOR.$PREFERRED_PYTHON_MINOR via py launcher for venv creation"
        return $pythonPath
    }

    # Now check if venv module is available
    if (-not $pythonPath) {
        Write-ErrorMessage "No valid Python installation found"
        exit 1
    }

    try {
        $venvCheck = & $pythonPath -c "import venv; print('venv available')"
        if (-not ($venvCheck -like "*venv available*")) {
            Write-ErrorMessage "python venv module is required but not available"
            exit 1
        }
        Write-InfoMessage "venv module is available"
    } catch {
        Write-ErrorMessage "python venv module is required but not available: $_"
        exit 1
    }

    # Determine Python version
    $pyVersion = & $pythonPath -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
    $pyMajor = [int]$pyVersion.Split('.')[0]
    $pyMinor = [int]$pyVersion.Split('.')[1]
    Write-InfoMessage "Python version: $pyVersion"

    if ($pyMajor -ne $PREFERRED_PYTHON_MAJOR -or $pyMinor -ne $PREFERRED_PYTHON_MINOR) {
        Write-WarningMessage "Non-preferred Python detected ($pyVersion). For best results, install Python $PREFERRED_PYTHON_MAJOR.$PREFERRED_PYTHON_MINOR."
    }

    return $pythonPath
}

function Install-PythonAutomatically {
    Write-Host "Attempting to install Python automatically..."
    Write-Host ""

    # Prefer installing Python 3.11 specifically (stata_kernel stability).
    # Try to install Python using winget if available
    try {
        Write-InfoMessage "Checking for winget (Windows Package Manager)..."
        $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetPath) {
            Write-InfoMessage "Installing Python $PREFERRED_PYTHON_MAJOR.$PREFERRED_PYTHON_MINOR using winget..."
            try {
                # Test winget first to make sure it's working
                $wingetTest = & winget --version 2>&1
                if (-not ($wingetTest -match "\d+\.\d+")) {
                    Write-WarningMessage "winget not working properly: $wingetTest"
                    return $null
                }

                # Try Python 3.11 package IDs first, then fall back to generic packages
                $pythonPackages = @(
                    "Python.Python.3.11",
                    "Python.Python.3",
                    "Python.Python",
                    "Python.3",
                    "python"
                )

                $installedSomething = $false
                foreach ($pkg in $pythonPackages) {
                    Write-InfoMessage "Attempting to install Python package: $pkg"
                    $installResult = & winget install --accept-package-agreements --accept-source-agreements $pkg 2>&1

                    if ($installResult -match "Successfully installed") {
                        Write-SuccessMessage "Python installed successfully via winget ($pkg)"
                        $installedSomething = $true
                        break
                    } elseif ($installResult -match "No package found") {
                        Write-InfoMessage "Package $pkg not found, trying next..."
                        continue
                    } else {
                        Write-WarningMessage "winget installation failed for $pkg"
                        continue
                    }
                }

                if (-not $installedSomething) {
                    Write-WarningMessage "winget did not report a successful Python installation"
                }

                # IMPORTANT: Do NOT verify by calling `python` / `python3`, since that may resolve
                # to Microsoft Store Python shims (WindowsApps) even after installation.
                # Instead, prefer returning the Python Launcher command which can target 3.11 explicitly.
                try {
                    $pyLauncher = (Get-Command py -ErrorAction Stop).Source
                    $ver = & $pyLauncher -3.11 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
                    if ($ver -match "^3\.11$") {
                        Write-InfoMessage "Verified Python 3.11 via py launcher"
                        return "$pyLauncher -3.11"
                    }
                } catch {
                    # Ignore and fall through
                }

                # Fall back: try common python.org install locations for 3.11
                $candidate = $null
                if ($env:LOCALAPPDATA) {
                    $candidate = Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\python.exe"
                    if (-not (Test-Path -Path $candidate)) {
                        $candidate = Join-Path $env:LOCALAPPDATA "Programs\Python\Python311-64\python.exe"
                    }
                }
                if ($candidate -and (Test-Path -Path $candidate)) {
                    $testOutput = & $candidate --version 2>&1
                    if ($testOutput -match "^Python 3\.11") {
                        Write-InfoMessage "Verified Python installation at: $candidate ($testOutput)"
                        return $candidate
                    }
                }

                Write-WarningMessage "Could not verify Python 3.11 after installation; you may need to restart the terminal or disable Microsoft Store Python app execution aliases."
                return $null
            } catch {
                Write-WarningMessage "winget installation failed: $_"
            }
        } else {
            Write-InfoMessage "winget not found"
        }
    } catch {
        Write-WarningMessage "winget check failed: $_"
    }

    # If still not found, try chocolatey
    try {
        Write-InfoMessage "Checking for chocolatey..."
        $chocoPath = Get-Command choco -ErrorAction SilentlyContinue
        if ($chocoPath) {
            Write-InfoMessage "Installing Python using chocolatey..."
            try {
                & choco install python -y
                Write-SuccessMessage "Python installed successfully via chocolatey"

                # Verify Python is actually installed and working
                try {
                    $pythonPath = (Get-Command python -ErrorAction Stop).Source
                    $testOutput = & $pythonPath --version 2>&1
                    if ($testOutput -match "Python \d+\.\d+") {
                        Write-InfoMessage "Verified Python installation: $testOutput"
                        return $pythonPath
                    } else {
                        Write-WarningMessage "Python installation verification failed"
                        return $null
                    }
                } catch {
                    try {
                        $pythonPath = (Get-Command python3 -ErrorAction Stop).Source
                        $testOutput = & $pythonPath --version 2>&1
                        if ($testOutput -match "Python \d+\.\d+") {
                            Write-InfoMessage "Verified Python installation: $testOutput"
                            return $pythonPath
                        } else {
                            Write-WarningMessage "Python installation verification failed"
                            return $null
                        }
                    } catch {
                        Write-WarningMessage "Could not find Python after chocolatey installation"
                        return $null
                    }
                }
            } catch {
                Write-WarningMessage "chocolatey installation failed: $_"
            }
        } else {
            Write-InfoMessage "chocolatey not available"
        }
    } catch {
        Write-WarningMessage "chocolatey check failed: $_"
    }

    # If we reach here and still don't have Python, try alternative winget package names
    if (-not $pythonPath) {
        try {
            Write-InfoMessage "Trying alternative Python package names..."
            $alternativePackages = @("Python.Python", "Python.3", "python")
            foreach ($pkg in $alternativePackages) {
                try {
                    Write-InfoMessage "Trying package: $pkg"
                    $installResult = & winget install --accept-package-agreements --accept-source-agreements $pkg 2>&1
                    if ($installResult -match "Successfully installed") {
                        # Verify installation
                        $pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
                        if ($pythonPath) {
                            $testOutput = & $pythonPath --version 2>&1
                            if ($testOutput -match "Python \d+\.\d+") {
                                Write-SuccessMessage "Python installed successfully via winget ($pkg)"
                                return $pythonPath
                            }
                        }
                    } else {
                        Write-WarningMessage "Failed to install $pkg via winget"
                    }
                } catch {
                    Write-WarningMessage "Failed to install $pkg"
                }
            }
        } catch {
            Write-WarningMessage "Alternative package installation failed"
        }
    }

    # If still not found, provide manual installation instructions
    Write-ErrorMessage "Automatic Python installation failed"
    Write-Host ""
    Write-Host "Please install Python manually from: https://www.python.org/downloads/"
    Write-Host "Make sure to:"
    Write-Host "  1. Download Python 3.9, 3.10, or 3.11 (recommended for stata_kernel)"
    Write-Host "  2. Check 'Add Python to PATH' during installation"
    Write-Host "  3. Run this script again after installation"
    Write-Host ""
    Write-Host "If you prefer automatic installation, you can:"
    Write-Host "  - Install winget (Windows Package Manager) first"
    Write-Host "  - Or install chocolatey and run: choco install python -y"
    Write-Host ""
    return $null
}

function Check-Prerequisites {
    Check-Windows
    $script:PYTHON_CMD = Check-Python3
}

# ============================================================================
# Stata Detection
# ============================================================================

function Find-StataInstallation {
    if ($env:STATA_PATH -and (Test-Path $env:STATA_PATH)) {
        return $env:STATA_PATH
    }

    $variants = @("StataMP-64.exe", "StataSE-64.exe", "StataBE-64.exe", "StataIC-64.exe",
                 "StataMP.exe", "StataSE.exe", "StataBE.exe", "StataIC.exe")

    for ($version = 50; $version -ge 13; $version--) {
        $searchPaths = @(
            "C:\Program Files\Stata$version\",
            "C:\Program Files (x86)\Stata$version\",
            "C:\Stata$version\",
            "C:\Program Files\StataNow$version\",
            "C:\Program Files (x86)\StataNow$version\",
            "C:\StataNow$version\"
        )

        foreach ($path in $searchPaths) {
            foreach ($variant in $variants) {
                $fullPath = Join-Path $path $variant
                if (Test-Path $fullPath) { return $fullPath }
            }
        }
    }

    foreach ($variant in $variants) {
        $fullPath = Join-Path "C:\Stata\" $variant
        if (Test-Path $fullPath) { return $fullPath }
    }

    return $null
}

function Detect-StataApp {
    $script:STATA_PATH = $env:STATA_PATH
    $script:STATA_EDITION = ""
    $script:EXECUTION_MODE = ""

    # Check environment variable override first
    if (-not [string]::IsNullOrEmpty($script:STATA_PATH)) {
        if (-not (Test-Path -Path $script:STATA_PATH)) {
            Write-ErrorMessage "STATA_PATH is set but not executable: $script:STATA_PATH"
            exit 1
        }

        # Extract edition from path
        if ($script:STATA_PATH -like "*stata-mp*" -or $script:STATA_PATH -like "*StataMP*") {
            $script:STATA_EDITION = "MP"
        } elseif ($script:STATA_PATH -like "*stata-se*" -or $script:STATA_PATH -like "*StataSE*") {
            $script:STATA_EDITION = "SE"
        } elseif ($script:STATA_PATH -like "*stata-ic*" -or $script:STATA_PATH -like "*StataIC*") {
            $script:STATA_EDITION = "IC"
        } elseif ($script:STATA_PATH -like "*stata-be*" -or $script:STATA_PATH -like "*StataBE*") {
            $script:STATA_EDITION = "BE"
        } else {
            $script:STATA_EDITION = "IC"  # Default assumption
        }
    } else {
        # Use comprehensive Stata detection
        $stataPath = Find-StataInstallation
        if ([string]::IsNullOrEmpty($stataPath)) {
            Write-ErrorMessage "No Stata installation found in common paths"
            Write-Host ""
            Write-Host "Set STATA_PATH environment variable:"
            Write-Host "  [System.Environment]::SetEnvironmentVariable('STATA_PATH', 'C:\path\to\stata.exe', 'User')"
            exit 1
        }

        $script:STATA_PATH = $stataPath

        # Extract edition from path
        if ($script:STATA_PATH -like "*stata-mp*" -or $script:STATA_PATH -like "*StataMP*") {
            $script:STATA_EDITION = "MP"
        } elseif ($script:STATA_PATH -like "*stata-se*" -or $script:STATA_PATH -like "*StataSE*") {
            $script:STATA_EDITION = "SE"
        } elseif ($script:STATA_PATH -like "*stata-ic*" -or $script:STATA_PATH -like "*StataIC*") {
            $script:STATA_EDITION = "IC"
        } elseif ($script:STATA_PATH -like "*stata-be*" -or $script:STATA_PATH -like "*StataBE*") {
            $script:STATA_EDITION = "BE"
        } else {
            $script:STATA_EDITION = "IC"  # Default assumption
        }
    }

    # Determine execution mode (allow override)
    if (-not [string]::IsNullOrEmpty($env:STATA_EXECUTION_MODE)) {
        $script:EXECUTION_MODE = $env:STATA_EXECUTION_MODE
    } else {
        switch ($script:STATA_EDITION) {
            "MP" { $script:EXECUTION_MODE = "console" }
            "SE" { $script:EXECUTION_MODE = "console" }
            default { $script:EXECUTION_MODE = "automation" }
        }
    }
}

# ============================================================================
# Virtual Environment Management
# ============================================================================

function Create-Venv {
    if (Test-Path -Path "$VENV_DIR\Scripts\python.exe") {
        # Force recreation if the existing venv is not using the preferred Python (3.11).
        $existingVenvVersion = $null
        try {
            $existingVenvVersion = & "$VENV_DIR\Scripts\python.exe" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
        } catch {
            $existingVenvVersion = $null
        }

        if ($existingVenvVersion -ne "$PREFERRED_PYTHON_MAJOR.$PREFERRED_PYTHON_MINOR") {
            Write-WarningMessage "Virtual environment exists but uses Python $existingVenvVersion (preferred: $PREFERRED_PYTHON_MAJOR.$PREFERRED_PYTHON_MINOR). Recreating venv..."
            try {
                Remove-Item -Recurse -Force "$VENV_DIR"
            } catch {
                Write-ErrorMessage "Failed to remove existing venv at ${VENV_DIR}: $($_.Exception.Message)"
                exit 2
            }
        } else {
            Write-InfoMessage "Virtual environment already exists at $VENV_DIR (Python $existingVenvVersion)"
            # Ensure pip exists even if venv already exists (Python 3.13 issue)
            if (-not (Test-Path -Path "$VENV_DIR\Scripts\pip.exe")) {
                Write-InfoMessage "pip not found in existing venv, bootstrapping..."
                try {
                    $ensurePipOutput = & "$VENV_DIR\Scripts\python.exe" -m ensurepip --upgrade 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-ErrorMessage "Failed to bootstrap pip: $ensurePipOutput"
                        Write-Host "Please delete the venv and try again: Remove-Item -Recurse -Force '$VENV_DIR'"
                        exit 2
                    }
                    Write-SuccessMessage "pip bootstrapped successfully"
                } catch {
                    Write-ErrorMessage "Failed to bootstrap pip: $_"
                    Write-Host "Please delete the venv and try again: Remove-Item -Recurse -Force '$VENV_DIR'"
                    exit 2
                }
            }
            return
        }
    }

    Write-InfoMessage "Creating virtual environment..."
    $venvParent = Split-Path -Path $VENV_DIR -Parent
    if (-not (Test-Path -Path $venvParent)) {
        New-Item -ItemType Directory -Path $venvParent -Force | Out-Null
    }

    try {
        # If we have the Python Launcher command string (e.g. "C:\Windows\py.exe -3.11"),
        # invoke it correctly (executable + args). This avoids PATH/AppExecutionAlias issues.
        if ($script:PYTHON_CMD -like "*\py.exe -3.11") {
            $pyExe = $script:PYTHON_CMD -replace " -3\.11$", ""
            & $pyExe -3.11 -m venv $VENV_DIR
        } else {
            & $script:PYTHON_CMD -m venv $VENV_DIR
        }

        # Verify venv creation succeeded
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -Path "$VENV_DIR\Scripts\python.exe")) {
            Write-ErrorMessage "Failed to create virtual environment at $VENV_DIR"
            exit 2
        }

        Write-SuccessMessage "Created virtual environment at $VENV_DIR"

        # Ensure pip is available (Python 3.13 sometimes doesn't include it)
        if (-not (Test-Path -Path "$VENV_DIR\Scripts\pip.exe")) {
            Write-InfoMessage "Bootstrapping pip..."
            try {
                $ensurePipOutput = & "$VENV_DIR\Scripts\python.exe" -m ensurepip --upgrade 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-ErrorMessage "Failed to bootstrap pip: $ensurePipOutput"
                    Write-Host "Venv creation failed. Please try deleting and recreating."
                    exit 2
                }
                Write-SuccessMessage "pip bootstrapped successfully"
            } catch {
                Write-ErrorMessage "Failed to bootstrap pip: $_"
                exit 2
            }
        }
    } catch {
        Write-ErrorMessage "Failed to create virtual environment: $_"
        exit 2
    }
}

function Install-Packages {
    Write-InfoMessage "Installing packages..."

    # Verify pip exists
    if (-not (Test-Path -Path "$VENV_DIR\Scripts\pip.exe")) {
        Write-ErrorMessage "pip.exe not found at $VENV_DIR\Scripts\pip.exe"
        Write-Host "This can happen with Python 3.13. Please delete the venv and try again:"
        Write-Host "  Remove-Item -Recurse -Force '$VENV_DIR'"
        exit 2
    }

    # Upgrade pip first (use python -m pip to avoid self-upgrade issues on Windows)
    Write-InfoMessage "Upgrading pip..."
    $pipUpgradeOutput = & "$VENV_DIR\Scripts\python.exe" -m pip install --upgrade pip 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMessage "Failed to upgrade pip"
        Write-Host $pipUpgradeOutput
        exit 2
    }
    Write-SuccessMessage "pip upgraded successfully"

    # Check Python version to determine installation strategy
    $pyVersion = & "$VENV_DIR\Scripts\python.exe" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
    $pyMajor = [int]$pyVersion.Split('.')[0]
    $pyMinor = [int]$pyVersion.Split('.')[1]

    if ($pyMajor -eq 3 -and $pyMinor -ge 11) {
        # Python 3.11+: stata_kernel's dependency pins are very old (e.g., ipykernel<5, packaging<18)
        # and can force pip into backtracking and/or native builds on Windows/ARM64 (e.g. pywinpty).
        #
        # Strategy: install stata_kernel WITHOUT dependencies, then install a modern, minimal set
        # of Jupyter/runtime deps explicitly (including a Zed-compatible ipykernel pin).
        Write-InfoMessage "Installing stata_kernel (without dependencies) for Python $pyVersion..."
        $stataKernelOutput = & "$VENV_DIR\Scripts\python.exe" -m pip install --upgrade --no-deps stata_kernel 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorMessage "Failed to install stata_kernel"
            Write-Host $stataKernelOutput
            exit 3
        } else {
            Write-SuccessMessage "Installed stata_kernel"
        }

        # Install runtime deps that stata_kernel imports, plus minimal Jupyter components.
        # Avoid the full `jupyter` meta-package (notebook/jupyterlab) to prevent pulling in pywinpty.
        #
        # IMPORTANT: stata_kernel tries to copy a CodeMirror mode file into the `notebook` package at
        # runtime (see StataKernel.__init__). Installing `notebook` on Windows can pull in `pywinpty`
        # and trigger native builds (NuGet/Rust) that frequently fail on Windows/ARM64.
        #
        # Strategy: do NOT install `notebook`; instead, patch stata_kernel in the venv to skip the
        # `files('notebook')...` copy on Windows.
        Write-InfoMessage "Installing pinned minimal Jupyter/runtime dependencies (Python $pyVersion)..."
        $depsOutput = & "$VENV_DIR\Scripts\python.exe" -m pip install --upgrade `
            "ipykernel==$IPYKERNEL_VERSION" `
            jupyter-core `
            jupyter-client `
            traitlets `
            tornado `
            pyzmq `
            pillow `
            pexpect `
            numpy `
            pandas `
            matplotlib `
            packaging `
            pywin32 `
            fake-useragent `
            beautifulsoup4 `
            nbclient `
            nbformat 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorMessage "Failed to install pinned minimal Jupyter/runtime dependencies"
            Write-Host $depsOutput
            exit 3
        } else {
            Write-SuccessMessage "Installed pinned minimal Jupyter/runtime dependencies"

            # Patch stata_kernel to avoid importing `notebook` at runtime on Windows.
            # stata_kernel's StataKernel.__init__ copies:
            #   files('stata_kernel')/... -> files('notebook')/static/components/codemirror/mode/stata/stata.js
            # which hard-requires the `notebook` package. We skip that copy on Windows to avoid the
            # notebook/pywinpty dependency chain.
            Write-InfoMessage "Patching stata_kernel to avoid notebook/pywinpty dependency on Windows..."
            try {
                # Locate site-packages in a venv reliably.
                # `site.getsitepackages()` can vary across platforms and virtualenv implementations,
                # so prefer an explicit query from Python.
                $sitePackages = & "$VENV_DIR\Scripts\python.exe" -c "import site; print(site.getsitepackages()[0])" 2>$null
                if (-not $sitePackages) {
                    Write-ErrorMessage "Failed to locate site-packages for venv"
                    exit 3
                }

                # On Windows venvs this should typically be:
                #   $VENV_DIR\Lib\site-packages
                # But verify and fall back if needed.
                if (-not (Test-Path -Path $sitePackages)) {
                    $fallbackSitePackages = Join-Path $VENV_DIR "Lib\site-packages"
                    if (Test-Path -Path $fallbackSitePackages) {
                        $sitePackages = $fallbackSitePackages
                    }
                }

                $kernelPy = Join-Path $sitePackages "stata_kernel\kernel.py"
                if (-not (Test-Path -Path $kernelPy)) {
                    # Final fallback: ask Python for the module file location
                    $kernelPy = & "$VENV_DIR\Scripts\python.exe" -c "import stata_kernel.kernel as k; import os; print(os.path.abspath(k.__file__))" 2>$null
                }

                if (-not $kernelPy -or -not (Test-Path -Path $kernelPy)) {
                    Write-ErrorMessage "stata_kernel kernel.py not found at: $kernelPy"
                    exit 3
                }

                $kernelContent = Get-Content -Path $kernelPy -Raw

                # Only patch if the notebook copy target exists and hasn't been patched yet.
                if ($kernelContent -match "files\\('notebook'\\)" -and -not ($kernelContent -match "SIGHT_ZED_PATCH_SKIP_NOTEBOOK")) {
                    # 1) Replace the notebook destination Path(...) entry in to_paths with a dummy Path().
                    $patternToPath = "Path\\(\\s*files\\('notebook'\\)\\s*\\.joinpath\\(\\s*'static/components/codemirror/mode/stata/stata\\.js'\\s*\\)\\s*\\)"
                    $patched = $kernelContent -replace $patternToPath, "Path()  # SIGHT_ZED_PATCH_SKIP_NOTEBOOK"

                    # 2) Skip copy attempts when to_path is the dummy Path().
                    $patternFor = "for from_path, to_path in zip\\(from_paths, to_paths\\):"
                    $replacementFor = @"
for from_path, to_path in zip(from_paths, to_paths):
            # SIGHT_ZED_PATCH_SKIP_NOTEBOOK: skip notebook codemirror copy target
            try:
                if not getattr(to_path, "name", None):
                    continue
            except Exception:
                continue
"@
                    $patched = $patched -replace $patternFor, $replacementFor

                    $patched | Out-File -FilePath $kernelPy -Encoding utf8
                    Write-SuccessMessage "Patched stata_kernel to skip notebook CodeMirror copy"
                } else {
                    Write-InfoMessage "stata_kernel patch not needed (already patched or notebook reference not present)"
                }
            } catch {
                Write-ErrorMessage "Failed to patch stata_kernel: $($_.Exception.Message)"
                exit 3
            }
        }
    } else {
        # Python 3.10 and below: normal installation is generally fine.
        # Still avoid the `jupyter` meta-package to reduce risk of native builds on Windows.
        Write-InfoMessage "Installing stata_kernel and minimal Jupyter components (this may take a minute)..."
        $installOutput = & "$VENV_DIR\Scripts\python.exe" -m pip install --upgrade stata_kernel jupyter-core jupyter-client 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorMessage "Failed to install stata_kernel and minimal Jupyter components"
            Write-Host $installOutput
            exit 2
        }
        Write-SuccessMessage "Installed stata_kernel and minimal Jupyter components"

        # Pin ipykernel to a Zed-compatible version (avoid ipykernel 7.x issues on Windows)
        Write-InfoMessage "Installing ipykernel==$IPYKERNEL_VERSION for Zed compatibility..."
        $ipykernelOutput = & "$VENV_DIR\Scripts\python.exe" -m pip install --upgrade "ipykernel==$IPYKERNEL_VERSION" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-WarningMessage "Failed to install pinned ipykernel, but continuing..."
            Write-Host $ipykernelOutput
        } else {
            Write-SuccessMessage "Installed ipykernel==$IPYKERNEL_VERSION"
        }
    }
}

# ============================================================================
# Configuration Management
# ============================================================================

function Get-ConfigTemplate {
    @"
# stata_kernel configuration file
# Documentation: https://kylebarron.dev/stata_kernel/using_stata_kernel/configuration/

[stata_kernel]

# stata_path: Full path to your Stata executable
stata_path = STATA_PATH_PLACEHOLDER

# execution_mode: How stata_kernel communicates with Stata (Windows only)
# Values: console (MP/SE), automation (IC/BE)
execution_mode = EXECUTION_MODE_PLACEHOLDER

# cache_directory: Directory for temporary log files and graphs
# cache_directory = ~/.stata_kernel_cache

# graph_format: Format for exported graphs (svg, png, eps)
# graph_format = svg

# graph_scale: Scale factor for graph dimensions
# graph_scale = 1.0

# graph_width: Width of graphs in pixels
# graph_width = 600

# graph_height: Height of graphs in pixels
# graph_height = 400

# autocomplete_closing_symbol: Include closing symbol in autocompletions
# autocomplete_closing_symbol = False

# user_graph_keywords: Additional commands that generate graphs
# user_graph_keywords =
"@
}

function Write-Config {
    if (-not (Test-Path -Path $CONFIG_FILE)) {
        # Create new config from template
        $configContent = Get-ConfigTemplate
        $configContent = $configContent -replace "STATA_PATH_PLACEHOLDER", $script:STATA_PATH
        $configContent = $configContent -replace "EXECUTION_MODE_PLACEHOLDER", $script:EXECUTION_MODE
        $configContent | Out-File -FilePath $CONFIG_FILE -Encoding utf8
        (Get-Item $CONFIG_FILE).Attributes = "Normal"
        Write-SuccessMessage "Created configuration at $CONFIG_FILE"
    } else {
        # Update existing config - preserve user settings
        $configContent = Get-Content -Path $CONFIG_FILE -Raw
        $configContent = $configContent -replace "stata_path\s*=.*", "stata_path = $($script:STATA_PATH)"
        $configContent = $configContent -replace "execution_mode\s*=.*", "execution_mode = $($script:EXECUTION_MODE)"
        $configContent | Out-File -FilePath $CONFIG_FILE -Encoding utf8
        Write-SuccessMessage "Updated configuration at $CONFIG_FILE"
    }
}

# ============================================================================
# Kernel Registration
# ============================================================================

function Register-Kernel {
    Write-InfoMessage "Registering kernel with Jupyter (deterministic kernelspec written into %APPDATA% for Zed discovery)..."
    try {
        # Deterministic install location:
        #   %APPDATA%\jupyter\kernels\stata
        $forcedKernelDir = Join-Path (Join-Path $KERNEL_INSTALL_PREFIX "jupyter\kernels") "stata"

        if (-not (Test-Path -Path (Split-Path -Path $forcedKernelDir -Parent))) {
            New-Item -ItemType Directory -Path (Split-Path -Path $forcedKernelDir -Parent) -Force | Out-Null
        }

        if (Test-Path -Path $forcedKernelDir) {
            Remove-Item -Path $forcedKernelDir -Recurse -Force
        }

        New-Item -ItemType Directory -Path $forcedKernelDir -Force | Out-Null

        # Write wrapper script that launches stata_kernel via ipykernel.
        # IMPORTANT: Do not name this file `stata_kernel.py` — that can shadow the real `stata_kernel`
        # package on sys.path and cause circular import errors.
        $wrapperScript = Join-Path $forcedKernelDir "sight_stata_kernel_wrapper.py"
        @'
#!/usr/bin/env python3
"""
Deterministic wrapper kernel for stata_kernel (Windows-friendly).

Why this exists:
- `stata_kernel.install` has produced incomplete kernelspecs on some Windows setups.
- `stata_kernel` also hard-requires the `notebook` package at runtime by calling:
    importlib.resources.files("notebook").joinpath("static/components/codemirror/mode/stata/stata.js")
  Installing `notebook` on Windows can pull in `pywinpty` and trigger native builds (NuGet/Rust),
  which frequently fail on Windows/ARM64.

What we do instead:
- Monkey-patch `importlib.resources.files` so that requests for the `notebook` package resolve
  to a small, local stub directory. This keeps `stata_kernel` happy without needing `notebook`.
"""

import importlib
import importlib.resources as resources
from pathlib import Path

from ipykernel.kernelapp import IPKernelApp


def _ensure_notebook_stub_dir() -> Path:
    """
    Create a minimal directory structure that matches what stata_kernel expects inside `notebook`:
      static/components/codemirror/mode/stata/
    """
    # Place stub next to this wrapper for determinism.
    root = Path(__file__).resolve().parent / "_notebook_stub"
    target_dir = root / "static" / "components" / "codemirror" / "mode" / "stata"
    target_dir.mkdir(parents=True, exist_ok=True)
    return root


_original_files = resources.files


def _patched_files(package):
    # Handle both string module names and module objects.
    name = package if isinstance(package, str) else getattr(package, "__name__", "")
    if name == "notebook":
        return _ensure_notebook_stub_dir()
    return _original_files(package)


# Patch only within this kernel process.
resources.files = _patched_files


kernel_mod = importlib.import_module("stata_kernel.kernel")
IPKernelApp.launch_instance(kernel_class=kernel_mod.StataKernel)
'@ | Out-File -FilePath $wrapperScript -Encoding utf8

        # Create kernel.json
        $kernelJson = @{
            argv = @("$VENV_DIR\Scripts\python.exe", "$wrapperScript", "-f", "{connection_file}")
            display_name = "Stata"
            language = "stata"
        } | ConvertTo-Json -Depth 4

        $kernelJsonPath = Join-Path $forcedKernelDir "kernel.json"
        $kernelJson | Out-File -FilePath $kernelJsonPath -Encoding utf8

        if (-not (Test-Path -Path $kernelJsonPath)) {
            Write-ErrorMessage "Failed to write kernel spec at $kernelJsonPath"
            exit 3
        }

        $script:KERNEL_DIR = $forcedKernelDir
        Write-SuccessMessage "Registered stata kernel into: $forcedKernelDir"
    } catch {
        Write-ErrorMessage "Failed to register kernel: $($_.Exception.Message)"
        exit 3
    }
}

function Verify-KernelSpec {
    # Dynamically find where the stata kernel was installed
    try {
        $kernelListOutputRaw = & "$VENV_DIR\Scripts\jupyter.exe" kernelspec list --json 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorMessage "Failed to list Jupyter kernels"
            Write-Host $kernelListOutputRaw
            exit 3
        }

        # Some Python/Jupyter setups emit debug warnings to stderr before JSON.
        # Since we capture 2>&1, strip any leading non-JSON lines and parse from the first '{'.
        $kernelListOutput = ($kernelListOutputRaw | Out-String)
        $jsonStart = $kernelListOutput.IndexOf('{')
        if ($jsonStart -lt 0) {
            Write-ErrorMessage "Failed to parse Jupyter kernelspec JSON (no JSON object found)"
            Write-Host $kernelListOutputRaw
            exit 3
        }
        $kernelListJson = $kernelListOutput.Substring($jsonStart)

        $kernelList = $kernelListJson | ConvertFrom-Json
        if (-not $kernelList.kernelspecs.stata) {
            Write-ErrorMessage "Stata kernel not found in Jupyter kernelspec list"
            exit 3
        }

        $script:KERNEL_DIR = $kernelList.kernelspecs.stata.resource_dir
        Write-InfoMessage "Found stata kernel at: $script:KERNEL_DIR"

        # Verify kernel.json exists
        if (-not (Test-Path -Path "$script:KERNEL_DIR\kernel.json")) {
            Write-ErrorMessage "Kernel spec not found at $script:KERNEL_DIR\kernel.json"
            exit 3
        }

        # Verify language is "stata" (lowercase) for Zed matching
        $kernelJson = Get-Content -Path "$script:KERNEL_DIR\kernel.json" -Raw
        if (-not ($kernelJson -match '"language"\s*:\s*"stata"')) {
            Write-WarningMessage "Kernel language may not be set correctly for Zed (expected `"stata`")"
        }

        Write-SuccessMessage "Verified kernel spec at $script:KERNEL_DIR"
    } catch {
        Write-ErrorMessage "Failed to verify kernel spec: $($_.Exception.Message)"
        exit 3
    }
}

# ============================================================================
# Workspace Kernel (changes to workspace root before starting Stata)
# ============================================================================

function Get-WorkspaceKernelScript {
    @'
#!/usr/bin/env python3
"""
Wrapper kernel for stata_kernel that changes to workspace root before starting (Windows-friendly).

Why this exists:
- Zed launches kernels in the file's directory. For many projects, Stata code expects to run from the
  workspace root (e.g., relative paths like "data/foo.dta").
- `stata_kernel` also hard-requires the `notebook` package at runtime by calling:
    importlib.resources.files("notebook").joinpath("static/components/codemirror/mode/stata/stata.js")
  Installing `notebook` on Windows can pull in `pywinpty` and trigger native builds (NuGet/Rust),
  which frequently fail on Windows/ARM64.

What we do instead:
- Find the workspace root and `chdir` to it before starting the kernel.
- Monkey-patch `importlib.resources.files` so that requests for the `notebook` package resolve to a
  small, local stub directory. This keeps `stata_kernel` happy without needing `notebook`.
"""

import os
import importlib
import importlib.resources as resources
from pathlib import Path

from ipykernel.kernelapp import IPKernelApp


def _ensure_notebook_stub_dir() -> Path:
    """
    Create a minimal directory structure that matches what stata_kernel expects inside `notebook`:
      static/components/codemirror/mode/stata/
    """
    # Place stub next to this wrapper for determinism.
    root = Path(__file__).resolve().parent / "_notebook_stub"
    target_dir = root / "static" / "components" / "codemirror" / "mode" / "stata"
    target_dir.mkdir(parents=True, exist_ok=True)
    return root


_original_files = resources.files


def _patched_files(package):
    # Handle both string module names and module objects.
    name = package if isinstance(package, str) else getattr(package, "__name__", "")
    if name == "notebook":
        return _ensure_notebook_stub_dir()
    return _original_files(package)


# Patch only within this kernel process.
resources.files = _patched_files


def find_workspace_root(start_path: Path) -> Path:
    """
    Walk up from start_path looking for workspace markers.
    Returns the workspace root, or start_path if no marker found.
    """
    markers = ['.git', '.stata-project', '.project']

    current = start_path.resolve()

    # Walk up to filesystem root (current == current.parent at root)
    while current != current.parent:
        for marker in markers:
            if (current / marker).exists():
                return current
        current = current.parent

    # No marker found, return original (resolved)
    return start_path.resolve()


def main():
    # Get the current working directory (set by Zed to file's directory)
    cwd = Path.cwd()

    # Find workspace root
    workspace_root = find_workspace_root(cwd)

    # Change to workspace root
    os.chdir(workspace_root)

    # Import and run stata_kernel without shadowing issues
    kernel_mod = importlib.import_module("stata_kernel.kernel")
    IPKernelApp.launch_instance(kernel_class=kernel_mod.StataKernel)


if __name__ == '__main__':
    main()
'@
}

function Install-WorkspaceKernel {
    Write-InfoMessage "Installing workspace kernel..."

    # Install the workspace kernel into the same forced prefix location used for the main kernel,
    # so Zed can discover both consistently.
    $script:WORKSPACE_KERNEL_DIR = Join-Path (Join-Path $KERNEL_INSTALL_PREFIX "jupyter\\kernels") "stata_workspace"

    # Create workspace kernel directory
    if (-not (Test-Path -Path $script:WORKSPACE_KERNEL_DIR)) {
        New-Item -ItemType Directory -Path $script:WORKSPACE_KERNEL_DIR -Force | Out-Null
    }

    # Write the wrapper script
    $wrapperScript = "$script:WORKSPACE_KERNEL_DIR\stata_workspace_kernel.py"
    Get-WorkspaceKernelScript | Out-File -FilePath $wrapperScript -Encoding utf8

    # Create kernel.json
    $kernelJson = @{
        argv = @("$VENV_DIR\Scripts\python.exe", "$wrapperScript", "-f", "{connection_file}")
        display_name = "Stata (Workspace)"
        language = "stata"
    } | ConvertTo-Json -Depth 4

    $kernelJson | Out-File -FilePath "$script:WORKSPACE_KERNEL_DIR\kernel.json" -Encoding utf8

    Write-SuccessMessage "Installed workspace kernel at $script:WORKSPACE_KERNEL_DIR"
}

function Uninstall-WorkspaceKernel {
    # Dynamically find workspace kernel location
    try {
        $jupyterPath = "$VENV_DIR\Scripts\jupyter.exe"
        if (-not (Test-Path -Path $jupyterPath)) {
            Write-InfoMessage "Workspace kernel not found (jupyter not installed)"
            return
        }

        $kernelListOutputRaw = & $jupyterPath kernelspec list --json 2>&1
        if ($LASTEXITCODE -eq 0) {
            $kernelListOutput = ($kernelListOutputRaw | Out-String)
            $jsonStart = $kernelListOutput.IndexOf('{')
            if ($jsonStart -lt 0) { return }
            $kernelList = $kernelListOutput.Substring($jsonStart) | ConvertFrom-Json
            if ($kernelList.kernelspecs.stata_workspace) {
                $workspaceKernelPath = $kernelList.kernelspecs.stata_workspace.resource_dir
                if (Test-Path -Path $workspaceKernelPath) {
                    Remove-Item -Path $workspaceKernelPath -Recurse -Force
                    Write-SuccessMessage "Removed workspace kernel"
                    return
                }
            }
        }
    } catch {
        # Ignore errors during uninstall
    }

    Write-InfoMessage "Workspace kernel not found (already removed)"
}

# ============================================================================
# PATH Management
# ============================================================================

function Add-VenvToPath {
    $venvScripts = "$VENV_DIR\Scripts"

    # Get current user PATH
    $currentPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')

    # Check if already in PATH
    $pathEntries = $currentPath -split ';' | Where-Object { $_ -ne '' }
    $normalized = $pathEntries | ForEach-Object { $_.TrimEnd('\') }
    $targetNormalized = $venvScripts.TrimEnd('\')

    if ($normalized -contains $targetNormalized) {
        Write-InfoMessage "Jupyter venv is already in PATH"
        return
    }

    # Add to PATH
    Write-InfoMessage "Adding Jupyter venv to user PATH for Zed integration..."
    $newPath = if ($currentPath) { "$currentPath;$venvScripts" } else { $venvScripts }
    [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-SuccessMessage "Added to PATH: $venvScripts"
}

function Remove-VenvFromPath {
    $venvScripts = "$VENV_DIR\Scripts"

    # Get current user PATH
    $currentPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')

    # Check if in PATH
    $pathEntries = $currentPath -split ';' | Where-Object { $_ -ne '' }
    $normalized = $pathEntries | ForEach-Object { $_.TrimEnd('\') }
    $targetNormalized = $venvScripts.TrimEnd('\')

    if ($normalized -notcontains $targetNormalized) {
        Write-InfoMessage "Jupyter venv not in PATH (already removed)"
        return
    }

    # Remove from PATH
    Write-InfoMessage "Removing Jupyter venv from user PATH..."
    $filteredEntries = $pathEntries | Where-Object {
        $_.TrimEnd('\') -ne $targetNormalized
    }
    $newPath = $filteredEntries -join ';'
    [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-SuccessMessage "Removed from PATH"
}

# ============================================================================
# Uninstallation
# ============================================================================

function Uninstall {
    param ([bool]$removeConfig)

    Write-InfoMessage "Uninstalling stata_kernel..."

    # Remove workspace kernel first (before removing venv)
    Uninstall-WorkspaceKernel

    # Remove from PATH
    Remove-VenvFromPath

    # Remove kernel spec - dynamically find it
    try {
        $jupyterPath = "$VENV_DIR\Scripts\jupyter.exe"
        if (Test-Path -Path $jupyterPath) {
            $kernelListOutputRaw = & $jupyterPath kernelspec list --json 2>&1
            if ($LASTEXITCODE -eq 0) {
                $kernelListOutput = ($kernelListOutputRaw | Out-String)
                $jsonStart = $kernelListOutput.IndexOf('{')
                if ($jsonStart -lt 0) {
                    Write-InfoMessage "Could not parse kernel list (no JSON found)"
                    return
                }
                $kernelList = $kernelListOutput.Substring($jsonStart) | ConvertFrom-Json
                if ($kernelList.kernelspecs.stata) {
                    $kernelPath = $kernelList.kernelspecs.stata.resource_dir
                    if (Test-Path -Path $kernelPath) {
                        Remove-Item -Path $kernelPath -Recurse -Force
                        Write-SuccessMessage "Removed kernel spec"
                    } else {
                        Write-InfoMessage "Kernel spec not found (already removed)"
                    }
                } else {
                    Write-InfoMessage "Kernel spec not found (already removed)"
                }
            } else {
                Write-InfoMessage "Could not list kernels (venv may be broken)"
            }
        } else {
            Write-InfoMessage "Kernel spec not found (already removed)"
        }
    } catch {
        Write-InfoMessage "Could not remove kernel spec (may already be removed)"
    }

    # Remove virtual environment
    if (Test-Path -Path $VENV_DIR) {
        Remove-Item -Path $VENV_DIR -Recurse -Force
        Write-SuccessMessage "Removed virtual environment"
    } else {
        Write-InfoMessage "Virtual environment not found (already removed)"
    }

    # Optionally remove config
    if ($removeConfig) {
        if (Test-Path -Path $CONFIG_FILE) {
            Remove-Item -Path $CONFIG_FILE -Force
            Write-SuccessMessage "Removed configuration file"
        } else {
            Write-InfoMessage "Configuration file not found (already removed)"
        }
    } else {
        Write-InfoMessage "Configuration preserved at $CONFIG_FILE (use --remove-config to delete)"
    }

    Write-SuccessMessage "Uninstallation complete"
}

# ============================================================================
# Main
# ============================================================================

function Print-Summary {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host "  stata_kernel installed successfully!"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host ""
    Write-Host "  Stata Edition:    $($script:STATA_EDITION)"
    Write-Host "  Execution Mode:   $($script:EXECUTION_MODE)"
    Write-Host "  Configuration:    $CONFIG_FILE"
    Write-Host ""
    Write-Host ""
    Write-Host "  Two kernels are installed:"
    Write-Host ""
    Write-Host "    Stata             Starts in the file's directory"
    Write-Host "                      Use for scripts with paths relative to the script"
    Write-Host ""
    Write-Host "    Stata (Workspace) Starts in the workspace root (looks for .git)"
    Write-Host "                      Use for scripts with paths relative to the project"
    Write-Host ""
    Write-Host "  The workspace kernel walks up from the file's directory looking for"
    Write-Host "  .git, .stata-project, or .project markers to find the project root."
    Write-Host ""
    Write-Host "  Usage in Zed:"
    Write-Host "    1. Open a .do file"
    Write-Host "    2. Select 'stata' or 'stata_workspace' as the kernel"
    Write-Host "    3. Click the 🔄 icon in the editor toolbar to execute code"
    Write-Host "       or use Control+Shift+Enter keyboard shortcut"
    Write-Host ""
    Write-Host "  To set a default kernel, add to %APPDATA%\zed\settings.json:"
    Write-Host ""
    Write-Host "    `"{"
    Write-Host "      `""jupyter`"": {"
    Write-Host "        `""kernel_selections`"": {"
    Write-Host "          `""stata`"": `""stata_workspace`"""
    Write-Host "        }"
    Write-Host "      }"
    Write-Host "    }"
    Write-Host ""
    Write-Host "  IMPORTANT: You must restart Zed for changes to take effect."
    Write-Host ""
    Write-Host "  The Jupyter venv has been added to your user PATH so Zed can"
    Write-Host "  discover the kernels. After restarting Zed, clicking the 🔄 icon"
    Write-Host "  should show 'Stata' and 'Stata (Workspace)' as kernel options."
    Write-Host ""
}

function Main {
    if ($uninstall) {
        Uninstall -removeConfig $removeConfig
        exit 0
    }

    Write-Host "Installing stata_kernel for Zed Jupyter integration..."
    Write-Host ""

    Check-Prerequisites
    Detect-StataApp

    Write-InfoMessage "Detected Stata $($script:STATA_EDITION) at $($script:STATA_PATH)"

    Create-Venv
    Install-Packages
    Write-Config
    Register-Kernel
    Verify-KernelSpec
    Install-WorkspaceKernel
    Add-VenvToPath

    Print-Summary
}

# Entry point
Main
