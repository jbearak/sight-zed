# Design Document: Send-to-Stata Windows

## Overview

This design specifies the Windows implementation of send-to-stata functionality for Zed editor. The solution uses PowerShell scripts to send Stata code from Zed to a running Stata GUI instance via clipboard and SendKeys automation.

The Windows implementation mirrors the macOS version's architecture but replaces AppleScript with Windows-native automation:
- **macOS**: AppleScript → `DoCommandAsync`
- **Windows**: Clipboard + SendKeys → Ctrl+1, Ctrl+V, Enter

### Key Design Decisions

1. **PowerShell 5.0+ Compatibility**: Use only built-in .NET assemblies available in Windows PowerShell
2. **Clipboard-Based Transfer**: Write command to clipboard, paste into Stata (avoids shell escaping issues)
3. **SendKeys via .NET**: Use `System.Windows.Forms.SendKeys` for keystroke simulation
4. **Temp File Execution**: Write code to temp .do file, send `do`/`include` command (same as macOS)
5. **Stdin Mode**: Read selected text from stdin to avoid PowerShell interpretation of special characters
6. **STA Threading**: Require Single-Threaded Apartment mode for clipboard operations
7. **Focus Acquisition Workaround**: Use ALT key simulation to bypass Windows focus-stealing prevention
8. **Command Window Focus**: Use Ctrl+1 to ensure Command window has focus before paste

### Why Not COM Automation?

Stata provides COM Automation (`stata.StataOLEApp`) on Windows, but it has a critical limitation: **Stata Automation is a single-use out-of-process server**, meaning `CreateObject("stata.StataOLEApp")` always launches a new Stata instance. The COM reference is tied to the script's lifetime—when the PowerShell script exits, the reference is released and Stata closes.

Sublime Text plugins work around this by keeping Python running persistently, storing the COM reference in a module-level variable. Zed tasks spawn a new PowerShell process for each invocation, making this approach impractical without a separate daemon process.

The clipboard + SendKeys approach targets the user's **existing** Stata session where their data is already loaded.

### Why Clipboard Instead of Typing via SendKeys?

SendKeys can simulate typing character-by-character, but this approach is fragile and slow. SendKeys uses special escape sequences (`^` for Ctrl, `+` for Shift, `%` for Alt, `{}` for special keys), which conflict with characters common in Stata code. Compound strings containing backticks and braces would require complex escaping. Clipboard transfer is atomic—the entire command arrives intact regardless of special characters—and is significantly faster.

### Why Not Shell Execute?

Double-clicking a `.do` file or using `Start-Process` on it causes Windows to launch a *new* Stata instance rather than sending the file to an existing session. This would discard the user's loaded data, working directory, and defined macros.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Zed Editor                                 │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  Keybinding (ctrl-enter) → Task → PowerShell -sta Command   │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      send-to-stata.ps1                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐   │
│  │ Argument     │→ │ Statement    │→ │ Temp File                │   │
│  │ Parser       │  │ Detector     │  │ Creator                  │   │
│  └──────────────┘  └──────────────┘  └──────────────────────────┘   │
│                                              │                       │
│  ┌──────────────┐  ┌──────────────┐          ▼                      │
│  │ Stata        │→ │ Window       │  ┌──────────────────────────┐   │
│  │ Detector     │  │ Activator    │→ │ Clipboard + SendKeys     │   │
│  └──────────────┘  └──────────────┘  └──────────────────────────┘   │
│                          │                                           │
│                          ▼                                           │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ Focus Acquisition Module (ALT workaround, Ctrl+1, retry)    │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Stata GUI                                    │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  Command Window receives: do "C:\...\temp.do" + Enter        │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. User presses keybinding in Zed (e.g., `ctrl-enter`)
2. Zed task spawns PowerShell **with `-sta` flag** and arguments
3. Script reads code (from stdin, file, or row detection)
4. Script writes code to temp .do file
5. Script copies `do "temp_path"` to clipboard (requires STA mode)
6. Script finds Stata window by process name and title pattern
7. Script restores window if minimized (ShowWindow SW_RESTORE)
8. Script simulates ALT keypress to satisfy focus-stealing prevention
9. Script activates Stata window (SetForegroundWindow)
10. Script verifies focus acquisition (GetForegroundWindow check)
11. Script sends Ctrl+1 (focus Command window)
12. Script sends Ctrl+V (paste) then Enter (execute)
13. Stata executes the temp file

## Components and Interfaces

### Component 1: send-to-stata.ps1

The main script that handles all send-to-stata operations.

#### Timing Configuration

Timing values are hardcoded at the top of the script. Users who experience issues can adjust these values directly; see README for guidance.

```powershell
# Timing configuration (adjust if script fails on your system - see README)
$clipPause = 10   # ms after clipboard copy before sending keys
$winPause  = 10   # ms between window operations
$keyPause  = 1    # ms between keystrokes
```

These values are based on tested configurations and work reliably on modern systems. Increase them if the script fails intermittently on slower machines.

#### Parameters

```powershell
param(
    [switch]$Statement,      # Statement mode
    [switch]$FileMode,       # File mode
    [switch]$Include,        # Use 'include' instead of 'do'
    [switch]$Stdin,          # Read text from stdin
    [string]$File,           # Source file path (required)
    [int]$Row                # Cursor row, 1-indexed
)
```

#### Functions

**Find-StataInstallation**
```powershell
# Searches for Stata in standard locations
# Returns: Full path to Stata executable, or $null if not found
# Priority: $env:STATA_PATH > auto-detection
function Find-StataInstallation {
    # Check STATA_PATH environment variable first
    # Search versions 19 down to 13
    # Search paths: Program Files, Program Files (x86), C:\
    # Search variants: StataMP-64, StataSE-64, StataBE-64, StataIC-64, StataMP, StataSE, StataBE, StataIC
}
```

**Find-StataWindow**
```powershell
# Finds running Stata window by process name and window title
# Returns: Process object with MainWindowHandle, or $null
function Find-StataWindow {
    # Get processes matching Stata* or StataNow* pattern
    # Filter by window title matching "Stata/(MP|SE|BE|IC)" or "StataNow/(MP|SE|BE|IC)"
    # Exclude Stata Viewer and other auxiliary windows
    # Return first match
}
```

**Get-StatementAtRow**
```powershell
# Detects the complete statement at the given cursor position
# Handles continuation markers (///)
# Parameters: $FilePath, $Row (1-indexed)
# Returns: Statement text with preserved line breaks
function Get-StatementAtRow {
    param([string]$FilePath, [int]$Row)
    # Read file lines
    # Search backwards for statement start (line not preceded by ///)
    # Search forwards for statement end (line not ending with ///)
    # Return joined lines
}
```

**New-TempDoFile**
```powershell
# Creates a temp .do file with the given content
# Returns: Full path to temp file
function New-TempDoFile {
    param([string]$Content)
    # Use [System.IO.Path]::GetTempFileName()
    # Rename to .do extension
    # Write content with UTF-8 encoding (no BOM)
}
```

**Send-ToStata**
```powershell
# Sends command to Stata via clipboard and SendKeys
# Parameters: $TempFilePath, $UseInclude
function Send-ToStata {
    param([string]$TempFilePath, [switch]$UseInclude)
    # Build command: do "path" or include "path"
    # Copy to clipboard (requires STA mode)
    # Find Stata window
    # Restore if minimized
    # Acquire focus with ALT workaround
    # Verify focus
    # Send Ctrl+1 (focus Command window)
    # Send Ctrl+V, wait, send Enter
}
```

### Component 2: install-send-to-stata.ps1

The installer script that sets up the environment.

#### Parameters

```powershell
param(
    [switch]$Uninstall,           # Remove all installed components
    [switch]$RegisterAutomation,  # Explicitly request type library registration
    [switch]$SkipAutomationCheck  # Skip the automation registration check
)
```

#### Functions

**Install-Script**
```powershell
# Copies send-to-stata.ps1 to $env:APPDATA\Zed\stata\
function Install-Script {
    # Create directory if needed
    # Copy script (from local or fetch from GitHub)
    # Verify checksum for web installation
}
```

**Install-Tasks**
```powershell
# Creates/updates Zed tasks.json
function Install-Tasks {
    # Read existing tasks.json (or create empty array)
    # Remove existing Stata: tasks
    # Add new Stata tasks with -sta flag
    # Write back to file
}
```

**Install-Keybindings**
```powershell
# Creates/updates Zed keymap.json
# Installs both standard keybindings (ctrl-enter, etc.) and 
# terminal-compatible keybindings (alt-enter, shift-alt-enter)
function Install-Keybindings {
    # Read existing keymap.json (or create empty array)
    # Remove existing .do file keybindings
    # Add standard keybindings (ctrl-enter, shift-ctrl-enter, alt-ctrl-enter, alt-shift-ctrl-enter)
    # Add terminal keybindings (alt-enter, shift-alt-enter)
    # Write back to file
}
```

**Test-StataAutomationRegistered**
```powershell
# Checks if Stata's Automation type library is registered
# Returns: Hashtable with 'IsRegistered', 'RegisteredPath', or $null if not registered
function Test-StataAutomationRegistered {
    # Query registry for stata.StataOLEApp ProgID
    # Check HKEY_CLASSES_ROOT\stata.StataOLEApp
    # If exists, get CLSID and read LocalServer32 path
    # Return @{ IsRegistered = $true; RegisteredPath = "C:\...\StataSE-64.exe" }
    # Return @{ IsRegistered = $false; RegisteredPath = $null } if not registered
}
```

**Register-StataAutomation**
```powershell
# Registers Stata's Automation type library (requires elevation)
# Parameters: $StataPath - path to Stata executable
# Returns: $true on success, $false on failure
function Register-StataAutomation {
    param([string]$StataPath)
    # Launch elevated PowerShell process
    # Execute: Start-Process -FilePath $StataPath -ArgumentList "/Register" -Verb RunAs -Wait
    # Capture exit code
    # Return success/failure
}
```

**Show-RegistrationPrompt**
```powershell
# Displays a popup dialog for registration decisions
# Parameters: $Message, $Title
# Returns: $true if user clicked Yes, $false if No
function Show-RegistrationPrompt {
    param([string]$Message, [string]$Title)
    # Use System.Windows.Forms.MessageBox
    # Return $true for Yes, $false for No
}
```

### Component 3: Window Activation Module

Uses Win32 API via .NET for window management. This is the most critical component for reliability.

```powershell
# Add required assemblies
Add-Type -AssemblyName System.Windows.Forms

# Win32 API declarations for window management
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class User32 {
    // Window activation
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    
    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);  // Check if minimized
    
    // Keyboard simulation for ALT workaround
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    
    // Constants
    public const int SW_RESTORE = 9;
    public const byte VK_MENU = 0x12;  // ALT key
    public const uint KEYEVENTF_KEYUP = 0x0002;
}
"@
```

### Component 4: Focus Acquisition Module

Handles the complex task of reliably activating the Stata window despite Windows focus-stealing prevention.

```powershell
function Invoke-FocusAcquisition {
    param(
        [IntPtr]$WindowHandle,
        [int]$MaxRetries = 3
    )
    
    # Step 1: Restore if minimized
    if ([User32]::IsIconic($WindowHandle)) {
        [User32]::ShowWindow($WindowHandle, [User32]::SW_RESTORE)
        Start-Sleep -Milliseconds $winPause
    }
    
    # Step 2: Try to acquire focus with retries
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        # Simulate ALT keypress to satisfy "last input event" requirement
        # This is the key workaround for Windows focus-stealing prevention
        [User32]::keybd_event([User32]::VK_MENU, 0, 0, [UIntPtr]::Zero)      # ALT down
        [User32]::keybd_event([User32]::VK_MENU, 0, [User32]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)  # ALT up
        
        # Now SetForegroundWindow should succeed
        [User32]::SetForegroundWindow($WindowHandle) | Out-Null
        
        # Wait for window to activate
        $delay = $winPause * $attempt  # Increasing delay: 10ms, 20ms, 30ms
        Start-Sleep -Milliseconds $delay
        
        # Verify focus was acquired
        $currentForeground = [User32]::GetForegroundWindow()
        if ($currentForeground -eq $WindowHandle) {
            return $true
        }
        
        Write-Verbose "Focus acquisition attempt $attempt failed, retrying..."
    }
    
    return $false
}
```

### Component 5: Keystroke Sequence

The complete keystroke sequence after focus acquisition:

```powershell
function Send-KeystrokesToStata {
    param([string]$Command)
    
    # Copy command to clipboard
    [System.Windows.Forms.Clipboard]::SetText($Command)
    Start-Sleep -Milliseconds $clipPause
    
    # Focus the Command window (Ctrl+1)
    [System.Windows.Forms.SendKeys]::SendWait("^1")
    Start-Sleep -Milliseconds $winPause
    
    # Paste from clipboard (Ctrl+V)
    [System.Windows.Forms.SendKeys]::SendWait("^v")
    Start-Sleep -Milliseconds $keyPause
    
    # Execute (Enter)
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
}
```

### Component 6: Stata Automation Registration

Handles one-time registration of Stata's Automation type library, which requires elevation.

#### Registry Check

```powershell
function Test-StataAutomationRegistered {
    # Check if the ProgID exists in registry
    $progIdPath = "Registry::HKEY_CLASSES_ROOT\stata.StataOLEApp"
    if (-not (Test-Path $progIdPath)) {
        return @{ IsRegistered = $false; RegisteredPath = $null }
    }
    
    # Get the CLSID reference
    $clsidPath = Join-Path $progIdPath "CLSID"
    if (-not (Test-Path $clsidPath)) {
        return @{ IsRegistered = $false; RegisteredPath = $null }
    }
    
    $clsid = (Get-ItemProperty $clsidPath).'(default)'
    if ([string]::IsNullOrEmpty($clsid)) {
        return @{ IsRegistered = $false; RegisteredPath = $null }
    }
    
    # Get the registered executable path from LocalServer32
    $localServerPath = "Registry::HKEY_CLASSES_ROOT\CLSID\$clsid\LocalServer32"
    if (-not (Test-Path $localServerPath)) {
        return @{ IsRegistered = $false; RegisteredPath = $null }
    }
    
    $registeredPath = (Get-ItemProperty $localServerPath).'(default)'
    # LocalServer32 may include arguments like "/Automation", strip them
    $registeredPath = ($registeredPath -split ' /')[0].Trim('"')
    
    return @{ IsRegistered = $true; RegisteredPath = $registeredPath }
}
```

#### Elevated Registration

```powershell
function Register-StataAutomation {
    param([string]$StataPath)
    
    # Validate Stata path exists
    if (-not (Test-Path $StataPath)) {
        Write-Error "Stata executable not found: $StataPath"
        return $false
    }
    
    Write-Host "Registering Stata Automation type library..."
    Write-Host "This requires administrator privileges. A UAC prompt will appear."
    
    try {
        # Launch Stata with /Register flag using elevation
        $process = Start-Process -FilePath $StataPath `
                                 -ArgumentList "/Register" `
                                 -Verb RunAs `
                                 -Wait `
                                 -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Stata Automation type library registered successfully." -ForegroundColor Green
            return $true
        } else {
            Write-Error "Registration failed with exit code: $($process.ExitCode)"
            return $false
        }
    } catch {
        if ($_.Exception.Message -match "canceled by the user") {
            Write-Warning "Registration canceled by user."
        } else {
            Write-Error "Registration failed: $_"
        }
        return $false
    }
}
```

#### Installer Integration

The installer checks and prompts for registration during setup:

```powershell
function Show-RegistrationPrompt {
    param([string]$Message, [string]$Title)
    
    Add-Type -AssemblyName System.Windows.Forms
    $result = [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Invoke-AutomationRegistrationCheck {
    param(
        [string]$StataPath,
        [switch]$Force,
        [switch]$Skip
    )
    
    if ($Skip) {
        Write-Verbose "Skipping Automation registration check"
        return
    }
    
    $regStatus = Test-StataAutomationRegistered
    
    # Case 1: Already registered with correct path
    if ($regStatus.IsRegistered -and $regStatus.RegisteredPath -eq $StataPath -and -not $Force) {
        Write-Host "Stata Automation type library is already registered." -ForegroundColor Green
        return
    }
    
    # Case 2: Registered but with different path (version mismatch)
    if ($regStatus.IsRegistered -and $regStatus.RegisteredPath -ne $StataPath) {
        $oldVersion = [System.IO.Path]::GetDirectoryName($regStatus.RegisteredPath) | Split-Path -Leaf
        $newVersion = [System.IO.Path]::GetDirectoryName($StataPath) | Split-Path -Leaf
        
        $message = "Stata version mismatch detected.`n`n" +
                   "Currently registered: $($regStatus.RegisteredPath)`n" +
                   "Detected installation: $StataPath`n`n" +
                   "Would you like to update the registration to use the new version?"
        
        $userConfirmed = Show-RegistrationPrompt -Message $message -Title "Stata Version Mismatch"
        
        if (-not $userConfirmed) {
            Write-Host "Skipping registration update." -ForegroundColor Yellow
            return
        }
    }
    
    # Case 3: Not registered at all
    if (-not $regStatus.IsRegistered -and -not $Force) {
        $message = "Stata Automation type library is not registered.`n`n" +
                   "Registration is required for some advanced features and is a one-time setup.`n`n" +
                   "Would you like to register it now?"
        
        $userConfirmed = Show-RegistrationPrompt -Message $message -Title "Stata Registration Required"
        
        if (-not $userConfirmed) {
            Write-Host "Skipping registration. You can register later with:"
            Write-Host "  $StataPath /Register" -ForegroundColor Cyan
            Write-Host "(Run as Administrator)"
            return
        }
    }
    
    # Proceed with registration
    $success = Register-StataAutomation -StataPath $StataPath
    if (-not $success) {
        Write-Host ""
        Write-Host "Manual registration instructions:" -ForegroundColor Yellow
        Write-Host "1. Open Command Prompt or PowerShell as Administrator"
        Write-Host "2. Run: $StataPath /Register" -ForegroundColor Cyan
    }
}
```

## Data Models

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Invalid arguments |
| 2 | Source file not found or unreadable |
| 3 | Temp file creation failed |
| 4 | Stata not found (installation or running instance) |
| 5 | SendKeys execution failed or focus acquisition failed |

### Stata Search Paths

```powershell
$SearchPaths = @(
    "C:\Program Files\Stata{0}\",
    "C:\Program Files (x86)\Stata{0}\",
    "C:\Stata{0}\",
    "C:\Program Files\StataNow{0}\",
    "C:\Program Files (x86)\StataNow{0}\",
    "C:\StataNow{0}\"
)

$Versions = 19..13  # Search newest first

$Variants = @(
    "StataMP-64.exe",
    "StataSE-64.exe",
    "StataBE-64.exe",
    "StataIC-64.exe",
    "StataMP.exe",
    "StataSE.exe",
    "StataBE.exe",
    "StataIC.exe"
)

$FallbackPaths = @(
    "C:\Stata\"
)
```

### Window Title Patterns

```powershell
# More precise pattern to avoid matching Stata Viewer or other windows
$StataTitlePatterns = @(
    "^Stata/(MP|SE|BE|IC)",      # Standard Stata
    "^StataNow/(MP|SE|BE|IC)"    # StataNow variant
)

# Process name patterns
$StataProcessPatterns = @(
    "StataMP*",
    "StataSE*",
    "StataBE*",
    "StataIC*"
)
```

### Zed Task Configuration

Tasks must launch PowerShell with `-sta` flag for clipboard operations:

```json
{
  "label": "Stata: Send Statement",
  "command": "powershell.exe",
  "args": [
    "-sta",
    "-ExecutionPolicy", "Bypass",
    "-File", "${APPDATA}\\Zed\\stata\\send-to-stata.ps1",
    "-Statement",
    "-Stdin",
    "-File", "$ZED_FILE",
    "-Row", "$ZED_ROW"
  ],
  "use_new_terminal": false,
  "allow_concurrent_runs": true,
  "reveal": "never",
  "hide": "on_success"
}
```

**Critical**: The `-sta` flag must come before other arguments. Without it, `[System.Windows.Forms.Clipboard]::SetText()` throws a `ThreadStateException` because PowerShell 5.0/5.1 console runs in MTA (multi-threaded apartment) mode by default.

### Zed Keybinding Configuration

```json
{
  "context": "Editor && extension == do",
  "bindings": {
    "ctrl-enter": ["workspace::Save", ["task::Spawn", { "task_name": "Stata: Send Statement" }]],
    "shift-ctrl-enter": ["workspace::Save", ["task::Spawn", { "task_name": "Stata: Send File" }]],
    "alt-ctrl-enter": ["workspace::Save", ["task::Spawn", { "task_name": "Stata: Include Statement" }]],
    "alt-shift-ctrl-enter": ["workspace::Save", ["task::Spawn", { "task_name": "Stata: Include File" }]]
  }
}
```

## Design Properties

These properties MUST hold for any valid implementation:

### Property 1: STATA_PATH Override
IF `$env:STATA_PATH` is set to a valid executable path, THEN auto-detection is skipped entirely.

### Property 2: Search Order Determinism
Given multiple Stata installations, the search order is deterministic: newer versions before older, Program Files before Program Files (x86) before C:\, 64-bit variants before 32-bit.

### Property 3: Multi-line Statement Detection
For any cursor position within a multi-line statement (connected by `///`), `Get-StatementAtRow` returns the complete statement including all continuation lines.

### Property 4: Stdin Content Preservation
Any text piped to stdin (including compound strings with backticks and quotes) is written to the temp file byte-for-byte identical.

### Property 5: File Content Preservation  
In file mode, the temp file content is byte-for-byte identical to the source file content.

### Property 6: Command Format by Mode
- `Include = $false` → command is `do "{path}"`
- `Include = $true` → command is `include "{path}"`

### Property 7: Temp File Characteristics
Every temp file: (a) is in the system temp directory, (b) has `.do` extension, (c) has a unique filename.

### Property 8: Config File Preservation
Installing/uninstalling preserves all non-Stata entries in tasks.json and keymap.json.

### Property 9: Checksum Verification
Web installation from main branch verifies SHA-256 checksum; non-main branches skip verification.

### Property 10: Platform-Independent Logic Isolation
All platform-independent functions (argument parsing, statement detection, file I/O) execute without calling Windows-specific APIs when mocks are enabled.

### Property 11: Focus Acquisition Reliability
The ALT key workaround followed by SetForegroundWindow succeeds in acquiring focus when:
- Both processes run at medium integrity level (standard user)
- The target window is not minimized OR is restored first via ShowWindow

### Property 12: STA Mode Enforcement
Clipboard operations only succeed when PowerShell is running in STA mode (launched with `-sta` flag).

### Property 13: Command Window Focus
Ctrl+1 is sent after window activation to ensure the Command window (not another Stata pane) receives the pasted text.

### Property 14: Automation Registration Idempotency
Calling `Register-StataAutomation` when the type library is already registered has no adverse effects; the operation succeeds silently.

### Property 15: Version Mismatch Detection
If the registered `LocalServer32` path differs from the detected Stata installation path, `Test-StataAutomationRegistered` returns the registered path enabling version mismatch detection.

## Windows Security Considerations

### User Interface Privilege Isolation (UIPI)

UIPI prevents a lower-integrity process from sending input to a higher-integrity process. This means:

- **Works**: Non-elevated script → Non-elevated Stata ✓
- **Fails silently**: Non-elevated script → Elevated Stata ✗

If Stata is "Run as Administrator" and the script is not elevated, `SendInput`/`SendKeys` calls will **silently fail**—Windows drops the messages without error. The script should detect this condition and display a helpful error message.

### Focus-Stealing Prevention

Windows prevents background processes from stealing focus. `SetForegroundWindow` only succeeds if one of these conditions is met:
1. The calling process is the foreground process
2. The calling process was started by the foreground process
3. **The calling process received the last input event**

Condition 3 is the workaround: by simulating an ALT keypress via `keybd_event` immediately before `SetForegroundWindow`, the script satisfies this requirement.

```powershell
# This is why we simulate ALT before SetForegroundWindow
[User32]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)      # ALT down
[User32]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)      # ALT up
[User32]::SetForegroundWindow($hwnd)                    # Now this works
```

### PowerShell Execution Policy

The `irm | iex` pattern (web installation) bypasses execution policy because policy only applies to `.ps1` files, not piped strings. The Zed tasks use `-ExecutionPolicy Bypass` to run the installed script without requiring system-wide policy changes.

## Error Handling

### Error Messages by Exit Code

| Exit Code | Condition | Message |
|-----------|-----------|---------|
| 1 | Mutually exclusive options | "Error: Cannot specify both -Statement and -FileMode" |
| 1 | Missing required parameter | "Error: -File parameter is required" |
| 2 | File not found | "Error: Cannot read file: {path}" |
| 3 | Temp file creation failed | "Error: Cannot create temp file: {exception}" |
| 4 | Stata not installed | "Error: No Stata installation found. Set STATA_PATH environment variable or install Stata" |
| 4 | Stata not running | "Error: No running Stata instance found. Start Stata before sending code" |
| 5 | Focus acquisition failed | "Error: Failed to activate Stata window after 3 attempts. Stata may be running as Administrator—try restarting Stata without elevation" |
| 5 | SendKeys failed | "Error: Failed to send keystrokes to Stata: {exception}" |

### Error Handling Patterns

**Argument Validation**
```powershell
# Validate mutually exclusive options
if ($Statement -and $FileMode) {
    Write-Error "Error: Cannot specify both -Statement and -FileMode"
    exit 1
}

# Validate required parameters
if (-not $File) {
    Write-Error "Error: -File parameter is required"
    exit 1
}
```

**File Operations**
```powershell
# Check file existence and readability
if (-not (Test-Path -Path $File -PathType Leaf)) {
    Write-Error "Error: Cannot read file: $File"
    exit 2
}

# Temp file creation with error handling
try {
    $tempFile = New-TempDoFile -Content $content
} catch {
    Write-Error "Error: Cannot create temp file: $_"
    exit 3
}
```

**Stata Detection**
```powershell
# Installation detection (informational only—we don't need the path, just a running instance)
$stataPath = Find-StataInstallation
if (-not $stataPath) {
    Write-Warning "No Stata installation found in standard locations"
}

# Running instance detection (required)
$stataWindow = Find-StataWindow
if (-not $stataWindow) {
    Write-Error "Error: No running Stata instance found"
    Write-Error "Start Stata before sending code"
    exit 4
}
```

**Focus Acquisition with Retry**
```powershell
$focusAcquired = Invoke-FocusAcquisition -WindowHandle $stataWindow.MainWindowHandle -MaxRetries 3
if (-not $focusAcquired) {
    Write-Error "Error: Failed to activate Stata window after 3 attempts"
    Write-Error "Stata may be running as Administrator—try restarting Stata without elevation"
    exit 5
}
```

**SendKeys Execution**
```powershell
try {
    Send-KeystrokesToStata -Command $command
} catch {
    Write-Error "Error: Failed to send keystrokes to Stata: $_"
    exit 5
}
```

## Testing Strategy

### Dual Testing Approach

This feature requires both unit tests and property-based tests:

- **Unit tests**: Verify specific examples, edge cases, and error conditions
- **Property tests**: Verify universal properties across generated inputs

### Cross-Platform Testability Architecture

To support development on macOS while targeting Windows (Requirement 14), the script separates concerns:

**Platform-Independent Functions** (testable on any OS):
- `Get-StatementAtRow` - Statement detection with continuation markers
- Argument parsing and validation
- File reading and content processing
- Temp file path generation
- Command string formatting (`do`/`include`)

**Windows-Specific Functions** (mockable for cross-platform tests):
- `Set-ClipboardContent` - Wrapper for clipboard operations
- `Find-StataWindow` - Window enumeration via Win32 API
- `Invoke-FocusAcquisition` - Focus acquisition with ALT workaround
- `Send-KeystrokesToStata` - SendKeys wrapper

```powershell
# Example: Mockable Windows function
function Set-ClipboardContent {
    param([string]$Text)
    if ($script:MockClipboard) {
        $script:ClipboardContent = $Text
        return
    }
    # Verify STA mode
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw "Clipboard operations require STA mode. Launch PowerShell with -sta flag."
    }
    [System.Windows.Forms.Clipboard]::SetText($Text)
}
```

### Test File Structure

```
tests/
├── send-to-stata.Tests.ps1          # Main script tests
├── install-send-to-stata.Tests.ps1  # Installer tests
├── Generators.ps1                   # Random data generators
├── Mocks.ps1                        # Mock functions for Windows APIs
└── CrossPlatform.ps1                # Platform detection and test skipping
```

### Cross-Platform Test Execution

Tests are runnable via Pester on both Windows and macOS/Linux:

```bash
# Run all tests (skips Windows-specific on non-Windows)
pwsh -Command "Invoke-Pester"

# Run only unit tests (cross-platform)
pwsh -Command "Invoke-Pester -Tag 'Unit'"

# Run integration tests (Windows only)
pwsh -Command "Invoke-Pester -Tag 'Integration'"
```

**CI Pipeline Configuration**:
- macOS runners: Execute unit tests and property tests for platform-independent logic
- Windows runners: Execute full test suite including integration tests with actual Stata window automation

### Property-Based Testing

Each property test MUST:
1. Run at least 100 iterations
2. Include a tag referencing the design property
3. Use random data generators for inputs

```powershell
Describe "Statement Detection Properties" {
    It "Property 3: Multi-line statement detection" -Tag "Property3" {
        foreach ($_ in 1..100) {
            $file = New-RandomStataFile -WithContinuations
            $statement = Get-RandomMultiLineStatement -File $file
            $randomLine = Get-Random -Minimum $statement.StartLine -Maximum $statement.EndLine
            
            $result = Get-StatementAtRow -FilePath $file.Path -Row $randomLine
            $result | Should -Be $statement.Content
        }
    }
}
```

## Changelog from Original Design

### Added

1. **STA Threading Requirement**: PowerShell must be launched with `-sta` flag for clipboard operations
2. **Focus Acquisition Module**: ALT key workaround, retry logic, and focus verification
3. **Command Window Focus**: Ctrl+1 sent after window activation to ensure correct target
4. **Minimized Window Handling**: ShowWindow with SW_RESTORE before activation
5. **UIPI Documentation**: Clear explanation of elevation requirements
6. **Hardcoded Timing Values**: 10ms clip pause, 10ms win pause, 1ms key pause
7. **Property 11**: Focus acquisition reliability property
8. **Property 12**: STA mode enforcement property
9. **Property 13**: Command window focus property

### Changed

1. **Execution keystroke**: Changed from Ctrl+D to Enter (Command window uses Enter, not Ctrl+D)
2. **Window title pattern**: Made more precise to avoid matching Stata Viewer
3. **Error messages**: Added diagnostic information for elevation issues
4. **Exit code 5**: Now covers both SendKeys failure and focus acquisition failure
5. **Configuration**: Hardcoded timing values instead of config file (document in README)

### Removed

1. **Configuration files**: No .ini or config.json; timing values hardcoded with README documentation
2. **COM Automation as option**: Moved to design rationale section explaining why it's not used
