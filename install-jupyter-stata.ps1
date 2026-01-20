# install-jupyter-stata.ps1 - Install stata_kernel for Zed Jupyter integration on Windows
#
# Usage:
#   .\install-jupyter-stata.ps1                    Install stata_kernel
#   .\install-jupyter-stata.ps1 --uninstall        Remove installation
#   .\install-jupyter-stata.ps1 --uninstall --remove-config  Remove including config

param (
    [switch]$uninstall,
    [switch]$removeConfig
)

# ============================================================================
# Configuration Constants
# ============================================================================
$VENV_DIR = "$env:LOCALAPPDATA\stata_kernel\venv"
$CONFIG_FILE = "$env:USERPROFILE\.stata_kernel.conf"
$KERNEL_DIR = "$env:LOCALAPPDATA\jupyter\kernels\stata"
$WORKSPACE_KERNEL_DIR = "$env:LOCALAPPDATA\jupyter\kernels\stata_workspace"

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

    # First try to find existing Python installation
    try {
        $pythonPath = (Get-Command python -ErrorAction Stop).Source
        Write-InfoMessage "Found Python at: $pythonPath"

        # Test if this Python actually works
        try {
            $testOutput = & $pythonPath --version 2>&1
            if ($testOutput -match "Python was not found") {
                Write-WarningMessage "Found Microsoft Store Python stub, will attempt real installation"
                $pythonPath = Install-PythonAutomatically
                if (-not $pythonPath) {
                    Write-ErrorMessage "Python installation failed"
                    exit 1
                }
            } elseif ($testOutput -match "Python \d+\.\d+") {
                Write-InfoMessage "Python executable works: $testOutput"
            } else {
                Write-WarningMessage "Python executable test failed, will attempt real installation"
                $pythonPath = Install-PythonAutomatically
                if (-not $pythonPath) {
                    Write-ErrorMessage "Python installation failed"
                    exit 1
                }
            }
        } catch {
            Write-WarningMessage "Python executable test failed: $_"
            $pythonPath = Install-PythonAutomatically
            if (-not $pythonPath) {
                Write-ErrorMessage "Python installation failed"
                exit 1
            }
        }
    } catch {
        try {
            $pythonPath = (Get-Command python3 -ErrorAction Stop).Source
            Write-InfoMessage "Found Python3 at: $pythonPath"

            # Test if this Python actually works
            try {
                $testOutput = & $pythonPath --version 2>&1
                if ($testOutput -match "Python was not found") {
                    Write-WarningMessage "Found Microsoft Store Python stub, will attempt real installation"
                    $pythonPath = Install-PythonAutomatically
                    if (-not $pythonPath) {
                        Write-ErrorMessage "Python installation failed"
                        exit 1
                    }
                } elseif ($testOutput -match "Python \d+\.\d+") {
                    Write-InfoMessage "Python executable works: $testOutput"
                } else {
                    Write-WarningMessage "Python executable test failed, will attempt real installation"
                    $pythonPath = Install-PythonAutomatically
                    if (-not $pythonPath) {
                        Write-ErrorMessage "Python installation failed"
                        exit 1
                    }
                }
            } catch {
                Write-WarningMessage "Python executable test failed: $_"
                $pythonPath = Install-PythonAutomatically
                if (-not $pythonPath) {
                    Write-ErrorMessage "Python installation failed"
                    exit 1
                }
            }
        } catch {
            Write-InfoMessage "Python not found, attempting automatic installation..."
            $pythonPath = Install-PythonAutomatically
            if (-not $pythonPath) {
                Write-ErrorMessage "Python installation failed"
                Write-Host ""
                Write-Host "Please install Python manually from: https://www.python.org/downloads/"
                Write-Host "Make sure to check 'Add Python to PATH' during installation."
                Write-Host ""
                Write-Host "After installing Python, run this script again."
                exit 1
            }
        }
    }

    # Now check if venv module is available
    if (-not $pythonPath) {
        Write-ErrorMessage "No valid Python installation found"
        exit 1
    }

    try {
        $venvCheck = & $pythonPath -c "import venv; print('venv available')"
        if (-not ($venvCheck -like "*venv available*")) {
            Write-ErrorMessage "python3 venv module is required but not available"
            exit 1
        }
        Write-InfoMessage "venv module is available"
    } catch {
        Write-ErrorMessage "python3 venv module is required but not available: $_"
        exit 1
    }

    # Determine Python version
    $pyVersion = & $pythonPath -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
    $pyMajor = [int]$pyVersion.Split('.')[0]
    $pyMinor = [int]$pyVersion.Split('.')[1]
    Write-InfoMessage "Python version: $pyVersion"

    # stata_kernel works best with Python 3.9-3.11
    if ($pyMajor -eq 3 -and $pyMinor -ge 12) {
        Write-WarningMessage "Python $pyVersion detected. stata_kernel may need package upgrades for compatibility."
        Write-InfoMessage "The installer will handle this automatically."
    }

    return $pythonPath
}

function Install-PythonAutomatically {
    Write-Host "Attempting to install Python automatically..."
    Write-Host ""

    # Try to install Python using winget if available
    try {
        Write-InfoMessage "Checking for winget (Windows Package Manager)..."
        $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetPath) {
            Write-InfoMessage "Installing Python using winget..."
            try {
                # Test winget first to make sure it's working
                $wingetTest = & winget --version 2>&1
                if (-not ($wingetTest -match "\d+\.\d+")) {
                    Write-WarningMessage "winget not working properly: $wingetTest"
                    return $null
                }

                # Try multiple Python package names
                $pythonPackages = @(
                    "Python.Python.3",
                    "Python.Python",
                    "Python.3",
                    "python"
                )

                foreach ($pkg in $pythonPackages) {
                    Write-InfoMessage "Attempting to install Python package: $pkg"
                    $installResult = & winget install --accept-package-agreements --accept-source-agreements $pkg 2>&1

                    if ($installResult -match "Successfully installed") {
                        Write-SuccessMessage "Python installed successfully via winget ($pkg)"
                        break
                    } elseif ($installResult -match "No package found") {
                        Write-InfoMessage "Package $pkg not found, trying next..."
                        continue
                    } else {
                        Write-WarningMessage "winget installation failed for $pkg"
                        continue
                    }
                }

                if (-not ($installResult -match "Successfully installed")) {
                    Write-WarningMessage "All winget package installations failed"
                    return $null
                }

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
                        Write-WarningMessage "Could not find Python after winget installation"
                        return $null
                    }
                }
            } catch {
                Write-WarningMessage "winget installation failed: $_"
            }
        } else {
            Write-InfoMessage "winget not available"
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
        Write-InfoMessage "Virtual environment already exists at $VENV_DIR"
        return
    }

    Write-InfoMessage "Creating virtual environment..."
    $venvParent = Split-Path -Path $VENV_DIR -Parent
    if (-not (Test-Path -Path $venvParent)) {
        New-Item -ItemType Directory -Path $venvParent -Force | Out-Null
    }

    try {
        & $script:PYTHON_CMD -m venv $VENV_DIR
        Write-SuccessMessage "Created virtual environment at $VENV_DIR"
    } catch {
        Write-ErrorMessage "Failed to create virtual environment"
        exit 2
    }
}

function Install-Packages {
    Write-InfoMessage "Installing packages..."
    try {
        & "$VENV_DIR\Scripts\pip.exe" install --upgrade pip | Out-Null
        & "$VENV_DIR\Scripts\pip.exe" install --upgrade stata_kernel jupyter | Out-Null
        Write-SuccessMessage "Installed stata_kernel and jupyter"

        # Check Python version for ipykernel upgrade
        $pyVersion = & "$VENV_DIR\Scripts\python.exe" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
        $pyMajor = [int]$pyVersion.Split('.')[0]
        $pyMinor = [int]$pyVersion.Split('.')[1]

        if ($pyMajor -eq 3 -and $pyMinor -ge 12) {
            Write-InfoMessage "Upgrading ipykernel for Python $pyVersion compatibility..."
            & "$VENV_DIR\Scripts\pip.exe" install --upgrade ipykernel | Out-Null
            Write-SuccessMessage "Upgraded ipykernel for Python $pyVersion"
        }
    } catch {
        Write-ErrorMessage "Failed to install packages"
        exit 2
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
        $configContent = $configContent -replace "stata_path[[:space:]]*=.*", "stata_path = $($script:STATA_PATH)"
        $configContent = $configContent -replace "execution_mode[[:space:]]*=.*", "execution_mode = $($script:EXECUTION_MODE)"
        $configContent | Out-File -FilePath $CONFIG_FILE -Encoding utf8
        Write-SuccessMessage "Updated configuration at $CONFIG_FILE"
    }
}

# ============================================================================
# Kernel Registration
# ============================================================================

function Register-Kernel {
    Write-InfoMessage "Registering kernel with Jupyter..."
    try {
        & "$VENV_DIR\Scripts\python.exe" -m stata_kernel.install | Out-Null
        Write-SuccessMessage "Registered stata kernel"
    } catch {
        Write-ErrorMessage "Failed to register kernel"
        exit 3
    }
}

function Verify-KernelSpec {
    if (-not (Test-Path -Path "$KERNEL_DIR\kernel.json")) {
        Write-ErrorMessage "Kernel spec not found at $KERNEL_DIR\kernel.json"
        exit 3
    }

    # Verify language is "stata" (lowercase) for Zed matching
    $kernelJson = Get-Content -Path "$KERNEL_DIR\kernel.json" -Raw
    if (-not ($kernelJson -match '"language"[[:space:]]*:[[:space:]]*"stata"')) {
        Write-WarningMessage "Kernel language may not be set correctly for Zed"
    }

    Write-SuccessMessage "Verified kernel spec at $KERNEL_DIR"
}

# ============================================================================
# Workspace Kernel (changes to workspace root before starting Stata)
# ============================================================================

function Get-WorkspaceKernelScript {
    @'
#!/usr/bin/env python3
"""
Wrapper kernel for stata_kernel that changes to workspace root before starting.

This kernel finds the workspace root by looking for marker files (.git, .stata-project)
and changes to that directory before delegating to stata_kernel.
"""

import os
import sys
from pathlib import Path

def find_workspace_root(start_path: Path) -> Path:
    """
    Walk up from start_path looking for workspace markers.
    Returns the workspace root, or start_path if no marker found.
    """
    markers = ['.git', '.stata-project', '.project']

    current = start_path.resolve()

    # Don't go above home directory
    home = Path.home().resolve()

    while current != current.parent:
        # Stop if we've gone above home
        try:
            current.relative_to(home)
        except ValueError:
            break

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

    # Now import and run stata_kernel
    from stata_kernel import kernel
    from ipykernel.kernelapp import IPKernelApp

    IPKernelApp.launch_instance(kernel_class=kernel.StataKernel)

if __name__ == '__main__':
    main()
'@
}

function Install-WorkspaceKernel {
    Write-InfoMessage "Installing workspace kernel..."

    # Create kernel directory
    if (-not (Test-Path -Path $WORKSPACE_KERNEL_DIR)) {
        New-Item -ItemType Directory -Path $WORKSPACE_KERNEL_DIR -Force | Out-Null
    }

    # Write the wrapper script
    $wrapperScript = "$WORKSPACE_KERNEL_DIR\stata_workspace_kernel.py"
    Get-WorkspaceKernelScript | Out-File -FilePath $wrapperScript -Encoding utf8

    # Create kernel.json
    $kernelJson = @{
        argv = @("$VENV_DIR\Scripts\python.exe", "$wrapperScript", "-f", "{connection_file}")
        display_name = "Stata (Workspace)"
        language = "stata"
    } | ConvertTo-Json -Depth 4

    $kernelJson | Out-File -FilePath "$WORKSPACE_KERNEL_DIR\kernel.json" -Encoding utf8

    Write-SuccessMessage "Installed workspace kernel at $WORKSPACE_KERNEL_DIR"
}

function Uninstall-WorkspaceKernel {
    if (Test-Path -Path $WORKSPACE_KERNEL_DIR) {
        Remove-Item -Path $WORKSPACE_KERNEL_DIR -Recurse -Force
        Write-SuccessMessage "Removed workspace kernel"
    } else {
        Write-InfoMessage "Workspace kernel not found (already removed)"
    }
}

# ============================================================================
# Uninstallation
# ============================================================================

function Uninstall {
    param ([bool]$removeConfig)

    Write-InfoMessage "Uninstalling stata_kernel..."

    # Remove virtual environment
    if (Test-Path -Path $VENV_DIR) {
        Remove-Item -Path $VENV_DIR -Recurse -Force
        Write-SuccessMessage "Removed virtual environment"
    } else {
        Write-InfoMessage "Virtual environment not found (already removed)"
    }

    # Remove kernel spec
    if (Test-Path -Path $KERNEL_DIR) {
        Remove-Item -Path $KERNEL_DIR -Recurse -Force
        Write-SuccessMessage "Removed kernel spec"
    } else {
        Write-InfoMessage "Kernel spec not found (already removed)"
    }

    # Remove workspace kernel
    Uninstall-WorkspaceKernel

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
    Write-Host "    2. Open the REPL panel (View → Toggle REPL)"
    Write-Host "    3. Select 'Stata' or 'Stata (Workspace)' as the kernel"
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

    Print-Summary
}

# Entry point
Main
