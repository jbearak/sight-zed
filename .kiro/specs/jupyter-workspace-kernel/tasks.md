# Implementation Plan: Jupyter Workspace Kernel

## Overview

This plan documents the completed workspace kernel implementation and creates tasks to update documentation. The core implementation in `install-jupyter-stata.sh` is already complete—these tasks focus on ensuring documentation accurately reflects the new dual-kernel functionality.

## Tasks

- [x] 1. Implement workspace kernel in installer (COMPLETED)
  - [x] 1.1 Add `get_workspace_kernel_script()` function with embedded Python wrapper
    - Wrapper finds workspace root by walking up looking for .git, .stata-project, .project
    - Falls back to original directory if no marker found
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_
  - [x] 1.2 Add `install_workspace_kernel()` function
    - Creates `~/Library/Jupyter/kernels/stata_workspace/` directory
    - Writes wrapper script and kernel.json
    - _Requirements: 2.1, 2.3_
  - [x] 1.3 Add `uninstall_workspace_kernel()` function
    - Removes workspace kernel directory during uninstall
    - _Requirements: 2.4_
  - [x] 1.4 Update `print_summary()` to explain both kernels
    - Lists both kernel options with descriptions
    - Includes Zed settings example for default kernel
    - _Requirements: 3.1, 3.2, 3.3_

- [x] 2. Update AGENTS.md documentation
  - [x] 2.1 Add "Jupyter Kernel Variants" section
    - Document the two kernels: Stata and Stata (Workspace)
    - Explain when to use each variant
    - Document the workspace marker files (.git, .stata-project, .project)
    - _Requirements: 4.1_

- [x] 3. Update README.md documentation
  - [x] 3.1 Update "Jupyter REPL (Optional)" section
    - Explain the two kernel options
    - Add instructions for choosing between kernels
    - Add Zed settings example for default kernel selection
    - _Requirements: 4.2_

- [x] 4. Review installer summary message
  - [x] 4.1 Verify the print_summary() output adequately explains both kernels
    - Check that kernel names and descriptions are clear
    - Verify Zed settings example is correct
    - _Requirements: 4.3_

- [x] 5. Final checkpoint
  - Ensure documentation is accurate and complete
  - Verify installer summary message is helpful

## Notes

- The core implementation (tasks 1.x) is already complete in `install-jupyter-stata.sh`
- Remaining tasks focus on documentation updates
- No code changes needed to the installer itself
