#!/bin/bash
#
# send-to-stata.sh - Send Stata code from Zed editor to Stata GUI
#
# Usage:
#   send-to-stata.sh <mode> [options]
#
# Modes:
#   --statement   Send current statement to Stata GUI
#   --file        Send entire file to Stata GUI
#
# Options:
#   --file <path>     Source file path (required)
#   --row <number>    Cursor row, 1-indexed (required for --statement without --text)
#   --text <string>   Selected text (if provided, used instead of file/row)
#   --stdin           Read text from stdin (mutually exclusive with --text)
#
# Exit Codes:
#   0 - Success
#   1 - Invalid arguments
#   2 - File not found or unreadable
#   3 - Temp file creation failed
#   4 - Stata not found
#   5 - AppleScript execution failed

set -euo pipefail

# ============================================================================
# Argument Parsing
# ============================================================================

MODE=""
FILE_PATH=""
ROW=""
TEXT=""
STDIN_MODE=false

print_usage() {
    cat <<EOF
Usage: send-to-stata.sh <mode> [options]

Modes:
  --statement   Send current statement to Stata GUI
  --file        Send entire file to Stata GUI

Options:
  --file <path>     Source file path (required)
  --row <number>    Cursor row, 1-indexed (required for --statement without --text)
  --text <string>   Selected text (if provided, used instead of file/row)
  --stdin           Read text from stdin (mutually exclusive with --text)

Environment Variables:
  STATA_APP         Stata application name (StataMP, StataSE, StataIC, Stata)

Exit Codes:
  0 - Success
  1 - Invalid arguments
  2 - File not found or unreadable
  3 - Temp file creation failed
  4 - Stata not found
  5 - AppleScript execution failed
  6 - Stdin read failed
EOF
}

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
            --file)
                # Check if this is the mode or the option
                if [[ -z "$MODE" ]]; then
                    # This is the mode
                    MODE="file"
                    shift
                else
                    # This is the --file option (file path)
                    if [[ $# -lt 2 ]]; then
                        echo "Error: --file option requires a path argument" >&2
                        exit 1
                    fi
                    shift
                    FILE_PATH="$1"
                    shift
                fi
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

validate_arguments() {
    # Check mutual exclusivity of --stdin and --text
    if [[ "$STDIN_MODE" == true && -n "$TEXT" ]]; then
        echo "Error: --stdin and --text are mutually exclusive" >&2
        exit 1
    fi

    # Mode is required
    if [[ -z "$MODE" ]]; then
        echo "Error: Mode is required (--statement or --file)" >&2
        exit 1
    fi

    # File path is always required
    if [[ -z "$FILE_PATH" ]]; then
        echo "Error: --file <path> is required" >&2
        exit 1
    fi

    # Mode-specific validation
    case "$MODE" in
        statement)
            # For statement mode, need one of: --stdin, --text, or --row
            if [[ "$STDIN_MODE" != true && -z "$TEXT" && -z "$ROW" ]]; then
                echo "Error: --statement mode requires --stdin, --text, or --row" >&2
                exit 1
            fi
            ;;
        file)
            # File mode only needs the file path, which we already validated
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

# Reads all content from stdin.
# Output: Prints content to stdout
# Exit Codes: 6 - Stdin read failed
read_stdin_content() {
    local content
    if ! content=$(cat); then
        echo "Error: Failed to read from stdin" >&2
        exit 6
    fi
    printf '%s' "$content"
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

# Creates a temporary file with the given content.
# The temp file is created in $TMPDIR (or /tmp as fallback) with a unique name.
#
# Arguments:
#   $1 - content: The content to write to the temp file
#
# Output:
#   Prints the path to the created temp file to stdout
#
# Exit Codes:
#   3 - Temp file creation failed
create_temp_file() {
    local content="$1"
    
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
    
    # Write content to temp file
    if ! printf '%s' "$content" > "$temp_file" 2>/dev/null; then
        echo "Error: Cannot write to temp file: $temp_file" >&2
        # Clean up the temp file we created
        rm -f "$temp_file" 2>/dev/null
        exit 3
    fi
    
    # Return the temp file path
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
    
    # Escape the temp file path for AppleScript
    local escaped_path
    escaped_path=$(escape_for_applescript "$temp_file")
    
    # Build the AppleScript command
    local applescript_cmd="tell application \"${stata_app}\" to DoCommandAsync \"do \\\"${escaped_path}\\\"\""
    
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

main() {
    parse_arguments "$@"
    validate_arguments

    # Validate file exists and is readable
    if [[ ! -f "$FILE_PATH" ]]; then
        echo "Error: Cannot read file: $FILE_PATH" >&2
        exit 2
    fi
    
    if [[ ! -r "$FILE_PATH" ]]; then
        echo "Error: Cannot read file: $FILE_PATH" >&2
        exit 2
    fi

    # Detect Stata application
    STATA_APP_NAME=$(detect_stata_app)

    # Determine the code to send based on mode
    local code_to_send=""
    
    case "$MODE" in
        statement)
            if [[ "$STDIN_MODE" == true ]]; then
                local stdin_content
                stdin_content=$(read_stdin_content)
                if [[ -n "$stdin_content" ]]; then
                    code_to_send="$stdin_content"
                elif [[ -n "$ROW" ]]; then
                    # Fall back to row detection if stdin is empty
                    code_to_send=$(detect_statement "$FILE_PATH" "$ROW")
                else
                    echo "Error: stdin is empty and no --row provided" >&2
                    exit 1
                fi
            elif [[ -n "$TEXT" ]]; then
                # Use selected text directly
                code_to_send="$TEXT"
            else
                # Detect statement at cursor position
                code_to_send=$(detect_statement "$FILE_PATH" "$ROW")
            fi
            ;;
        file)
            # Read entire file
            code_to_send=$(cat "$FILE_PATH")
            ;;
    esac

    # Create temp file with the code to send
    local temp_file
    temp_file=$(create_temp_file "$code_to_send")

    # Send to Stata via AppleScript
    send_to_stata "$STATA_APP_NAME" "$temp_file"
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
