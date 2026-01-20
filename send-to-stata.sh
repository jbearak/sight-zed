#!/bin/bash
#
# send-to-stata.sh - Send Stata code from Zed editor to Stata GUI
#
# Usage:
#   send-to-stata.sh <mode> [options]
#
# Modes:
#   --statement      Send current statement to Stata GUI
#   --file-mode      Send entire file to Stata GUI
#   --cd-workspace   Change Stata's working directory to workspace root
#   --cd-file        Change Stata's working directory to file's directory
#   --upward         Execute lines from start of file to cursor row
#   --downward       Execute lines from cursor row to end of file
#
# Options:
#   --file <path>       Source file path (required for most modes)
#   --row <number>      Cursor row, 1-indexed (required for --statement without --text, --upward, --downward)
#   --text <string>     Selected text (if provided, used instead of file/row)
#   --workspace <path>  Workspace root path (required for --cd-workspace)
#   --stdin           Read text from stdin (mutually exclusive with --text)
#
# Exit Codes:
#   0 - Success
#   1 - Invalid arguments
#   2 - File not found or unreadable
#   3 - Temp file creation failed
#   4 - Stata not found
#   5 - AppleScript execution failed
#   6 - Stdin read failed
#   7 - Stdin content too large

set -euo pipefail

# ============================================================================
# Argument Parsing
# ============================================================================

MODE=""
FILE_PATH=""
ROW=""
TEXT=""
STDIN_MODE=false
INCLUDE_MODE=false
WORKSPACE_PATH=""

# Prints usage information to stdout.
print_usage() {
    cat <<EOF
Usage: send-to-stata.sh <mode> [options]

Modes:
  --statement      Send current statement to Stata GUI
  --file-mode      Send entire file to Stata GUI
  --cd-workspace   Change Stata's working directory to workspace root
  --cd-file        Change Stata's working directory to file's directory
  --upward         Execute lines from start of file to cursor row
  --downward       Execute lines from cursor row to end of file

Options:
  --file <path>       Source file path (required for most modes)
  --row <number>      Cursor row, 1-indexed (required for --statement without --text, --upward, --downward)
  --text <string>     Selected text (if provided, used instead of file/row)
  --stdin             Read text from stdin (mutually exclusive with --text)
  --include           Use 'include' instead of 'do' (preserves local macro scope)
  --workspace <path>  Workspace root path (required for --cd-workspace)

Environment Variables:
  STATA_APP              Stata application name (StataMP, StataSE, StataIC, Stata)
  STATA_STDIN_MAX_BYTES  Max bytes allowed in --stdin mode (default: 10485760)
  STATA_CLEANUP_ON_ERROR If set to 1, delete temp file on AppleScript failure

Exit Codes:
  0 - Success
  1 - Invalid arguments
  2 - File not found or unreadable
  3 - Temp file creation failed
  4 - Stata not found
  5 - AppleScript execution failed
  6 - Stdin read failed
  7 - Stdin content too large
EOF
}

# Parses command-line arguments and sets global variables.
# Sets: MODE, FILE_PATH, ROW, TEXT, STDIN_MODE, INCLUDE_MODE
# Exits with code 1 on invalid arguments.
parse_arguments() {
    if [[ $# -eq 0 ]]; then
        echo "Error: No arguments provided" >&2
        print_usage >&2
        exit 1
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --statement)
                if [[ -n "$MODE" ]]; then
                    echo "Error: Cannot specify multiple modes" >&2
                    exit 1
                fi
                MODE="statement"
                shift
                ;;
            --file-mode)
                if [[ -n "$MODE" ]]; then
                    echo "Error: Cannot specify multiple modes" >&2
                    exit 1
                fi
                MODE="file"
                shift
                ;;
            --cd-workspace)
                if [[ -n "$MODE" ]]; then
                    echo "Error: Cannot specify multiple modes" >&2
                    exit 1
                fi
                MODE="cd-workspace"
                shift
                ;;
            --cd-file)
                if [[ -n "$MODE" ]]; then
                    echo "Error: Cannot specify multiple modes" >&2
                    exit 1
                fi
                MODE="cd-file"
                shift
                ;;
            --upward)
                if [[ -n "$MODE" ]]; then
                    echo "Error: Cannot specify multiple modes" >&2
                    exit 1
                fi
                MODE="upward"
                shift
                ;;
            --downward)
                if [[ -n "$MODE" ]]; then
                    echo "Error: Cannot specify multiple modes" >&2
                    exit 1
                fi
                MODE="downward"
                shift
                ;;
            --file)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --file option requires a path argument" >&2
                    exit 1
                fi
                shift
                FILE_PATH="$1"
                shift
                ;;
            --row)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --row option requires a number argument" >&2
                    exit 1
                fi
                shift
                ROW="$1"
                # Validate that row is a positive integer
                if ! [[ "$ROW" =~ ^[1-9][0-9]*$ ]]; then
                    echo "Error: --row must be a positive integer, got: $ROW" >&2
                    exit 1
                fi
                shift
                ;;
            --text)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --text option requires a string argument" >&2
                    exit 1
                fi
                shift
                TEXT="$1"
                shift
                ;;
            --stdin)
                STDIN_MODE=true
                shift
                ;;
            --workspace)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --workspace option requires a path argument" >&2
                    exit 1
                fi
                shift
                WORKSPACE_PATH="$1"
                shift
                ;;
            --include)
                INCLUDE_MODE=true
                shift
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                echo "Error: Unknown argument: $1" >&2
                print_usage >&2
                exit 1
                ;;
        esac
    done
}

# Validates parsed arguments for consistency and completeness.
# Exits with code 1 if validation fails.
validate_arguments() {
    # Check mutual exclusivity of --stdin and --text
    if [[ "$STDIN_MODE" == true && -n "$TEXT" ]]; then
        echo "Error: --stdin and --text are mutually exclusive" >&2
        exit 1
    fi

    # Mode is required
    if [[ -z "$MODE" ]]; then
        echo "Error: Mode is required (--statement, --file-mode, --cd-workspace, --cd-file, --upward, or --downward)" >&2
        exit 1
    fi

    # Mode-specific validation
    case "$MODE" in
        statement)
            # File path is required for statement mode
            if [[ -z "$FILE_PATH" ]]; then
                echo "Error: --file <path> is required" >&2
                exit 1
            fi
            # For statement mode, need one of: --stdin, --text, or --row
            if [[ "$STDIN_MODE" != true && -z "$TEXT" && -z "$ROW" ]]; then
                echo "Error: --statement mode requires --stdin, --text, or --row" >&2
                exit 1
            fi
            ;;
        file)
            # File path is required for file mode
            if [[ -z "$FILE_PATH" ]]; then
                echo "Error: --file <path> is required" >&2
                exit 1
            fi
            ;;
        cd-workspace)
            # Workspace path is required for cd-workspace mode
            if [[ -z "$WORKSPACE_PATH" ]]; then
                echo "Error: --workspace <path> is required for --cd-workspace mode" >&2
                exit 1
            fi
            ;;
        cd-file)
            # File path is required for cd-file mode
            if [[ -z "$FILE_PATH" ]]; then
                echo "Error: --file <path> is required for --cd-file mode" >&2
                exit 1
            fi
            ;;
        upward)
            # File path and row are required for upward mode
            if [[ -z "$FILE_PATH" ]]; then
                echo "Error: --file <path> is required for --upward mode" >&2
                exit 1
            fi
            if [[ -z "$ROW" ]]; then
                echo "Error: --row <number> is required for --upward mode" >&2
                exit 1
            fi
            ;;
        downward)
            # File path and row are required for downward mode
            if [[ -z "$FILE_PATH" ]]; then
                echo "Error: --file <path> is required for --downward mode" >&2
                exit 1
            fi
            if [[ -z "$ROW" ]]; then
                echo "Error: --row <number> is required for --downward mode" >&2
                exit 1
            fi
            ;;
        *)
            echo "Error: Invalid mode: $MODE" >&2
            exit 1
            ;;
    esac
}

# ============================================================================
# Stdin Reading
# ============================================================================

# Reads all content from stdin and writes it to a file.
#
# Arguments:
#   $1 - out_file: Destination file path
#   $2 - max_bytes: Maximum bytes allowed (0 means unlimited)
#
# Output:
#   Prints the number of bytes written to stdout
#
# Exit Codes:
#   6 - Stdin read failed
#   7 - Stdin content too large
read_stdin_to_file() {
    local out_file="$1"
    local max_bytes="$2"

    if ! cat > "$out_file"; then
        echo "Error: Failed to read from stdin" >&2
        rm -f "$out_file" 2>/dev/null || true
        exit 6
    fi

    local byte_count
    byte_count=$(wc -c < "$out_file" | tr -d ' ')

    if [[ "$max_bytes" -gt 0 && "$byte_count" -gt "$max_bytes" ]]; then
        echo "Error: stdin content too large (${byte_count} bytes; max ${max_bytes})" >&2
        rm -f "$out_file" 2>/dev/null || true
        exit 7
    fi

    echo "$byte_count"
}

# ============================================================================
# Path Escaping for Stata CD Commands
# ============================================================================

# Escapes a path for use in Stata's cd command.
# Doubles backslashes and detects if compound string syntax is needed.
#
# Arguments:
#   $1 - path: The path to escape
#
# Output:
#   Prints "escaped_path|use_compound" to stdout
#   use_compound is "true" if path contains double quotes, "false" otherwise
#
# Example:
#   escape_path_for_stata 'C:\Users\test"file'
#   # Output: C:\\Users\\test"file|true
escape_path_for_stata() {
    local path="$1"
    
    # Double all backslashes for Stata compatibility
    local escaped="${path//\\/\\\\}"
    
    # Check if path contains double quotes
    local use_compound="false"
    if [[ "$path" == *'"'* ]]; then
        use_compound="true"
    fi
    
    echo "${escaped}|${use_compound}"
}

# Formats a cd command for Stata with proper string syntax.
# Uses compound string syntax (`"path"') when path contains double quotes,
# otherwise uses regular string syntax ("path").
#
# Arguments:
#   $1 - directory_path: The directory path to cd into
#
# Output:
#   Prints the formatted cd command to stdout
#
# Example:
#   format_cd_command '/Users/test'
#   # Output: cd "/Users/test"
#
#   format_cd_command '/Users/test"dir'
#   # Output: cd `"/Users/test"dir"'
format_cd_command() {
    local directory_path="$1"
    
    # Get escaped path and compound flag
    local result
    result=$(escape_path_for_stata "$directory_path")
    
    local escaped_path="${result%|*}"
    local use_compound="${result#*|}"
    
    if [[ "$use_compound" == "true" ]]; then
        # Use compound string syntax: cd `"path"'
        printf 'cd `"%s"\047\n' "$escaped_path"
    else
        # Use regular string syntax: cd "path"
        printf 'cd "%s"\n' "$escaped_path"
    fi
}

# ============================================================================
# Stata Application Detection
# ============================================================================

# Detects the Stata application to use.
# Priority:
#   1. STATA_APP environment variable (if set)
#   2. Auto-detect from /Applications/Stata/ (StataMP, StataSE, StataIC, Stata)
# Outputs the application name to stdout.
# Exits with code 4 if no Stata installation is found.
detect_stata_app() {
    # Check environment variable first
    if [[ -n "${STATA_APP:-}" ]]; then
        echo "$STATA_APP"
        return
    fi

    # Auto-detect by checking /Applications/Stata/ for variants
    for app in StataMP StataSE StataIC Stata; do
        if [[ -d "/Applications/Stata/${app}.app" ]]; then
            echo "$app"
            return
        fi
    done

    # No Stata installation found
    echo "Error: No Stata installation found in /Applications/Stata/" >&2
    echo "Set STATA_APP environment variable or install Stata" >&2
    exit 4
}

# ============================================================================
# Statement Detection
# ============================================================================

# Checks if a line ends with the continuation marker (/// followed by optional whitespace)
# Arguments:
#   $1 - The line to check
# Returns:
#   0 (true) if line ends with continuation marker
#   1 (false) otherwise
ends_with_continuation() {
    local line="$1"
    # Check if line ends with /// followed by optional whitespace
    [[ "$line" =~ ///[[:space:]]*$ ]]
}

# ============================================================================
# Line Extraction Functions
# ============================================================================

# Gets lines from the start of the file to the cursor row (inclusive).
# If the cursor row ends with a continuation marker, extends to include the complete statement.
#
# Arguments:
#   $1 - file_path: Path to the Stata file
#   $2 - row: Cursor row (1-indexed)
#
# Output:
#   Prints the extracted lines to stdout (preserving line breaks)
#
# Exit Codes:
#   1 - Invalid arguments (row out of bounds)
#   2 - File not found or unreadable
#
# Algorithm:
#   1. Read file into array of lines
#   2. Start at line 1
#   3. End at cursor row, extending forward if line has continuation
#   4. Extract and output lines from start to end
get_upward_lines() {
    local file_path="$1"
    local row="$2"
    
    # Validate file exists and is readable
    if [[ ! -f "$file_path" ]]; then
        echo "Error: Cannot read file: $file_path" >&2
        exit 2
    fi
    
    if [[ ! -r "$file_path" ]]; then
        echo "Error: Cannot read file: $file_path" >&2
        exit 2
    fi
    
    # Read file into array of lines
    local -a lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done < "$file_path"
    
    local total_lines=${#lines[@]}
    
    # Handle empty file
    if [[ $total_lines -eq 0 ]]; then
        echo ""
        return
    fi
    
    # Validate row is within bounds
    if [[ $row -lt 1 || $row -gt $total_lines ]]; then
        echo "Error: Row $row is out of bounds (file has $total_lines lines)" >&2
        exit 1
    fi
    
    # Convert to 0-indexed for array access
    local row_idx=$((row - 1))
    
    # Start is always line 1 (index 0)
    local start_idx=0
    
    # End at cursor row, extending forward if line has continuation
    local end_idx=$row_idx
    while [[ $end_idx -lt $((total_lines - 1)) ]]; do
        if ends_with_continuation "${lines[$end_idx]}"; then
            end_idx=$((end_idx + 1))
        else
            break
        fi
    done
    
    # Extract and output the lines
    local first=true
    for ((i = start_idx; i <= end_idx; i++)); do
        if [[ "$first" == true ]]; then
            first=false
        else
            echo ""
        fi
        printf '%s' "${lines[$i]}"
    done
    # Add final newline
    echo ""
}

# Gets lines from the cursor row to the end of the file (inclusive).
# If the cursor is on a continuation line (previous line ends with ///),
# extends backward to include the complete statement start.
#
# Arguments:
#   $1 - file_path: Path to the Stata file
#   $2 - row: Cursor row (1-indexed)
#
# Output:
#   Prints the extracted lines to stdout (preserving line breaks)
#
# Exit Codes:
#   1 - Invalid arguments (row out of bounds)
#   2 - File not found or unreadable
#
# Algorithm:
#   1. Read file into array of lines
#   2. Start at cursor row, extending backward if on continuation line
#   3. End at last line of file
#   4. Extract and output lines from start to end
get_downward_lines() {
    local file_path="$1"
    local row="$2"
    
    # Validate file exists and is readable
    if [[ ! -f "$file_path" ]]; then
        echo "Error: Cannot read file: $file_path" >&2
        exit 2
    fi
    
    if [[ ! -r "$file_path" ]]; then
        echo "Error: Cannot read file: $file_path" >&2
        exit 2
    fi
    
    # Read file into array of lines
    local -a lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done < "$file_path"
    
    local total_lines=${#lines[@]}
    
    # Handle empty file
    if [[ $total_lines -eq 0 ]]; then
        echo ""
        return
    fi
    
    # Validate row is within bounds
    if [[ $row -lt 1 || $row -gt $total_lines ]]; then
        echo "Error: Row $row is out of bounds (file has $total_lines lines)" >&2
        exit 1
    fi
    
    # Convert to 0-indexed for array access
    local row_idx=$((row - 1))
    
    # Start at cursor row, extending backward if on continuation line
    # A line is a continuation if the PREVIOUS line ends with ///
    local start_idx=$row_idx
    while [[ $start_idx -gt 0 ]]; do
        local prev_idx=$((start_idx - 1))
        # If the previous line ends with ///, then current line is a continuation
        # So we need to include the previous line
        if ends_with_continuation "${lines[$prev_idx]}"; then
            start_idx=$prev_idx
        else
            # Previous line doesn't end with ///, so current line is the start
            break
        fi
    done
    
    # End is always the last line
    local end_idx=$((total_lines - 1))
    
    # Extract and output the lines
    local first=true
    for ((i = start_idx; i <= end_idx; i++)); do
        if [[ "$first" == true ]]; then
            first=false
        else
            echo ""
        fi
        printf '%s' "${lines[$i]}"
    done
    # Add final newline
    echo ""
}

# Detects the statement at the given cursor position.
# Handles multi-line statements with continuation markers (///).
#
# Arguments:
#   $1 - file_path: Path to the Stata file
#   $2 - row: Cursor row (1-indexed)
#
# Output:
#   Prints the detected statement to stdout (preserving line breaks)
#
# Algorithm:
#   1. Read file into array of lines
#   2. Search backwards from row to find statement start
#      - Stop when line doesn't end with /// AND previous line doesn't end with ///
#   3. Search forwards from row to find statement end
#      - Stop when line doesn't end with ///
#   4. Extract lines from start to end
#   5. Return joined statement (preserving line breaks)
detect_statement() {
    local file_path="$1"
    local row="$2"
    
    # Validate file exists and is readable
    if [[ ! -f "$file_path" ]]; then
        echo "Error: Cannot read file: $file_path" >&2
        exit 2
    fi
    
    if [[ ! -r "$file_path" ]]; then
        echo "Error: Cannot read file: $file_path" >&2
        exit 2
    fi
    
    # Read file into array of lines
    local -a lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done < "$file_path"
    
    local total_lines=${#lines[@]}
    
    # Handle empty file
    if [[ $total_lines -eq 0 ]]; then
        echo ""
        return
    fi
    
    # Validate row is within bounds
    if [[ $row -lt 1 || $row -gt $total_lines ]]; then
        echo "Error: Row $row is out of bounds (file has $total_lines lines)" >&2
        exit 1
    fi
    
    # Convert to 0-indexed for array access
    local row_idx=$((row - 1))
    
    # Find statement start by searching backwards
    # We need to find where the statement begins:
    # - If current line is a continuation of a previous line, go back
    # - A line is a continuation if the PREVIOUS line ends with ///
    local start_idx=$row_idx
    while [[ $start_idx -gt 0 ]]; do
        local prev_idx=$((start_idx - 1))
        # If the previous line ends with ///, then current line is a continuation
        # So we need to include the previous line
        if ends_with_continuation "${lines[$prev_idx]}"; then
            start_idx=$prev_idx
        else
            # Previous line doesn't end with ///, so current line is the start
            break
        fi
    done
    
    # Find statement end by searching forwards
    # Continue while current line ends with ///
    local end_idx=$row_idx
    while [[ $end_idx -lt $((total_lines - 1)) ]]; do
        if ends_with_continuation "${lines[$end_idx]}"; then
            end_idx=$((end_idx + 1))
        else
            # Current line doesn't end with ///, so this is the end
            break
        fi
    done
    
    # Extract and output the statement lines
    local first=true
    for ((i = start_idx; i <= end_idx; i++)); do
        if [[ "$first" == true ]]; then
            first=false
        else
            echo ""
        fi
        printf '%s' "${lines[$i]}"
    done
    # Add final newline
    echo ""
}

# ============================================================================
# Temp File Creation
# ============================================================================

# Creates an empty temporary .do file.
# The temp file is created in $TMPDIR (or /tmp as fallback) with a unique name.
#
# Output:
#   Prints the path to the created temp file to stdout
#
# Exit Codes:
#   3 - Temp file creation failed
create_temp_file_path() {
    # Determine temp directory: use $TMPDIR if set, otherwise /tmp
    local temp_dir="${TMPDIR:-/tmp}"

    # Create temp file with mktemp
    # macOS mktemp requires X's at the end, so we create without .do suffix first
    # then rename to add the .do extension
    local temp_base
    temp_base=$(mktemp "${temp_dir}/stata_send_XXXXXX" 2>/dev/null) || {
        echo "Error: Cannot create temp file" >&2
        exit 3
    }

    # Rename to add .do extension
    local temp_file="${temp_base}.do"
    if ! mv "$temp_base" "$temp_file" 2>/dev/null; then
        echo "Error: Cannot rename temp file to add .do extension" >&2
        rm -f "$temp_base" 2>/dev/null
        exit 3
    fi

    echo "$temp_file"
}

# Creates a temporary file with the given content.
# Note: bash variables cannot represent NUL bytes; use stdin mode for robust transfer.
create_temp_file() {
    local content="$1"

    local temp_file
    temp_file=$(create_temp_file_path)

    if ! printf '%s' "$content" > "$temp_file" 2>/dev/null; then
        echo "Error: Cannot write to temp file: $temp_file" >&2
        rm -f "$temp_file" 2>/dev/null
        exit 3
    fi

    echo "$temp_file"
}

# ============================================================================
# AppleScript Execution
# ============================================================================

# Escapes a path for use in AppleScript string.
# Escapes backslashes and double quotes.
#
# Arguments:
#   $1 - path: The path to escape
#
# Output:
#   Prints the escaped path to stdout
escape_for_applescript() {
    local path="$1"
    # Escape backslashes first (\ -> \\), then double quotes (" -> \")
    path="${path//\\/\\\\}"
    path="${path//\"/\\\"}"
    echo "$path"
}

# Sends a do-file command to Stata via AppleScript.
#
# Arguments:
#   $1 - stata_app: The Stata application name (e.g., StataMP)
#   $2 - temp_file: Path to the temp .do file to execute
#
# Exit Codes:
#   5 - AppleScript execution failed
send_to_stata() {
    local stata_app="$1"
    local temp_file="$2"

    # Validate stata_app to prevent command injection
    case "$stata_app" in
        StataMP|StataSE|StataIC|StataBE|Stata) ;;
        *) echo "Error: Invalid Stata application: $stata_app" >&2; exit 1 ;;
    esac

    # Escape the temp file path for AppleScript
    local escaped_path
    escaped_path=$(escape_for_applescript "$temp_file")

    # Determine Stata command based on INCLUDE_MODE
    local stata_cmd="do"
    if [[ "$INCLUDE_MODE" == true ]]; then
        stata_cmd="include"
    fi

    # Build the AppleScript command
    local applescript_cmd="tell application \"${stata_app}\" to DoCommandAsync \"${stata_cmd} \\\"${escaped_path}\\\"\""

    # Execute via osascript
    local error_output
    if ! error_output=$(osascript -e "$applescript_cmd" 2>&1); then
        echo "Error: AppleScript failed: $error_output" >&2
        if [[ "${STATA_CLEANUP_ON_ERROR:-0}" == "1" ]]; then
            rm -f "$temp_file" 2>/dev/null || true
        fi
        exit 5
    fi
}

# Sends a raw Stata command directly via AppleScript (no temp file).
#
# Arguments:
#   $1 - stata_app: The Stata application name (e.g., StataMP)
#   $2 - command: The Stata command to execute
#
# Exit Codes:
#   5 - AppleScript execution failed
send_command_to_stata() {
    local stata_app="$1"
    local command="$2"

    # Validate stata_app to prevent command injection
    case "$stata_app" in
        StataMP|StataSE|StataIC|StataBE|Stata) ;;
        *) echo "Error: Invalid Stata application: $stata_app" >&2; exit 1 ;;
    esac

    # Escape the command for AppleScript
    local escaped_command
    escaped_command=$(escape_for_applescript "$command")

    # Build the AppleScript command
    local applescript_cmd="tell application \"${stata_app}\" to DoCommandAsync \"${escaped_command}\""

    # Execute via osascript
    local error_output
    if ! error_output=$(osascript -e "$applescript_cmd" 2>&1); then
        echo "Error: AppleScript failed: $error_output" >&2
        exit 5
    fi
}

# ============================================================================
# Main Entry Point
# ============================================================================

# Main entry point. Parses arguments, detects Stata, and sends code.
main() {
    parse_arguments "$@"
    validate_arguments

    # Detect Stata application
    STATA_APP_NAME=$(detect_stata_app)

    # Handle CD modes separately (no temp file needed)
    case "$MODE" in
        cd-workspace)
            # Validate workspace path exists
            if [[ ! -d "$WORKSPACE_PATH" ]]; then
                echo "Error: Workspace directory does not exist: $WORKSPACE_PATH" >&2
                exit 2
            fi
            # Generate and send cd command
            local cd_cmd
            cd_cmd=$(format_cd_command "$WORKSPACE_PATH")
            send_command_to_stata "$STATA_APP_NAME" "$cd_cmd"
            exit 0
            ;;
        cd-file)
            # Validate file exists
            if [[ ! -f "$FILE_PATH" ]]; then
                echo "Error: Cannot read file: $FILE_PATH" >&2
                exit 2
            fi
            # Extract parent directory
            local parent_dir
            parent_dir=$(dirname "$FILE_PATH")
            # Generate and send cd command
            local cd_cmd
            cd_cmd=$(format_cd_command "$parent_dir")
            send_command_to_stata "$STATA_APP_NAME" "$cd_cmd"
            exit 0
            ;;
    esac

    # For statement and file modes, validate file exists and is readable
    if [[ ! -f "$FILE_PATH" ]]; then
        echo "Error: Cannot read file: $FILE_PATH" >&2
        exit 2
    fi
    
    if [[ ! -r "$FILE_PATH" ]]; then
        echo "Error: Cannot read file: $FILE_PATH" >&2
        exit 2
    fi

    # Create temp file and write the code to send based on mode
    local temp_file
    temp_file=$(create_temp_file_path)

    case "$MODE" in
        statement)
            if [[ "$STDIN_MODE" == true ]]; then
                # Read stdin to temp file first so we can:
                # - preserve bytes (including trailing newlines)
                # - avoid holding the entire selection in memory
                # - detect empty stdin for --row fallback
                local max_bytes="${STATA_STDIN_MAX_BYTES:-10485760}"
                local byte_count
                byte_count=$(read_stdin_to_file "$temp_file" "$max_bytes")

                if [[ "$byte_count" -eq 0 ]]; then
                    if [[ -n "$ROW" ]]; then
                        # Fall back to row detection if stdin is empty
                        detect_statement "$FILE_PATH" "$ROW" > "$temp_file"
                    else
                        echo "Error: stdin is empty and no --row provided" >&2
                        rm -f "$temp_file" 2>/dev/null || true
                        exit 1
                    fi
                fi
            elif [[ -n "$TEXT" ]]; then
                # Use selected text directly
                printf '%s' "$TEXT" > "$temp_file"
            else
                # Detect statement at cursor position
                detect_statement "$FILE_PATH" "$ROW" > "$temp_file"
            fi
            ;;
        file)
            # Copy entire file to temp file without losing trailing newlines
            cat "$FILE_PATH" > "$temp_file"
            ;;
        upward)
            # Extract lines from start of file to cursor row
            get_upward_lines "$FILE_PATH" "$ROW" > "$temp_file"
            ;;
        downward)
            # Extract lines from cursor row to end of file
            get_downward_lines "$FILE_PATH" "$ROW" > "$temp_file"
            ;;
    esac

    # Send to Stata via AppleScript
    send_to_stata "$STATA_APP_NAME" "$temp_file"
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
