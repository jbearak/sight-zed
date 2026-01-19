param(
    [switch]$Statement,
    [switch]$FileMode,
    [switch]$Include,
    [switch]$Stdin,
    [string]$File,
    [int]$Row
)

# Exit codes
$EXIT_SUCCESS = 0
$EXIT_INVALID_ARGS = 1
$EXIT_FILE_NOT_FOUND = 2
$EXIT_TEMP_FILE_FAIL = 3
$EXIT_STATA_NOT_FOUND = 4
$EXIT_SENDKEYS_FAIL = 5

# Timing configuration
$clipPause = 10
$winPause = 10
$keyPause = 1

# Add required assemblies
Add-Type -AssemblyName System.Windows.Forms

# Mockable wrappers for testing
$script:MockClipboard = $false
$script:MockWindow = $false
$script:MockSendKeys = $false
$script:ClipboardContent = $null
$script:SentKeystrokes = @()

function Set-ClipboardContent {
    param([string]$Text)
    if ($script:MockClipboard) {
        $script:ClipboardContent = $Text
        return
    }
    [System.Windows.Forms.Clipboard]::SetText($Text)
}

function Invoke-SendKeys {
    param([string]$Keys)
    if ($script:MockSendKeys) {
        $script:SentKeystrokes += $Keys
        return
    }
    [System.Windows.Forms.SendKeys]::SendWait($Keys)
}

# Win32 API declarations
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class User32 {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    
    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    
    public const int SW_RESTORE = 9;
    public const byte VK_MENU = 0x12;
    public const uint KEYEVENTF_KEYUP = 0x0002;
}
"@

# Parameter validation
if ($Statement -and $FileMode) {
    Write-Error "Statement and FileMode are mutually exclusive"
    exit $EXIT_INVALID_ARGS
}

if (-not $File) {
    Write-Error "File parameter is required"
    exit $EXIT_INVALID_ARGS
}

function Find-StataInstallation {
    # Check environment variable first
    if ($env:STATA_PATH -and (Test-Path $env:STATA_PATH)) {
        return $env:STATA_PATH
    }
    
    # Search versions 19 down to 13
    for ($version = 19; $version -ge 13; $version--) {
        $searchPaths = @(
            "C:\Program Files\Stata$version\",
            "C:\Program Files (x86)\Stata$version\",
            "C:\Stata$version\",
            "C:\Program Files\StataNow$version\",
            "C:\Program Files (x86)\StataNow$version\",
            "C:\StataNow$version\"
        )
        
        $variants = @("StataMP-64.exe", "StataSE-64.exe", "StataBE-64.exe", "StataIC-64.exe", 
                     "StataMP.exe", "StataSE.exe", "StataBE.exe", "StataIC.exe")
        
        foreach ($path in $searchPaths) {
            foreach ($variant in $variants) {
                $fullPath = Join-Path $path $variant
                if (Test-Path $fullPath) {
                    return $fullPath
                }
            }
        }
    }
    
    # Fallback to C:\Stata\
    $variants = @("StataMP-64.exe", "StataSE-64.exe", "StataBE-64.exe", "StataIC-64.exe", 
                 "StataMP.exe", "StataSE.exe", "StataBE.exe", "StataIC.exe")
    
    foreach ($variant in $variants) {
        $fullPath = Join-Path "C:\Stata\" $variant
        if (Test-Path $fullPath) {
            return $fullPath
        }
    }
    
    return $null
}

function Find-StataWindow {
    $stataProcesses = @()
    $stataProcesses += Get-Process -Name "Stata*" -ErrorAction SilentlyContinue
    $stataProcesses += Get-Process -Name "StataNow*" -ErrorAction SilentlyContinue
    
    foreach ($process in $stataProcesses) {
        if ($process.MainWindowTitle -match "^Stata/(MP|SE|BE|IC)" -or 
            $process.MainWindowTitle -match "^StataNow/(MP|SE|BE|IC)") {
            if ($process.MainWindowTitle -notmatch "Viewer") {
                return $process
            }
        }
    }
    
    return $null
}

function Invoke-FocusAcquisition {
    param(
        [IntPtr]$WindowHandle,
        [int]$MaxRetries = 3
    )
    
    if ([User32]::IsIconic($WindowHandle)) {
        [User32]::ShowWindow($WindowHandle, [User32]::SW_RESTORE)
        Start-Sleep -Milliseconds $winPause
    }
    
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        [User32]::keybd_event([User32]::VK_MENU, 0, 0, [UIntPtr]::Zero)
        [User32]::keybd_event([User32]::VK_MENU, 0, [User32]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
        
        [User32]::SetForegroundWindow($WindowHandle)
        
        Start-Sleep -Milliseconds ($winPause * $attempt)
        
        if ([User32]::GetForegroundWindow() -eq $WindowHandle) {
            return $true
        }
    }
    
    return $false
}

# Placeholder functions to be implemented later
function Get-StatementAtRow {
    param([string]$FilePath, [int]$Row)
    
    $lines = Get-Content $FilePath
    $startRow = $Row
    $endRow = $Row
    
    # Find statement start (search backwards)
    while ($startRow -gt 1 -and $lines[$startRow - 2] -match '///\s*$') {
        $startRow--
    }
    
    # Find statement end (search forwards)
    while ($endRow -lt $lines.Count -and $lines[$endRow - 1] -match '///\s*$') {
        $endRow++
    }
    
    return ($lines[($startRow - 1)..($endRow - 1)] -join [Environment]::NewLine)
}

function New-TempDoFile {
    param([string]$Content)
    
    try {
        $tempPath = [System.IO.Path]::GetTempPath()
        $fileName = [System.IO.Path]::GetRandomFileName()
        $doFile = [System.IO.Path]::ChangeExtension($fileName, ".do")
        $fullPath = Join-Path $tempPath $doFile
        
        [System.IO.File]::WriteAllText($fullPath, $Content, [System.Text.UTF8Encoding]::new($false))
        return $fullPath
    }
    catch {
        return $null
    }
}

function Read-SourceFile {
    param([string]$FilePath)
    
    return [System.IO.File]::ReadAllText($FilePath)
}

# Note: Stdin must be read in main script body, not in a function
# $input is only available at script scope

function Send-ToStata {
    param(
        [string]$TempFilePath,
        [switch]$UseInclude
    )
    
    $command = if ($UseInclude) { "include `"$TempFilePath`"" } else { "do `"$TempFilePath`"" }
    
    $stataWindow = Find-StataWindow
    if (-not $stataWindow) {
        Write-Error "Error: No running Stata instance found. Start Stata before sending code"
        exit $EXIT_STATA_NOT_FOUND
    }
    
    if (-not (Invoke-FocusAcquisition -WindowHandle $stataWindow.MainWindowHandle)) {
        Write-Error "Error: Failed to activate Stata window. Stata may be running as Administrator"
        exit $EXIT_SENDKEYS_FAIL
    }
    
    Set-ClipboardContent -Text $command
    Start-Sleep -Milliseconds $clipPause
    
    Invoke-SendKeys -Keys "^1"
    Start-Sleep -Milliseconds $winPause
    
    Invoke-SendKeys -Keys "^v"
    Start-Sleep -Milliseconds $keyPause
    
    Invoke-SendKeys -Keys "{ENTER}"
}

# Main execution
if (-not (Test-Path $File)) {
    Write-Error "Error: Cannot read file: $File"
    exit $EXIT_FILE_NOT_FOUND
}

# Read stdin at script scope (must be done here, not in a function)
$stdinContent = @($input) -join [Environment]::NewLine

if ($Stdin -and $stdinContent) {
    $content = $stdinContent
} elseif ($FileMode) {
    $content = Read-SourceFile -FilePath $File
} elseif ($Row) {
    $content = Get-StatementAtRow -FilePath $File -Row $Row
} else {
    Write-Error "Error: Either -FileMode or -Row must be specified"
    exit $EXIT_INVALID_ARGS
}

$tempFile = New-TempDoFile -Content $content
if (-not $tempFile) {
    Write-Error "Error: Cannot create temp file"
    exit $EXIT_TEMP_FILE_FAIL
}

Send-ToStata -TempFilePath $tempFile -UseInclude:$Include
exit $EXIT_SUCCESS
