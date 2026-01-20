# Implementation Plan: Stata Zed Tasks

## Overview

This implementation adds four new Zed tasks for Stata: CD into Workspace Folder, CD into File Folder, Do Upward Lines, and Do Downward Lines. The implementation extends the existing `send-to-stata.sh` (macOS) and `SendToStata.cs` (Windows) with new modes, and updates both platform installers to add the tasks and keybindings.

## Tasks

- [ ] 1. Implement path escaping functions
  - [ ] 1.1 Add `escape_path_for_stata` function to `send-to-stata.sh`
    - Implement backslash doubling logic
    - Implement quote detection logic
    - Return escaped path and use_compound flag
    - _Requirements: 1.2, 1.3, 2.2, 2.3, 5.1, 5.2, 5.3_
  
  - [ ] 1.2 Add `format_cd_command` function to `send-to-stata.sh`
    - Use compound string syntax when use_compound is true
    - Use regular string syntax when use_compound is false
    - _Requirements: 5.4, 5.5_
  
  - [ ] 1.3 Write property tests for path escaping (macOS)
    - **Property 1: Backslash Doubling**
    - **Property 2: Quote Detection Sets Compound Flag**
    - **Property 3: CD Command Formatting**
    - **Validates: Requirements 1.2, 1.3, 2.2, 2.3, 5.1-5.5**
  
  - [ ] 1.4 Add `EscapePathForStata` method to `SendToStata.cs`
    - Implement backslash doubling logic
    - Implement quote detection logic
    - Return PathEscapeResult record
    - _Requirements: 1.2, 1.3, 2.2, 2.3, 5.1, 5.2, 5.3_
  
  - [ ] 1.5 Add `FormatCdCommand` method to `SendToStata.cs`
    - Use compound string syntax when UseCompound is true
    - Use regular string syntax when UseCompound is false
    - _Requirements: 5.4, 5.5_
  
  - [ ] 1.6 Write property tests for path escaping (Windows)
    - **Property 1: Backslash Doubling**
    - **Property 2: Quote Detection Sets Compound Flag**
    - **Property 3: CD Command Formatting**
    - **Validates: Requirements 1.2, 1.3, 2.2, 2.3, 5.1-5.5**

- [ ] 2. Implement CD command modes
  - [ ] 2.1 Add `--cd-workspace` mode to `send-to-stata.sh`
    - Parse `--workspace <path>` argument
    - Generate cd command using format_cd_command
    - Send to Stata via existing AppleScript mechanism
    - Handle missing workspace error
    - _Requirements: 1.1, 1.4, 1.5_
  
  - [ ] 2.2 Add `--cd-file` mode to `send-to-stata.sh`
    - Extract parent directory from file path
    - Generate cd command using format_cd_command
    - Send to Stata via existing AppleScript mechanism
    - Handle missing file error
    - _Requirements: 2.1, 2.4, 2.5_
  
  - [ ] 2.3 Add `-CDWorkspace` parameter to `SendToStata.cs`
    - Parse `-Workspace <path>` argument
    - Generate cd command using FormatCdCommand
    - Send to Stata via existing SendKeys mechanism
    - Handle missing workspace error
    - _Requirements: 1.1, 1.4, 1.5_
  
  - [ ] 2.4 Add `-CDFile` parameter to `SendToStata.cs`
    - Extract parent directory from file path
    - Generate cd command using FormatCdCommand
    - Send to Stata via existing SendKeys mechanism
    - Handle missing file error
    - _Requirements: 2.1, 2.4, 2.5_

- [ ] 3. Checkpoint - Verify CD commands work
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 4. Implement line extraction functions
  - [ ] 4.1 Add `get_upward_lines` function to `send-to-stata.sh`
    - Read file into array of lines
    - Start at line 1
    - End at cursor row, extending forward if line has continuation
    - Return extracted lines preserving line breaks
    - _Requirements: 3.1, 3.2, 3.5_
  
  - [ ] 4.2 Add `get_downward_lines` function to `send-to-stata.sh`
    - Read file into array of lines
    - Start at cursor row, extending backward if on continuation line
    - End at last line of file
    - Return extracted lines preserving line breaks
    - _Requirements: 4.1, 4.2, 4.5_
  
  - [ ] 4.3 Write property tests for line extraction (macOS)
    - **Property 4: Upward Bounds Extraction**
    - **Property 5: Downward Bounds Extraction**
    - **Validates: Requirements 3.1, 3.2, 3.5, 4.1, 4.2, 4.5**
  
  - [ ] 4.4 Add `GetUpwardLines` method to `SendToStata.cs`
    - Read file into array of lines
    - Start at line 1
    - End at cursor row, extending forward if line has continuation
    - Return extracted lines preserving line breaks
    - _Requirements: 3.1, 3.2, 3.5_
  
  - [ ] 4.5 Add `GetDownwardLines` method to `SendToStata.cs`
    - Read file into array of lines
    - Start at cursor row, extending backward if on continuation line
    - End at last line of file
    - Return extracted lines preserving line breaks
    - _Requirements: 4.1, 4.2, 4.5_
  
  - [ ] 4.6 Write property tests for line extraction (Windows)
    - **Property 4: Upward Bounds Extraction**
    - **Property 5: Downward Bounds Extraction**
    - **Validates: Requirements 3.1, 3.2, 3.5, 4.1, 4.2, 4.5**

- [ ] 5. Implement upward/downward modes
  - [ ] 5.1 Add `--upward` mode to `send-to-stata.sh`
    - Parse `--file <path>` and `--row <n>` arguments
    - Call get_upward_lines to extract content
    - Write to temp file and execute via do command
    - _Requirements: 3.1, 3.4_
  
  - [ ] 5.2 Add `--downward` mode to `send-to-stata.sh`
    - Parse `--file <path>` and `--row <n>` arguments
    - Call get_downward_lines to extract content
    - Write to temp file and execute via do command
    - _Requirements: 4.1, 4.4_
  
  - [ ] 5.3 Add `-Upward` parameter to `SendToStata.cs`
    - Parse `-File <path>` and `-Row <n>` arguments
    - Call GetUpwardLines to extract content
    - Write to temp file and execute via do command
    - _Requirements: 3.1, 3.4_
  
  - [ ] 5.4 Add `-Downward` parameter to `SendToStata.cs`
    - Parse `-File <path>` and `-Row <n>` arguments
    - Call GetDownwardLines to extract content
    - Write to temp file and execute via do command
    - _Requirements: 4.1, 4.4_

- [ ] 6. Checkpoint - Verify all script modes work
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 7. Update macOS installer
  - [ ] 7.1 Add new tasks to `generate_stata_tasks` function in `install-send-to-stata.sh`
    - Add "Stata: CD into Workspace Folder" task
    - Add "Stata: CD into File Folder" task
    - Add "Stata: Do Upward Lines" task
    - Add "Stata: Do Downward Lines" task
    - Respect ACTIVATE_STATA setting for focus behavior
    - _Requirements: 6.1, 6.4_
  
  - [ ] 7.2 Add new keybindings to `install_keybindings` function in `install-send-to-stata.sh`
    - Add ctrl-shift-w for CD Workspace
    - Add ctrl-shift-f for CD File
    - Add ctrl-shift-up for Do Upward Lines
    - Add ctrl-shift-down for Do Downward Lines
    - _Requirements: 6.2, 6.3_
  
  - [ ] 7.3 Update uninstall function to remove new tasks
    - Ensure uninstall removes all Stata: prefixed tasks
    - _Requirements: 6.5_

- [ ] 8. Update Windows installer
  - [ ] 8.1 Add new tasks to `Install-Tasks` function in `install-send-to-stata.ps1`
    - Add "Stata: CD into Workspace Folder" task
    - Add "Stata: CD into File Folder" task
    - Add "Stata: Do Upward Lines" task
    - Add "Stata: Do Downward Lines" task
    - Respect UseActivateStata setting for focus behavior
    - _Requirements: 6.1, 6.4_
  
  - [ ] 8.2 Add new keybindings to `Install-Keybindings` function in `install-send-to-stata.ps1`
    - Add ctrl-shift-w for CD Workspace
    - Add ctrl-shift-f for CD File
    - Add ctrl-shift-up for Do Upward Lines
    - Add ctrl-shift-down for Do Downward Lines
    - _Requirements: 6.2, 6.3_
  
  - [ ] 8.3 Update uninstall function to remove new tasks
    - Ensure Uninstall-SendToStata removes all Stata: prefixed tasks
    - _Requirements: 6.5_

- [ ] 9. Update documentation
  - [ ] 9.1 Update SEND-TO-STATA.md with new commands
    - Document new keybindings
    - Document new command-line modes
    - Add usage examples
    - _Requirements: 7.1, 7.2_

- [ ] 10. Final checkpoint - Full integration test
  - Ensure all tests pass, ask the user if questions arise.
  - Verify installer adds all tasks and keybindings
  - Verify uninstaller removes all tasks and keybindings

## Notes

- All tasks are required for comprehensive implementation
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties
- Unit tests validate specific examples and edge cases
- The existing `ends_with_continuation` function in `send-to-stata.sh` can be reused for line extraction
- The existing `ContinuationMarkerRegex` in `SendToStata.cs` can be reused for line extraction
