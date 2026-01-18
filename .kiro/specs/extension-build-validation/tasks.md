# Implementation Tasks

## Task 1: Create validation script skeleton
**Validates: Requirements 5.1, 5.2**
- [x] 1.1 Create `validate.sh` script with shebang and basic structure
- [x] 1.2 Add command-line argument parsing for `--all`, `--lsp`, `--grammar-rev`, `--build`, `--grammar-build` flags
- [x] 1.3 Add help text and usage information
- [x] 1.4 Set up result tracking variables and exit code logic

## Task 2: Implement configuration parser
**Validates: Requirements 6.1, 6.2, 6.3**
- [x] 2.1 Implement `extract_server_version()` function to parse SERVER_VERSION from `src/lib.rs`
- [x] 2.2 Implement `extract_grammar_revision()` function to parse rev from `extension.toml`
- [x] 2.3 Add error handling for missing files and parsing failures
- [x] 2.4 [PBT] Write property test for version extraction consistency (Property 1)
- [x] 2.5 [PBT] Write property test for revision extraction consistency (Property 2)

## Task 3: Implement LSP release validator
**Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 6.4**
- [x] 3.1 Implement `validate_lsp_release()` function with GitHub API call
- [x] 3.2 Add version prefix handling (with/without "v")
- [x] 3.3 Implement asset completeness checking for all 5 required binaries
- [x] 3.4 Add error reporting for missing release or assets
- [x] 3.5 [PBT] Write property test for asset completeness identification (Property 3)
- [x] 3.6 [PBT] Write property test for version prefix handling (Property 5)

## Task 4: Implement grammar revision validator
**Validates: Requirements 2.1, 2.2, 2.3**
- [x] 4.1 Implement `validate_grammar_revision()` function with GitHub API call
- [x] 4.2 Add error reporting for invalid commit SHA
- [x] 4.3 Handle GitHub API rate limiting with GITHUB_TOKEN support

## Task 5: Implement extension build validator
**Validates: Requirements 3.1, 3.2, 3.3, 3.4**
- [x] 5.1 Implement `validate_extension_build()` function
- [x] 5.2 Execute `cargo build --release --target wasm32-wasip1`
- [x] 5.3 Verify WASM output file exists and report size
- [x] 5.4 Add error handling for missing toolchain/target

## Task 6: Implement grammar build validator
**Validates: Requirements 4.1, 4.2, 4.3, 4.4, 4.5**
- [x] 6.1 Implement `validate_grammar_build()` function
- [x] 6.2 Clone tree-sitter-stata at specified revision to temp directory
- [x] 6.3 Execute `tree-sitter build --wasm`
- [x] 6.4 Verify `.wasm` file is produced
- [x] 6.5 Implement temp directory cleanup (success and failure paths)
- [x] 6.6 [PBT] Write property test for grammar build output verification (Property 6)
- [x] 6.7 [PBT] Write property test for temporary directory cleanup (Property 7)

## Task 7: Implement main orchestration and reporting
**Validates: Requirements 5.3, 5.4, 5.5**
- [ ] 7.1 Implement main() function to orchestrate validations
- [ ] 7.2 Add human-readable output formatting for each validation
- [ ] 7.3 Implement exit code logic (0 for all pass, non-zero for any failure)
- [ ] 7.4 [PBT] Write property test for exit code correctness (Property 4)

## Task 8: Update AGENTS.md documentation
**Validates: Requirements 7.1, 7.2, 7.3, 7.4**
- [ ] 8.1 Add "Extension Build Validation" section to AGENTS.md
- [ ] 8.2 Document prerequisites (Rust toolchain, tree-sitter CLI, curl, git)
- [ ] 8.3 Document how to run full validation suite
- [ ] 8.4 Document how to run individual validation checks

## Task 9: Integration testing
**Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5**
- [ ] 9.1 Test full validation suite against current extension configuration
- [ ] 9.2 Verify script works in CI environment (no interactive prompts)
- [ ] 9.3 Test error cases (invalid version, invalid revision, build failures)
