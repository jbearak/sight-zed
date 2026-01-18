# Implementation Plan: Send Code to Stata

## Overview

This plan implements the send-to-stata feature using shell scripts integrated with Zed's task system. The implementation creates three main files: the send script, the installer script, and documentation.

## Tasks

- [ ] 1. Create the send-to-stata shell script
  - [x] 1.1 Create `send-to-stata.sh` with argument parsing
    - Parse `--statement` and `--file` modes
    - Parse `--file`, `--row`, `--text` options
    - Validate required arguments for each mode
    - Exit with code 1 for invalid arguments
    - _Requirements: 1.1, 1.2, 2.1_

  - [x] 1.2 Implement Stata application detection
    - Check `STATA_APP` environment variable first
    - Auto-detect by checking `/Applications/Stata/` for variants
    - Return first found: StataMP, StataSE, StataIC, Stata
    - Exit with code 4 if no Stata found
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [x] 1.3 Implement statement detection with continuation handling
    - Read file into array of lines
    - Search backwards from cursor row to find statement start
    - Search forwards to find all continuation lines (ending with `///`)
    - Handle chained continuations
    - _Requirements: 1.2, 1.3, 1.4, 4.1, 4.3, 4.4, 4.5_

  - [x] 1.4 Implement temp file creation
    - Create temp file in `$TMPDIR` (fallback to `/tmp`)
    - Use `mktemp` with pattern `stata_send_XXXXXX.do`
    - Write content to temp file
    - Exit with code 3 if creation fails
    - _Requirements: 1.5, 2.2, 8.1, 8.2_

  - [x] 1.5 Implement AppleScript execution
    - Build AppleScript command with proper escaping
    - Escape backslashes and double quotes in path
    - Execute via `osascript`
    - Exit with code 5 if AppleScript fails
    - _Requirements: 1.6, 1.7, 2.3_

  - [x] 1.6 Write unit tests for send-to-stata.sh
    - Test argument parsing (valid and invalid)
    - Test statement detection edge cases
    - Test Stata detection with mocked filesystem
    - Test path escaping
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

  - [x] 1.7 Write property test for statement detection
    - **Property 1: Statement Detection with Continuations**
    - Generate random Stata files with continuation markers
    - Verify correct statement boundaries for any cursor position
    - **Validates: Requirements 1.2, 1.3, 1.4, 4.1, 4.3, 4.4, 4.5**

  - [x] 1.8 Write property test for temp file creation
    - **Property 4: Temp File Creation**
    - Verify unique filenames across multiple invocations
    - Verify files created in correct directory
    - Verify files persist after script completion
    - **Validates: Requirements 1.5, 2.2, 8.1, 8.2, 8.3**

- [x] 2. Checkpoint - Verify send script works
  - Ensure all tests pass, ask the user if questions arise.

- [x] 3. Create the installer script
  - [x] 3.1 Create `install-send-to-stata.sh` with prerequisite checks
    - Check for macOS (required for AppleScript)
    - Check for `jq` dependency
    - Provide Homebrew install command if `jq` missing
    - _Requirements: 5.1, 5.2_

  - [x] 3.2 Implement script installation
    - Create `~/.local/bin/` if needed
    - Copy `send-to-stata.sh` to `~/.local/bin/`
    - Make executable with `chmod +x`
    - Check if `~/.local/bin` is in PATH, warn if not
    - _Requirements: 5.3, 5.7_

  - [x] 3.3 Implement Zed tasks installation
    - Read existing `~/.config/zed/tasks.json` or create empty array
    - Remove any existing "Stata:" prefixed tasks
    - Merge in new Stata task definitions
    - Write back using `jq`
    - _Requirements: 5.4, 6.1_

  - [x] 3.4 Implement keybindings installation
    - Read existing `~/.config/zed/keymap.json` or create empty array
    - Remove any existing Stata keybindings (by context match)
    - Merge in new keybindings
    - Write back using `jq`
    - _Requirements: 5.5, 6.2_

  - [x] 3.5 Implement Stata detection and summary
    - Detect installed Stata variant
    - Print installation summary
    - Show keybindings
    - _Requirements: 5.6_

  - [x] 3.6 Implement uninstall option
    - Support `--uninstall` flag
    - Remove `send-to-stata.sh` from `~/.local/bin/`
    - Remove Stata tasks from `tasks.json`
    - Remove Stata keybindings from `keymap.json`
    - _Requirements: 5.8_

  - [x] 3.7 Write unit tests for installer script
    - Test prerequisite checks
    - Test JSON merging logic
    - Test uninstall functionality
    - _Requirements: 5.1-5.8_

- [ ] 4. Checkpoint - Verify installer works
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 5. Create documentation
  - [ ] 5.1 Create `SEND-TO-STATA.md` documentation file
    - Prerequisites section
    - Quick start with installer command
    - Manual installation steps
    - Configuration (STATA_APP env var)
    - Keybindings reference table
    - Troubleshooting section
    - Uninstallation instructions
    - Temp file cleanup guidance
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_

- [ ] 6. Final checkpoint
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Shell scripts use bash for macOS compatibility
- `jq` is required for JSON manipulation in the installer
- Property tests use BATS with generated test data
- Integration tests (actually sending to Stata) require manual verification
