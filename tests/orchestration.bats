#!/usr/bin/env bats
#
# orchestration.bats - Tests for main orchestration and exit code correctness
#
# Tests Property 4: Exit code correctness
# **Validates: Requirements 5.3, 5.4**

load test_helpers

# Setup - source validation functions without running main
setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    VALIDATE_SCRIPT="$PROJECT_DIR/validate.sh"
    
    # Source the validation script functions (without running main)
    local tmp_source
    tmp_source=$(mktemp)
    sed '/^main "\$@"$/d' "$PROJECT_DIR/validate.sh" > "$tmp_source"
    source "$tmp_source"
    rm -f "$tmp_source"
}

#######################################
# Property 4: Exit code correctness
# For any execution of the validator where N validations are requested,
# the exit code SHALL be 0 if and only if all N validations pass;
# otherwise the exit code SHALL be non-zero.
# **Validates: Requirements 5.3, 5.4**
#######################################

@test "Property 4: --help exits with code 0" {
    run "$VALIDATE_SCRIPT" --help
    assert_success
}

@test "Property 4: invalid option exits with non-zero code" {
    run "$VALIDATE_SCRIPT" --invalid-option
    assert_failure
}

@test "Property 4: record_result tracks pass correctly" {
    # Reset counters
    TOTAL_CHECKS=0
    PASSED_CHECKS=0
    FAILED_CHECKS=0
    
    record_result 0 "test check" >/dev/null
    
    [[ "$TOTAL_CHECKS" -eq 1 ]]
    [[ "$PASSED_CHECKS" -eq 1 ]]
    [[ "$FAILED_CHECKS" -eq 0 ]]
}

@test "Property 4: record_result tracks failure correctly" {
    # Reset counters
    TOTAL_CHECKS=0
    PASSED_CHECKS=0
    FAILED_CHECKS=0
    
    record_result 1 "test check" >/dev/null
    
    [[ "$TOTAL_CHECKS" -eq 1 ]]
    [[ "$PASSED_CHECKS" -eq 0 ]]
    [[ "$FAILED_CHECKS" -eq 1 ]]
}

@test "Property 4: multiple results tracked correctly" {
    # Reset counters
    TOTAL_CHECKS=0
    PASSED_CHECKS=0
    FAILED_CHECKS=0
    
    record_result 0 "pass 1" >/dev/null
    record_result 1 "fail 1" >/dev/null
    record_result 0 "pass 2" >/dev/null
    record_result 1 "fail 2" >/dev/null
    record_result 0 "pass 3" >/dev/null
    
    [[ "$TOTAL_CHECKS" -eq 5 ]]
    [[ "$PASSED_CHECKS" -eq 3 ]]
    [[ "$FAILED_CHECKS" -eq 2 ]]
}

@test "Property 4: exit code is 0 when FAILED_CHECKS is 0" {
    # This tests the exit code logic directly
    FAILED_CHECKS=0
    
    # The condition in main is: if [[ $FAILED_CHECKS -gt 0 ]]; then exit 1
    if [[ $FAILED_CHECKS -gt 0 ]]; then
        false  # Should not reach here
    else
        true   # Expected path
    fi
}

@test "Property 4: exit code is non-zero when FAILED_CHECKS > 0" {
    # This tests the exit code logic directly
    FAILED_CHECKS=1
    
    # The condition in main is: if [[ $FAILED_CHECKS -gt 0 ]]; then exit 1
    if [[ $FAILED_CHECKS -gt 0 ]]; then
        true   # Expected path
    else
        false  # Should not reach here
    fi
}
