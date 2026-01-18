# Implementation Plan: Jupyter Kernel Installer

## Overview

This plan implements `install-jupyter-stata.sh`, a self-contained installer script for stata_kernel that enables Jupyter REPL support in Zed. The implementation follows patterns established by `install-send-to-stata.sh`.

## Tasks

- [x] 1. Create installer script skeleton with output helpers
  - [x] 1.1 Create `install-jupyter-stata.sh` with shebang, header comments, and `set -euo pipefail`
    - Include usage documentation in header
    - Define configuration constants (VENV_DIR, CONFIG_FILE, GITHUB_RAW_BASE, GITHUB_REF)
    - _Requirements: 6.1, 6.3_
  - [x] 1.2 Implement output helper functions
    - `print_error()`, `print_success()`, `print_warning()`, `print_info()`
    - Use ANSI color codes matching `install-send-to-stata.sh` pattern
    - _Requirements: 10.2_

- [x] 2. Implement prerequisite checks
  - [x] 2.1 Implement `check_macos()` function
    - Verify `uname` returns "Darwin"
    - Exit with error if not macOS
    - _Requirements: 7.1_
  - [x] 2.2 Implement `check_python3()` function
    - Verify `python3` command exists
    - Verify venv module is available (`python3 -m venv --help`)
    - Display helpful error with install instructions if missing
    - _Requirements: 7.2_
  - [x] 2.3 Implement `check_prerequisites()` that calls both checks
    - _Requirements: 7.5_

- [x] 3. Implement Stata detection
  - [x] 3.1 Implement `detect_stata_app()` function
    - Check STATA_PATH environment variable first
    - Auto-detect from /Applications/Stata/ in order: StataMP, StataSE, StataIC, StataBE, Stata
    - Extract executable path: `/Applications/Stata/{App}.app/Contents/MacOS/{executable}`
    - Determine edition from app name
    - _Requirements: 2.1, 2.2, 2.3_
  - [x] 3.2 Implement execution mode determination
    - MP/SE → console, IC/BE → automation
    - Check STATA_EXECUTION_MODE environment variable for override
    - Set global variables: STATA_PATH, STATA_EDITION, EXECUTION_MODE
    - _Requirements: 2.5, 3.1, 3.2, 3.4_
  - [x] 3.3 Write property test for edition-to-mode mapping
    - **Property 4: Edition Determines Execution Mode**
    - **Validates: Requirements 2.5, 3.1, 3.2, 3.3**

- [x] 4. Implement virtual environment management
  - [x] 4.1 Implement `create_venv()` function
    - Create parent directory `~/.local/share/stata_kernel` if needed
    - Check if venv already exists and is valid (has bin/python)
    - Create new venv with `python3 -m venv "$VENV_DIR"` if needed
    - Handle errors and display appropriate messages
    - _Requirements: 1.1, 1.2, 1.5_
  - [x] 4.2 Implement `install_packages()` function
    - Activate venv by using full path to pip
    - Run `pip install --upgrade pip`
    - Run `pip install --upgrade stata_kernel jupyter`
    - Verify installation succeeded
    - _Requirements: 1.3, 1.4_

- [x] 5. Implement configuration management
  - [x] 5.1 Implement `get_config_template()` function
    - Return full config file template with documentation comments
    - Include all stata_kernel settings with descriptions and possible values
    - Only stata_path and execution_mode uncommented
    - _Requirements: 4.1_
  - [x] 5.2 Implement `write_config()` function
    - If config doesn't exist, create from template with detected values
    - If config exists, update only stata_path and execution_mode
    - Preserve all other settings and user comments
    - Set appropriate file permissions (600)
    - _Requirements: 4.2, 4.3, 4.4, 4.5_
  - [x] 5.3 Write property test for config preservation
    - **Property 6: Config File Preserves User Customizations**
    - **Validates: Requirements 4.4**

- [x] 6. Implement kernel registration
  - [x] 6.1 Implement `register_kernel()` function
    - Run `$VENV_DIR/bin/python -m stata_kernel.install`
    - Handle registration errors
    - _Requirements: 5.1_
  - [x] 6.2 Implement `verify_kernel_spec()` function
    - Check kernel spec directory exists at `~/Library/Jupyter/kernels/stata/`
    - Verify kernel.json exists and has `"language": "stata"`
    - _Requirements: 5.2, 5.3_

- [x] 7. Implement uninstallation
  - [x] 7.1 Implement `uninstall()` function
    - Parse --remove-config flag
    - Remove venv directory if exists
    - Remove kernel spec using `jupyter kernelspec uninstall stata -y` or direct removal
    - Optionally remove config file based on flag
    - Display what was removed
    - Handle missing components gracefully
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5_

- [x] 8. Implement main function and installation summary
  - [x] 8.1 Implement `main()` function
    - Handle --uninstall flag
    - Call prerequisite checks
    - Call Stata detection (exit if not found)
    - Call venv creation and package installation
    - Call config writing
    - Call kernel registration and verification
    - Call summary display
    - _Requirements: 7.3, 7.4_
  - [x] 8.2 Implement `print_summary()` function
    - Display detected Stata edition and execution mode
    - Display installation locations
    - Display usage instructions for Zed
    - _Requirements: 10.1, 10.3, 10.4, 10.5_
  - [x] 8.3 Add main entry point guard
    - Only run main if script is executed directly (not sourced)
    - Handle curl-pipe context where BASH_SOURCE may be empty
    - _Requirements: 6.2, 6.3_

- [x] 9. Checkpoint - Test installer locally
  - Ensure all tests pass, ask the user if questions arise.
  - Test fresh installation
  - Test re-running (idempotency)
  - Test uninstallation
  - Test with different Stata editions if available

- [x] 10. Update README.md documentation
  - [x] 10.1 Add "Jupyter REPL (Optional)" section after "Send to Stata"
    - Include description of what stata_kernel provides
    - Include curl-pipe installation command
    - Include configuration documentation
    - Include usage instructions for Zed
    - Include uninstall command
    - Link to stata_kernel documentation
    - _Requirements: 11.1, 11.2, 11.3, 11.5, 11.6, 11.7_
  - [x] 10.2 Add "Jupyter Kernel" subsection to "Building from Source"
    - Include git clone installation instructions
    - _Requirements: 11.4_

- [x] 11. Final checkpoint
  - Ensure all tests pass, ask the user if questions arise.
  - Verify curl-pipe installation works
  - Verify documentation is accurate

## Notes

- The installer follows patterns from `install-send-to-stata.sh` for consistency
- Property tests validate the edition-to-mode mapping and config preservation logic
- Integration testing requires a macOS system with Stata installed
