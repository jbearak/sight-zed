# verify-jupyter.ps1
# Verifies that Jupyter is properly installed and accessible for Zed integration

$ErrorActionPreference = 'Continue'

function Write-Section {
    param([string]$title)
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
}

function Write-Check {
    param([string]$message, [bool]$success)
    if ($success) {
        Write-Host "  ✓ $message" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $message" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Jupyter Integration Verification for Zed" -ForegroundColor Yellow
Write-Host ""

# Check 1: User PATH
Write-Section "User PATH Configuration"
$userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
$venvPath = "$env:LOCALAPPDATA\stata_kernel\venv\Scripts"
$inPath = $userPath -split ';' | Where-Object { $_.TrimEnd('\') -eq $venvPath.TrimEnd('\') }

if ($inPath) {
    Write-Check "Jupyter venv is in user PATH" $true
    Write-Host "    Path: $venvPath" -ForegroundColor Gray
} else {
    Write-Check "Jupyter venv is NOT in user PATH" $false
    Write-Host "    Expected: $venvPath" -ForegroundColor Gray
    Write-Host "    Run: .\add-jupyter-to-path.ps1" -ForegroundColor Yellow
}

# Check 2: Current Process PATH
Write-Section "Current Process PATH"
$currentPath = $env:PATH
$inCurrentPath = $currentPath -split ';' | Where-Object { $_.TrimEnd('\') -eq $venvPath.TrimEnd('\') }

if ($inCurrentPath) {
    Write-Check "Jupyter venv is in current process PATH" $true
} else {
    Write-Check "Jupyter venv is NOT in current process PATH" $false
    Write-Host "    This is normal if you just added it to PATH." -ForegroundColor Gray
    Write-Host "    You must close all terminal/PowerShell windows and open a new one." -ForegroundColor Yellow
}

# Check 3: Jupyter executable
Write-Section "Jupyter Executable"
try {
    $jupyterCmd = Get-Command jupyter -ErrorAction Stop
    Write-Check "Jupyter executable found" $true
    Write-Host "    Location: $($jupyterCmd.Source)" -ForegroundColor Gray

    # Get version
    $version = & jupyter --version 2>&1 | Select-String "jupyter_core" | Out-String
    if ($version) {
        Write-Host "    Version: $($version.Trim())" -ForegroundColor Gray
    }
} catch {
    Write-Check "Jupyter executable NOT found" $false
    Write-Host "    Jupyter is not accessible from PATH" -ForegroundColor Gray
}

# Check 4: Kernels
Write-Section "Installed Jupyter Kernels"
try {
    $kernelJson = & jupyter kernelspec list --json 2>$null
    $kernelList = $kernelJson | ConvertFrom-Json

    if ($kernelList.kernelspecs) {
        $kernelCount = ($kernelList.kernelspecs | Get-Member -MemberType NoteProperty).Count
        Write-Check "Found $kernelCount kernel(s)" $true

        # Check for stata kernel
        if ($kernelList.kernelspecs.stata) {
            Write-Check "stata kernel registered" $true
            Write-Host "    Location: $($kernelList.kernelspecs.stata.resource_dir)" -ForegroundColor Gray

            # Verify language field
            $kernelJson = Get-Content "$($kernelList.kernelspecs.stata.resource_dir)\kernel.json" | ConvertFrom-Json
            if ($kernelJson.language -eq "stata") {
                Write-Check "stata kernel language field is correct" $true
            } else {
                Write-Check "stata kernel language field is INCORRECT: $($kernelJson.language)" $false
            }
        } else {
            Write-Check "stata kernel NOT registered" $false
        }

        # Check for stata_workspace kernel
        if ($kernelList.kernelspecs.stata_workspace) {
            Write-Check "stata_workspace kernel registered" $true
            Write-Host "    Location: $($kernelList.kernelspecs.stata_workspace.resource_dir)" -ForegroundColor Gray
        } else {
            Write-Check "stata_workspace kernel NOT registered" $false
        }

        # List all kernels
        Write-Host ""
        Write-Host "  All kernels:" -ForegroundColor Gray
        foreach ($kernel in ($kernelList.kernelspecs | Get-Member -MemberType NoteProperty)) {
            $name = $kernel.Name
            $spec = $kernelList.kernelspecs.$name
            Write-Host "    - $name (language: $($spec.spec.language))" -ForegroundColor Gray
        }
    }
} catch {
    Write-Check "Failed to list kernels" $false
    Write-Host "    Error: $_" -ForegroundColor Gray
}

# Check 5: Zed extension
Write-Section "Zed Extension Configuration"
$extPath = "$env:LOCALAPPDATA\Zed\extensions\installed\sight"
if (Test-Path $extPath) {
    Write-Check "Sight extension is installed" $true
    Write-Host "    Location: $extPath" -ForegroundColor Gray

    # Check config.toml
    $configPath = "$extPath\languages\stata\config.toml"
    if (Test-Path $configPath) {
        $config = Get-Content $configPath -Raw
        if ($config -match 'jupyter_kernels\s*=\s*\[.*stata.*\]') {
            Write-Check "config.toml has jupyter_kernels declaration" $true
            $match = $config | Select-String 'jupyter_kernels\s*=\s*(\[.*\])'
            if ($match) {
                Write-Host "    Value: $($match.Matches[0].Groups[1].Value)" -ForegroundColor Gray
            }
        } else {
            Write-Check "config.toml is MISSING jupyter_kernels declaration" $false
            Write-Host "    The extension needs to be rebuilt with jupyter_kernels support" -ForegroundColor Yellow
        }
    } else {
        Write-Check "config.toml NOT found" $false
    }
} else {
    Write-Check "Sight extension NOT installed" $false
}

# Check 6: Zed process
Write-Section "Zed Process Status"
$zedProcess = Get-Process -Name "Zed" -ErrorAction SilentlyContinue
if ($zedProcess) {
    Write-Check "Zed is currently running (PID: $($zedProcess.Id))" $true
    Write-Host ""
    Write-Host "  IMPORTANT: If you just updated the PATH, you must:" -ForegroundColor Yellow
    Write-Host "    1. Completely close Zed (not just restart)" -ForegroundColor Yellow
    Write-Host "    2. Close this PowerShell window" -ForegroundColor Yellow
    Write-Host "    3. Open a NEW PowerShell window" -ForegroundColor Yellow
    Write-Host "    4. Launch Zed from the new window" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Applications inherit PATH from their parent process." -ForegroundColor Gray
    Write-Host "  PATH changes only take effect in new processes." -ForegroundColor Gray
} else {
    Write-Check "Zed is not running" $true
}

# Summary
Write-Section "Summary"
$allGood = $true

if (-not $inPath) {
    Write-Host "  ⚠ Jupyter venv not in user PATH - run .\add-jupyter-to-path.ps1" -ForegroundColor Yellow
    $allGood = $false
}

if (-not $inCurrentPath) {
    Write-Host "  ⚠ Current shell doesn't see updated PATH - restart PowerShell" -ForegroundColor Yellow
    $allGood = $false
}

try {
    $null = Get-Command jupyter -ErrorAction Stop
} catch {
    Write-Host "  ⚠ Jupyter not accessible - check installation" -ForegroundColor Yellow
    $allGood = $false
}

if ($zedProcess) {
    Write-Host "  ⚠ Zed is running - must be restarted from a NEW shell for PATH changes" -ForegroundColor Yellow
    $allGood = $false
}

if ($allGood) {
    Write-Host ""
    Write-Host "  ✓ Everything looks good!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor Cyan
    Write-Host "    1. Open a .do file in Zed" -ForegroundColor Gray
    Write-Host "    2. Open View → Toggle REPL (or press Ctrl+Shift+P and search 'REPL')" -ForegroundColor Gray
    Write-Host "    3. Select 'Stata' or 'Stata (Workspace)' kernel" -ForegroundColor Gray
} else {
    Write-Host ""
    Write-Host "  ⚠ Issues detected - see above for details" -ForegroundColor Yellow
}

Write-Host ""
