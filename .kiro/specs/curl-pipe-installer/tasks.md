# Implementation Plan: Curl-Pipe Installer Support

## Overview

Add curl-pipe-to-bash installation support to `install-send-to-stata.sh` by detecting execution context and fetching from GitHub when no local file exists.

## Tasks

- [x] 1. Add GitHub URL constants and fetch function
  - [x] 1.1 Add `GITHUB_RAW_BASE` and `GITHUB_REF` constants at top of script
    - `GITHUB_RAW_BASE="https://raw.githubusercontent.com/jbearak/sight"`
    - `GITHUB_REF="${SIGHT_GITHUB_REF:-main}"`
    - _Requirements: 3.2, 3.5_
  
  - [x] 1.2 Add `fetch_script_from_github()` function
    - Construct URL from base and ref
    - Use `curl -fsSL` to download
    - Handle download failure with error message showing URL
    - Exit with code 1 on failure
    - _Requirements: 3.1, 3.3, 3.4_

- [x] 2. Modify `install_script()` for context detection
  - [x] 2.1 Add local file existence check before copy
    - Check if `$SCRIPT_DIR/send-to-stata.sh` exists
    - _Requirements: 1.1, 1.2, 1.3_
  
  - [x] 2.2 Branch to local copy or remote fetch
    - If local file exists: copy from local (existing behavior)
    - If local file absent: call `fetch_script_from_github()`
    - Update success message to indicate source (local vs GitHub)
    - _Requirements: 2.1, 2.2, 3.1_

- [x] 3. Checkpoint - Test locally
  - Ensure all tests pass, ask the user if questions arise.
  - Test local installation still works: `./install-send-to-stata.sh`
  - Test detection by running from temp directory without send-to-stata.sh

- [-] 4. Integration testing from feature branch
  - [-] 4.1 Push changes to feature branch and test curl-pipe installation
    - Push to a feature branch
    - Run: `SIGHT_GITHUB_REF=<branch> /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jbearak/sight/<branch>/install-send-to-stata.sh)"`
    - Verify `~/.local/bin/send-to-stata.sh` is installed and executable
    - _Requirements: 4.1, 4.2, 5.1_

- [ ] 5. Final checkpoint
  - Ensure all tests pass, ask the user if questions arise.
  - Verify both installation methods produce working setup

## Notes

- All tasks involve modifying `install-send-to-stata.sh`
- No new files need to be created
- Integration testing requires pushing to GitHub first
- The `SIGHT_GITHUB_REF` env var enables pre-merge testing
