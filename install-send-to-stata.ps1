param(
    [switch]$Uninstall,
    [switch]$RegisterAutomation,
    [switch]$SkipAutomationCheck
)

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

    # Select the correct binary based on architecture
    $arch = Get-HostArch
    $exeName = if ($arch -eq 'Arm64') { "send-to-stata-arm64.exe" } else { "send-to-stata-x64.exe" }
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
        Write-Host "Downloaded send-to-stata.exe from GitHub"
    }
}

function Install-Tasks {
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

    $newTasks = @(
        @{
            label = "Stata: Send Statement"
            command = "& `"$exePath`" -Statement -ReturnFocus -File `"`$ZED_FILE`" -Row `$ZED_ROW"
            use_new_terminal = $false
            allow_concurrent_runs = $true
            reveal = "never"
            hide = "on_success"
        },
        @{
            label = "Stata: Send File"
            command = "& `"$exePath`" -FileMode -ReturnFocus -File `"`$ZED_FILE`""
            use_new_terminal = $false
            allow_concurrent_runs = $true
            reveal = "never"
            hide = "on_success"
        },
        @{
            label = "Stata: Include Statement"
            command = "& `"$exePath`" -Statement -Include -ReturnFocus -File `"`$ZED_FILE`" -Row `$ZED_ROW"
            use_new_terminal = $false
            allow_concurrent_runs = $true
            reveal = "never"
            hide = "on_success"
        },
        @{
            label = "Stata: Include File"
            command = "& `"$exePath`" -FileMode -Include -ReturnFocus -File `"`$ZED_FILE`""
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

    for ($version = 19; $version -ge 13; $version--) {
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
        $tasks = Get-Content $tasksPath | ConvertFrom-Json
        $tasks = $tasks | Where-Object { !$_.label.StartsWith("Stata:") }
        $tasks | ConvertTo-Json -Depth 10 | Out-File $tasksPath -Encoding UTF8
        Write-Host "Removed Stata tasks"
    }

    $keymapPath = "$env:APPDATA\Zed\keymap.json"
    if (Test-Path $keymapPath) {
        $keybindings = Get-Content $keymapPath | ConvertFrom-Json
        $keybindings = $keybindings | Where-Object {
            !($_.context -eq "Editor && extension == do")
        }
        $keybindings | ConvertTo-Json -Depth 10 | Out-File $keymapPath -Encoding UTF8
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

Install-Tasks
Install-Keybindings

Write-Host "Send-to-Stata installed successfully!"
Write-Host "Keyboard shortcuts are now available in .do files:"
Write-Host "  Ctrl+Enter: Send statement to Stata"
Write-Host "  Shift+Ctrl+Enter: Send file to Stata"
Write-Host "  Alt+Ctrl+Enter: Include statement"
Write-Host "  Alt+Shift+Ctrl+Enter: Include file"
Write-Host "  Shift+Enter: Paste selection to terminal"
Write-Host "  Alt+Enter: Paste current line to terminal"
