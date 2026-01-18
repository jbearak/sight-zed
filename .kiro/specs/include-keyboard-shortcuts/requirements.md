# Requirements Document

## Introduction

This feature adds two new keyboard shortcuts to the send-to-stata functionality that use Stata's `include` command instead of `do`. In Stata, local macros are scoped to the running file when using `do`, but `include` preserves locals in the calling context. This is useful for debugging when you need to access local variables after running code.

## Glossary

- **Send_To_Stata_Script**: The `send-to-stata.sh` bash script that sends Stata code to the Stata GUI via AppleScript
- **Installer_Script**: The `install-send-to-stata.sh` script that installs tasks and keybindings for Zed
- **Zed_Task**: A task definition in Zed's `tasks.json` that executes a shell command
- **Keybinding**: A keyboard shortcut defined in Zed's `keymap.json` that triggers an action
- **Include_Command**: Stata's `include` command which executes a do-file while preserving local macro scope
- **Do_Command**: Stata's `do` command which executes a do-file with isolated local macro scope

## Requirements

### Requirement 1: Add Include Flag to Send-To-Stata Script

**User Story:** As a developer, I want the send-to-stata script to support an `--include` flag, so that I can choose between `do` and `include` commands when sending code to Stata.

#### Acceptance Criteria

1. WHEN the Send_To_Stata_Script is invoked with the `--include` flag, THE Send_To_Stata_Script SHALL use `include` instead of `do` in the AppleScript command sent to Stata
2. WHEN the Send_To_Stata_Script is invoked without the `--include` flag, THE Send_To_Stata_Script SHALL use `do` in the AppleScript command (existing behavior)
3. THE Send_To_Stata_Script SHALL accept the `--include` flag in combination with both `--statement` and `--file` modes
4. WHEN the `--include` flag is provided, THE Send_To_Stata_Script SHALL document this option in the usage help text

### Requirement 2: Add Include Tasks to Installer

**User Story:** As a user, I want the installer to create Zed tasks for include mode, so that I can trigger include commands from the task palette.

#### Acceptance Criteria

1. WHEN the Installer_Script runs, THE Installer_Script SHALL create a "Stata: Include Statement" Zed_Task that sends the current statement using `include`
2. WHEN the Installer_Script runs, THE Installer_Script SHALL create a "Stata: Include File" Zed_Task that sends the entire file using `include`
3. THE "Stata: Include Statement" Zed_Task SHALL behave identically to "Stata: Send Statement" except using `include` instead of `do`
4. THE "Stata: Include File" Zed_Task SHALL behave identically to "Stata: Send File" except using `include` instead of `do`

### Requirement 3: Add Include Keybindings to Installer

**User Story:** As a user, I want keyboard shortcuts for include mode, so that I can quickly send code with `include` without using the task palette.

#### Acceptance Criteria

1. WHEN the Installer_Script runs, THE Installer_Script SHALL bind `alt-cmd-enter` to the "Stata: Include Statement" task in `.do` files
2. WHEN the Installer_Script runs, THE Installer_Script SHALL bind `alt-shift-cmd-enter` to the "Stata: Include File" task in `.do` files
3. THE keybindings SHALL save the file before executing the task (matching existing behavior)
4. THE Installer_Script SHALL nullify any conflicting default keybindings for `alt-cmd-enter` and `alt-shift-cmd-enter` in a broader context to prevent unintended behavior
5. WHEN the Installer_Script uninstalls, THE Installer_Script SHALL remove the include keybindings along with existing keybindings

### Requirement 4: Update Documentation

**User Story:** As a user, I want documentation of all keyboard shortcuts, so that I can learn and reference the available commands.

#### Acceptance Criteria

1. THE SEND-TO-STATA.md documentation SHALL list all four keybindings in the keybindings table
2. THE SEND-TO-STATA.md documentation SHALL explain the difference between `do` and `include` commands
3. THE README.md SHALL mention the send-to-stata feature and point to SEND-TO-STATA.md for details
4. THE AGENTS.md SHALL include a concise keybinding reference for all four shortcuts
5. THE manual installation section in SEND-TO-STATA.md SHALL include the new tasks and keybindings
