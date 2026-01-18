#!/usr/bin/env bats

load test_helpers

@test "Property 4: Exit code correctness - all validations pass" {
    # Mock successful validations
    export MOCK_LSP_SUCCESS=1
    export MOCK_GRAMMAR_SUCCESS=1
    export MOCK_BUILD_SUCCESS=1
    export MOCK_GRAMMAR_BUILD_SUCCESS=1
    
    run "$VALIDATE_SCRIPT" --all
    assert_success
}

@test "Property 4: Exit code correctness - LSP validation fails" {
    export MOCK_LSP_SUCCESS=0
    export MOCK_GRAMMAR_SUCCESS=1
    export MOCK_BUILD_SUCCESS=1
    export MOCK_GRAMMAR_BUILD_SUCCESS=1
    
    run "$VALIDATE_SCRIPT" --all
    assert_failure
}

@test "Property 4: Exit code correctness - single validation passes" {
    export MOCK_LSP_SUCCESS=1
    
    run "$VALIDATE_SCRIPT" --lsp
    assert_success
}

@test "Property 4: Exit code correctness - single validation fails" {
    export MOCK_LSP_SUCCESS=0
    
    run "$VALIDATE_SCRIPT" --lsp
    assert_failure
}