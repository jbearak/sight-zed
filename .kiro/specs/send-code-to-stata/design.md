# Design Document: Send Code to Stata

## Overview

This design specifies a shell script-based solution for sending Stata code from Zed editor to the Stata GUI application for execution. The implementation uses a single shell script (`send-to-stata.sh`) with mode arguments, integrated with Zed's task system and keybindings.

The architecture prioritizes simplicity and reliability:
- Single shell script handles both operations (send statement, send file)
- Zed tasks handle auto-save before invoking the script
- AppleScript communicates with Stata GUI on macOS
- Temporary files ensure safe execution even when source files are edited

**Note:** Terminal mode (sending to a terminal running Stata) was considered but removed because Zed tasks spawn new terminal instances rather than sending text to existing terminals.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Zed Editor                               │
│  ┌─────────────┐    ┌──────────────┐    ┌───────────────────┐   │
│  │  Keybinding │───▶│   Zed Task   │───▶│ Auto-save (when   │   │
│  │  (cmd-enter)│    │  Definition  │    │ no selection)     │   │
│  └─────────────┘    └──────────────┘    └───────────────────┘   │
│                            │                                     │
│                            │ $ZED_FILE, $ZED_ROW,               │
│                            │ $ZED_SELECTED_TEXT                  │
│                            ▼                                     │
└────────────────────────────┼────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    send-to-stata.sh                              │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Mode Router                                             │    │
│  │  --statement | --file                                    │    │
│  └─────────────────────────────────────────────────────────┘    │
│                            │                                     │
│         ┌──────────────────┼──────────────────┐                 │
│         ▼                  ▼                  ▼                  │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────────┐       │
│  │  Statement  │   │  Temp File  │   │  AppleScript    │       │
│  │  Detection  │   │  Creation   │   │  Execution      │       │
│  └─────────────┘   └─────────────┘   └─────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
                             │
                             ▼
              ┌─────────────────────────┐
              │      Stata GUI          │
              │  (via AppleScript)      │
              └─────────────────────────┘
```

## Components and Interfaces

### Component 1: Send Script (`send-to-stata.sh`)

The main script that handles all send-to-stata operations. Installed to `~/.local/bin/`.

**Interface:**
```bash
send-to-stata.sh <mode> [options]

Modes:
  --statement   Send current statement to Stata GUI
  --file        Send entire file to Stata GUI

Options:
  --file <path>     Source file path (required)
  --row <number>    Cursor row, 1-indexed (required for --statement without --text)
  --text <string>   Selected text (if provided, used instead of file/row)

Environment Variables:
  STATA_APP         Stata application name (StataMP, StataSE, StataIC, Stata)
```

**Exit Codes:**
- 0: Success
- 1: Invalid arguments
- 2: File not found or unreadable
- 3: Temp file creation failed
- 4: Stata not found or not running
- 5: AppleScript execution failed

**Stata Variant Detection:**

The script determines which Stata variant to use in this priority order:

1. **Environment variable**: If `STATA_APP` is set, use that value
   ```bash
   export STATA_APP="StataSE"  # Add to ~/.zshrc or ~/.bashrc
   ```

2. **Auto-detection**: If no env var, check `/Applications/Stata/` for installed variants in order:
   - `/Applications/Stata/StataMP.app` → `StataMP`
   - `/Applications/Stata/StataSE.app` → `StataSE`
   - `/Applications/Stata/StataIC.app` → `StataIC`
   - `/Applications/Stata/Stata.app` → `Stata`
   
   Uses the first one found.

3. **Error**: If no env var and no Stata found in `/Applications/`, exit with error.

**Auto-detection logic:**
```bash
detect_stata_app() {
    if [[ -n "$STATA_APP" ]]; then
        echo "$STATA_APP"
        return
    fi
    
    for app in StataMP StataSE StataIC Stata; do
        if [[ -d "/Applications/Stata/${app}.app" ]]; then
            echo "$app"
            return
        fi
    done
    
    echo "Error: No Stata installation found in /Applications/Stata/" >&2
    echo "Set STATA_APP environment variable or install Stata" >&2
    exit 4
}
```

### Component 2: Statement Detection Module

A function within the shell script that extracts the current statement.

**Algorithm:**
```
Input: file_path, row_number (1-indexed)
Output: statement_text

1. Read file into array of lines
2. Find statement boundaries:
   a. Search backwards from row to find statement start
      - Stop when line doesn't end with /// AND previous line doesn't end with ///
   b. Search forwards from row to find statement end
      - Stop when line doesn't end with ///
3. Extract lines from start to end
4. Return joined statement (preserving line breaks)
```

**Continuation Marker Rules:**
- `///` at end of line (ignoring trailing whitespace) indicates continuation
- The marker must be outside strings and comments
- For simplicity, we use a regex pattern: `///[[:space:]]*$`

### Component 3: Temp File Manager

Creates unique temporary files for Stata execution.

**Behavior:**
- Creates files in `$TMPDIR` (falls back to `/tmp`)
- Uses pattern: `stata_send_XXXXXX.do` (mktemp)
- Does NOT delete files (Stata needs time to read them)
- Files accumulate and require periodic manual cleanup

### Component 4: AppleScript Executor

Sends commands to Stata GUI via osascript.

**AppleScript Template:**
```applescript
tell application "{STATA_APP}" to DoCommandAsync "do \"{TEMP_FILE_PATH}\""
```

**Escaping Rules:**
- Backslashes: `\` → `\\`
- Double quotes: `"` → `\"`
- These apply to the temp file path (content is in the file, not the command)

### Component 5: Installation Script (`install-send-to-stata.sh`)

A shell script that automates the installation process. Users clone the repo and run:

```bash
git clone https://github.com/jbearak/sight
cd sight
./install-send-to-stata.sh
```

**Installer Behavior:**

1. **Check prerequisites**:
   - Verify macOS (required for AppleScript)
   - Check if `jq` is installed (for JSON manipulation)
   - If `jq` not found, offer to install via Homebrew or provide manual instructions

2. **Install the shell script**:
   - Copy `send-to-stata.sh` to `~/.local/bin/` (create dir if needed)
   - Make it executable
   - Check if `~/.local/bin` is in PATH, warn if not

3. **Install Zed tasks**:
   - Read existing `~/.config/zed/tasks.json` (or create empty array if doesn't exist)
   - Merge in the Stata tasks (avoid duplicates by checking label)
   - Write back the updated JSON

4. **Install keybindings**:
   - Read existing `~/.config/zed/keymap.json` (or create empty array if doesn't exist)
   - Merge in the Stata keybindings (check for context match to avoid duplicates)
   - Write back the updated JSON

5. **Detect Stata**:
   - Check `/Applications/Stata/` for installed variants
   - Report which variant was found
   - If none found, warn user but continue (they may install Stata later)

6. **Print summary**:
   - List what was installed
   - Show the keybindings
   - Remind about PATH if needed

**JSON Manipulation with `jq`:**

```bash
# Merge tasks into existing tasks.json
merge_tasks() {
    local tasks_file="$HOME/.config/zed/tasks.json"
    local new_tasks='[...task definitions...]'
    
    if [[ ! -f "$tasks_file" ]]; then
        echo "$new_tasks" > "$tasks_file"
        return
    fi
    
    # Remove existing Stata tasks, then add new ones
    jq --argjson new "$new_tasks" '
        [.[] | select(.label | startswith("Stata:") | not)] + $new
    ' "$tasks_file" > "${tasks_file}.tmp" && mv "${tasks_file}.tmp" "$tasks_file"
}
```

**Uninstall Option:**

The script also supports `--uninstall` to remove the components:
```bash
./install-send-to-stata.sh --uninstall
```

### Component 6: Zed Task Definitions

Installed to `~/.config/zed/tasks.json` by the installer:

```json
[
  {
    "label": "Stata: Send Statement",
    "command": "send-to-stata.sh",
    "args": ["--statement", "--file", "$ZED_FILE", "--row", "$ZED_ROW", "--text", "$ZED_SELECTED_TEXT"],
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "never"
  },
  {
    "label": "Stata: Send File",
    "command": "send-to-stata.sh",
    "args": ["--file", "--file", "$ZED_FILE"],
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "never"
  }
]
```

**Task Behavior:**
- `reveal: "never"` - Don't show terminal panel (AppleScript runs silently)
- `allow_concurrent_runs: true` - Allow rapid repeated sends
- `use_new_terminal: false` - Reuse same terminal instance

### Component 7: Keybinding Configuration

Installed to `~/.config/zed/keymap.json` by the installer:

```json
[
  {
    "context": "Editor && extension == do",
    "bindings": {
      "cmd-enter": ["task::Spawn", { "task_name": "Stata: Send Statement" }],
      "shift-cmd-enter": ["task::Spawn", { "task_name": "Stata: Send File" }]
    }
  }
]
```

**Keybinding Summary:**
| Shortcut | Action |
|----------|--------|
| `cmd-enter` | Send current statement (or selection) to Stata |
| `shift-cmd-enter` | Send entire file to Stata |

### Component 8: Documentation File (`SEND-TO-STATA.md`)

A markdown file in the extension repository root that provides:

1. **Prerequisites**: macOS, Stata installed, Zed editor
2. **Quick Start**: One-command installation via `./install-send-to-stata.sh`
3. **Manual Installation**: Step-by-step for users who prefer manual setup
4. **Configuration**: How to override Stata variant with `STATA_APP` env var
5. **Keybindings Reference**: Table of shortcuts
6. **Troubleshooting**: Common issues and solutions
7. **Uninstallation**: How to remove with `./install-send-to-stata.sh --uninstall`
8. **Temp File Cleanup**: How to clean up accumulated temp files

## Data Models

### Statement Boundaries

```
StatementBounds {
  start_line: integer  // 1-indexed, inclusive
  end_line: integer    // 1-indexed, inclusive
}
```

### Script Arguments (parsed)

```
Arguments {
  mode: enum { statement, file }
  file_path: string
  row: integer | null       // 1-indexed, for statement mode
  selected_text: string | null
}
```

### Execution Result

```
Result {
  success: boolean
  error_code: integer       // 0-5
  error_message: string | null
  temp_file_path: string | null
}
```



## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Statement Detection with Continuations

*For any* Stata file and any cursor row within that file, the extracted statement SHALL include:
- The line at the cursor position
- All preceding lines that are part of the same statement (backward search for continuation)
- All following lines that are continuations (forward search for `///`)

The statement boundaries are correctly identified when:
- Starting from a line ending with `///`, all continuation lines are included
- Starting from a continuation line, the statement start is found by searching backwards
- Chained continuations (multiple consecutive `///` lines) are fully captured

**Validates: Requirements 1.2, 1.3, 1.4, 4.1, 4.3, 4.4, 4.5**

### Property 2: Selected Text Passthrough

*For any* non-empty selected text string, when the script is invoked with `--text` argument, the script SHALL use that text directly without reading from the file, and the resulting temp file SHALL contain exactly the selected text.

**Validates: Requirements 1.1**

### Property 3: File Content Preservation

*For any* valid Stata file, when the script is invoked in file mode, the temp file SHALL contain the exact contents of the source file, preserving:
- All characters including special characters (unicode, backslashes, quotes)
- Line endings
- Empty lines

**Validates: Requirements 2.1, 2.5**

### Property 4: Temp File Creation

*For any* script invocation (all modes), the script SHALL:
- Create a temp file in `$TMPDIR` (or `/tmp` if not set)
- Use a unique filename matching pattern `stata_send_*.do`
- Leave the temp file in place after script completion (not delete it)
- Create a new unique file for each invocation (no filename collisions)

**Validates: Requirements 1.5, 2.2, 8.1, 8.2, 8.3**

### Property 5: AppleScript Path Escaping

*For any* temp file path containing special characters (backslashes, double quotes, spaces), the generated AppleScript command SHALL properly escape these characters so that osascript can parse and execute the command.

Escaping rules:
- `\` → `\\`
- `"` → `\"`

**Validates: Requirements 1.7**

### Property 6: Stata Application Configuration

*For any* Stata application name (StataMP, StataSE, StataIC, Stata):
- When configured via `STATA_APP` environment variable, the script SHALL use that value
- When no env var is set, the script SHALL auto-detect by checking `/Applications/Stata/` for installed variants
- The generated AppleScript SHALL use the determined application name in the `tell application` command

**Validates: Requirements 3.1, 3.2, 3.3**

## Error Handling

### Error Categories and Exit Codes

| Exit Code | Category | Condition | Message Format |
|-----------|----------|-----------|----------------|
| 0 | Success | Operation completed | (no message) |
| 1 | Invalid Arguments | Missing required args, unknown mode | `Error: <specific issue>` |
| 2 | File Error | File not found, not readable | `Error: Cannot read file: <path>` |
| 3 | Temp File Error | Cannot create temp file | `Error: Cannot create temp file` |
| 4 | Stata Not Found | No Stata installation found | `Error: No Stata installation found` |
| 5 | AppleScript Error | osascript failed | `Error: AppleScript failed: <details>` |

### Error Detection Strategy

**File Errors:**
```bash
if [[ ! -f "$file_path" ]]; then
    echo "Error: Cannot read file: $file_path" >&2
    exit 2
fi
```

**Stata Detection:**
```bash
# Auto-detection handles this - exits with code 4 if not found
stata_app=$(detect_stata_app)
```

**AppleScript Execution:**
```bash
if ! osascript -e "$applescript_cmd" 2>&1; then
    echo "Error: AppleScript failed" >&2
    exit 5
fi
```

### Error Output

All error messages are written to stderr.

## Testing Strategy

### Unit Tests (BATS)

Unit tests verify specific examples and edge cases:

1. **Argument Parsing**
   - Valid mode arguments (`--statement`, `--file`)
   - Missing required arguments
   - Unknown arguments

2. **Statement Detection Edge Cases**
   - Single-line statement
   - Multi-line statement with `///`
   - Cursor on first line of continuation
   - Cursor on middle line of continuation
   - Cursor on last line of continuation
   - `///` inside string literal (should not be treated as continuation)
   - `///` inside comment (should not be treated as continuation)

3. **Error Conditions**
   - Non-existent file
   - Invalid row number (0, negative, beyond file length)
   - Empty file

4. **Escaping**
   - Path with spaces
   - Path with backslashes
   - Path with double quotes

5. **Stata Detection**
   - With STATA_APP env var set
   - Auto-detection with various app installations

### Property-Based Tests

Property tests verify universal properties across generated inputs. Since this is a shell script, we'll use BATS with generated test data.

**Test Configuration:**
- Minimum 100 iterations per property
- Random file generation with varying:
  - Number of lines (1-100)
  - Line lengths (0-500 chars)
  - Continuation marker placement
  - Special character inclusion

**Property Test Tags:**
Each property test will be tagged with:
```bash
# Feature: send-code-to-stata, Property N: <property description>
```

### Test File Structure

```
tests/
├── send_to_stata.bats           # Unit tests
├── send_to_stata_props.bats     # Property-based tests
└── fixtures/
    ├── simple.do                # Single-line statements
    ├── continuation.do          # Multi-line with ///
    ├── nested_continuation.do   # Chained ///
    ├── string_with_slashes.do   # /// inside strings
    └── special_chars.do         # Unicode, escapes
```

### Integration Tests

Integration tests require Stata to be installed. These are marked as optional and skipped in CI:

1. **End-to-end**: Verify command reaches Stata and executes (manual verification)
