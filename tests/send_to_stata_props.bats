#!/usr/bin/env bats

#
# send_to_stata_props.bats - Property-based tests for send-to-stata.sh
#
# Property 1: Statement Detection with Continuations
# Property 4: Temp File Creation
#
# **Validates: Requirements 1.2-1.5, 2.2, 4.1, 4.3-4.5, 8.1-8.3**

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
# Property 1: Statement Detection with Continuations
# For any Stata file and any cursor row, the extracted statement SHALL include
# all lines that are part of the same statement (continuation handling).
# **Validates: Requirements 1.2, 1.3, 1.4, 4.1, 4.3, 4.4, 4.5**
# ============================================================================

# Generate a random Stata file with statements and continuations
# Returns: path to generated file, and metadata about statement boundaries
generate_stata_file() {
    local file="$TEMP_DIR/generated_$RANDOM.do"
    local num_statements=$((RANDOM % 5 + 1))  # 1-5 statements
    local line_num=1
    local -a statement_starts=()
    local -a statement_ends=()
    
    > "$file"  # Create empty file
    
    for ((s = 0; s < num_statements; s++)); do
        statement_starts+=($line_num)
        
        # Random number of continuation lines (0-3)
        local continuations=$((RANDOM % 4))
        
        # First line of statement
        if [[ $continuations -gt 0 ]]; then
            echo "statement_$s line_0 ///" >> "$file"
        else
            echo "statement_$s line_0" >> "$file"
        fi
        line_num=$((line_num + 1))
        
        # Continuation lines
        for ((c = 1; c <= continuations; c++)); do
            if [[ $c -lt $continuations ]]; then
                echo "    continuation_$c ///" >> "$file"
            else
                echo "    continuation_$c" >> "$file"
            fi
            line_num=$((line_num + 1))
        done
        
        statement_ends+=($((line_num - 1)))
    done
    
    # Output file path and metadata
    echo "$file"
    echo "${statement_starts[*]}"
    echo "${statement_ends[*]}"
}

# Feature: send-code-to-stata, Property 1: Statement Detection with Continuations
@test "Property 1: statement detection finds correct boundaries for random files" {
    for ((i = 0; i < ITERATIONS; i++)); do
        # Generate random file
        local output
        output=$(generate_stata_file)
        local file=$(echo "$output" | sed -n '1p')
        local starts=$(echo "$output" | sed -n '2p')
        local ends=$(echo "$output" | sed -n '3p')
        
        # Convert to arrays
        local -a start_arr=($starts)
        local -a end_arr=($ends)
        local num_statements=${#start_arr[@]}
        
        # For each statement, verify detection from any line within it
        for ((s = 0; s < num_statements; s++)); do
            local start=${start_arr[$s]}
            local end=${end_arr[$s]}
            
            # Test from each line in the statement
            for ((row = start; row <= end; row++)); do
                local result
                result=$(call_func detect_statement "$file" "$row")
                
                # Verify result contains first line of statement
                local first_line
                first_line=$(sed -n "${start}p" "$file")
                if [[ "$result" != *"$first_line"* ]]; then
                    echo "FAIL: iteration=$i, row=$row, expected first line '$first_line' in result"
                    echo "Result: $result"
                    echo "File contents:"
                    cat -n "$file"
                    return 1
                fi
                
                # Verify result contains last line of statement
                local last_line
                last_line=$(sed -n "${end}p" "$file")
                if [[ "$result" != *"$last_line"* ]]; then
                    echo "FAIL: iteration=$i, row=$row, expected last line '$last_line' in result"
                    echo "Result: $result"
                    return 1
                fi
            done
        done
        
        # Cleanup
        rm -f "$file"
    done
}

# Feature: send-code-to-stata, Property 1: Continuation marker at end of line
@test "Property 1: lines ending with /// include next line" {
    for ((i = 0; i < ITERATIONS; i++)); do
        local file="$TEMP_DIR/cont_$i.do"
        local num_continuations=$((RANDOM % 5 + 1))  # 1-5 continuations
        
        # Generate file with chained continuations
        > "$file"
        for ((c = 0; c < num_continuations; c++)); do
            if [[ $c -lt $((num_continuations - 1)) ]]; then
                echo "line_$c ///" >> "$file"
            else
                echo "line_$c" >> "$file"
            fi
        done
        
        # From any line, should get all lines
        local row=$((RANDOM % num_continuations + 1))
        local result
        result=$(call_func detect_statement "$file" "$row")
        
        # Count lines in result
        local result_lines
        result_lines=$(echo "$result" | wc -l | tr -d ' ')
        
        if [[ $result_lines -ne $num_continuations ]]; then
            echo "FAIL: iteration=$i, expected $num_continuations lines, got $result_lines"
            echo "File:"
            cat -n "$file"
            echo "Result:"
            echo "$result"
            return 1
        fi
        
        rm -f "$file"
    done
}

# Feature: send-code-to-stata, Property 1: Non-continuation lines are separate
@test "Property 1: lines without /// are separate statements" {
    for ((i = 0; i < ITERATIONS; i++)); do
        local file="$TEMP_DIR/sep_$i.do"
        local num_lines=$((RANDOM % 5 + 2))  # 2-6 lines
        
        # Generate file with separate statements (no continuations)
        > "$file"
        for ((l = 1; l <= num_lines; l++)); do
            echo "statement_$l" >> "$file"
        done
        
        # Each line should be its own statement
        local row=$((RANDOM % num_lines + 1))
        local result
        result=$(call_func detect_statement "$file" "$row")
        
        # Result should be exactly one line
        local result_lines
        result_lines=$(echo "$result" | wc -l | tr -d ' ')
        
        if [[ $result_lines -ne 1 ]]; then
            echo "FAIL: iteration=$i, row=$row, expected 1 line, got $result_lines"
            echo "Result: '$result'"
            return 1
        fi
        
        # Result should match the specific line
        local expected
        expected=$(sed -n "${row}p" "$file")
        if [[ "$result" != "$expected" ]]; then
            echo "FAIL: iteration=$i, row=$row, expected '$expected', got '$result'"
            return 1
        fi
        
        rm -f "$file"
    done
}

# ============================================================================
# Property 4: Temp File Creation
# For any script invocation, temp files SHALL be created in $TMPDIR with
# unique filenames matching pattern stata_send_*.do
# **Validates: Requirements 1.5, 2.2, 8.1, 8.2, 8.3**
# ============================================================================

# Feature: send-code-to-stata, Property 4: Unique filenames
@test "Property 4: temp files have unique names across invocations" {
    local -a created_files=()
    
    for ((i = 0; i < ITERATIONS; i++)); do
        local content="test content $RANDOM"
        local temp_file
        temp_file=$(bash -c "export TMPDIR='$TEMP_DIR'; source '$SCRIPT'; create_temp_file '$content'")
        
        # Check file was created
        if [[ ! -f "$temp_file" ]]; then
            echo "FAIL: iteration=$i, temp file not created: $temp_file"
            return 1
        fi
        
        # Check for uniqueness
        for existing in "${created_files[@]}"; do
            if [[ "$temp_file" == "$existing" ]]; then
                echo "FAIL: iteration=$i, duplicate filename: $temp_file"
                return 1
            fi
        done
        
        created_files+=("$temp_file")
    done
    
    # Verify we created the expected number of unique files
    if [[ ${#created_files[@]} -ne $ITERATIONS ]]; then
        echo "FAIL: expected $ITERATIONS unique files, got ${#created_files[@]}"
        return 1
    fi
}

# Feature: send-code-to-stata, Property 4: Correct directory
@test "Property 4: temp files created in TMPDIR" {
    for ((i = 0; i < ITERATIONS; i++)); do
        local custom_tmpdir="$TEMP_DIR/custom_$i"
        mkdir -p "$custom_tmpdir"
        
        local temp_file
        temp_file=$(bash -c "export TMPDIR='$custom_tmpdir'; source '$SCRIPT'; create_temp_file 'test'")
        
        # Verify file is in the custom TMPDIR
        if [[ "$temp_file" != "$custom_tmpdir/"* ]]; then
            echo "FAIL: iteration=$i, file not in TMPDIR"
            echo "Expected prefix: $custom_tmpdir/"
            echo "Got: $temp_file"
            return 1
        fi
    done
}

# Feature: send-code-to-stata, Property 4: Files persist after creation
@test "Property 4: temp files persist after script completion" {
    local -a created_files=()
    
    # Create multiple temp files
    for ((i = 0; i < 10; i++)); do
        local temp_file
        temp_file=$(bash -c "export TMPDIR='$TEMP_DIR'; source '$SCRIPT'; create_temp_file 'content $i'")
        created_files+=("$temp_file")
    done
    
    # Verify all files still exist
    for temp_file in "${created_files[@]}"; do
        if [[ ! -f "$temp_file" ]]; then
            echo "FAIL: temp file was deleted: $temp_file"
            return 1
        fi
    done
}

# Feature: send-code-to-stata, Property 4: Correct .do extension
@test "Property 4: temp files have .do extension" {
    for ((i = 0; i < ITERATIONS; i++)); do
        local temp_file
        temp_file=$(bash -c "export TMPDIR='$TEMP_DIR'; source '$SCRIPT'; create_temp_file 'test'")
        
        if [[ "$temp_file" != *.do ]]; then
            echo "FAIL: iteration=$i, file missing .do extension: $temp_file"
            return 1
        fi
    done
}

# Feature: send-code-to-stata, Property 4: Filename pattern
@test "Property 4: temp files match stata_send_*.do pattern" {
    for ((i = 0; i < ITERATIONS; i++)); do
        local temp_file
        temp_file=$(bash -c "export TMPDIR='$TEMP_DIR'; source '$SCRIPT'; create_temp_file 'test'")
        
        local basename
        basename=$(basename "$temp_file")
        
        if [[ ! "$basename" =~ ^stata_send_[A-Za-z0-9]+\.do$ ]]; then
            echo "FAIL: iteration=$i, filename doesn't match pattern: $basename"
            return 1
        fi
    done
}
