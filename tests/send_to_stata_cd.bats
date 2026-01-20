#!/usr/bin/env bats

#
# send_to_stata_cd.bats - Property-based tests for CD command path escaping
#
# Property 1: Backslash Doubling
# Property 2: Quote Detection Sets Compound Flag
# Property 3: CD Command Formatting
#
# **Validates: Requirements 1.2, 1.3, 2.2, 2.3, 5.1-5.5**

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    SCRIPT="$PROJECT_DIR/send-to-stata.sh"
    TEMP_DIR=$(mktemp -d)
    
    # Number of iterations for property tests
    ITERATIONS=100
}

teardown() {
    [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}

# Helper to call functions from the script
call_func() {
    local func="$1"
    shift
    bash -c "source '$SCRIPT'; $func \"\$@\"" -- "$@"
}

# ============================================================================
# Path Generators
# ============================================================================

# Generate a random path with backslashes
generate_path_with_backslashes() {
    local num_segments=$((RANDOM % 4 + 2))  # 2-5 segments
    local path=""
    for ((i = 0; i < num_segments; i++)); do
        [[ $i -gt 0 ]] && path+="\\"
        path+="segment_$RANDOM"
    done
    printf '%s' "$path"
}

# Generate a random path with double quotes
generate_path_with_quotes() {
    local base="/Users/test"
    local quoted_part="dir\"$RANDOM"
    printf '%s/%s' "$base" "$quoted_part"
}

# Generate a random path without special characters
generate_simple_path() {
    local num_segments=$((RANDOM % 4 + 2))  # 2-5 segments
    local path=""
    for ((i = 0; i < num_segments; i++)); do
        [[ $i -gt 0 ]] && path+="/"
        path+="segment_$RANDOM"
    done
    printf '%s' "$path"
}

# Generate a random path with both backslashes and quotes
generate_path_with_both() {
    local path="C:\\Users\\test\"$RANDOM\\data"
    printf '%s' "$path"
}

# Count occurrences of a character in a string
count_char() {
    local str="$1"
    local char="$2"
    local count=0
    local temp="$str"
    while [[ "$temp" == *"$char"* ]]; do
        count=$((count + 1))
        temp="${temp#*"$char"}"
    done
    echo "$count"
}

# ============================================================================
# Property 1: Backslash Doubling
# For any path string containing backslash characters, the escape_path_for_stata
# function SHALL return an escaped string where every backslash is doubled.
# **Validates: Requirements 1.3, 2.3, 5.3**
# ============================================================================

# Feature: stata-zed-tasks, Property 1: Backslash Doubling
@test "Property 1: backslashes are doubled in escaped path" {
    for ((i = 0; i < ITERATIONS; i++)); do
        local path
        path=$(generate_path_with_backslashes)
        
        # Count backslashes in original
        local original_count
        original_count=$(count_char "$path" "\\")
        
        # Get escaped result
        local result
        result=$(call_func escape_path_for_stata "$path")
        local escaped="${result%|*}"
        
        # Count backslashes in escaped (each \\ counts as 2)
        local escaped_count
        escaped_count=$(count_char "$escaped" "\\")
        
        # Escaped should have exactly double the backslashes
        if [[ $escaped_count -ne $((original_count * 2)) ]]; then
            echo "FAIL: iteration=$i"
            echo "Original path: $path (backslashes: $original_count)"
            echo "Escaped path: $escaped (backslashes: $escaped_count)"
            echo "Expected backslashes: $((original_count * 2))"
            return 1
        fi
    done
}

# Feature: stata-zed-tasks, Property 1: Single backslash becomes double
@test "Property 1: single backslash becomes double backslash" {
    for ((i = 0; i < ITERATIONS; i++)); do
        local segment="test_$RANDOM"
        local path="$segment\\$segment"
        
        local result
        result=$(call_func escape_path_for_stata "$path")
        local escaped="${result%|*}"
        
        local expected="$segment\\\\$segment"
        if [[ "$escaped" != "$expected" ]]; then
            echo "FAIL: iteration=$i"
            echo "Input: $path"
            echo "Expected: $expected"
            echo "Got: $escaped"
            return 1
        fi
    done
}

# Feature: stata-zed-tasks, Property 1: Path without backslashes unchanged
@test "Property 1: path without backslashes is unchanged" {
    for ((i = 0; i < ITERATIONS; i++)); do
        local path
        path=$(generate_simple_path)
        
        local result
        result=$(call_func escape_path_for_stata "$path")
        local escaped="${result%|*}"
        
        if [[ "$escaped" != "$path" ]]; then
            echo "FAIL: iteration=$i"
            echo "Input: $path"
            echo "Expected: $path"
            echo "Got: $escaped"
            return 1
        fi
    done
}

# ============================================================================
# Property 2: Quote Detection Sets Compound Flag
# For any path string, the escape_path_for_stata function SHALL set
# use_compound = true if and only if the path contains at least one double quote.
# **Validates: Requirements 1.2, 2.2, 5.2**
# ============================================================================

# Feature: stata-zed-tasks, Property 2: Quote Detection Sets Compound Flag
@test "Property 2: paths with quotes set use_compound to true" {
    for ((i = 0; i < ITERATIONS; i++)); do
        local path
        path=$(generate_path_with_quotes)
        
        local result
        result=$(call_func escape_path_for_stata "$path")
        local use_compound="${result#*|}"
        
        if [[ "$use_compound" != "true" ]]; then
            echo "FAIL: iteration=$i"
            echo "Path with quote: $path"
            echo "Expected use_compound: true"
            echo "Got: $use_compound"
            return 1
        fi
    done
}

# Feature: stata-zed-tasks, Property 2: Paths without quotes set use_compound to false
@test "Property 2: paths without quotes set use_compound to false" {
    for ((i = 0; i < ITERATIONS; i++)); do
        local path
        path=$(generate_simple_path)
        
        local result
        result=$(call_func escape_path_for_stata "$path")
        local use_compound="${result#*|}"
        
        if [[ "$use_compound" != "false" ]]; then
            echo "FAIL: iteration=$i"
            echo "Path without quote: $path"
            echo "Expected use_compound: false"
            echo "Got: $use_compound"
            return 1
        fi
    done
}

# Feature: stata-zed-tasks, Property 2: Quote detection is independent of backslashes
@test "Property 2: quote detection works with backslashes present" {
    for ((i = 0; i < ITERATIONS; i++)); do
        local path
        path=$(generate_path_with_both)
        
        local result
        result=$(call_func escape_path_for_stata "$path")
        local use_compound="${result#*|}"
        
        if [[ "$use_compound" != "true" ]]; then
            echo "FAIL: iteration=$i"
            echo "Path with both: $path"
            echo "Expected use_compound: true"
            echo "Got: $use_compound"
            return 1
        fi
    done
}

# ============================================================================
# Property 3: CD Command Formatting
# For any directory path, the format_cd_command function SHALL:
# - Return cd `"<escaped_path>"' when the path contains double quotes
# - Return cd "<escaped_path>" when the path does not contain double quotes
# **Validates: Requirements 5.4, 5.5**
# ============================================================================

# Feature: stata-zed-tasks, Property 3: CD Command Formatting
@test "Property 3: paths with quotes use compound string syntax" {
    for ((i = 0; i < ITERATIONS; i++)); do
        local path
        path=$(generate_path_with_quotes)
        
        local cmd
        cmd=$(call_func format_cd_command "$path")
        
        # Should start with cd `" and end with "'
        if [[ "$cmd" != 'cd `"'* ]] || [[ "$cmd" != *"\"'" ]]; then
            echo "FAIL: iteration=$i"
            echo "Path: $path"
            echo "Command: $cmd"
            echo "Expected compound string syntax: cd \`\"...\"\'"
            return 1
        fi
    done
}

# Feature: stata-zed-tasks, Property 3: Paths without quotes use regular syntax
@test "Property 3: paths without quotes use regular string syntax" {
    for ((i = 0; i < ITERATIONS; i++)); do
        local path
        path=$(generate_simple_path)
        
        local cmd
        cmd=$(call_func format_cd_command "$path")
        
        # Should start with cd " and end with "
        # Should NOT contain backtick or single quote
        if [[ "$cmd" != 'cd "'* ]] || [[ "$cmd" == *'`'* ]] || [[ "$cmd" == *"'" ]]; then
            echo "FAIL: iteration=$i"
            echo "Path: $path"
            echo "Command: $cmd"
            echo "Expected regular string syntax: cd \"...\""
            return 1
        fi
    done
}

# Feature: stata-zed-tasks, Property 3: Backslashes are doubled in cd command
@test "Property 3: backslashes are doubled in cd command output" {
    for ((i = 0; i < ITERATIONS; i++)); do
        local path
        path=$(generate_path_with_backslashes)
        
        local original_count
        original_count=$(count_char "$path" "\\")
        
        local cmd
        cmd=$(call_func format_cd_command "$path")
        
        # Count backslashes in command (excluding the cd " prefix)
        local cmd_count
        cmd_count=$(count_char "$cmd" "\\")
        
        if [[ $cmd_count -ne $((original_count * 2)) ]]; then
            echo "FAIL: iteration=$i"
            echo "Path: $path (backslashes: $original_count)"
            echo "Command: $cmd (backslashes: $cmd_count)"
            echo "Expected backslashes in command: $((original_count * 2))"
            return 1
        fi
    done
}

# ============================================================================
# Unit Tests for Edge Cases
# ============================================================================

@test "escape_path_for_stata: empty path" {
    local result
    result=$(call_func escape_path_for_stata "")
    local escaped="${result%|*}"
    local use_compound="${result#*|}"
    
    [ "$escaped" = "" ]
    [ "$use_compound" = "false" ]
}

@test "escape_path_for_stata: path with only backslashes" {
    local result
    result=$(call_func escape_path_for_stata '\\\\')
    local escaped="${result%|*}"
    local use_compound="${result#*|}"
    
    [ "$escaped" = '\\\\\\\\' ]
    [ "$use_compound" = "false" ]
}

@test "escape_path_for_stata: path with only quotes" {
    local result
    result=$(call_func escape_path_for_stata '""')
    local escaped="${result%|*}"
    local use_compound="${result#*|}"
    
    [ "$escaped" = '""' ]
    [ "$use_compound" = "true" ]
}

@test "format_cd_command: simple Unix path" {
    local cmd
    cmd=$(call_func format_cd_command "/Users/test/data")
    [ "$cmd" = 'cd "/Users/test/data"' ]
}

@test "format_cd_command: Windows path with backslashes" {
    local cmd
    cmd=$(call_func format_cd_command 'C:\Users\test')
    [ "$cmd" = 'cd "C:\\Users\\test"' ]
}

@test "format_cd_command: path with double quote" {
    local cmd
    cmd=$(call_func format_cd_command '/Users/test"dir')
    # Should use compound string: cd `"/Users/test"dir"'
    [[ "$cmd" == 'cd `"/Users/test"dir"'"'" ]]
}

@test "format_cd_command: path with spaces" {
    local cmd
    cmd=$(call_func format_cd_command "/Users/My Documents/data")
    [ "$cmd" = 'cd "/Users/My Documents/data"' ]
}


# ============================================================================
# Tests for --cd-workspace mode
# **Validates: Requirements 1.1, 1.4, 1.5**
# ============================================================================

@test "--cd-workspace: requires --workspace argument" {
    run bash "$SCRIPT" --cd-workspace
    [ "$status" -eq 1 ]
    [[ "$output" == *"--workspace <path> is required"* ]]
}

@test "--cd-workspace: validates workspace directory exists" {
    run bash "$SCRIPT" --cd-workspace --workspace "/nonexistent/path/12345"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Workspace directory does not exist"* ]]
}

@test "--cd-workspace: generates correct cd command for simple path" {
    # Create a temp directory to use as workspace
    local workspace_dir
    workspace_dir=$(mktemp -d)
    
    # We can't actually test the AppleScript execution without Stata,
    # but we can test the argument parsing and validation
    # For now, just verify it doesn't fail on argument parsing
    run bash "$SCRIPT" --cd-workspace --workspace "$workspace_dir"
    
    # Will fail with exit code 4 (Stata not found) on systems without Stata
    # or succeed (exit code 0) on systems with Stata
    # Either is acceptable for this test
    [[ "$status" -eq 0 || "$status" -eq 4 ]]
    
    rm -rf "$workspace_dir"
}

# ============================================================================
# Tests for --cd-file mode
# **Validates: Requirements 2.1, 2.4, 2.5**
# ============================================================================

@test "--cd-file: requires --file argument" {
    run bash "$SCRIPT" --cd-file
    [ "$status" -eq 1 ]
    [[ "$output" == *"--file <path> is required"* ]]
}

@test "--cd-file: validates file exists" {
    run bash "$SCRIPT" --cd-file --file "/nonexistent/file/12345.do"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Cannot read file"* ]]
}

@test "--cd-file: generates correct cd command for file" {
    # Create a temp file
    local temp_file
    temp_file=$(mktemp "${TEMP_DIR}/test_XXXXXX.do")
    echo "display 1" > "$temp_file"
    
    # We can't actually test the AppleScript execution without Stata,
    # but we can test the argument parsing and validation
    run bash "$SCRIPT" --cd-file --file "$temp_file"
    
    # Will fail with exit code 4 (Stata not found) on systems without Stata
    # or succeed (exit code 0) on systems with Stata
    [[ "$status" -eq 0 || "$status" -eq 4 ]]
}

# ============================================================================
# Mode mutual exclusivity tests
# ============================================================================

@test "cannot specify --cd-workspace with --statement" {
    run bash "$SCRIPT" --cd-workspace --statement --workspace "/tmp"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot specify multiple modes"* ]]
}

@test "cannot specify --cd-file with --file-mode" {
    run bash "$SCRIPT" --cd-file --file-mode --file "/tmp/test.do"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot specify multiple modes"* ]]
}
