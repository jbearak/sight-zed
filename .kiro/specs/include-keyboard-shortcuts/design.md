# Design Document: Include Keyboard Shortcuts

## Overview

This feature extends the send-to-stata functionality to support Stata's `include` command as an alternative to `do`. The key difference is local macro scoping: `do` isolates locals to the executed file, while `include` preserves them in the calling context—essential for interactive debugging.

The implementation requires:
1. Adding an `--include` flag to `send-to-stata.sh`
2. Creating two new Zed tasks that mirror existing tasks but use `include`
3. Adding keybindings for the new tasks
4. Updating documentation

## Architecture

The architecture follows the existing pattern with minimal changes:

```
┌─────────────────────────────────────────────────────────────────┐
│                         Zed Editor                               │
├─────────────────────────────────────────────────────────────────┤
│  Keybindings (keymap.json)                                       │
│  ┌─────────────────┐  ┌─────────────────┐                       │
│  │ cmd-enter       │  │ alt-cmd-enter   │  ← NEW                │
│  │ shift-cmd-enter │  │ alt-shift-cmd-  │  ← NEW                │
│  │                 │  │ enter           │                       │
│  └────────┬────────┘  └────────┬────────┘                       │
│           │                    │                                 │
│  Tasks (tasks.json)            │                                 │
│  ┌─────────────────┐  ┌────────┴────────┐                       │
│  │ Send Statement  │  │ Include Statement│ ← NEW                │
│  │ Send File       │  │ Include File     │ ← NEW                │
│  └────────┬────────┘  └────────┬────────┘                       │
└───────────┼────────────────────┼────────────────────────────────┘
            │                    │
            ▼                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    send-to-stata.sh                              │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Argument Parsing                                             ││
│  │ - --statement / --file (mode)                                ││
│  │ - --include (NEW: command type flag)                         ││
│  └─────────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ AppleScript Generation                                       ││
│  │ - do "filepath"     (default)                                ││
│  │ - include "filepath" (when --include)                        ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Stata GUI (via AppleScript)                   │
└─────────────────────────────────────────────────────────────────┘
```

## Components and Interfaces

### 1. send-to-stata.sh Modifications

**New Flag**: `--include`

```bash
# New global variable
INCLUDE_MODE=false

# In parse_arguments(), add case:
--include)
    INCLUDE_MODE=true
    shift
    ;;

# In send_to_stata(), modify command generation:
local stata_cmd
if [[ "$INCLUDE_MODE" == true ]]; then
    stata_cmd="include"
else
    stata_cmd="do"
fi
local applescript_cmd="tell application \"${stata_app}\" to DoCommandAsync \"${stata_cmd} \\\"${escaped_path}\\\"\""
```

**Interface Changes**:
- Input: New optional `--include` flag
- Output: AppleScript command uses `include` instead of `do` when flag is present
- No changes to exit codes or error handling

### 2. Zed Task Definitions

Two new tasks mirror the existing tasks with `--include` flag added:

```json
{
  "label": "Stata: Include Statement",
  "command": "python3 -c 'import os,sys; sys.exit(0 if os.environ.get(\"ZED_SELECTED_TEXT\", \"\") else 1)' && python3 -c 'import os,sys; sys.stdout.write(os.environ.get(\"ZED_SELECTED_TEXT\", \"\"))' | send-to-stata.sh --statement --include --stdin --file \"$ZED_FILE\" || send-to-stata.sh --statement --include --file \"$ZED_FILE\" --row \"$ZED_ROW\"",
  "use_new_terminal": false,
  "allow_concurrent_runs": true,
  "reveal": "never",
  "hide": "on_success"
}
```

```json
{
  "label": "Stata: Include File",
  "command": "send-to-stata.sh --file --include --file \"$ZED_FILE\"",
  "use_new_terminal": false,
  "allow_concurrent_runs": true,
  "reveal": "never",
  "hide": "on_success"
}
```

### 3. Keybinding Definitions

New keybindings in the same context as existing ones:

```json
{
  "context": "Editor && extension == do",
  "bindings": {
    "cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Send Statement"}]]],
    "shift-cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Send File"}]]],
    "alt-cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Include Statement"}]]],
    "alt-shift-cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Include File"}]]]
  }
}
```

### 4. Installer Script Modifications

The `install-send-to-stata.sh` script needs updates to:

1. **STATA_TASKS variable**: Add the two new task definitions
2. **install_keybindings()**: Add the two new keybindings
3. **uninstall()**: No changes needed—existing logic removes all `Stata:` prefixed tasks and `extension == do` keybindings
4. **print_summary()**: Update to show all four keybindings

## Data Models

No new data models are required. The feature uses existing structures:

- **Task JSON schema**: Standard Zed task format with `label`, `command`, `use_new_terminal`, `allow_concurrent_runs`, `reveal`, `hide`
- **Keybinding JSON schema**: Standard Zed keymap format with `context` and `bindings`
- **Script arguments**: Simple boolean flag (`--include`) added to existing argument set



## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

Based on the prework analysis, most acceptance criteria are examples (specific verifications of installer output or documentation content) rather than universal properties. The script behavior yields two testable properties:

### Property 1: Include Flag Determines Command Type

*For any* valid file path and mode (statement or file), when `send-to-stata.sh` is invoked with the `--include` flag, the generated AppleScript command SHALL contain `include` as the Stata command; when invoked without `--include`, it SHALL contain `do`.

**Validates: Requirements 1.1, 1.2**

### Property 2: Include Flag Compatible with Both Modes

*For any* valid file path, the `--include` flag SHALL be accepted without error when combined with either `--statement` mode or `--file` mode.

**Validates: Requirements 1.3**

### Non-Property Acceptance Criteria

The following acceptance criteria are testable as examples rather than properties:

- **1.4**: Help text includes `--include` documentation (single example check)
- **2.1-2.4**: Installer creates specific tasks with correct structure (example checks)
- **3.1-3.3, 3.5**: Installer creates/removes specific keybindings (example checks)
- **4.1-4.5**: Documentation contains specific content (example checks)

## Error Handling

The feature introduces minimal new error conditions:

| Scenario | Handling | Exit Code |
|----------|----------|-----------|
| `--include` with invalid mode | Existing validation rejects | 1 |
| `--include` without required args | Existing validation rejects | 1 |
| `--include` with `--help` | Shows updated help text | 0 |

No new exit codes are needed. The `--include` flag is purely additive and doesn't introduce new failure modes.

## Testing Strategy

### Unit Tests (Examples)

Unit tests verify specific examples and installer output:

1. **Script argument parsing**:
   - `--include` flag is recognized
   - `--include` works with `--statement`
   - `--include` works with `--file`
   - `--help` output includes `--include` documentation

2. **Installer output verification**:
   - tasks.json contains "Stata: Include Statement" task
   - tasks.json contains "Stata: Include File" task
   - Include tasks have `--include` flag in command
   - keymap.json contains `alt-cmd-enter` binding
   - keymap.json contains `alt-shift-cmd-enter` binding
   - Keybindings use `action::Sequence` with `workspace::Save`
   - Uninstall removes all Stata keybindings

3. **Documentation verification**:
   - SEND-TO-STATA.md lists all four keybindings
   - SEND-TO-STATA.md explains do vs include
   - README.md references send-to-stata
   - AGENTS.md includes keybinding reference

### Property-Based Tests

Property tests verify universal properties across generated inputs:

1. **Property 1: Include Flag Determines Command Type**
   - Generate random valid file paths
   - For each path, invoke script with and without `--include`
   - Verify command type matches flag presence
   - **Feature: include-keyboard-shortcuts, Property 1: Include flag determines command type**
   - Minimum 100 iterations

2. **Property 2: Include Flag Compatible with Both Modes**
   - Generate random valid file paths
   - For each path, invoke with `--include --statement` and `--include --file`
   - Verify no argument parsing errors
   - **Feature: include-keyboard-shortcuts, Property 2: Include flag compatible with both modes**
   - Minimum 100 iterations

### Test Configuration

- **Framework**: Shell script tests using `bats` or manual verification
- **Property testing**: Due to the simple nature of the properties (flag parsing), manual verification with representative inputs is acceptable
- **Coverage**: All acceptance criteria covered by either unit tests or property tests
