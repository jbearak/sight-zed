# Design Document: Robust Compound String Handling

## Overview

This design addresses the shell metacharacter problem when passing Stata code from Zed to the `send-to-stata.sh` script. The core issue is that command-line arguments are subject to shell interpretation, causing backticks (command substitution) and quotes to break the command structure.

The solution introduces a **stdin input mode** where selected text is piped to the script rather than passed as an argument. This bypasses shell interpretation entirely since piped data is not processed by the shell.

### Key Design Decisions

1. **Stdin over environment variables**: Environment variables still require shell escaping in some contexts. Stdin is the cleanest solution.
2. **Conditional stdin usage**: Only use stdin when there's selected text; fall back to `--row` when no selection exists.
3. **Backward compatibility**: The `--text` argument remains functional for simple cases or programmatic use.

## Architecture

```mermaid
flowchart TD
    subgraph Zed["Zed Editor"]
        A[User presses cmd-enter] --> B{Text selected?}
        B -->|Yes| C[Pipe selection to stdin]
        B -->|No| D[Pass --row argument]
    end
    
    subgraph Script["send-to-stata.sh"]
        C --> E[Read from stdin]
        D --> F[Detect statement from file]
        E --> G[Create temp .do file]
        F --> G
        G --> H[Send to Stata via AppleScript]
    end
    
    subgraph Stata["Stata GUI"]
        H --> I[Execute do-file]
    end
```

### Data Flow

1. **With selection (stdin mode)**:
   - Zed task must avoid inlining the selection into the zsh command string (backticks would be parsed as command substitution).
   - Implementation reads the environment at runtime and pipes to stdin:
     - `python3 -c 'import os,sys; sys.exit(0 if os.environ.get("ZED_SELECTED_TEXT", "") else 1)' && \
        python3 -c 'import os,sys; sys.stdout.write(os.environ.get("ZED_SELECTED_TEXT", ""))' \
        | send-to-stata.sh --statement --stdin --file "$ZED_FILE"`
   - Script streams stdin directly to a temp `.do` file, then sends to Stata.

2. **Without selection (row mode)**:
   - Zed task falls back via `||` to row-based detection:
     - `send-to-stata.sh --statement --file "$ZED_FILE" --row "$ZED_ROW"`

## Components and Interfaces

### Modified Components

#### 1. Argument Parser (`parse_arguments`)

**Changes**:
- Add `--stdin` flag recognition
- Track `STDIN_MODE` boolean variable
- Validate mutual exclusivity with `--text`

**Interface**:
```bash
# New global variable
STDIN_MODE=false

# Updated parse_arguments function
parse_arguments() {
    # ... existing code ...
    case "$1" in
        --stdin)
            STDIN_MODE=true
            shift
            ;;
        # ... existing cases ...
    esac
}
```

#### 2. Argument Validator (`validate_arguments`)

**Changes**:
- Check for `--stdin` and `--text` mutual exclusivity
- Allow `--stdin` as alternative to `--text` or `--row` in statement mode

**Interface**:
```bash
validate_arguments() {
    # Check mutual exclusivity
    if [[ "$STDIN_MODE" == true && -n "$TEXT" ]]; then
        echo "Error: --stdin and --text are mutually exclusive" >&2
        exit 1
    fi
    
    # For statement mode, need one of: --stdin, --text, or --row
    if [[ "$MODE" == "statement" ]]; then
        if [[ "$STDIN_MODE" != true && -z "$TEXT" && -z "$ROW" ]]; then
            echo "Error: --statement mode requires --stdin, --text, or --row" >&2
            exit 1
        fi
    fi
}
```

#### 3. Stdin Reader (New Function)

**Purpose**: Read arbitrary content from stdin without interpretation *and without losing trailing newlines*.

**Design note**: Command substitution (e.g., `content=$(cat)`) strips trailing newlines and cannot represent NUL bytes. For robustness and performance, stdin is streamed directly into the temp `.do` file.

**Interface**:
```bash
# Reads stdin and writes it to a file
# Arguments: out_file, max_bytes (0 = unlimited)
# Prints: number of bytes written
# Exit: 6 on read failure, 7 on size limit exceeded
read_stdin_to_file() {
    local out_file="$1"
    local max_bytes="$2"

    cat > "$out_file" || exit 6

    local byte_count
    byte_count=$(wc -c < "$out_file" | tr -d ' ')

    if [[ "$max_bytes" -gt 0 && "$byte_count" -gt "$max_bytes" ]]; then
        rm -f "$out_file"
        exit 7
    fi

    echo "$byte_count"
}
```

#### 4. Main Entry Point (`main`)

**Changes**:
- In `--statement` mode, stdin is written directly to the temp file when `--stdin` is set.
- Empty stdin triggers `--row` fallback.
- File mode copies the file contents to the temp file (avoids command substitution/newline loss).

**Interface (high level)**:
```bash
main() {
  # ... validation ...
  temp_file=$(create_temp_file_path)

  case "$MODE" in
    statement)
      if [[ "$STDIN_MODE" == true ]]; then
        byte_count=$(read_stdin_to_file "$temp_file" "$STATA_STDIN_MAX_BYTES")
        if [[ "$byte_count" -eq 0 ]]; then
          detect_statement "$FILE_PATH" "$ROW" > "$temp_file"
        fi
      elif [[ -n "$TEXT" ]]; then
        printf '%s' "$TEXT" > "$temp_file"
      else
        detect_statement "$FILE_PATH" "$ROW" > "$temp_file"
      fi
      ;;
    file)
      cat "$FILE_PATH" > "$temp_file"
      ;;
  esac

  send_to_stata "$STATA_APP_NAME" "$temp_file"
}
```

### New Exit Code

| Code | Meaning |
|------|---------|
| 6 | Stdin read failed |

### Zed Task Updates

#### Current Task (problematic)
```json
{
  "label": "Stata: Send Statement",
  "command": "send-to-stata.sh --statement --file \"$ZED_FILE\" --row \"$ZED_ROW\" --text \"${ZED_SELECTED_TEXT:}\""
}
```

#### New Task (robust)
```json
{
  "label": "Stata: Send Statement",
  "command": "python3 -c 'import os,sys; sys.exit(0 if os.environ.get(\\\"ZED_SELECTED_TEXT\\\", \\\"\\\") else 1)' && python3 -c 'import os,sys; sys.stdout.write(os.environ.get(\\\"ZED_SELECTED_TEXT\\\", \\\"\\\"))' | send-to-stata.sh --statement --stdin --file \"$ZED_FILE\" || send-to-stata.sh --statement --file \"$ZED_FILE\" --row \"$ZED_ROW\""
}
```

**Rationale**:
- Avoids inlining the selection into the zsh `-c` command string (backticks would be parsed as command substitution).
- Reads selection at runtime from the environment via `python3` and streams it through stdin.
- Uses `&&` / `||` instead of `if ... else` to keep quoting simpler.

## Data Models

### Input Modes

```
┌─────────────────────────────────────────────────────────────┐
│                    Input Mode Selection                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  --statement mode:                                           │
│    Priority: --stdin > --text > --row                        │
│                                                              │
│    1. If --stdin: read from stdin                            │
│       - If stdin non-empty: use stdin content                │
│       - If stdin empty AND --row: detect from file           │
│       - If stdin empty AND no --row: error                   │
│                                                              │
│    2. If --text: use text argument (legacy)                  │
│                                                              │
│    3. If --row: detect statement from file                   │
│                                                              │
│  --file mode:                                                │
│    Always reads entire file (unchanged)                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `MODE` | string | "statement" or "file" |
| `FILE_PATH` | string | Path to source .do file |
| `ROW` | integer | Cursor row (1-indexed) |
| `TEXT` | string | Text from --text argument |
| `STDIN_MODE` | boolean | Whether --stdin flag was provided |



## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Stdin Content Round-Trip Preservation

*For any* input string (including strings containing shell metacharacters like backticks, quotes, and dollar signs), piping the string to the script via stdin with `--stdin` flag SHALL result in a temp file containing the exact same byte sequence.

**Validates: Requirements 1.1, 1.2, 1.3, 4.1, 4.2, 4.3**

**Rationale**: This is the core property that ensures compound strings and other special characters are preserved. By testing with randomly generated strings containing various metacharacters, we verify the stdin mechanism bypasses shell interpretation entirely.

### Property 2: Backward Compatibility with --text

*For any* input string passed via the `--text` argument (without `--stdin`), the script SHALL produce the same temp file content as the current implementation.

**Validates: Requirements 2.1, 2.2**

**Rationale**: Existing workflows using `--text` must continue to work. This property ensures we don't break backward compatibility.

## Error Handling

### Error Conditions

| Condition | Exit Code | Message |
|-----------|-----------|---------|
| `--stdin` and `--text` both provided | 1 | "Error: --stdin and --text are mutually exclusive" |
| Stdin empty and no `--row` provided | 1 | "Error: stdin is empty and no --row provided" |
| Stdin read failure | 6 | "Error: Failed to read from stdin" |

### Error Handling Strategy

1. **Argument validation**: Check for mutually exclusive options before any I/O operations
2. **Stdin validation**: After reading stdin, check if content is empty and handle fallback
3. **Cleanup**: The existing temp file creation handles cleanup on failure

## Testing Strategy

### Dual Testing Approach

This feature requires both unit tests and property-based tests:

- **Unit tests**: Verify specific examples, edge cases, and error conditions
- **Property tests**: Verify universal properties across randomly generated inputs

### Unit Tests

1. **Argument parsing tests**:
   - `--stdin` flag is recognized
   - `--stdin` and `--text` mutual exclusivity error
   - `--stdin` with `--row` fallback when stdin empty

2. **Integration tests**:
   - Stdin mode with simple content
   - Stdin mode with compound strings (`` `"test"' ``)
   - Stdin mode with various metacharacters

### Property-Based Tests

Property tests will use the existing BATS framework with randomized inputs.

**Configuration**:
- Minimum 100 iterations per property test
- Each test tagged with: **Feature: robust-compound-strings, Property N: [description]**

**Property 1 Test Strategy**:
- Generate random strings containing:
  - Backticks (`` ` ``)
  - Single quotes (`'`)
  - Double quotes (`"`)
  - Dollar signs (`$`)
  - Backslashes (`\`)
  - Newlines
  - Compound string patterns (`` `"..."' ``)
- Pipe to script with `--stdin`
- Verify temp file content matches input exactly

**Property 2 Test Strategy**:
- Generate random strings (simple ASCII, no metacharacters)
- Pass via `--text` argument
- Verify temp file content matches input
- Compare behavior with and without `--stdin` available

### Test File Organization

```
tests/
├── send_to_stata.bats           # Add stdin unit tests
├── send_to_stata_props.bats     # Add stdin property tests
└── fixtures/
    └── compound_strings.do      # New fixture with compound strings
```
