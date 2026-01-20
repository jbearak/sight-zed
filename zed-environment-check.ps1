# zed-environment-check.ps1
# Diagnostic script to check what environment Zed sees when spawning processes
# Run this from within Zed's terminal or via a Zed task to see what Zed can access

$ErrorActionPreference = 'Continue'

function Write-Header {
    param([string]$title)
    Write-Host ""
    Write-Host "================================================================================================" -ForegroundColor Cyan
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host "================================================================================================" -ForegroundColor Cyan
}

function Write-Check {
    param([string]$message, [bool]$success)
    if ($success) {
        Write-Host "  [OK] $message" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $message" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "ZED ENVIRONMENT DIAGNOSTIC" -ForegroundColor Yellow
Write-Host "Checking what Zed can see when spawning processes..." -ForegroundColor Gray
Write-Host ""

# Check 1: PATH environment variable
Write-Header "PATH Environment Variable"
$paths = $env:PATH -split ';'
$hasJupyterPath = $false
$jupyterVenvPath = "$env:LOCALAPPDATA\stata_kernel\venv\Scripts"

Write-Host "  PATH contains $($paths.Count) entries" -ForegroundColor Gray
Write-Host ""
Write-Host "  Checking for Jupyter venv in PATH:" -ForegroundColor Gray

foreach ($path in $paths) {
    if ($path.TrimEnd('\') -eq $jupyterVenvPath.TrimEnd('\')) {
        Write-Check "Found Jupyter venv: $path" $true
        $hasJupyterPath = $true
    }
}

if (-not $hasJupyterPath) {
    Write-Check "Jupyter venv NOT in PATH" $false
    Write-Host "    Expected: $jupyterVenvPath" -ForegroundColor Yellow
}

# Check 2: Jupyter executable
Write-Header "Jupyter Executable"
try {
    $jupyterCmd = Get-Command jupyter -ErrorAction Stop
    Write-Check "Found jupyter command" $true
    Write-Host "    Location: $($jupyterCmd.Source)" -ForegroundColor Gray
    Write-Host "    Type: $($jupyterCmd.CommandType)" -ForegroundColor Gray
} catch {
    Write-Check "jupyter command NOT found" $false
    Write-Host "    Error: $_" -ForegroundColor Yellow
}

# Check 3: Try running jupyter --version
Write-Header "Jupyter Version"
try {
    $version = & jupyter --version 2>&1
    Write-Check "Successfully ran 'jupyter --version'" $true
    Write-Host ""
    Write-Host "    Output:" -ForegroundColor Gray
    $version | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
} catch {
    Write-Check "Failed to run 'jupyter --version'" $false
    Write-Host "    Error: $_" -ForegroundColor Yellow
}

# Check 4: Try running jupyter kernelspec list
Write-Header "Jupyter Kernelspec List"
try {
    $kernelList = & jupyter kernelspec list 2>&1
    Write-Check "Successfully ran 'jupyter kernelspec list'" $true
    Write-Host ""
    Write-Host "    Output:" -ForegroundColor Gray
    $kernelList | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
} catch {
    Write-Check "Failed to run 'jupyter kernelspec list'" $false
    Write-Host "    Error: $_" -ForegroundColor Yellow
}

# Check 5: Try running jupyter kernelspec list --json
Write-Header "Jupyter Kernelspec List (JSON)"
try {
    $kernelJson = & jupyter kernelspec list --json 2>&1 | ConvertFrom-Json
    Write-Check "Successfully parsed kernel list JSON" $true
    Write-Host ""
    Write-Host "    Found kernels:" -ForegroundColor Gray
    foreach ($kernel in ($kernelJson.kernelspecs | Get-Member -MemberType NoteProperty)) {
        $name = $kernel.Name
        $spec = $kernelJson.kernelspecs.$name
        Write-Host "      - $name" -ForegroundColor Cyan
        Write-Host "        Language: $($spec.spec.language)" -ForegroundColor Gray
        Write-Host "        Display: $($spec.spec.display_name)" -ForegroundColor Gray
        Write-Host "        Location: $($spec.resource_dir)" -ForegroundColor Gray
    }
} catch {
    Write-Check "Failed to get kernel list as JSON" $false
    Write-Host "    Error: $_" -ForegroundColor Yellow
}

# Check 6: Python
Write-Header "Python"
try {
    $pythonCmd = Get-Command python -ErrorAction Stop
    Write-Check "Found python command" $true
    Write-Host "    Location: $($pythonCmd.Source)" -ForegroundColor Gray

    try {
        $pyVersion = & python --version 2>&1
        Write-Host "    Version: $pyVersion" -ForegroundColor Gray
    } catch {
        Write-Host "    Version: Could not determine" -ForegroundColor Yellow
    }
} catch {
    Write-Check "python command NOT found" $false
}

# Check 7: Process environment
Write-Header "Process Information"
Write-Host "  Process ID: $PID" -ForegroundColor Gray
Write-Host "  Parent Process: $((Get-Process -Id $PID).Parent.ProcessName)" -ForegroundColor Gray -ErrorAction SilentlyContinue
Write-Host "  PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
Write-Host "  Execution Policy: $(Get-ExecutionPolicy -Scope CurrentUser)" -ForegroundColor Gray

# Check 8: User environment variables
Write-Header "User PATH (from Registry)"
$userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
$userPaths = $userPath -split ';'
$foundInRegistry = $false

Write-Host "  User PATH contains $($userPaths.Count) entries" -ForegroundColor Gray
foreach ($path in $userPaths) {
    if ($path.TrimEnd('\') -eq $jupyterVenvPath.TrimEnd('\')) {
        Write-Check "Jupyter venv is in user PATH registry" $true
        Write-Host "    Path: $path" -ForegroundColor Gray
        $foundInRegistry = $true
    }
}

if (-not $foundInRegistry) {
    Write-Check "Jupyter venv NOT in user PATH registry" $false
}

# Summary
Write-Header "Summary"
Write-Host ""

if ($hasJupyterPath) {
    Write-Host "  [OK] Jupyter venv is in current process PATH" -ForegroundColor Green
} else {
    Write-Host "  [!!] Jupyter venv is NOT in current process PATH" -ForegroundColor Red
    Write-Host "       Zed cannot find jupyter!" -ForegroundColor Yellow
}

if ($foundInRegistry) {
    Write-Host "  [OK] Jupyter venv is in user PATH registry" -ForegroundColor Green
} else {
    Write-Host "  [!!] Jupyter venv is NOT in user PATH registry" -ForegroundColor Red
    Write-Host "       Run: .\add-jupyter-to-path.ps1" -ForegroundColor Yellow
}

try {
    $null = Get-Command jupyter -ErrorAction Stop
    Write-Host "  [OK] jupyter command is accessible" -ForegroundColor Green
} catch {
    Write-Host "  [!!] jupyter command is NOT accessible" -ForegroundColor Red
    Write-Host "       Zed will not be able to discover kernels!" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "To use this diagnostic in Zed:" -ForegroundColor Cyan
Write-Host "  1. Open Zed's terminal (View > Terminal)" -ForegroundColor Gray
Write-Host "  2. Run: pwsh -File zed-environment-check.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "If jupyter is not found when run from Zed's terminal:" -ForegroundColor Cyan
Write-Host "  - Zed needs to be completely restarted" -ForegroundColor Gray
Write-Host "  - Launch Zed from a fresh shell after PATH changes" -ForegroundColor Gray
Write-Host "  - On Windows, you may need to log out and log back in" -ForegroundColor Gray
Write-Host ""
