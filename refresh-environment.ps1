# refresh-environment.ps1
# Broadcasts environment variable changes to all windows so taskbar/Start Menu apps
# can pick up PATH changes without logging out and back in

param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Write-Info {
    param([string]$message)
    if (-not $Quiet) {
        Write-Host $message
    }
}

function Write-Success {
    param([string]$message)
    if (-not $Quiet) {
        Write-Host "✓ $message" -ForegroundColor Green
    }
}

function Invoke-EnvironmentRefresh {
    if (-not ("Win32.NativeMethods" -as [Type])) {
        # Define the Windows API function to broadcast environment changes
        Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd,
    uint Msg,
    UIntPtr wParam,
    string lParam,
    uint fuFlags,
    uint uTimeout,
    out UIntPtr lpdwResult
);
"@
    }

    $HWND_BROADCAST = [IntPtr]0xffff
    $WM_SETTINGCHANGE = 0x1a
    $result = [UIntPtr]::Zero

    # Broadcast the message to all top-level windows
    Write-Info "Broadcasting environment variable changes to all windows..."

    $returnValue = [Win32.NativeMethods]::SendMessageTimeout(
        $HWND_BROADCAST,
        $WM_SETTINGCHANGE,
        [UIntPtr]::Zero,
        "Environment",
        2, # SMTO_ABORTIFHUNG
        5000,
        [ref]$result
    )

    if ($returnValue -ne [IntPtr]::Zero) {
        Write-Success "Environment variables refreshed"
        Write-Info ""
        Write-Info "Applications launched from the taskbar/Start Menu will now see:"
        Write-Info "  - Updated PATH variable"
        Write-Info "  - Other environment variable changes"
        Write-Info ""
        Write-Info "Note: Applications that are ALREADY RUNNING won't see the changes."
        Write-Info "You must close and relaunch them."
        Write-Info ""
        if (-not $Quiet) {
            Write-Host "Next steps:" -ForegroundColor Cyan
            Write-Host "  1. Close Zed completely (if it's running)" -ForegroundColor Gray
            Write-Host "  2. Launch Zed from the taskbar or Start Menu" -ForegroundColor Gray
            Write-Host "  3. Open a .do file" -ForegroundColor Gray
            Write-Host "  4. Open View → Toggle REPL" -ForegroundColor Gray
        }
        return $true
    } else {
        Write-Host "Failed to broadcast environment changes" -ForegroundColor Red
        Write-Host "You may need to log out and log back in for changes to take effect." -ForegroundColor Yellow
        return $false
    }
}

# Main execution
Write-Info ""
Write-Info "Windows Environment Variable Refresh"
Write-Info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Info ""

$success = Invoke-EnvironmentRefresh

if (-not $success) {
    exit 1
}

Write-Info ""
