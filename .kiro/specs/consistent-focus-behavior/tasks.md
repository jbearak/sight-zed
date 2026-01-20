# Implementation Plan: Consistent Focus Behavior

## Overview

This implementation adds consistent focus behavior to send-to-stata across macOS and Windows. The macOS installer will generate task commands with optional Stata activation, while the Windows executable will be modified to return focus to Zed by default with a new `-ActivateStata` flag to opt-out.

## Tasks

- [ ] 1. Update Windows executable for new default behavior
  - [ ] 1.1 Modify SendToStata.cs to return focus to Zed by default
    - Change default behavior so focus returns to Zed without requiring `-ReturnFocus` flag
    - Add new `-ActivateStata` flag that skips the return-focus logic
    - Keep `-ReturnFocus` flag for backward compatibility (now a no-op, prints deprecation warning)
    - Implement flag precedence: `-ActivateStata` takes precedence over `-ReturnFocus`
    - _Requirements: 1.2, 2.2, 4.1, 4.2, 4.3, 4.4_

  - [ ] 1.2 Write unit tests for Windows argument parsing
    - Test `-ActivateStata` sets correct internal state
    - Test `-ReturnFocus` prints deprecation warning
    - Test flag precedence when both flags provided
    - _Requirements: 4.3, 4.4_

- [ ] 2. Checkpoint - Rebuild Windows executable
  - Rebuild send-to-stata.exe with `dotnet publish`
  - Update checksums in install-send-to-stata.ps1 using update-checksum.ps1
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 3. Update Windows installer for new focus behavior
  - [ ] 3.1 Update Install-Tasks function in install-send-to-stata.ps1
    - Change task generation to NOT include `-ReturnFocus` by default (new default behavior)
    - Add `-ActivateStata` flag to task commands when user selects "switch to Stata"
    - Update parameter handling: rename/add `-ActivateStata` parameter
    - _Requirements: 5.4, 5.5, 6.3, 6.4_

  - [ ] 3.2 Update interactive prompt wording
    - Change prompt to match new semantics: "Switch to Stata after sending code? [y/N]"
    - Default to "No" (stay in Zed)
    - _Requirements: 5.1, 5.2, 5.3_

  - [ ] 3.3 Write unit tests for Windows installer task generation
    - Test tasks.json contains `-ActivateStata` when configured
    - Test tasks.json does NOT contain `-ActivateStata` when not configured
    - _Requirements: 5.4, 5.5_

- [ ] 4. Update macOS installer for focus behavior
  - [ ] 4.1 Add focus behavior prompt to install-send-to-stata.sh
    - Add interactive prompt: "Switch to Stata after sending code? [y/N]"
    - Default to "No" (stay in Zed)
    - Add `--activate-stata` and `--stay-in-zed` flags for non-interactive mode
    - Validate mutual exclusivity of flags
    - _Requirements: 5.1, 5.2, 5.3, 6.1, 6.2_

  - [ ] 4.2 Update task generation in install-send-to-stata.sh
    - Detect Stata variant using existing `detect_stata_app` function
    - When "switch to Stata" selected, append `&& osascript -e 'tell application "StataXX" to activate'` to task commands
    - Substitute correct Stata app name in activation command
    - _Requirements: 2.1, 3.1, 3.2, 3.3, 5.4, 5.5_

  - [ ] 4.3 Write unit tests for macOS installer task generation
    - Test tasks.json contains activation suffix when `--activate-stata` provided
    - Test tasks.json does NOT contain activation suffix when `--stay-in-zed` or default
    - Test correct Stata variant name is used
    - _Requirements: 3.1, 3.2, 3.3_

- [ ] 5. Checkpoint - Test installers
  - Run macOS installer with both `--activate-stata` and `--stay-in-zed` flags
  - Run Windows installer with both `-ActivateStata true` and `-ActivateStata false`
  - Verify generated tasks.json on both platforms
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 6. Update documentation
  - [ ] 6.1 Update SEND-TO-STATA.md
    - Document default focus behavior (stay in Zed)
    - Document how to change focus behavior during installation
    - Document how to change focus behavior after installation (re-run installer)
    - Update installer parameter documentation
    - _Requirements: 7.1, 7.2, 7.3_

  - [ ] 6.2 Update AGENTS.md
    - Update installer parameters section for both platforms
    - Document new `-ActivateStata` parameter for Windows
    - Document new `--activate-stata` and `--stay-in-zed` flags for macOS
    - _Requirements: 7.4_

- [ ] 7. Final checkpoint
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- All tasks including tests are required for comprehensive coverage
- The macOS script (`send-to-stata.sh`) is NOT modified - all changes are in the installer
- The Windows executable IS modified to change default behavior
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties
- Unit tests validate specific examples and edge cases
