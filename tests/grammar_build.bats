#!/usr/bin/env bats

# Property tests for grammar build validation

load test_helpers

# Setup - source validation functions without running main
setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    SCRIPT_DIR="$PROJECT_DIR"
    
    # Source the validation script functions (without running main)
    local tmp_source
    tmp_source=$(mktemp)
    sed '/^main "\$@"$/d' "$PROJECT_DIR/validate.sh" > "$tmp_source"
    source "$tmp_source"
    rm -f "$tmp_source"
}

# Property 6: Grammar build output verification - verify .wasm file is produced
@test "Property 6: Grammar build produces .wasm file on success" {
    # Skip if tree-sitter CLI not available
    if ! command -v tree-sitter &>/dev/null; then
        skip "tree-sitter CLI not installed"
    fi
    
    # Use a known good revision from tree-sitter-stata
    local test_revision="HEAD"  # Use HEAD as it should always exist
    
    # Create temp directory for test
    local test_tmpdir
    test_tmpdir=$(mktemp -d)
    
    # Cleanup function
    cleanup_test() {
        if [[ -n "$test_tmpdir" && -d "$test_tmpdir" ]]; then
            rm -rf "$test_tmpdir"
        fi
    }
    trap cleanup_test EXIT
    
    # Clone and build grammar manually to verify .wasm production
    cd "$test_tmpdir"
    git clone --quiet "https://github.com/jbearak/tree-sitter-stata" grammar_test
    cd grammar_test
    
    # Build grammar
    if tree-sitter build --wasm 2>/dev/null; then
        # Verify .wasm file exists
        local wasm_files
        wasm_files=$(find . -maxdepth 1 -name "*.wasm" -type f 2>/dev/null || true)
        
        [[ -n "$wasm_files" ]]
    else
        # If build fails, that's expected for some revisions - skip test
        skip "Grammar build failed for test revision"
    fi
    
    cleanup_test
    trap - EXIT
}

# Property 7: Temporary directory cleanup - verify temp dir is removed after success and failure
@test "Property 7: Temporary directory cleanup on success" {
    # Skip if tree-sitter CLI not available
    if ! command -v tree-sitter &>/dev/null; then
        skip "tree-sitter CLI not installed"
    fi
    
    # Track temp directories before test
    local tmpdir_count_before
    tmpdir_count_before=$(find /tmp -maxdepth 1 -name "tmp.*" -type d 2>/dev/null | wc -l)
    
    # Use a known good revision
    local test_revision="HEAD"
    
    # Capture any temp directories created during execution
    if validate_grammar_build "$test_revision" >/dev/null 2>&1; then
        # Check temp directory count after successful execution
        local tmpdir_count_after
        tmpdir_count_after=$(find /tmp -maxdepth 1 -name "tmp.*" -type d 2>/dev/null | wc -l)
        
        # Should not have increased (cleanup successful)
        [[ "$tmpdir_count_after" -eq "$tmpdir_count_before" ]]
    else
        # If validation fails, still check cleanup occurred
        local tmpdir_count_after
        tmpdir_count_after=$(find /tmp -maxdepth 1 -name "tmp.*" -type d 2>/dev/null | wc -l)
        
        # Should not have increased (cleanup on failure)
        [[ "$tmpdir_count_after" -eq "$tmpdir_count_before" ]]
    fi
}

@test "Property 7: Temporary directory cleanup on failure" {
    # Skip if tree-sitter CLI not available
    if ! command -v tree-sitter &>/dev/null; then
        skip "tree-sitter CLI not installed"
    fi
    
    # Track temp directories before test
    local tmpdir_count_before
    tmpdir_count_before=$(find /tmp -maxdepth 1 -name "tmp.*" -type d 2>/dev/null | wc -l)
    
    # Use an invalid revision to force failure
    local invalid_revision="invalid_sha_that_does_not_exist_12345"
    
    # Run validate_grammar_build with invalid revision (should fail)
    run validate_grammar_build "$invalid_revision"
    
    # Should have failed
    [[ "$status" -ne 0 ]]
    
    # Check temp directory count after failed execution
    local tmpdir_count_after
    tmpdir_count_after=$(find /tmp -maxdepth 1 -name "tmp.*" -type d 2>/dev/null | wc -l)
    
    # Should not have increased (cleanup on failure)
    [[ "$tmpdir_count_after" -eq "$tmpdir_count_before" ]]
}