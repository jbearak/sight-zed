#!/usr/bin/env bash
#
# test_helpers.sh - Test helper functions for property-based testing
#
# This file provides utilities for running property-based tests on the
# validation script functions.

set -euo pipefail

# Test result tracking
TEST_COUNT=0
TEST_PASSED=0
TEST_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get script directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$TEST_DIR")"
SCRIPT_DIR="$PROJECT_DIR"
VALIDATE_SCRIPT="$PROJECT_DIR/validate.sh"

# Source the validation script functions (without running main)
source_validate_functions() {
    # Create a temporary file that sources validate.sh but doesn't run main
    local tmp_source=$(mktemp)
    # Extract just the functions from validate.sh (everything before main "$@")
    sed '/^main "\$@"$/d' "$PROJECT_DIR/validate.sh" > "$tmp_source"
    source "$tmp_source"
    rm -f "$tmp_source"
}

# Assert equality
assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        echo -e "${RED}ASSERTION FAILED${NC}: $message"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        return 1
    fi
}

# Assert not empty
assert_not_empty() {
    local value="$1"
    local message="${2:-}"
    
    if [[ -n "$value" ]]; then
        return 0
    else
        echo -e "${RED}ASSERTION FAILED${NC}: $message"
        echo "  Value was empty"
        return 1
    fi
}

# Assert contains
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        echo -e "${RED}ASSERTION FAILED${NC}: $message"
        echo "  Expected to contain: '$needle'"
        echo "  In: '$haystack'"
        return 1
    fi
}

# Assert exit code
assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    if [[ "$expected" -eq "$actual" ]]; then
        return 0
    else
        echo -e "${RED}ASSERTION FAILED${NC}: $message"
        echo "  Expected exit code: $expected"
        echo "  Actual exit code:   $actual"
        return 1
    fi
}

# Assert success (exit code 0) - for bats compatibility
assert_success() {
    if [[ "$status" -eq 0 ]]; then
        return 0
    else
        echo "Expected success (exit code 0), got exit code $status"
        return 1
    fi
}

# Assert failure (non-zero exit code) - for bats compatibility
assert_failure() {
    if [[ "$status" -ne 0 ]]; then
        return 0
    else
        echo "Expected failure (non-zero exit code), got exit code 0"
        return 1
    fi
}

# Run a test case
run_test() {
    local test_name="$1"
    local test_func="$2"
    
    ((TEST_COUNT++)) || true
    
    echo -n "  Testing: $test_name... "
    
    if $test_func; then
        ((TEST_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}"
        return 0
    else
        ((TEST_FAILED++)) || true
        echo -e "${RED}FAIL${NC}"
        return 1
    fi
}

# Print test summary
print_test_summary() {
    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo "Total:  $TEST_COUNT"
    echo -e "Passed: ${GREEN}$TEST_PASSED${NC}"
    echo -e "Failed: ${RED}$TEST_FAILED${NC}"
    
    if [[ $TEST_FAILED -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Generate random version string for property testing
generate_random_version() {
    local major=$((RANDOM % 10))
    local minor=$((RANDOM % 100))
    local patch=$((RANDOM % 100))
    
    # Randomly add 'v' prefix
    if [[ $((RANDOM % 2)) -eq 0 ]]; then
        echo "v${major}.${minor}.${patch}"
    else
        echo "${major}.${minor}.${patch}"
    fi
}

# Generate random commit SHA for property testing
generate_random_sha() {
    # Generate a 40-character hex string
    local sha=""
    for i in {1..40}; do
        sha+=$(printf '%x' $((RANDOM % 16)))
    done
    echo "$sha"
}

# Create a temporary lib.rs file with a specific version
create_temp_lib_rs() {
    local version="$1"
    local tmpfile=$(mktemp)
    cat > "$tmpfile" << EOF
use zed_extension_api::{self as zed, DownloadedFileType, Result};

const SERVER_VERSION: &str = "$version";

struct SightExtension {
    cached_binary_path: Option<String>,
}
EOF
    echo "$tmpfile"
}

# Create a temporary extension.toml with a specific revision
create_temp_extension_toml() {
    local revision="$1"
    local tmpfile=$(mktemp)
    cat > "$tmpfile" << EOF
id = "sight"
name = "Sight - Stata Language Server"
version = "0.1.10"

[grammars.stata]
repository = "https://github.com/jbearak/tree-sitter-stata"
rev = "$revision"
EOF
    echo "$tmpfile"
}
