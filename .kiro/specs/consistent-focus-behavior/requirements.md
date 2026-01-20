# Requirements Document

## Introduction

This feature adds consistent focus behavior to the send-to-stata functionality across macOS and Windows platforms. Currently, macOS keeps focus in Zed after sending code (using `DoCommandAsync`), while Windows steals focus to Stata (using COM automation with `SetForegroundWindow`). The goal is to make both platforms behave consistently, matching Stata's own do-file editor behavior where focus remains on the editor after running a command, while providing an opt-in mechanism for users who want to switch focus to Stata.

## Glossary

- **Send_To_Stata_Script**: The platform-specific script that sends Stata code from Zed to the Stata application (`send-to-stata.sh` on macOS, `send-to-stata.exe` on Windows)
- **Installer**: The platform-specific installation script (`install-send-to-stata.sh` on macOS, `install-send-to-stata.ps1` on Windows)
- **Focus_Behavior**: Whether the window focus remains in Zed or switches to Stata after sending code
- **Activate_Stata_Flag**: A command-line flag that causes the script to switch focus to Stata after sending code
- **Zed_Task**: A task definition in Zed's `tasks.json` that invokes the Send_To_Stata_Script

## Requirements

### Requirement 1: Default Focus Behavior

**User Story:** As a Stata developer, I want Zed to keep focus after sending code to Stata, so that I can continue typing without manually switching windows.

#### Acceptance Criteria

1. WHEN the Send_To_Stata_Script sends code to Stata on macOS, THE Send_To_Stata_Script SHALL keep focus in the calling application by default
2. WHEN the Send_To_Stata_Script sends code to Stata on Windows, THE Send_To_Stata_Script SHALL return focus to Zed by default
3. THE default behavior on both platforms SHALL match Stata's do-file editor behavior where focus remains on the editor

### Requirement 2: Optional Focus Switch to Stata

**User Story:** As a Stata developer using Zed in fullscreen mode, I want the option to switch focus to Stata after sending code, so that I can see the output immediately.

#### Acceptance Criteria

1. WHEN the user configures "activate Stata" during macOS installation, THE Installer SHALL generate task commands that include an AppleScript activation call after the main script
2. WHEN the `-ActivateStata` flag is provided on Windows, THE Send_To_Stata_Script SHALL NOT return focus to Zed after sending the command
3. WHEN activation is NOT configured, THE system SHALL use the default focus behavior (stay in Zed)

### Requirement 3: macOS Installer Task Generation

**User Story:** As a developer, I want the macOS installer to generate task commands with optional Stata activation, so that focus behavior can be controlled without modifying the script.

#### Acceptance Criteria

1. WHEN the user selects "switch to Stata" during installation, THE Installer SHALL append `&& osascript -e 'tell application "StataXX" to activate'` to each task command
2. WHEN the user selects "stay in Zed" during installation, THE Installer SHALL NOT append any activation command to task commands
3. THE Installer SHALL detect the installed Stata variant and use the correct application name in the activation command

### Requirement 4: Windows Executable Flag Implementation

**User Story:** As a developer, I want the Windows executable to support an `--activate-stata` flag that inverts the current `-ReturnFocus` behavior, so that the flag semantics are consistent across platforms.

#### Acceptance Criteria

1. WHEN the `-ActivateStata` flag is provided, THE Send_To_Stata_Script SHALL NOT return focus to Zed after sending code
2. WHEN the `-ActivateStata` flag is NOT provided, THE Send_To_Stata_Script SHALL return focus to Zed by default
3. THE `-ReturnFocus` flag SHALL be deprecated but continue to work for backward compatibility
4. IF both `-ActivateStata` and `-ReturnFocus` flags are provided, THEN THE Send_To_Stata_Script SHALL treat `-ActivateStata` as taking precedence

### Requirement 5: Installer Focus Behavior Prompt

**User Story:** As a user installing send-to-stata, I want to be prompted about my preferred focus behavior, so that I can configure it during installation.

#### Acceptance Criteria

1. WHEN the Installer runs interactively, THE Installer SHALL prompt the user with a focus behavior question
2. THE prompt text SHALL be consistent across both platforms
3. THE prompt SHALL default to "No" (stay in Zed) when the user presses Enter without input
4. WHEN the user selects "Yes" (switch to Stata), THE Installer SHALL add the `--activate-stata` flag to all Zed task commands
5. WHEN the user selects "No" (stay in Zed), THE Installer SHALL NOT add the `--activate-stata` flag to Zed task commands

### Requirement 6: Non-Interactive Installation Support

**User Story:** As a DevOps engineer, I want to install send-to-stata non-interactively with explicit focus preference, so that I can automate installation in CI/CD pipelines.

#### Acceptance Criteria

1. WHEN the macOS Installer is invoked with `--activate-stata`, THE Installer SHALL configure tasks to switch focus to Stata without prompting
2. WHEN the macOS Installer is invoked with `--stay-in-zed`, THE Installer SHALL configure tasks to keep focus in Zed without prompting
3. WHEN the Windows Installer is invoked with `-ActivateStata true`, THE Installer SHALL configure tasks to switch focus to Stata without prompting
4. WHEN the Windows Installer is invoked with `-ActivateStata false`, THE Installer SHALL configure tasks to keep focus in Zed without prompting
5. THE existing Windows `-ReturnFocus` parameter SHALL continue to work for backward compatibility

### Requirement 7: Documentation Updates

**User Story:** As a user, I want the documentation to explain the focus behavior options, so that I can understand and configure my preferred behavior.

#### Acceptance Criteria

1. THE SEND-TO-STATA.md documentation SHALL describe the default focus behavior
2. THE SEND-TO-STATA.md documentation SHALL explain how to change focus behavior during installation
3. THE SEND-TO-STATA.md documentation SHALL explain how to change focus behavior after installation
4. THE AGENTS.md documentation SHALL be updated to reflect the new installer parameters
