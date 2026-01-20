# Design Document: Consistent Focus Behavior

## Overview

This design implements consistent focus behavior for the send-to-stata functionality across macOS and Windows platforms. The core change is to make both platforms default to keeping focus in Zed after sending code to Stata, with an opt-in `--activate-stata` flag to switch focus to Stata when desired.

### Current State

| Platform | Current Behavior | Mechanism |
|----------|------------------|-----------|
| macOS | Focus stays in Zed | `DoCommandAsync` doesn't activate Stata |
| Windows | Focus switches to Stata | `SetForegroundWindow` + `AcquireFocus` |

### Target State

| Platform | Default Behavior | With `--activate-stata` |
|----------|------------------|-------------------------|
| macOS | Focus stays in Zed | Focus switches to Stata |
| Windows | Focus stays in Zed | Focus switches to Stata |

## Architecture

The solution modifies three components (macOS script unchanged):

```
┌─────────────────────────────────────────────────────────────────┐
│                         Zed Editor                               │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ tasks.json                                               │    │
│  │  - Stata: Send Statement [+ osascript activate optional] │    │
│  │  - Stata: Send File [+ osascript activate optional]      │    │
│  │  - Stata: Include Statement [+ osascript activate opt.]  │    │
│  │  - Stata: Include File [+ osascript activate optional]   │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Platform Scripts                              │
│                                                                  │
│  macOS: send-to-stata.sh          Windows: send-to-stata.exe    │
│  ┌─────────────────────────┐      ┌─────────────────────────┐   │
│  │ (unchanged)             │      │ -ActivateStata flag     │   │
│  │ DoCommandAsync only     │      │ → Skip ReturnFocus      │   │
│  └─────────────────────────┘      └─────────────────────────┘   │
│           │                                                      │
│           ▼ (if activate configured in task)                    │
│  ┌─────────────────────────┐                                    │
│  │ osascript -e 'tell app  │                                    │
│  │ "StataXX" to activate'  │                                    │
│  └─────────────────────────┘                                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Stata Application                           │
│  Receives command via DoCommandAsync (macOS) or clipboard (Win)  │
└─────────────────────────────────────────────────────────────────┘
```

## Components and Interfaces

### 1. macOS Script (`send-to-stata.sh`) - No Changes

The script remains unchanged. The focus behavior is controlled entirely by the installer, which generates different task commands with different AppleScript content.

### 2. macOS Installer (`install-send-to-stata.sh`)

**Approach**: The installer generates task commands that embed the AppleScript directly, with or without the activation line based on user preference. This avoids modifying the script and keeps all configuration in the installer.

**New Parameters**:
- `--activate-stata`: Configure tasks to switch focus to Stata
- `--stay-in-zed`: Configure tasks to keep focus in Zed (default)

**Interactive Prompt**:
```
Focus behavior after sending code to Stata:
  [Y] Switch to Stata (see output immediately)
  [N] Stay in Zed (keep typing without switching windows)

Switch to Stata after sending code? [y/N]
```

**Task Command Variants**:

The installer currently generates tasks that call `send-to-stata.sh`, which internally uses AppleScript. Instead, for the activation case, the installer will generate tasks that:
1. Call `send-to-stata.sh` to send the code
2. Then call `osascript` to activate Stata (as a separate command in the same task)

Default (stay in Zed) - unchanged:
```bash
"command": "send-to-stata.sh --statement --file \"$ZED_FILE\" --row \"$ZED_ROW\""
```

With Stata activation - adds activation after script:
```bash
"command": "send-to-stata.sh --statement --file \"$ZED_FILE\" --row \"$ZED_ROW\" && osascript -e 'tell application \"StataMP\" to activate'"
```

The installer detects the Stata variant and substitutes the correct application name (StataMP, StataSE, StataIC, or Stata).

**Note**: While this spawns a second `osascript` process, the overhead is minimal (~10ms) and keeps the script unchanged.

### 2. Windows Executable (`SendToStata.cs`)

**New Flag**: `-ActivateStata`

**Interface Changes**:
```csharp
// New parameter (replaces -ReturnFocus as default behavior)
bool activateStata = false;

// Argument parsing
case "-activatestata":
    activateStata = true;
    break;
```

**Behavior Change**:
- Default: Return focus to Zed (current `-ReturnFocus` behavior becomes default)
- With `-ActivateStata`: Do NOT return focus to Zed (current default behavior)

**Backward Compatibility**:
- `-ReturnFocus` flag continues to work but is now a no-op (default behavior)
- Deprecation warning printed to stderr when `-ReturnFocus` is used

### 3. macOS Installer (`install-send-to-stata.sh`) - Task Generation Details

**Task Generation Logic**:
```bash
# Detect Stata variant first
STATA_APP_NAME=$(detect_stata_app)  # Returns StataMP, StataSE, etc.

# If user selects "Yes" or --activate-stata flag provided
if [[ "$ACTIVATE_STATA_PREF" == true ]]; then
    ACTIVATE_SUFFIX=" && osascript -e 'tell application \"${STATA_APP_NAME}\" to activate'"
else
    ACTIVATE_SUFFIX=""
fi

# Task command includes activation suffix conditionally
"command": "send-to-stata.sh --statement --file \"$ZED_FILE\" --row \"$ZED_ROW\"${ACTIVATE_SUFFIX}"
```

### 4. Windows Installer (`install-send-to-stata.ps1`)

**Parameter Changes**:
- New: `-ActivateStata` parameter (accepts `true`/`false`)
- Existing: `-ReturnFocus` deprecated but still functional (now a no-op)

**Interactive Prompt** (actual implementation):
```
Focus behavior after sending code to Stata:
  [Y] Return focus to Zed (keep typing without switching windows)
  [N] Stay in Stata (ensures you see output, even if Zed is fullscreen)

Return focus to Zed after sending code to Stata? [Y/n]
```

Note: The Windows prompt uses inverted logic compared to macOS—answering "n" (stay in Stata) results in `-ActivateStata` being added to task commands.

**Task Generation**:
```powershell
# If user answers "n" (stay in Stata) or -ActivateStata true
$activateArg = if ($UseActivateStata) { " -ActivateStata" } else { "" }

# Task command includes flag conditionally
command = "& `"$exePath`" -Statement$activateArg -File `"`$ZED_FILE`" -Row `$ZED_ROW"
```

## Data Models

### Command-Line Arguments

**macOS Script Arguments** (unchanged):

| Argument | Type | Default | Description |
|----------|------|---------|-------------|
| `--statement` | flag | - | Send current statement mode |
| `--file-mode` | flag | - | Send entire file mode |
| `--include` | flag | false | Use `include` instead of `do` |
| `--file` | string | required | Source file path |
| `--row` | integer | - | Cursor row (1-indexed) |
| `--stdin` | flag | false | Read text from stdin |
| `--text` | string | - | Selected text |

**Windows Executable Arguments**:

| Argument | Type | Default | Description |
|----------|------|---------|-------------|
| `-ActivateStata` | flag | false | Switch focus to Stata (skip return focus) |
| `-ReturnFocus` | flag | false | (Deprecated) Return focus to Zed |
| `-Statement` | flag | - | Send current statement mode |
| `-FileMode` | flag | - | Send entire file mode |
| `-Include` | flag | false | Use `include` instead of `do` |
| `-File` | string | required | Source file path |
| `-Row` | integer | - | Cursor row (1-indexed) |

### Installer Parameters

**macOS Installer**:

| Parameter | Type | Description |
|-----------|------|-------------|
| `--activate-stata` | flag | Configure tasks to switch focus to Stata |
| `--stay-in-zed` | flag | Configure tasks to keep focus in Zed |
| `--uninstall` | flag | Remove installed components |
| `--quiet` | flag | Suppress output |

**Windows Installer**:

| Parameter | Type | Description |
|-----------|------|-------------|
| `-ActivateStata` | string | `true`/`false` - Configure focus behavior |
| `-ReturnFocus` | string | (Deprecated) `true`/`false` - Legacy parameter |
| `-Uninstall` | switch | Remove installed components |
| `-RegisterAutomation` | switch | Force Stata automation registration |
| `-SkipAutomationCheck` | switch | Skip automation check |



## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: macOS Task Command Activation Suffix

*For any* macOS installer execution with a focus preference, the generated task commands in `tasks.json` SHALL include `&& osascript -e 'tell application "StataXX" to activate'` if and only if the user selected "switch to Stata" behavior.

#### Validates

Requirements 1.1, 2.1, 5.4, 5.5, 6.1, 6.2

### Property 2: Windows Flag Precedence

*For any* invocation of `send-to-stata.exe` where both `-ActivateStata` and `-ReturnFocus` flags are provided, the behavior SHALL be equivalent to providing only `-ActivateStata` (focus stays in Stata).

#### Validates

Requirements 4.4

### Property 3: Windows Backward Compatibility

*For any* invocation of `send-to-stata.exe` with the `-ReturnFocus` flag (without `-ActivateStata`), the executable SHALL not produce an error and SHALL behave as if no focus-related flags were provided (default behavior: return focus to Zed).

#### Validates

Requirements 4.3

### Property 4: Windows Task Command Generation

*For any* Windows installer execution with a focus preference, the generated task commands in `tasks.json` SHALL include `-ActivateStata` if and only if the user selected "switch to Stata" behavior.

#### Validates

Requirements 5.4, 5.5, 6.3, 6.4

### Property 5: Installer Stata Variant Detection

*For any* macOS installer execution with "switch to Stata" preference, the generated activation command SHALL use the correct Stata application name as detected by the installer (StataMP, StataSE, StataIC, or Stata).

#### Validates

Requirements 2.1, 3.3

## Error Handling

### macOS Installer Errors

| Error Condition | Behavior |
|-----------------|----------|
| Both `--activate-stata` and `--stay-in-zed` | Print error, exit 1 |
| tasks.json parse failure | Overwrite with new tasks (existing behavior) |
| Stata not detected | Warning, continue (activation command will use fallback name) |

### Windows Executable Errors

| Error Condition | Exit Code | Behavior |
|-----------------|-----------|----------|
| Both `-ActivateStata` and `-ReturnFocus` | 0 | Warning to stderr, `-ActivateStata` takes precedence |
| `-ReturnFocus` alone | 0 | Deprecation warning to stderr, continue |
| Focus return fails | 0 | Silent failure (code already sent successfully) |

### Windows Installer Errors

| Error Condition | Behavior |
|-----------------|----------|
| Invalid `-ActivateStata` value | Print error, exit 1 |
| tasks.json parse failure | Overwrite with new tasks (existing behavior) |

## Testing Strategy

### Unit Tests

Unit tests focus on specific examples and edge cases:

1. **macOS Installer Task Generation Tests**
   - Verify tasks.json contains `&& osascript -e 'tell application ... to activate'` when `--activate-stata` flag provided
   - Verify tasks.json does NOT contain activation suffix when `--stay-in-zed` or default
   - Verify correct Stata variant name is used in activation command

2. **Windows Argument Parsing Tests**
   - Verify `-ActivateStata` sets `activateStata=true`
   - Verify `-ReturnFocus` prints deprecation warning
   - Verify default behavior (no flags) returns focus to Zed

3. **Windows Flag Precedence Tests**
   - Verify `-ActivateStata` overrides `-ReturnFocus`
   - Verify order independence (`-ReturnFocus -ActivateStata` same as `-ActivateStata -ReturnFocus`)

4. **Windows Installer Task Generation Tests**
   - Verify tasks.json contains `-ActivateStata` when configured
   - Verify tasks.json does NOT contain `-ActivateStata` when not configured

### Property-Based Tests

Property tests verify universal properties across all inputs. Each test runs minimum 100 iterations.

**Test Configuration**: Use shell script testing framework (bats) for macOS installer, NUnit/xUnit for Windows C#.

1. **Property Test: macOS Task Command Activation Suffix**
   - **Feature: consistent-focus-behavior, Property 1: macOS Task Command Activation Suffix**
   - Generate installer invocations with various focus preferences
   - Verify generated tasks.json matches expected activation suffix presence

2. **Property Test: Windows Flag Precedence**
   - **Feature: consistent-focus-behavior, Property 2: Windows Flag Precedence**
   - Generate all combinations of `-ActivateStata` and `-ReturnFocus`
   - Verify behavior matches `-ActivateStata` when both present

3. **Property Test: Windows Backward Compatibility**
   - **Feature: consistent-focus-behavior, Property 3: Windows Backward Compatibility**
   - Generate invocations with `-ReturnFocus` flag
   - Verify no errors and default behavior applies

4. **Property Test: Windows Task Command Generation**
   - **Feature: consistent-focus-behavior, Property 4: Windows Task Command Generation**
   - Generate installer invocations with various focus preferences
   - Verify generated tasks.json matches expected flag presence

5. **Property Test: Installer Stata Variant Detection**
   - **Feature: consistent-focus-behavior, Property 5: Installer Stata Variant Detection**
   - Generate installer invocations with different Stata installations
   - Verify activation command uses correct application name

### Integration Tests

Manual integration tests (not automated):

1. **macOS Focus Behavior**
   - Install without `--activate-stata`: Send code, verify Zed keeps focus
   - Install with `--activate-stata`: Send code, verify Stata gets focus

2. **Windows Focus Behavior**
   - Install without `-ActivateStata true`: Send code, verify Zed gets focus back
   - Install with `-ActivateStata true`: Send code, verify Stata keeps focus

3. **Cross-Platform Consistency**
   - Verify both platforms behave identically with same logical configuration
