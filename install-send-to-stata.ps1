param(
    [switch]$Uninstall,
    [switch]$RegisterAutomation,
    [switch]$SkipAutomationCheck
)

function Install-Script {
    $stataDir = "$env:APPDATA\Zed\stata"
    if (!(Test-Path $stataDir)) {
        New-Item -ItemType Directory -Path $stataDir -Force | Out-Null
    }

    $localScript = "send-to-stata.ps1"
    if (Test-Path $localScript) {
        Copy-Item $localScript "$stataDir\send-to-stata.ps1" -Force
        Write-Host "Installed send-to-stata.ps1 from local file"
    } else {
        $githubRef = $env:SIGHT_GITHUB_REF
        if (!$githubRef) { $githubRef = "main" }
        
        $url = "https://raw.githubusercontent.com/jbearak/sight-zed/$githubRef/send-to-stata.ps1"
        $content = Invoke-RestMethod -Uri $url
        
        if ($githubRef -eq "main" -and !$env:SIGHT_GITHUB_REF) {
            $expectedChecksum = "PUT_CHECKSUM_HERE"
            $actualChecksum = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($content))) -Algorithm SHA256).Hash
            if ($actualChecksum -ne $expectedChecksum) {
                throw "Checksum mismatch. Expected: $expectedChecksum, Got: $actualChecksum"
            }
        }
        
        $content | Out-File "$stataDir\send-to-stata.ps1" -Encoding UTF8
        Write-Host "Downloaded send-to-stata.ps1 from GitHub"
    }
}

function Install-Tasks {
    $tasksPath = "$env:APPDATA\Zed\tasks.json"
    $tasks = @()
    if (Test-Path $tasksPath) {
        $tasks = Get-Content $tasksPath | ConvertFrom-Json
    }
    
    $tasks = $tasks | Where-Object { !$_.label.StartsWith("Stata:") }
    
    $newTasks = @(
        @{
            label = "Stata: Send Statement"
            command = "powershell.exe -sta -ExecutionPolicy Bypass -File `"$env:APPDATA\Zed\stata\send-to-stata.ps1`" -Statement -Stdin -File `"`$ZED_FILE`" -Row `$ZED_ROW"
            use_new_terminal = $false
            allow_concurrent_runs = $true
            reveal = "never"
            hide = "on_success"
        },
        @{
            label = "Stata: Send File"
            command = "powershell.exe -sta -ExecutionPolicy Bypass -File `"$env:APPDATA\Zed\stata\send-to-stata.ps1`" -FileMode -File `"`$ZED_FILE`""
            use_new_terminal = $false
            allow_concurrent_runs = $true
            reveal = "never"
            hide = "on_success"
        },
        @{
            label = "Stata: Include Statement"
            command = "powershell.exe -sta -ExecutionPolicy Bypass -File `"$env:APPDATA\Zed\stata\send-to-stata.ps1`" -Statement -Include -Stdin -File `"`$ZED_FILE`" -Row `$ZED_ROW"
            use_new_terminal = $false
            allow_concurrent_runs = $true
            reveal = "never"
            hide = "on_success"
        },
        @{
            label = "Stata: Include File"
            command = "powershell.exe -sta -ExecutionPolicy Bypass -File `"$env:APPDATA\Zed\stata\send-to-stata.ps1`" -FileMode -Include -File `"`$ZED_FILE`""
            use_new_terminal = $false
            allow_concurrent_runs = $true
            reveal = "never"
            hide = "on_success"
        }
    )
    
    $tasks += $newTasks
    $tasks | ConvertTo-Json -Depth 10 | Out-File $tasksPath -Encoding UTF8
}

function Install-Keybindings {
    $keymapPath = "$env:APPDATA\Zed\keymap.json"
    $keybindings = @()
    if (Test-Path $keymapPath) {
        $keybindings = Get-Content $keymapPath | ConvertFrom-Json
    }
    
    $keybindings = $keybindings | Where-Object { $_.context -ne "Editor && extension == do" }
    
    $newKeybindings = @(
        @{
            context = "Editor && extension == do"
            bindings = @{
                "ctrl-enter" = @("workspace::Save", @(@{ task_name = "Stata: Send Statement" }))
                "shift-ctrl-enter" = @("workspace::Save", @(@{ task_name = "Stata: Send File" }))
                "alt-ctrl-enter" = @("workspace::Save", @(@{ task_name = "Stata: Include Statement" }))
                "alt-shift-ctrl-enter" = @("workspace::Save", @(@{ task_name = "Stata: Include File" }))
                "shift-enter" = @("editor::Copy", "terminal_panel::ToggleFocus", "terminal::Paste", "SendKeystrokes", "enter")
                "alt-enter" = @("editor::SelectLine", "editor::Copy", "terminal_panel::ToggleFocus", "terminal::Paste", "SendKeystrokes", "enter")
            }
        }
    )
    
    $keybindings += $newKeybindings
    $keybindings | ConvertTo-Json -Depth 10 | Out-File $keymapPath -Encoding UTF8
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
            return @{ IsRegistered = $true; RegisteredPath = $serverPath }
        }
    } catch {}
    return @{ IsRegistered = $false; RegisteredPath = $null }
}

function Register-StataAutomation {
    param([string]$StataPath)
    Start-Process -FilePath $StataPath -ArgumentList "/Register" -Verb RunAs -Wait
}

function Show-RegistrationPrompt {
    param([string]$Message)
    Add-Type -AssemblyName System.Windows.Forms
    $result = [System.Windows.Forms.MessageBox]::Show($Message, "Stata Automation Registration", [System.Windows.Forms.MessageBoxButtons]::YesNo)
    return $result -eq [System.Windows.Forms.DialogResult]::Yes
}

function Invoke-AutomationRegistrationCheck {
    param([string]$StataPath)
    
    if ($SkipAutomationCheck) { return }
    
    $regStatus = Test-StataAutomationRegistered
    
    if (!$regStatus.IsRegistered) {
        $message = "Stata automation is not registered. Register now to enable send-to-Stata functionality?"
        if (Show-RegistrationPrompt $message) {
            Register-StataAutomation $StataPath
        }
    } elseif ($regStatus.RegisteredPath -and $regStatus.RegisteredPath -ne $StataPath) {
        $message = "Stata automation is registered to a different path. Re-register with current installation?"
        if (Show-RegistrationPrompt $message) {
            Register-StataAutomation $StataPath
        }
    }
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

Install-Script

$stataPath = Find-StataInstallation
if ($stataPath) {
    Write-Host "Found Stata: $stataPath"
    Invoke-AutomationRegistrationCheck $stataPath
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