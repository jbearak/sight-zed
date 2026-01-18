# Implementation Plan: Extension Build Validation

## Overview

Implement a shell-based validation script that verifies the Sight Zed extension can build successfully with its specified LSP and tree-sitter grammar revisions. The script will be executable locally and in CI.

## Tasks

- [ ] 1. Create validation script with configuration parsing
  - [ ] 1.1 Create `scripts/validate.sh` with shebang and basic structure
    - Add argument parsing for `--all`, `--lsp`, `--grammar-rev`, `--build`, `--grammar-build` flags
    - Add help text with `--help` flag
    - _Requirements: 5.1, 5.2_
  
  - [ ] 1.2 Implement `extract_server_version` function
    - Parse `src/lib.rs` to extract SERVER_VERSION constant
    - Handle missing file and missing constant errors
    - _Requirements: 1.1, 6.1, 6.3_
  
  - [ ] 1.3 Implement `extract_grammar_revision` function
    - Parse `extension.toml` to extract rev field under `[grammars.stata]`
    - Handle missing file and missing field errors
    - _Requirements: 2.1, 6.2, 6.3_
  
  - [ ] 1.4 Write property tests for configuration parsing
    - **Property 1: Version extraction consistency**
    - **Property 2: Revision extraction consistency**
    - **Validates: Requirements 1.1, 2.1, 6.1, 6.2**

- [ ] 2. Implement LSP release validation
  - [ ] 2.1 Implement `validate_lsp_release` function
    - Query GitHub API for release by tag at `jbearak/sight`
    - Support GITHUB_TOKEN environment variable for authentication
    - Handle 404 and network errors
    - _Requirements: 1.2, 1.4_
  
  - [ ] 2.2 Implement asset checking logic
    - Check for all 5 required binary assets in release
    - Report list of missing assets if any
    - _Requirements: 1.3, 1.5_
  
  - [ ] 2.3 Write property test for asset completeness
    - **Property 3: Asset completeness identification**
    - **Validates: Requirements 1.3, 1.5**

- [ ] 3. Implement grammar revision validation
  - [ ] 3.1 Implement `validate_grammar_revision` function
    - Query GitHub API for commit at `jbearak/tree-sitter-stata`
    - Handle 404 and network errors
    - _Requirements: 2.2, 2.3_

- [ ] 4. Implement extension build validation
  - [ ] 4.1 Implement `validate_extension_build` function
    - Execute `cargo build --release --target wasm32-wasip1`
    - Check for wasm32-wasip1 target availability
    - Verify output WASM file exists
    - Report file size on success
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [ ] 5. Implement grammar build validation (Required)
  - [ ] 5.1 Implement `validate_grammar_build` function
    - Clone tree-sitter-stata at specified revision to temp directory
    - Build grammar using `tree-sitter build --wasm`
    - Verify grammar WASM artifact produced
    - Clean up temp directory
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_
  
  - [ ] 5.2 Write property test for grammar build validation
    - **Property 5: Grammar WASM production**
    - **Validates: Requirements 4.2, 4.4**

- [ ] 6. Implement main orchestration and result reporting
  - [ ] 6.1 Implement result aggregation and reporting
    - Track pass/fail status for each validation
    - Output clear results with PASS/FAIL indicators
    - _Requirements: 5.5_
  
  - [ ] 6.2 Implement exit code logic
    - Exit 0 when all requested validations pass
    - Exit non-zero when any validation fails
    - _Requirements: 5.3, 5.4_
  
  - [ ] 6.3 Write property test for exit code correctness
    - **Property 4: Exit code correctness**
    - **Validates: Requirements 5.3, 5.4**

- [ ] 7. Checkpoint - Verify all validations work
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 8. Update documentation
  - [ ] 8.1 Add validation section to AGENTS.md
    - Document how to run full validation suite
    - Document individual validation flags
    - List prerequisites (curl, jq, cargo, rustup target)
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

- [ ] 9. Final checkpoint - Ensure script works end-to-end
  - Run `./scripts/validate.sh --all` and verify all checks pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- The script uses `curl` for GitHub API calls and `jq` for JSON parsing
- GITHUB_TOKEN environment variable is optional but recommended to avoid rate limits
- Grammar build validation requires `tree-sitter` CLI to be installed
