# Implementation Plan: Include Keyboard Shortcuts

## Overview

Add `--include` flag to send-to-stata.sh and create corresponding Zed tasks and keybindings for `alt-cmd-enter` (include statement) and `alt-shift-cmd-enter` (include file).

## Tasks

- [x] 1. Add --include flag to send-to-stata.sh
  - [x] 1.1 Add INCLUDE_MODE variable and parse --include flag in argument parsing
    - Add `INCLUDE_MODE=false` to global variables
    - Add case for `--include)` in parse_arguments() that sets INCLUDE_MODE=true
    - _Requirements: 1.1, 1.2, 1.3_
  - [x] 1.2 Modify send_to_stata() to use include or do based on flag
    - Change hardcoded `do` to variable based on INCLUDE_MODE
    - Generate AppleScript with `include` when INCLUDE_MODE=true, `do` otherwise
    - _Requirements: 1.1, 1.2_
  - [x] 1.3 Update print_usage() to document --include flag
    - Add `--include` to Options section in help text
    - _Requirements: 1.4_

- [x] 2. Update installer with new tasks and keybindings
  - [x] 2.1 Add Include Statement and Include File tasks to STATA_TASKS
    - Add "Stata: Include Statement" task with --include flag in command
    - Add "Stata: Include File" task with --include flag in command
    - _Requirements: 2.1, 2.2, 2.3, 2.4_
  - [x] 2.2 Add alt-cmd-enter and alt-shift-cmd-enter keybindings
    - Add `alt-cmd-enter` binding for "Stata: Include Statement"
    - Add `alt-shift-cmd-enter` binding for "Stata: Include File"
    - Both use action::Sequence with workspace::Save
    - _Requirements: 3.1, 3.2, 3.3_
  - [x] 2.3 Update print_summary() to show all four keybindings
    - Add include keybindings to the summary output
    - _Requirements: 3.1, 3.2_

- [x] 3. Checkpoint - Verify script and installer changes
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Update documentation
  - [x] 4.1 Update SEND-TO-STATA.md with all four keybindings and do vs include explanation
    - Update keybindings table to show all four shortcuts
    - Add section explaining difference between `do` and `include` commands
    - Update manual installation section with new tasks and keybindings
    - _Requirements: 4.1, 4.2, 4.5_
  - [x] 4.2 Update README.md to mention send-to-stata feature
    - Add brief mention of send-to-stata with link to SEND-TO-STATA.md
    - _Requirements: 4.3_
  - [x] 4.3 Add keybinding reference to AGENTS.md
    - Add concise section listing all four keyboard shortcuts
    - _Requirements: 4.4_

- [x] 5. Final checkpoint - Verify all changes
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- The existing uninstall logic already handles the new tasks and keybindings (removes all `Stata:` prefixed tasks and `extension == do` keybindings)
- Task commands follow existing patterns from AGENTS.md (args in command string, stdin mode for compound strings)
- Keybindings use same context and action::Sequence pattern as existing bindings
