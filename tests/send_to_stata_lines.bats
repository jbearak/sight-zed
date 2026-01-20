#!/usr/bin/env bats

#
# send_to_stata_lines.bats - Property-based tests for line extraction functions
#
# Property 4: Upward Bounds Extraction
# Property 5: Downward Bounds Extraction
#
# **Validates: Requirements 3.1, 3.2, 3.5, 4.1, 4.2, 4.5**

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
# Test File Generators
# ============================================================================

# Generate a simple file with N lines (no continuations)
generate_simple_file() {
    local num_lines=$1
    local file="$TEMP_DIR/simple_$RANDOM.do"
    for ((i = 1; i <= num_lines; i++)); do
        echo "display \"line $i\""
    done > "$file"
    printf '%s' "$file"
}

# Generate a file with a continuation block at a specific position
# Args: total_lines, continuation_start, continuation_length
generate_continuation_file() {
    local total_lines=$1
    local cont_start=$2
    local cont_length=$3
    local file="$TEMP_DIR/cont_$RANDOM.do"
    
    for ((i = 1; i <= total_lines; i++)); do
        if [[ $i -ge $cont_start && $i -lt $((cont_start + cont_length)) ]]; then
            # This line is part of continuation (ends with ///)
            echo "local x$i = $i ///"
        else
            echo "display \"line $i\""
        fi
    done > "$file"
    printf '%s' "$file"
}

# Generate a random file with random continuation blocks
generate_random_file() {
    local num_lines=$((RANDOM % 10 + 3))  # 3-12 lines
    local file="$TEMP_DIR/random_$RANDOM.do"
    
    local in_continuation=false
    for ((i = 1; i <= num_lines; i++)); do
        if [[ "$in_continuation" == true ]]; then
            # 50% chance to continue, 50% to end
            if [[ $((RANDOM % 2)) -eq 0 && $i -lt $num_lines ]]; then
                echo "    x$i ///"
            else
                echo "    x$i"
                in_continuation=false
            fi
        else
            # 30% chance to start a continuation
            if [[ $((RANDOM % 10)) -lt 3 && $i -lt $num_lines ]]; then
                echo "local myvar = x$i ///"
                in_continuation=true
            else
                echo "display \"line $i\""
            fi
        fi
    done > "$file"
    printf '%s' "$file"
}

# Count lines in output
count_output_lines() {
    local output="$1"
    if [[ -z "$output" ]]; then
        echo 0
    else
        echo "$output" | wc -l | tr -d ' '
    fi
}

# Get line count of a file
get_file_line_count() {
    local file="$1"
    wc -l < "$file" | tr -d ' '
}

# Check if a line ends with continuation marker
line_ends_with_continuation() {
    local line="$1"
    [[ "$line" =~ ///[[:space:]]*$ ]]
}

# ============================================================================
# Property 4: Upward Bounds Extraction
# For any valid file and row number, the get_upward_lines function SHALL return
# bounds where:
# - start_line equals 1
# - end_line is greater than or equal to the input row
# - If the line at input row ends with ///, end_line extends to include the
#   complete statement
# **Validates: Requirements 3.1, 3.2, 3.5**
# ============================================================================

# Feature: stata-zed-tasks, Property 4: Upward Bounds Extraction
@test "Property 4: upward lines always start from line 1" {
    for ((iter = 0; iter < ITERATIONS; iter++)); do
        local file
        file=$(generate_random_file)
        local total_lines
        total_lines=$(get_file_line_count "$file")
        
        # Pick a random row
        local row=$((RANDOM % total_lines + 1))
        
        local output
        output=$(call_func get_upward_lines "$file" "$row")
        
        # First line of output should be first line of file
        local first_output_line
        first_output_line=$(echo "$output" | head -n 1)
        local first_file_line
        first_file_line=$(head -n 1 "$file")
        
        if [[ "$first_output_line" != "$first_file_line" ]]; then
            echo "FAIL: iteration=$iter"
            echo "File: $file"
            echo "Row: $row"
            echo "Expected first line: $first_file_line"
            echo "Got first line: $first_output_line"
            return 1
        fi
    done
}

# Feature: stata-zed-tasks, Property 4: Upward includes at least up to cursor row
@test "Property 4: upward lines include at least up to cursor row" {
    for ((iter = 0; iter < ITERATIONS; iter++)); do
        local file
        file=$(generate_simple_file $((RANDOM % 10 + 3)))
        local total_lines
        total_lines=$(get_file_line_count "$file")
        
        # Pick a random row
        local row=$((RANDOM % total_lines + 1))
        
        local output
        output=$(call_func get_upward_lines "$file" "$row")
        local output_lines
        output_lines=$(count_output_lines "$output")
        
        # Output should have at least 'row' lines
        if [[ $output_lines -lt $row ]]; then
            echo "FAIL: iteration=$iter"
            echo "File: $file"
            echo "Row: $row"
            echo "Output lines: $output_lines"
            echo "Expected at least: $row"
            return 1
        fi
    done
}

# Feature: stata-zed-tasks, Property 4: Upward extends forward for continuations
@test "Property 4: upward extends forward when cursor line has continuation" {
    for ((iter = 0; iter < ITERATIONS; iter++)); do
        # Create file with continuation at a known position
        local total_lines=$((RANDOM % 5 + 5))  # 5-9 lines
        local cont_start=$((RANDOM % (total_lines - 2) + 1))  # Start somewhere in middle
        local cont_length=$((RANDOM % 3 + 2))  # 2-4 lines of continuation
        
        # Ensure continuation doesn't exceed file
        if [[ $((cont_start + cont_length)) -gt $total_lines ]]; then
            cont_length=$((total_lines - cont_start))
        fi
        
        local file
        file=$(generate_continuation_file "$total_lines" "$cont_start" "$cont_length")
        
        # Set cursor to first line of continuation
        local row=$cont_start
        
        local output
        output=$(call_func get_upward_lines "$file" "$row")
        local output_lines
        output_lines=$(count_output_lines "$output")
        
        # Output should include all continuation lines
        local expected_end=$((cont_start + cont_length - 1))
        if [[ $output_lines -lt $expected_end ]]; then
            echo "FAIL: iteration=$iter"
            echo "File: $file"
            echo "Row: $row"
            echo "Continuation: lines $cont_start to $expected_end"
            echo "Output lines: $output_lines"
            echo "Expected at least: $expected_end"
            cat "$file"
            return 1
        fi
    done
}

# Feature: stata-zed-tasks, Property 4: Upward preserves line breaks
@test "Property 4: upward preserves line breaks" {
    for ((iter = 0; iter < ITERATIONS; iter++)); do
        local file
        file=$(generate_simple_file $((RANDOM % 5 + 3)))
        local total_lines
        total_lines=$(get_file_line_count "$file")
        
        local row=$total_lines  # Get all lines
        
        local output
        output=$(call_func get_upward_lines "$file" "$row")
        
        # Compare line by line
        local line_num=1
        while IFS= read -r expected_line; do
            local actual_line
            actual_line=$(echo "$output" | sed -n "${line_num}p")
            if [[ "$actual_line" != "$expected_line" ]]; then
                echo "FAIL: iteration=$iter, line=$line_num"
                echo "Expected: $expected_line"
                echo "Got: $actual_line"
                return 1
            fi
            line_num=$((line_num + 1))
        done < "$file"
    done
}

# ============================================================================
# Property 5: Downward Bounds Extraction
# For any valid file and row number, the get_downward_lines function SHALL return
# bounds where:
# - start_line is less than or equal to the input row
# - end_line equals the last line of the file
# - If the line before input row ends with ///, start_line is adjusted to the
#   statement start
# **Validates: Requirements 4.1, 4.2, 4.5**
# ============================================================================

# Feature: stata-zed-tasks, Property 5: Downward Bounds Extraction
@test "Property 5: downward lines always end at last line" {
    for ((iter = 0; iter < ITERATIONS; iter++)); do
        local file
        file=$(generate_random_file)
        local total_lines
        total_lines=$(get_file_line_count "$file")
        
        # Pick a random row
        local row=$((RANDOM % total_lines + 1))
        
        local output
        output=$(call_func get_downward_lines "$file" "$row")
        
        # Last line of output should be last line of file
        local last_output_line
        last_output_line=$(echo "$output" | tail -n 1)
        local last_file_line
        last_file_line=$(tail -n 1 "$file")
        
        if [[ "$last_output_line" != "$last_file_line" ]]; then
            echo "FAIL: iteration=$iter"
            echo "File: $file"
            echo "Row: $row"
            echo "Expected last line: $last_file_line"
            echo "Got last line: $last_output_line"
            return 1
        fi
    done
}

# Feature: stata-zed-tasks, Property 5: Downward starts at or before cursor row
@test "Property 5: downward lines start at or before cursor row" {
    for ((iter = 0; iter < ITERATIONS; iter++)); do
        local file
        file=$(generate_simple_file $((RANDOM % 10 + 3)))
        local total_lines
        total_lines=$(get_file_line_count "$file")
        
        # Pick a random row
        local row=$((RANDOM % total_lines + 1))
        
        local output
        output=$(call_func get_downward_lines "$file" "$row")
        local output_lines
        output_lines=$(count_output_lines "$output")
        
        # Output should have at least (total_lines - row + 1) lines
        local expected_min=$((total_lines - row + 1))
        if [[ $output_lines -lt $expected_min ]]; then
            echo "FAIL: iteration=$iter"
            echo "File: $file"
            echo "Row: $row"
            echo "Total lines: $total_lines"
            echo "Output lines: $output_lines"
            echo "Expected at least: $expected_min"
            return 1
        fi
    done
}

# Feature: stata-zed-tasks, Property 5: Downward extends backward for continuations
@test "Property 5: downward extends backward when on continuation line" {
    for ((iter = 0; iter < ITERATIONS; iter++)); do
        # Create file with continuation at a known position
        local total_lines=$((RANDOM % 5 + 5))  # 5-9 lines
        local cont_start=$((RANDOM % (total_lines - 3) + 2))  # Start after line 1
        local cont_length=$((RANDOM % 3 + 2))  # 2-4 lines of continuation
        
        # Ensure continuation doesn't exceed file
        if [[ $((cont_start + cont_length)) -gt $total_lines ]]; then
            cont_length=$((total_lines - cont_start))
        fi
        
        local file
        file=$(generate_continuation_file "$total_lines" "$cont_start" "$cont_length")
        
        # Set cursor to last line of continuation (which is a continuation of previous)
        local row=$((cont_start + cont_length - 1))
        
        local output
        output=$(call_func get_downward_lines "$file" "$row")
        
        # First line of output should be the start of the continuation block
        local first_output_line
        first_output_line=$(echo "$output" | head -n 1)
        local expected_first_line
        expected_first_line=$(sed -n "${cont_start}p" "$file")
        
        if [[ "$first_output_line" != "$expected_first_line" ]]; then
            echo "FAIL: iteration=$iter"
            echo "File: $file"
            echo "Row: $row"
            echo "Continuation start: $cont_start"
            echo "Expected first line: $expected_first_line"
            echo "Got first line: $first_output_line"
            cat "$file"
            return 1
        fi
    done
}

# Feature: stata-zed-tasks, Property 5: Downward preserves line breaks
@test "Property 5: downward preserves line breaks" {
    for ((iter = 0; iter < ITERATIONS; iter++)); do
        local file
        file=$(generate_simple_file $((RANDOM % 5 + 3)))
        local total_lines
        total_lines=$(get_file_line_count "$file")
        
        local row=1  # Get all lines
        
        local output
        output=$(call_func get_downward_lines "$file" "$row")
        
        # Compare line by line
        local line_num=1
        while IFS= read -r expected_line; do
            local actual_line
            actual_line=$(echo "$output" | sed -n "${line_num}p")
            if [[ "$actual_line" != "$expected_line" ]]; then
                echo "FAIL: iteration=$iter, line=$line_num"
                echo "Expected: $expected_line"
                echo "Got: $actual_line"
                return 1
            fi
            line_num=$((line_num + 1))
        done < "$file"
    done
}

# ============================================================================
# Unit Tests for Edge Cases
# ============================================================================

@test "get_upward_lines: single line file" {
    local file="$TEMP_DIR/single.do"
    echo "display 1" > "$file"
    
    local output
    output=$(call_func get_upward_lines "$file" 1)
    
    [ "$output" = "display 1" ]
}

@test "get_upward_lines: cursor on first line" {
    local file="$TEMP_DIR/multi.do"
    printf 'line 1\nline 2\nline 3\n' > "$file"
    
    local output
    output=$(call_func get_upward_lines "$file" 1)
    
    [ "$output" = "line 1" ]
}

@test "get_upward_lines: cursor on last line" {
    local file="$TEMP_DIR/multi.do"
    printf 'line 1\nline 2\nline 3\n' > "$file"
    
    local output
    output=$(call_func get_upward_lines "$file" 3)
    local expected
    expected=$(printf 'line 1\nline 2\nline 3')
    
    [ "$output" = "$expected" ]
}

@test "get_upward_lines: extends through continuation" {
    local file="$TEMP_DIR/cont.do"
    printf 'line 1\nlocal x = 1 ///\n    + 2 ///\n    + 3\nline 5\n' > "$file"
    
    # Cursor on line 2 (first continuation line)
    local output
    output=$(call_func get_upward_lines "$file" 2)
    
    # Should include lines 1-4 (complete statement)
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    [ "$line_count" -eq 4 ]
}

@test "get_upward_lines: row out of bounds" {
    local file="$TEMP_DIR/small.do"
    printf 'line 1\nline 2\n' > "$file"
    
    run call_func get_upward_lines "$file" 5
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of bounds"* ]]
}

@test "get_upward_lines: file not found" {
    run call_func get_upward_lines "/nonexistent/file.do" 1
    [ "$status" -eq 2 ]
    [[ "$output" == *"Cannot read file"* ]]
}

@test "get_downward_lines: single line file" {
    local file="$TEMP_DIR/single.do"
    echo "display 1" > "$file"
    
    local output
    output=$(call_func get_downward_lines "$file" 1)
    
    [ "$output" = "display 1" ]
}

@test "get_downward_lines: cursor on first line" {
    local file="$TEMP_DIR/multi.do"
    printf 'line 1\nline 2\nline 3\n' > "$file"
    
    local output
    output=$(call_func get_downward_lines "$file" 1)
    local expected
    expected=$(printf 'line 1\nline 2\nline 3')
    
    [ "$output" = "$expected" ]
}

@test "get_downward_lines: cursor on last line" {
    local file="$TEMP_DIR/multi.do"
    printf 'line 1\nline 2\nline 3\n' > "$file"
    
    local output
    output=$(call_func get_downward_lines "$file" 3)
    
    [ "$output" = "line 3" ]
}

@test "get_downward_lines: extends backward through continuation" {
    local file="$TEMP_DIR/cont.do"
    printf 'line 1\nlocal x = 1 ///\n    + 2 ///\n    + 3\nline 5\n' > "$file"
    
    # Cursor on line 4 (last line of continuation)
    local output
    output=$(call_func get_downward_lines "$file" 4)
    
    # Should include lines 2-5 (statement start to end of file)
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    [ "$line_count" -eq 4 ]
    
    # First line should be the start of the continuation
    local first_line
    first_line=$(echo "$output" | head -n 1)
    [[ "$first_line" == "local x = 1 ///" ]]
}

@test "get_downward_lines: row out of bounds" {
    local file="$TEMP_DIR/small.do"
    printf 'line 1\nline 2\n' > "$file"
    
    run call_func get_downward_lines "$file" 5
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of bounds"* ]]
}

@test "get_downward_lines: file not found" {
    run call_func get_downward_lines "/nonexistent/file.do" 1
    [ "$status" -eq 2 ]
    [[ "$output" == *"Cannot read file"* ]]
}

# ============================================================================
# Tests with existing fixtures
# ============================================================================

@test "get_upward_lines: continuation.do fixture - cursor on line 2" {
    local file="$TEST_DIR/fixtures/continuation.do"
    
    local output
    output=$(call_func get_upward_lines "$file" 2)
    
    # Line 2 starts a continuation that ends at line 4, should get lines 1-4
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    [ "$line_count" -eq 4 ]
}

@test "get_downward_lines: continuation.do fixture - cursor on line 4" {
    local file="$TEST_DIR/fixtures/continuation.do"
    
    local output
    output=$(call_func get_downward_lines "$file" 4)
    
    # Line 4 is a continuation of line 2, should start from line 2
    local first_line
    first_line=$(echo "$output" | head -n 1)
    [[ "$first_line" == "regress y x1 x2 ///" ]]
}

@test "get_upward_lines: nested_continuation.do fixture - cursor on line 5" {
    local file="$TEST_DIR/fixtures/nested_continuation.do"
    
    local output
    output=$(call_func get_upward_lines "$file" 5)
    
    # Line 5 is in the middle of a continuation (lines 4-7), should get lines 1-7
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    [ "$line_count" -eq 7 ]
}

@test "get_downward_lines: nested_continuation.do fixture - cursor on line 6" {
    local file="$TEST_DIR/fixtures/nested_continuation.do"
    
    local output
    output=$(call_func get_downward_lines "$file" 6)
    
    # Line 6 is a continuation of line 4, should start from line 4
    local first_line
    first_line=$(echo "$output" | head -n 1)
    [[ "$first_line" == "local mylist a b c ///" ]]
}
