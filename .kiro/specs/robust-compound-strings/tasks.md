# Implementation Plan: Robust Compound String Handling

## Overview

This plan implements stdin-based input for `send-to-stata.sh` to handle Stata compound strings and other shell metacharacters. The implementation modifies the script to accept a `--stdin` flag, updates the Zed task definitions, and adds comprehensive tests.

## Tasks

- [x] 1. Add stdin mode to send-to-stata.sh
  - [ ] 1.1 Add --stdin flag parsing in parse_arguments function
    - Add `STDIN_MODE=false` global variable initialization
    - Add case for `--stdin)` that sets `STDIN_MODE=true`
    - _Requirements: 1.1_
  
  - [ ] 1.2 Update validate_arguments for stdin mode
    - Add mutual exclusivity check for `--stdin` and `--text`
    - Update statement mode validation to accept `--stdin` as alternative to `--text` or `--row`
    - _Requirements: 1.5, 2.1_
  
  - [ ] 1.3 Implement read_stdin_content function
    - Create function that reads all content from stdin using `cat`
    - Return content via stdout
    - Exit with code 6 on read failure
    - _Requirements: 1.1, 1.2, 4.1_
  
  - [ ] 1.4 Update main function to use stdin mode
    - Check `STDIN_MODE` before `TEXT` in statement mode
    - Call `read_stdin_content()` when stdin mode is active
    - Fall back to `--row` detection if stdin is empty and `--row` provided
    - Error if stdin empty and no `--row`
    - _Requirements: 1.3, 1.4, 4.1_
  
  - [ ] 1.5 Update usage/help text
    - Add `--stdin` to usage documentation
    - Document exit code 6
    - _Requirements: 1.1_

- [x] 2. Add unit tests for stdin mode
  - [ ] 2.1 Add argument parsing tests for --stdin
    - Test `--stdin` flag is recognized
    - Test `--stdin` and `--text` mutual exclusivity error
    - Test `--stdin` with `--row` is valid
    - _Requirements: 1.1, 1.5_
  
  - [ ] 2.2 Add stdin content tests
    - Test simple content via stdin
    - Test compound string `` `"test"' `` via stdin
    - Test content with backticks, quotes, dollar signs
    - Test empty stdin with `--row` fallback
    - Test empty stdin without `--row` error
    - _Requirements: 1.2, 1.3, 1.4, 4.1, 4.2_

- [x] 3. Checkpoint - Verify script changes work
  - Ensure all existing tests still pass
  - Ensure new stdin tests pass
  - Ask user if questions arise

- [x] 4. Add property tests for stdin mode
  - [ ] 4.1 Write property test for stdin round-trip preservation
    - **Property 1: Stdin Content Round-Trip Preservation**
    - Generate random strings with shell metacharacters
    - Pipe to script, verify temp file matches input exactly
    - Minimum 100 iterations
    - **Validates: Requirements 1.1, 1.2, 1.3, 4.1, 4.2, 4.3**
  
  - [ ] 4.2 Write property test for backward compatibility
    - **Property 2: Backward Compatibility with --text**
    - Generate random simple strings
    - Verify --text behavior unchanged
    - Minimum 100 iterations
    - **Validates: Requirements 2.1, 2.2**

- [x] 5. Update Zed task definitions
  - [ ] 5.1 Update STATA_TASKS in install-send-to-stata.sh
    - Change "Send Statement" task to use conditional stdin piping
    - Use: `if [ -n \"$ZED_SELECTED_TEXT\" ]; then printf '%s' \"$ZED_SELECTED_TEXT\" | send-to-stata.sh --statement --stdin --file \"$ZED_FILE\"; else send-to-stata.sh --statement --file \"$ZED_FILE\" --row \"$ZED_ROW\"; fi`
    - _Requirements: 3.1, 3.2, 3.3_
  
  - [ ] 5.2 Update documentation in SEND-TO-STATA.md
    - Document the stdin mode and why it's used
    - Update manual installation instructions with new task format
    - _Requirements: 3.3_

- [x] 6. Add test fixture for compound strings
  - Create tests/fixtures/compound_strings.do with various compound string examples
  - _Requirements: 4.2_

- [x] 7. Final checkpoint - Ensure all tests pass
  - Run full test suite
  - Verify backward compatibility
  - Ask user if questions arise

## Notes

- The Zed task uses shell conditional to choose between stdin and row modes
- Uses `printf '%s'` instead of `echo` to avoid escape sequence interpretation
- Exit code 6 is new for stdin read failures
