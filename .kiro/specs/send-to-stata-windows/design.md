# Design Document: Send-to-Stata Windows

## Overview

This design specifies the Windows implementation of send-to-stata functionality for Zed editor. The solution uses PowerShell scripts to send Stata code from Zed to a running Stata GUI instance via clipboard and SendKeys automation.

The Windows implementation mirrors the macOS version's architecture but replaces AppleScript with Windows-native automation:
- **macOS**: AppleScript → `DoCommandAsync`
- **Windows**: Clipboard + SendKeys → Ctrl+V, Ctrl+D

### Key Design Decisions

1. **PowerShell 5.0+ Compatibility**: Use only built-in .NET assemblies available in Windows PowerShell
2. **Clipboard-Based Transfer**: Write command to clipboard, paste into Stata (avoids shell escaping issues)
3. **SendKeys via .NET**: Use `System.Windows.Forms.SendKeys` for keystroke simulation
4. **Temp File Execution**: Write code to temp .do file, send `do`/`include` command (same as macOS)
5. **Stdin Mode**: Read selected text from stdin to avoid PowerShell interpretation of special characters

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Zed Editor                                 │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  Keybinding (ctrl-enter) → Task → PowerShell Command        │    │
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
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Stata GUI                                    │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  Command Window receives: do "C:\...\temp.do"               │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. User presses keybinding in Zed (e.g., `ctrl-enter`)
2. Zed task spawns PowerShell with arguments
3. Script reads code (from stdin, file, or row detection)
4. Script writes code to temp .do file
5. Script copies `do "temp_path"` to clipboard
6. Script finds and activates Stata window
7. Script sends Ctrl+V (paste) then Ctrl+D (execute)
8. Stata executes the temp file

## Components and Interfaces

### Component 1: send-to-stata.ps1

The main script that handles all send-to-stata operations.

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
    # Get processes matching Stata* pattern
    # Filter by window title containing "Stata/"
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
    # Copy to clipboard
    # Find and activate Stata window
    # Send Ctrl+V, wait, send Ctrl+D
}
```

### Component 2: install-send-to-stata.ps1

The installer script that sets up the environment.

#### Parameters

```powershell
param(
    [switch]$Uninstall       # Remove all installed components
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
    # Add new Stata tasks
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

### Component 3: Window Activation Module

Uses Win32 API via .NET for window management.

```powershell
# Add required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic

# For window activation, use SetForegroundWindow via P/Invoke
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
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
| 5 | SendKeys execution failed |

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

# Fallback path (no version number)
$FallbackPath = "C:\Stata\"
```

### Zed Task Configuration

```json
{
    "label": "Stata: Send Statement",
    "command": "powershell.exe -ExecutionPolicy Bypass -File \"$env:APPDATA\\Zed\\stata\\send-to-stata.ps1\" -Statement -Stdin -File \"$ZED_FILE\" -Row $ZED_ROW",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "never",
    "hide": "on_success"
}
```

### Keybinding Configuration

```json
{
    "context": "Editor && extension == do",
    "bindings": {
        "ctrl-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Send Statement"}]]],
        "shift-ctrl-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Send File"}]]],
        "alt-ctrl-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Include Statement"}]]],
        "alt-shift-ctrl-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Include File"}]]]
    }
}
```

Note: Windows uses `ctrl` instead of macOS `cmd`. The keybinding pattern matches macOS:
- macOS: `cmd-enter`, `shift-cmd-enter`, `alt-cmd-enter`, `alt-shift-cmd-enter`
- Windows: `ctrl-enter`, `shift-ctrl-enter`, `alt-ctrl-enter`, `alt-shift-ctrl-enter`



## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: STATA_PATH Override

*For any* value of the STATA_PATH environment variable pointing to a valid executable, the script SHALL use that path and skip auto-detection entirely, regardless of what Stata installations exist on the system.

**Validates: Requirements 1.3**

### Property 2: Stata Search Order

*For any* filesystem state with multiple Stata installations, the script SHALL return the first match when searching: versions 19→13, then paths (Program Files → Program Files (x86) → C:\), then variants (StataMP-64 → StataSE-64 → StataBE-64 → StataIC-64 → StataMP → StataSE → StataBE → StataIC), then fallback C:\Stata\.

**Validates: Requirements 1.1, 1.2, 1.5**

### Property 3: Multi-line Statement Detection

*For any* Stata file containing statements with continuation markers (`///`), and *for any* cursor position within a multi-line statement, the `Get-StatementAtRow` function SHALL return the complete statement including all continuation lines, with line breaks preserved.

**Validates: Requirements 2.3, 2.4, 2.5**

### Property 4: Stdin Content Round-Trip

*For any* text content (including compound strings with backticks and quotes), reading from stdin and writing to a temp file SHALL preserve the content exactly—the temp file content SHALL be byte-for-byte identical to the stdin input.

**Validates: Requirements 2.1, 2.6, 12.1, 12.2, 12.3**

### Property 5: File Content Round-Trip

*For any* source file, reading in file mode and writing to a temp file SHALL preserve all content exactly—including line breaks, whitespace, and special characters.

**Validates: Requirements 3.1, 3.2**

### Property 6: Command Format by Mode

*For any* temp file path, the generated Stata command SHALL be `do "{path}"` when Include mode is false, and `include "{path}"` when Include mode is true.

**Validates: Requirements 4.1, 4.2, 4.3**

### Property 7: Temp File Characteristics

*For any* temp file created by the script, the file SHALL: (a) be located in the system temp directory, (b) have a `.do` extension, and (c) have a unique filename that does not collide with existing files.

**Validates: Requirements 6.1, 6.2**

### Property 8: Config File Preservation

*For any* existing tasks.json or keymap.json containing non-Stata entries, running the installer SHALL preserve all non-Stata entries while adding/updating only Stata-related entries.

**Validates: Requirements 7.5, 7.6**

### Property 9: Checksum Verification

*For any* web installation from the main branch, the installer SHALL verify the SHA-256 checksum of the downloaded send-to-stata.ps1 against the embedded expected value, and SHALL fail if they do not match.

**Validates: Requirements 7.10**

## Error Handling

### Exit Code Strategy

The script uses consistent exit codes matching the macOS implementation:

| Exit Code | Condition | Error Message |
|-----------|-----------|---------------|
| 0 | Success | (none) |
| 1 | Invalid arguments | "Error: {specific issue}" |
| 2 | File not found/unreadable | "Error: Cannot read file: {path}" |
| 3 | Temp file creation failed | "Error: Cannot create temp file" |
| 4 | Stata not found | "Error: No Stata installation found" or "Error: No running Stata instance found" |
| 5 | SendKeys execution failed | "Error: Failed to send keystrokes to Stata" |

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
# Installation detection
$stataPath = Find-StataInstallation
if (-not $stataPath) {
    Write-Error "Error: No Stata installation found"
    Write-Error "Set STATA_PATH environment variable or install Stata"
    exit 4
}

# Running instance detection
$stataWindow = Find-StataWindow
if (-not $stataWindow) {
    Write-Error "Error: No running Stata instance found"
    Write-Error "Start Stata before sending code"
    exit 4
}
```

**SendKeys Execution**
```powershell
try {
    # Activate window and send keystrokes
    [Win32]::SetForegroundWindow($stataWindow.MainWindowHandle)
    Start-Sleep -Milliseconds 100
    [System.Windows.Forms.SendKeys]::SendWait("^v")  # Ctrl+V
    Start-Sleep -Milliseconds 50
    [System.Windows.Forms.SendKeys]::SendWait("^d")  # Ctrl+D
} catch {
    Write-Error "Error: Failed to send keystrokes to Stata: $_"
    exit 5
}
```

### Timing and Reliability

SendKeys requires careful timing to ensure reliable execution:

1. **Window Activation Delay**: 100ms after `SetForegroundWindow` before sending keys
2. **Inter-Key Delay**: 50ms between Ctrl+V and Ctrl+D
3. **Configurable via Environment**: `$env:STATA_SENDKEYS_DELAY` can override defaults

```powershell
$activationDelay = [int]($env:STATA_ACTIVATION_DELAY ?? 100)
$interKeyDelay = [int]($env:STATA_INTERKEY_DELAY ?? 50)
```

## Testing Strategy

### Dual Testing Approach

This feature requires both unit tests and property-based tests:

- **Unit tests**: Verify specific examples, edge cases, and error conditions
- **Property tests**: Verify universal properties across generated inputs

### Property-Based Testing Framework

Use **Pester** with custom generators for property-based testing in PowerShell:

```powershell
# Example property test structure
Describe "Statement Detection Properties" {
    It "Property 3: Multi-line statement detection - detects complete statement from any position" -Tag "Feature: send-to-stata-windows, Property 3: Multi-line Statement Detection" {
        # Generate random Stata files with continuation markers
        # For each cursor position within a multi-line statement
        # Verify complete statement is returned
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

### Test Categories

**Unit Tests (Specific Examples)**
- Argument parsing with valid/invalid inputs
- Exit codes for each error condition
- Stata path detection with mocked filesystem
- Window title matching patterns

**Property Tests (Universal Properties)**
- Property 1: STATA_PATH override behavior
- Property 2: Search order correctness
- Property 3: Multi-line statement detection
- Property 4: Stdin content round-trip
- Property 5: File content round-trip
- Property 6: Command format by mode
- Property 7: Temp file characteristics
- Property 8: Config file preservation
- Property 9: Checksum verification

**Integration Tests**
- End-to-end flow with mocked Stata window
- Installer creates correct file structure
- Uninstaller removes all components

### Test File Structure

```
tests/
├── send-to-stata.Tests.ps1      # Main script tests
├── install-send-to-stata.Tests.ps1  # Installer tests
├── Generators.ps1               # Random data generators
└── Mocks.ps1                    # Mock functions for Stata/filesystem
```

### Generator Examples

```powershell
# Generate random Stata file with continuation markers
function New-RandomStataFile {
    param([switch]$WithContinuations)
    
    $lines = @()
    $numStatements = Get-Random -Minimum 3 -Maximum 10
    
    for ($i = 0; $i -lt $numStatements; $i++) {
        if ($WithContinuations -and (Get-Random -Maximum 2) -eq 1) {
            # Multi-line statement
            $numLines = Get-Random -Minimum 2 -Maximum 5
            for ($j = 0; $j -lt $numLines - 1; $j++) {
                $lines += "$(New-RandomStataCode) ///"
            }
            $lines += New-RandomStataCode
        } else {
            $lines += New-RandomStataCode
        }
    }
    
    # Write to temp file and return info
    $path = [System.IO.Path]::GetTempFileName()
    $lines | Set-Content -Path $path
    return @{ Path = $path; Lines = $lines }
}

# Generate random compound string
function New-RandomCompoundString {
    $inner = -join ((65..90) + (97..122) | Get-Random -Count (Get-Random -Minimum 5 -Maximum 20) | ForEach-Object { [char]$_ })
    return '`"' + $inner + '"' + "'"
}
```

### Minimum Test Iterations

Each property test MUST run at least 100 iterations to ensure adequate coverage of the input space.

### Test Tagging

Each property test MUST include a tag referencing the design property:

```powershell
-Tag "Feature: send-to-stata-windows, Property N: {property_text}"
```
