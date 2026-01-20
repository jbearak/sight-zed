param(
    [switch]$Uninstall,
    [switch]$RegisterAutomation,
    [switch]$SkipAutomationCheck,
    [string]$ReturnFocus = "",
    [string]$ActivateStata = ""
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
            if ($Uninstall) { $scriptArgs += '-Uninstall' }
            if ($RegisterAutomation) { $scriptArgs += '-RegisterAutomation' }
            if ($SkipAutomationCheck) { $scriptArgs += '-SkipAutomationCheck' }
            if ($ReturnFocus) { $scriptArgs += '-ReturnFocus'; $scriptArgs += $ReturnFocus }
            if ($ActivateStata) { $scriptArgs += '-ActivateStata'; $scriptArgs += $ActivateStata }
            & pwsh -File $scriptPath @scriptArgs
            exit $LASTEXITCODE
        } else {
            # Piped via irm | iex - re-fetch and invoke as scriptblock with args
            $scriptArgs = @()
            if ($Uninstall) { $scriptArgs += '-Uninstall' }
            if ($RegisterAutomation) { $scriptArgs += '-RegisterAutomation' }
            if ($SkipAutomationCheck) { $scriptArgs += '-SkipAutomationCheck' }
            if ($ReturnFocus) { $scriptArgs += '-ReturnFocus'; $scriptArgs += $ReturnFocus }
            if ($ActivateStata) { $scriptArgs += '-ActivateStata'; $scriptArgs += $ActivateStata }
            $url = "https://raw.githubusercontent.com/jbearak/sight-zed/main/install-send-to-stata.ps1"
            $argsStr = ($scriptArgs | ForEach-Object { "'$_'" }) -join ','
            & pwsh -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((irm '$url'))) $argsStr"
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
    Write-Host "  pwsh -c `"irm https://raw.githubusercontent.com/jbearak/sight-zed/main/install-send-to-stata.ps1 | iex`""
    exit 1
}

# Expected SHA-256 checksums for send-to-stata executables
# Update these when rebuilding the executables (run update-checksum.ps1)
$expectedChecksumArm64 = "7476b2f0e9e767b7b72ccecdcc7605588463e89f4b204f283bc8f5a64dc06def"
$expectedChecksumX64 = "bbdf2d24fc6652f1acb2867336ad625497abd9cf05b1cc3ed4293b81643f002f"

function Get-HostArch {
    # Detect host architecture for selecting the correct binary
    try {
        $arch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
        if ($arch) { return $arch.ToString() }
    } catch { }
    $pa = $env:PROCESSOR_ARCHITECTURE
    if ($pa -match 'ARM64') { return 'Arm64' }
    if ([Environment]::Is64BitProcess) { return 'X64' }
    return 'X86'
}

function Install-Executable {
    $stataDir = "$env:APPDATA\Zed\stata"
    if (!(Test-Path $stataDir)) {
        New-Item -ItemType Directory -Path $stataDir -Force | Out-Null
    }

    # Select the correct binary and checksum based on architecture
    $arch = Get-HostArch
    if ($arch -eq 'Arm64') {
        $exeName = "send-to-stata-arm64.exe"
        $expectedChecksum = $expectedChecksumArm64
    } else {
        $exeName = "send-to-stata-x64.exe"
        $expectedChecksum = $expectedChecksumX64
    }
    $destExe = "$stataDir\send-to-stata.exe"

    # Try local file first (for development)
    if (Test-Path $exeName) {
        Copy-Item $exeName $destExe -Force
        Write-Host "Installed send-to-stata.exe from local file ($exeName)"
    } else {
        # Download from GitHub
        $githubRef = $env:SIGHT_GITHUB_REF
        if (!$githubRef) { $githubRef = "main" }

        $url = "https://github.com/jbearak/sight-zed/raw/$githubRef/$exeName"
        Write-Host "Downloading $exeName from GitHub..."
        Invoke-WebRequest -Uri $url -OutFile $destExe

        # Verify checksum (skip for custom refs used in testing)
        if ($githubRef -eq "main") {
            $actualChecksum = (Get-FileHash -Path $destExe -Algorithm SHA256).Hash.ToLower()
            if ($actualChecksum -ne $expectedChecksum.ToLower()) {
                Remove-Item $destExe -Force -ErrorAction SilentlyContinue
                throw "Checksum verification failed for $exeName`nExpected: $expectedChecksum`nActual:   $actualChecksum`nThis may indicate a corrupted download or CDN caching issue. Try again in a few minutes."
            }
            Write-Host "Checksum verified for $exeName"
        } else {
            Write-Host "Skipping checksum verification (custom SIGHT_GITHUB_REF: $githubRef)"
        }

        Write-Host "Downloaded send-to-stata.exe from GitHub"
    }
}

function Install-Tasks {
    param([bool]$UseActivateStata)

    $tasksPath = "$env:APPDATA\Zed\tasks.json"
    $tasks = @()
    if (Test-Path $tasksPath) {
        try {
            $raw = Get-Content $tasksPath -Raw
            $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
            if ($parsed) { $tasks = @($parsed) }
        } catch { $tasks = @() }
    }

    $tasks = $tasks | Where-Object { -not ($_.label) -or -not $_.label.StartsWith("Stata:") }

    # Native executable - Zed wraps commands in PowerShell, so we use & (call operator)
    # Zed expands $ZED_FILE and $ZED_ROW before passing to shell
    $exePath = "$env:APPDATA\Zed\stata\send-to-stata.exe"
    $activateStataArg = if ($UseActivateStata) { " -ActivateStata" } else { "" }

    $newTasks = @(
        @{
            label = "Stata: Send Statement"
            command = "& `"$exePath`" -Statement$activateStataArg -File `"`$ZED_FILE`" -Row `$ZED_ROW"
            use_new_terminal = $false
            allow_concurrent_runs = $true
            reveal = "never"
            hide = "on_success"
        },
        @{
            label = "Stata: Send File"
            command = "& `"$exePath`" -FileMode$activateStataArg -File `"`$ZED_FILE`""
            use_new_terminal = $false
            allow_concurrent_runs = $true
            reveal = "never"
            hide = "on_success"
        },
        @{
            label = "Stata: Include Statement"
            command = "& `"$exePath`" -Statement -Include$activateStataArg -File `"`$ZED_FILE`" -Row `$ZED_ROW"
            use_new_terminal = $false
            allow_concurrent_runs = $true
            reveal = "never"
            hide = "on_success"
        },
        @{
            label = "Stata: Include File"
            command = "& `"$exePath`" -FileMode -Include$activateStataArg -File `"`$ZED_FILE`""
            use_new_terminal = $false
            allow_concurrent_runs = $true
            reveal = "never"
            hide = "on_success"
        }
    )

    $tasks += $newTasks
    $json = ConvertTo-Json -InputObject $tasks -Depth 10 -Compress
    # Make it human-readable and avoid BOM
    $json = $json -replace '\\u0026','&' -replace '\\u003c','<' -replace '\\u003e','>' -replace '\\u0027',"'"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tasksPath, $json, $utf8NoBom)
}

function Install-Keybindings {
    $keymapPath = "$env:APPDATA\Zed\keymap.json"
    $existing = $null
    if (Test-Path $keymapPath) {
        try { $existing = Get-Content $keymapPath -Raw | ConvertFrom-Json } catch { $existing = $null }
    }

    # Normalize to an array
    $keybindings = @()
    if ($existing) {
        if ($existing -is [System.Collections.IEnumerable] -and -not ($existing -is [string])) {
            $keybindings = @($existing)
        } else {
            $keybindings = @($existing)
        }
    }

    # Remove any prior Stata block by context value (old or new form)
    $keybindings = $keybindings | Where-Object { -not ($_.PSObject.Properties.Name -contains 'context' -and ($_.context -eq "Editor && extension == 'do'" -or $_.context -eq "Editor && extension == do")) }

    $newBlock = @{
        context = "Editor && extension == do"
        bindings = @{
            "ctrl-enter" = @("action::Sequence", @("workspace::Save", @("task::Spawn", @{ task_name = "Stata: Send Statement" })))
            "shift-ctrl-enter" = @("action::Sequence", @("workspace::Save", @("task::Spawn", @{ task_name = "Stata: Send File" })))
            "alt-ctrl-enter" = @("action::Sequence", @("workspace::Save", @("task::Spawn", @{ task_name = "Stata: Include Statement" })))
            "alt-shift-ctrl-enter" = @("action::Sequence", @("workspace::Save", @("task::Spawn", @{ task_name = "Stata: Include File" })))
            # Use literal backtick (``) so it survives PowerShell parsing
            "shift-enter" = @("workspace::SendKeystrokes", "ctrl-c ctrl-`` ctrl-v enter")
            "alt-enter" = @("workspace::SendKeystrokes", "home shift-end ctrl-c ctrl-`` ctrl-v enter")
        }
    }

    $result = @()
    if ($keybindings) { $result += $keybindings }
    $result += $newBlock

    $json = ConvertTo-Json -InputObject $result -Depth 10 -Compress
    # Decode HTML-safe escapes that PowerShell adds so Zed sees human-readable context
    $json = $json -replace '\\u0026','&'
    $json = $json -replace '\\u003c','<'
    $json = $json -replace '\\u003e','>'
    $json = $json -replace '\\u0027',"'"
    # Write UTF-8 without BOM so Zed doesn't choke on BOM
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($keymapPath, $json, $utf8NoBom)
}

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

function Test-StataAutomationRegistered {
    try {
        $regPath = "HKEY_CLASSES_ROOT\stata.StataOLEApp\CLSID"
        $clsid = [Microsoft.Win32.Registry]::GetValue($regPath, "", $null)
        if ($clsid) {
            $serverPath = [Microsoft.Win32.Registry]::GetValue("HKEY_CLASSES_ROOT\CLSID\$clsid\LocalServer32", "", $null)
            # LocalServer32 may include arguments like "/Automation", strip them
            if ($serverPath) {
                $serverPath = ($serverPath -split ' /')[0].Trim('"')
            }
            return @{ IsRegistered = $true; RegisteredPath = $serverPath }
        }
    } catch {}
    return @{ IsRegistered = $false; RegisteredPath = $null }
}

function Register-StataAutomation {
    param([string]$StataPath)

    Write-Host "Registering Stata Automation type library..."
    Write-Host "This requires administrator privileges. A UAC prompt will appear."

    try {
        $process = Start-Process -FilePath $StataPath -ArgumentList "/Register" -Verb RunAs -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-Host "Stata Automation type library registered successfully." -ForegroundColor Green
            return $true
        } else {
            Write-Error "Registration failed with exit code: $($process.ExitCode)"
            Write-Host "Manual registration instructions:" -ForegroundColor Yellow
            Write-Host "1. Open PowerShell as Administrator"
            Write-Host "2. Run: & `"$StataPath`" /Register" -ForegroundColor Cyan
            return $false
        }
    } catch {
        if ($_.Exception.Message -match "canceled by the user") {
            Write-Warning "Registration canceled by user."
        } else {
            Write-Error "Registration failed: $_"
            Write-Host "Manual registration instructions:" -ForegroundColor Yellow
            Write-Host "1. Open PowerShell as Administrator"
            Write-Host "2. Run: & `"$StataPath`" /Register" -ForegroundColor Cyan
        }
        return $false
    }
}

function Invoke-AutomationRegistrationCheck {
    param(
        [string]$StataPath,
        [switch]$Force
    )

    if ($SkipAutomationCheck -and -not $Force) { return }

    $regStatus = Test-StataAutomationRegistered

    if ($Force -or -not $regStatus.IsRegistered) {
        if (-not $regStatus.IsRegistered) {
            Write-Host "We couldn't confirm whether Stata automation is registered. Proceeding to register it so Send-to-Stata works." -ForegroundColor Yellow
        } else {
            Write-Host "Force re-registration requested. Updating Stata automation registration..." -ForegroundColor Yellow
        }
        Write-Host "Windows may show a UAC elevation prompt from Stata during registration." -ForegroundColor Yellow
        Register-StataAutomation $StataPath | Out-Null
        return
    }

    if ($regStatus.RegisteredPath -and $regStatus.RegisteredPath -ne $StataPath) {
        Write-Host "Stata version mismatch detected." -ForegroundColor Yellow
        Write-Host "  Registered: $($regStatus.RegisteredPath)" -ForegroundColor Yellow
        Write-Host "  Detected:   $StataPath" -ForegroundColor Yellow
        Write-Host "Updating the registration to the detected installation..." -ForegroundColor Yellow
        Register-StataAutomation $StataPath | Out-Null
        return
    }

    Write-Host "Stata Automation type library is already registered."
}

function Uninstall-SendToStata {
    $stataDir = "$env:APPDATA\Zed\stata"
    if (Test-Path $stataDir) {
        Remove-Item $stataDir -Recurse -Force
        Write-Host "Removed Stata directory"
    }

    $tasksPath = "$env:APPDATA\Zed\tasks.json"
    if (Test-Path $tasksPath) {
        $tasks = Get-Content $tasksPath -Raw | ConvertFrom-Json
        $tasks = $tasks | Where-Object { -not $_.label -or -not $_.label.StartsWith("Stata:") }
        $json = ConvertTo-Json -InputObject $tasks -Depth 10 -Compress
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tasksPath, $json, $utf8NoBom)
        Write-Host "Removed Stata tasks"
    }

    $keymapPath = "$env:APPDATA\Zed\keymap.json"
    if (Test-Path $keymapPath) {
        $keybindings = Get-Content $keymapPath -Raw | ConvertFrom-Json
        $keybindings = $keybindings | Where-Object {
            -not $_.context -or $_.context -ne "Editor && extension == do"
        }
        $json = ConvertTo-Json -InputObject $keybindings -Depth 10 -Compress
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($keymapPath, $json, $utf8NoBom)
        Write-Host "Removed Stata keybindings"
    }
}

# Main execution
if ($Uninstall) {
    Uninstall-SendToStata
    Write-Host "Send-to-Stata uninstalled successfully"
    exit 0
}

Install-Executable

$stataPath = Find-StataInstallation
if ($stataPath) {
    Write-Host "Found Stata: $stataPath"
    Invoke-AutomationRegistrationCheck -StataPath $stataPath -Force:$RegisterAutomation
} else {
    Write-Host "Stata installation not found in standard locations"
}

# Determine ActivateStata setting
# New semantics:
# - Default is to stay in Zed (do NOT activate Stata)
# - If ActivateStata is true/yes/1 OR user answers "y", add -ActivateStata to task commands
# Backward compat:
# - ReturnFocus parameter is accepted but ignored (focus behavior is now controlled by -ActivateStata)
$useActivateStata = $false
if ($ActivateStata -eq "true" -or $ActivateStata -eq "yes" -or $ActivateStata -eq "1") {
    # Explicit true via parameter (for CI/CD)
    $useActivateStata = $true
} elseif ($ActivateStata -eq "false" -or $ActivateStata -eq "no" -or $ActivateStata -eq "0") {
    # Explicit false via parameter (for CI/CD)
    $useActivateStata = $false
} elseif (-not [string]::IsNullOrEmpty($ActivateStata)) {
    # Invalid value provided - fail fast for CI/non-interactive
    Write-Error "Invalid value for -ActivateStata: '$ActivateStata'. Accepted values: true, yes, 1, false, no, 0"
    exit 1
} elseif ($ReturnFocus) {
    # Deprecated param is now a no-op; keep it accepted so old scripts don't break
    Write-Host ""
    Write-Host "Note: -ReturnFocus is deprecated and is now a no-op. Focus behavior is controlled by -ActivateStata."
    $useActivateStata = $false
} else {
    # Interactive prompt (no parameter or empty string)
    Write-Host ""
    Write-Host "Focus behavior after sending code to Stata:"
    Write-Host "  [Y] Return focus to Zed (keep typing without switching windows)"
    Write-Host "  [N] Stay in Stata (ensures you see output, even if Zed is fullscreen)"
    Write-Host ""
    $response = Read-Host "Return focus to Zed after sending code to Stata? [Y/n]"
    $useActivateStata = $response -eq 'n' -or $response -eq 'N'
}

Install-Tasks -UseActivateStata $useActivateStata
Install-Keybindings

Write-Host "Send-to-Stata installed successfully!"
Write-Host "Keyboard shortcuts are now available in .do files:"
Write-Host "  Ctrl+Enter: Send statement to Stata"
Write-Host "  Shift+Ctrl+Enter: Send file to Stata"
Write-Host "  Alt+Ctrl+Enter: Include statement"
Write-Host "  Alt+Shift+Ctrl+Enter: Include file"
Write-Host "  Shift+Enter: Paste selection to terminal"
Write-Host "  Alt+Enter: Paste current line to terminal"
