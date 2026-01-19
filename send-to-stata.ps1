param(
    [switch]$Statement,
    [switch]$FileMode,
    [switch]$Include,
    [switch]$Stdin,
    [string]$File,
    [int]$Row,
    [switch]$MockMode
)

# Exit codes
$EXIT_SUCCESS        = 0
$EXIT_INVALID_ARGS   = 1
$EXIT_FILE_NOT_FOUND = 2
$EXIT_TEMP_FILE_FAIL = 3
$EXIT_STATA_NOT_FOUND= 4
$EXIT_SENDKEYS_FAIL  = 5

# Timing (ms)
$clipPause = 10
$winPause  = 10
$keyPause  = 1

Add-Type -AssemblyName System.Windows.Forms

# Mock flags/state
$script:MockClipboard   = $false
$script:MockWindow      = $false
$script:MockSendKeys    = $false
$script:MockFocus       = $false
$script:ClipboardContent= $null
$script:SentKeystrokes  = @()


function Ensure-STA {
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        Write-Error "Error: Clipboard operations require STA mode. Relaunch with -sta."
        exit $EXIT_SENDKEYS_FAIL
    }
}

function Set-ClipboardContent {
    param([string]$Text)
    if ($script:MockClipboard) { $script:ClipboardContent = $Text; return }
    [System.Windows.Forms.Clipboard]::SetText($Text)
}

function Invoke-SendKeys {
    param([string]$Keys)
    if ($script:MockSendKeys) { $script:SentKeystrokes += $Keys; return }
    [System.Windows.Forms.SendKeys]::SendWait($Keys)
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class User32 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    public const int SW_RESTORE = 9;
    public const byte VK_MENU = 0x12;
    public const uint KEYEVENTF_KEYUP = 0x0002;
}
"@

# Placeholder elevation check (returns false unless mocked differently later)
function Test-ProcessElevated {
    param([int]$ProcessId)
    return $false
}

# Parameter validation will run in main execution block

function Find-StataInstallation {
    if ($env:STATA_PATH -and (Test-Path $env:STATA_PATH)) { return $env:STATA_PATH }
    $variants = @("StataMP-64.exe","StataSE-64.exe","StataBE-64.exe","StataIC-64.exe","StataMP.exe","StataSE.exe","StataBE.exe","StataIC.exe")
    for ($v=19; $v -ge 13; $v--) {
        $paths = @("C:\Program Files\Stata$v\","C:\Program Files (x86)\Stata$v\","C:\Stata$v\","C:\Program Files\StataNow$v\","C:\Program Files (x86)\StataNow$v\","C:\StataNow$v\")
        foreach ($p in $paths) { foreach ($var in $variants) { $fp = Join-Path $p $var; if (Test-Path $fp) { return $fp } } }
    }
    foreach ($var in $variants) { $fp = Join-Path "C:\Stata\" $var; if (Test-Path $fp) { return $fp } }
    return $null
}

function Find-StataWindow {
    if ($script:MockWindow) { return [pscustomobject]@{ MainWindowHandle=[IntPtr]::Zero; Id=0; MainWindowTitle="MockStata/MP" } }
    $procs = @()
    $procs += Get-Process -Name "Stata*" -ErrorAction SilentlyContinue
    $procs += Get-Process -Name "StataNow*" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        if ($p.MainWindowTitle -match "^Stata/(MP|SE|BE|IC)" -or $p.MainWindowTitle -match "^StataNow/(MP|SE|BE|IC)") {
            if ($p.MainWindowTitle -notmatch "Viewer") { return $p }
        }
    }
    return $null
}

function Invoke-FocusAcquisition {
    param([IntPtr]$WindowHandle,[int]$MaxRetries=3)
    if ($script:MockFocus) { return $true }
    if ([User32]::IsIconic($WindowHandle)) {
        [User32]::ShowWindow($WindowHandle,[User32]::SW_RESTORE)
        Start-Sleep -Milliseconds $winPause
    }
    for ($i=1; $i -le $MaxRetries; $i++) {
        [User32]::keybd_event([User32]::VK_MENU,0,0,[UIntPtr]::Zero)
        [User32]::keybd_event([User32]::VK_MENU,0,[User32]::KEYEVENTF_KEYUP,[UIntPtr]::Zero)
        [User32]::SetForegroundWindow($WindowHandle) | Out-Null
        Start-Sleep -Milliseconds ($winPause * $i)
        if ([User32]::GetForegroundWindow() -eq $WindowHandle) { return $true }
    }
    return $false
}

function Get-StatementAtRow {
    param([string]$FilePath,[int]$Row)
    $lines = Get-Content $FilePath -ReadCount 0
    $start=$Row; $end=$Row
    while ($start -gt 1 -and $lines[$start-2] -match '///\s*$') { $start-- }
    while ($end -lt $lines.Count -and $lines[$end-1] -match '///\s*$') { $end++ }
    return ($lines[($start-1)..($end-1)] -join [Environment]::NewLine)
}

function New-TempDoFile {
    param([string]$Content)
    try {
        $temp = [System.IO.Path]::GetTempPath()
        $name = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetRandomFileName(),".do")
        $full = Join-Path $temp $name
        [System.IO.File]::WriteAllText($full,$Content,[System.Text.UTF8Encoding]::new($false))
        return $full
    } catch { return $null }
}

function Read-SourceFile {
    param([string]$FilePath)
    return [System.IO.File]::ReadAllText($FilePath)
}

function Send-ToStata {
    param([string]$TempFilePath,[switch]$UseInclude)
    $command = if ($UseInclude) { "include `"$TempFilePath`"" } else { "do `"$TempFilePath`"" }
    $stataWindow = Find-StataWindow
    if (-not $stataWindow) { Write-Error "Error: No running Stata instance found. Start Stata before sending code"; exit $EXIT_STATA_NOT_FOUND }
    if (-not (Invoke-FocusAcquisition -WindowHandle $stataWindow.MainWindowHandle)) {
        $maybeElevated = Test-ProcessElevated -ProcessId $stataWindow.Id
        $isAdmin = ([System.Security.Principal.WindowsPrincipal] [System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($maybeElevated -and -not $isAdmin) {
            Write-Error "Error: Failed to activate Stata window after 3 attempts. Stata may be running as Administrator. Restart Stata without elevation."
        } else {
            Write-Error "Error: Failed to activate Stata window after 3 attempts. Focus-stealing prevention may be blocking SetForegroundWindow."
        }
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

# Allow dot-sourcing for tests
if ($env:SEND_TO_STATA_SKIP_MAIN) { return }

# Main execution
if ($MockMode) {
    $script:MockClipboard = $true
    $script:MockWindow    = $true
    $script:MockSendKeys  = $true
    $script:MockFocus     = $true
}
if ($Statement -and $FileMode) { Write-Error "Error: Cannot specify both -Statement and -FileMode"; exit $EXIT_INVALID_ARGS }
if (-not $File) { Write-Error "Error: -File parameter is required"; exit $EXIT_INVALID_ARGS }

Ensure-STA
if (-not (Test-Path $File)) { Write-Error "Error: Cannot read file: $File"; exit $EXIT_FILE_NOT_FOUND }

$stdinContent = @($input) -join [Environment]::NewLine
if ($Stdin -and $stdinContent) {
    $content = $stdinContent
} elseif ($env:ZED_SELECTED_TEXT) {
    # Zed sets ZED_SELECTED_TEXT when text is selected; use it directly
    $content = $env:ZED_SELECTED_TEXT
} elseif ($FileMode) {
    $content = Read-SourceFile -FilePath $File
} elseif ($Row) {
    $content = Get-StatementAtRow -FilePath $File -Row $Row
} else {
    Write-Error "Error: Either -FileMode or -Row must be specified"
    exit $EXIT_INVALID_ARGS
}

$tempFile = New-TempDoFile -Content $content
if (-not $tempFile) { Write-Error "Error: Cannot create temp file"; exit $EXIT_TEMP_FILE_FAIL }

Send-ToStata -TempFilePath $tempFile -UseInclude:$Include
exit $EXIT_SUCCESS
