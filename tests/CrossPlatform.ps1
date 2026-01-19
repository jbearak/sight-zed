$script:IsWindowsPlatform = $env:OS -eq "Windows_NT"
$script:IsMacOSPlatform = $IsMacOS -or (uname 2>$null) -eq "Darwin"

function Skip-WindowsOnly {
    if (-not $script:IsWindowsPlatform) {
        Set-ItResult -Skipped -Because "Windows-only test"
    }
}

function Skip-MacOSOnly {
    if (-not $script:IsMacOSPlatform) {
        Set-ItResult -Skipped -Because "macOS-only test"
    }
}