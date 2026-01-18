#!/usr/bin/env bats

#
# send_to_stata.bats - Unit tests for send-to-stata.sh
#
# Tests argument parsing, statement detection, Stata detection, and path escaping.
# **Validates: Requirements 1.1-1.7, 2.1-2.5, 3.1-3.4, 4.1-4.5, 7.1-7.4**

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    SCRIPT="$PROJECT_DIR/send-to-stata.sh"
    FIXTURES="$TEST_DIR/fixtures"
    TEMP_DIR=$(mktemp -d)
}

teardown() {
    [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}

# ============================================================================
# Argument Parsing Tests
# ============================================================================

@test "argument parsing: no arguments shows error" {
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: No arguments provided"* ]]
}

@test "argument parsing: --help shows usage" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "argument parsing: unknown argument shows error" {
    run "$SCRIPT" --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Unknown argument"* ]]
}

@test "argument parsing: --statement without --file shows error" {
    run "$SCRIPT" --statement --row 1
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: --file <path> is required"* ]]
}

@test "argument parsing: --statement without --row or --text shows error" {
    run "$SCRIPT" --statement --file "$FIXTURES/simple.do"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: --statement mode requires --stdin, --text, or --row"* ]]
}

@test "argument parsing: --row with non-integer shows error" {
    run "$SCRIPT" --statement --file "$FIXTURES/simple.do" --row abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: --row must be a positive integer"* ]]
}

@test "argument parsing: --row with zero shows error" {
    run "$SCRIPT" --statement --file "$FIXTURES/simple.do" --row 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: --row must be a positive integer"* ]]
}

@test "argument parsing: --row with negative shows error" {
    run "$SCRIPT" --statement --file "$FIXTURES/simple.do" --row -1
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: --row must be a positive integer"* ]]
}

@test "argument parsing: multiple modes shows error" {
    run "$SCRIPT" --statement --statement
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Cannot specify multiple modes"* ]]
}

# ============================================================================
# Stdin Mode Argument Tests
# ============================================================================

@test "argument parsing: --stdin flag is recognized" {
    run "$SCRIPT" --statement --stdin --file "$FIXTURES/simple.do" </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"stdin is empty"* ]]
}

@test "argument parsing: --stdin and --text are mutually exclusive" {
    run "$SCRIPT" --statement --stdin --text "test" --file "$FIXTURES/simple.do"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--stdin and --text are mutually exclusive"* ]]
}

@test "argument parsing: --stdin with --row is valid" {
    run env STATA_APP=StataMP "$SCRIPT" --statement --stdin --file "$FIXTURES/simple.do" --row 2 </dev/null
    [[ "$status" -eq 0 || "$status" -eq 5 ]]
}

# ============================================================================
# Stdin Content Tests
# ============================================================================

@test "stdin: simple content via stdin" {
    local content="display 123"
    temp_file=$(printf '%s' "$content" | bash -c "export TMPDIR='$TEMP_DIR'; source '$SCRIPT'; f=\$(create_temp_file_path); read_stdin_to_file \"\$f\" 0 >/dev/null; echo \"\$f\"")
    [ -f "$temp_file" ]
    [ "$(cat "$temp_file")" = "$content" ]
}

@test "stdin: compound string via stdin" {
    # Stata compound string: `"test"'
    local content=$'`"test"\''
    temp_file=$(printf '%s' "$content" | bash -c "export TMPDIR='$TEMP_DIR'; source '$SCRIPT'; f=\$(create_temp_file_path); read_stdin_to_file \"\$f\" 0 >/dev/null; echo \"\$f\"")
    [ -f "$temp_file" ]
    [ "$(cat "$temp_file")" = "$content" ]
}

@test "stdin: content with backticks" {
    local content='display `var`'
    temp_file=$(printf '%s' "$content" | bash -c "export TMPDIR='$TEMP_DIR'; source '$SCRIPT'; f=\$(create_temp_file_path); read_stdin_to_file \"\$f\" 0 >/dev/null; echo \"\$f\"")
    [ -f "$temp_file" ]
    [ "$(cat "$temp_file")" = "$content" ]
}

@test "stdin: content with dollar signs" {
    local content='display $var'
    temp_file=$(printf '%s' "$content" | bash -c "export TMPDIR='$TEMP_DIR'; source '$SCRIPT'; f=\$(create_temp_file_path); read_stdin_to_file \"\$f\" 0 >/dev/null; echo \"\$f\"")
    [ -f "$temp_file" ]
    [ "$(cat "$temp_file")" = "$content" ]
}

@test "stdin: preserves trailing newline" {
    # Two bytes: 'a' + '\n'
    temp_file=$(printf 'a\n' | bash -c "export TMPDIR='$TEMP_DIR'; source '$SCRIPT'; f=\$(create_temp_file_path); read_stdin_to_file \"\$f\" 0 >/dev/null; echo \"\$f\"")
    [ -f "$temp_file" ]

    run wc -c < "$temp_file"
    [ "$status" -eq 0 ]
    [[ "$(echo "$output" | tr -d ' ')" -eq 2 ]]

    # Verify exact bytes: 0x61 0x0a
    run od -An -tx1 -v "$temp_file"
    [ "$status" -eq 0 ]
    hex=$(echo "$output" | tr -d ' \n')
    [ "$hex" = "610a" ]
}

@test "stdin: enforces size limit" {
    run bash -c "source '$SCRIPT'; f=\$(mktemp); printf 'ab' | read_stdin_to_file \"\$f\" 1"
    [ "$status" -eq 7 ]
    [[ "$output" == *"stdin content too large"* ]]
}

@test "applescript: cleanup on error deletes temp file when enabled" {
    temp_file=$(bash -c "export TMPDIR='$TEMP_DIR'; source '$SCRIPT'; create_temp_file 'display 1'")
    [ -f "$temp_file" ]

    run bash -c "export STATA_CLEANUP_ON_ERROR=1; source '$SCRIPT'; send_to_stata DefinitelyNotAStataApp '$temp_file'"
    [ "$status" -eq 5 ]
    [ ! -f "$temp_file" ]
}

@test "stdin: empty stdin with --row fallback" {
    run env STATA_APP=StataMP "$SCRIPT" --statement --stdin --file "$FIXTURES/simple.do" --row 2 </dev/null
    [[ "$status" -eq 0 || "$status" -eq 5 ]]
}

@test "stdin: empty stdin without --row shows error" {
    run "$SCRIPT" --statement --stdin --file "$FIXTURES/simple.do" </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"stdin is empty and no --row provided"* ]]
}

# ============================================================================
# File Validation Tests
# ============================================================================

@test "file validation: non-existent file shows error" {
    run env STATA_APP=StataMP "$SCRIPT" --file --file "/nonexistent/path.do"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Error: Cannot read file"* ]]
}

# ============================================================================
# Statement Detection Tests - Single Line
# ============================================================================

# Helper to call functions from the script
call_func() {
    local func="$1"
    shift
    bash -c "source '$SCRIPT'; $func \"\$@\"" -- "$@"
}

@test "statement detection: single line statement" {
    echo 'display "hello"' > "$TEMP_DIR/test.do"
    run call_func detect_statement "$TEMP_DIR/test.do" 1
    [ "$status" -eq 0 ]
    [[ "$output" == 'display "hello"' ]]
}

@test "statement detection: second line of simple file" {
    run call_func detect_statement "$FIXTURES/simple.do" 2
    [ "$status" -eq 0 ]
    [[ "$output" == 'display "Hello World"' ]]
}

# ============================================================================
# Statement Detection Tests - Continuation
# ============================================================================

@test "statement detection: cursor on first line of continuation" {
    run call_func detect_statement "$FIXTURES/continuation.do" 2
    [ "$status" -eq 0 ]
    # Should include all three lines of the continuation
    [[ "$output" == *"regress y x1 x2 ///"* ]]
    [[ "$output" == *"x3 x4 ///"* ]]
    [[ "$output" == *"x5 x6"* ]]
}

@test "statement detection: cursor on middle line of continuation" {
    run call_func detect_statement "$FIXTURES/continuation.do" 3
    [ "$status" -eq 0 ]
    [[ "$output" == *"regress y x1 x2 ///"* ]]
    [[ "$output" == *"x3 x4 ///"* ]]
    [[ "$output" == *"x5 x6"* ]]
}

@test "statement detection: cursor on last line of continuation" {
    run call_func detect_statement "$FIXTURES/continuation.do" 4
    [ "$status" -eq 0 ]
    [[ "$output" == *"regress y x1 x2 ///"* ]]
    [[ "$output" == *"x5 x6"* ]]
}

@test "statement detection: line after continuation is separate" {
    run call_func detect_statement "$FIXTURES/continuation.do" 5
    [ "$status" -eq 0 ]
    [[ "$output" == 'display "done"' ]]
}

# ============================================================================
# Statement Detection Tests - Nested/Chained Continuation
# ============================================================================

@test "statement detection: chained continuation from first line" {
    run call_func detect_statement "$FIXTURES/nested_continuation.do" 4
    [ "$status" -eq 0 ]
    [[ "$output" == *"local mylist a b c ///"* ]]
    [[ "$output" == *"j k l"* ]]
}

@test "statement detection: chained continuation from middle" {
    run call_func detect_statement "$FIXTURES/nested_continuation.do" 6
    [ "$status" -eq 0 ]
    [[ "$output" == *"local mylist a b c ///"* ]]
    [[ "$output" == *"g h i ///"* ]]
}

# ============================================================================
# Statement Detection Tests - Trailing Whitespace
# ============================================================================

@test "statement detection: continuation with trailing whitespace" {
    run call_func detect_statement "$FIXTURES/trailing_whitespace.do" 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"regress y x1 ///"* ]]
    [[ "$output" == *"x2 x3"* ]]
}

# ============================================================================
# Statement Detection Tests - Edge Cases
# ============================================================================

@test "statement detection: row out of bounds shows error" {
    run call_func detect_statement "$FIXTURES/simple.do" 100
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Row 100 is out of bounds"* ]]
}

@test "statement detection: empty file returns empty" {
    echo -n "" > "$TEMP_DIR/empty.do"
    run call_func detect_statement "$TEMP_DIR/empty.do" 1
    # Empty file has 0 lines, so returns empty string
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ============================================================================
# Stata Detection Tests
# ============================================================================

@test "stata detection: uses STATA_APP env var" {
    run bash -c "export STATA_APP=TestStata; source '$SCRIPT'; detect_stata_app"
    [ "$status" -eq 0 ]
    [ "$output" = "TestStata" ]
}

@test "stata detection: no stata found shows error" {
    # Unset STATA_APP and ensure no Stata in /Applications
    run bash -c "unset STATA_APP; source '$SCRIPT'; detect_stata_app"
    # This will either find Stata (if installed) or exit with code 4
    if [ "$status" -eq 4 ]; then
        [[ "$output" == *"Error: No Stata installation found"* ]]
    else
        # Stata is installed on this system, which is fine
        [ "$status" -eq 0 ]
    fi
}

# ============================================================================
# Path Escaping Tests
# ============================================================================

@test "path escaping: simple path unchanged" {
    run call_func escape_for_applescript "/tmp/test.do"
    [ "$status" -eq 0 ]
    [ "$output" = "/tmp/test.do" ]
}

@test "path escaping: path with spaces" {
    run call_func escape_for_applescript "/tmp/my file.do"
    [ "$status" -eq 0 ]
    [ "$output" = "/tmp/my file.do" ]
}

@test "path escaping: path with backslash" {
    run call_func escape_for_applescript '/tmp/test\path.do'
    [ "$status" -eq 0 ]
    [ "$output" = '/tmp/test\\path.do' ]
}

@test "path escaping: path with double quote" {
    run call_func escape_for_applescript '/tmp/test"file.do'
    [ "$status" -eq 0 ]
    [ "$output" = '/tmp/test\"file.do' ]
}

@test "path escaping: path with both backslash and quote" {
    run call_func escape_for_applescript '/tmp/a\b"c.do'
    [ "$status" -eq 0 ]
    [ "$output" = '/tmp/a\\b\"c.do' ]
}

# ============================================================================
# Temp File Creation Tests
# ============================================================================

@test "temp file: creates file in TMPDIR" {
    run bash -c "export TMPDIR='$TEMP_DIR'; source '$SCRIPT'; create_temp_file 'test content'"
    [ "$status" -eq 0 ]
    [[ "$output" == "$TEMP_DIR/stata_send_"*".do" ]]
    [ -f "$output" ]
}

@test "temp file: has .do extension" {
    run bash -c "export TMPDIR='$TEMP_DIR'; source '$SCRIPT'; create_temp_file 'test'"
    [ "$status" -eq 0 ]
    [[ "$output" == *.do ]]
}

@test "temp file: contains correct content" {
    local content="display \"hello world\""
    temp_file=$(bash -c "export TMPDIR='$TEMP_DIR'; source '$SCRIPT'; create_temp_file '$content'")
    [ -f "$temp_file" ]
    [ "$(cat "$temp_file")" = "$content" ]
}

# ============================================================================
# Integration Tests (with mocked Stata)
# ============================================================================

@test "integration: --file mode with STATA_APP set" {
    # AppleScript DoCommandAsync succeeds even if Stata isn't running
    # (it queues the command or launches Stata)
    run env STATA_APP=StataMP "$SCRIPT" --file --file "$FIXTURES/simple.do"
    # Should succeed (exit 0) or fail with AppleScript error (exit 5)
    [[ "$status" -eq 0 || "$status" -eq 5 ]]
}

@test "integration: --statement mode with --text" {
    run env STATA_APP=StataMP "$SCRIPT" --statement --file "$FIXTURES/simple.do" --text "display 1"
    [[ "$status" -eq 0 || "$status" -eq 5 ]]
}

@test "integration: --statement mode with --row" {
    run env STATA_APP=StataMP "$SCRIPT" --statement --file "$FIXTURES/simple.do" --row 2
    [[ "$status" -eq 0 || "$status" -eq 5 ]]
}
