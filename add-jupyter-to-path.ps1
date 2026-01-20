# add-jupyter-to-path.ps1
# Adds the stata_kernel venv Scripts directory to user PATH for Zed Jupyter integration

param(
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

$VENV_SCRIPTS = "$env:LOCALAPPDATA\stata_kernel\venv\Scripts"

function Write-Success {
    param([string]$message)
    Write-Host "✓ $message" -ForegroundColor Green
}

function Write-Info {
    param([string]$message)
    Write-Host $message
}

function Write-Error {
    param([string]$message)
    Write-Host "Error: $message" -ForegroundColor Red
}

function Add-ToPath {
    # Check if venv exists
    if (-not (Test-Path $VENV_SCRIPTS)) {
        Write-Error "Jupyter venv not found at: $VENV_SCRIPTS"
        Write-Info ""
        Write-Info "Please run install-jupyter-stata.ps1 first to create the virtual environment."
        exit 1
    }

    # Get current user PATH
    $currentPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')

    # Check if already in PATH
    $pathEntries = $currentPath -split ';' | Where-Object { $_ -ne '' }
    $normalized = $pathEntries | ForEach-Object { $_.TrimEnd('\') }
    $targetNormalized = $VENV_SCRIPTS.TrimEnd('\')

    if ($normalized -contains $targetNormalized) {
        Write-Success "Jupyter venv Scripts directory is already in PATH"
        Write-Info "Path: $VENV_SCRIPTS"
        exit 0
    }

    # Add to PATH
    Write-Info "Adding to user PATH: $VENV_SCRIPTS"
    $newPath = "$currentPath;$VENV_SCRIPTS"
    [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')

    Write-Success "Successfully added to PATH"
    Write-Info ""
    Write-Info "IMPORTANT: You must restart Zed for the change to take effect."
    Write-Info ""
    Write-Info "To verify, after restarting Zed, open a terminal and run:"
    Write-Info "  jupyter --version"
}

function Remove-FromPath {
    # Get current user PATH
    $currentPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')

    # Check if in PATH
    $pathEntries = $currentPath -split ';' | Where-Object { $_ -ne '' }
    $normalized = $pathEntries | ForEach-Object { $_.TrimEnd('\') }
    $targetNormalized = $VENV_SCRIPTS.TrimEnd('\')

    if ($normalized -notcontains $targetNormalized) {
        Write-Info "Jupyter venv Scripts directory is not in PATH"
        exit 0
    }

    # Remove from PATH
    Write-Info "Removing from user PATH: $VENV_SCRIPTS"
    $filteredEntries = $pathEntries | Where-Object {
        $_.TrimEnd('\') -ne $targetNormalized
    }
    $newPath = $filteredEntries -join ';'
    [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')

    Write-Success "Successfully removed from PATH"
    Write-Info ""
    Write-Info "You may need to restart applications for the change to take effect."
}

# Main
if ($Remove) {
    Remove-FromPath
} else {
    Add-ToPath
}
