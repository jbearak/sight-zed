# Requirements Document

## Introduction

This document defines the requirements for sending Stata code from Zed editor to the Stata GUI application for execution. The feature supports sending the current statement or the entire file using keyboard shortcuts. Code is sent via AppleScript on macOS.

**Note:** Terminal mode (sending to a terminal running Stata) was considered but removed because Zed tasks spawn new terminal instances rather than sending text to existing terminals.

## Glossary

- **Stata_GUI**: The Stata graphical application (StataMP, StataSE, StataIC, or Stata) running on macOS
- **Statement**: A single Stata command, which may span multiple lines when using continuation markers (`///`)
- **Continuation_Marker**: The `///` sequence at the end of a line indicating the statement continues on the next line
- **AppleScript**: macOS scripting language used to communicate with the Stata GUI application
- **DoCommandAsync**: The AppleScript command used to send code to Stata for execution
- **Temp_File**: A temporary `.do` file used to pass code to Stata
- **Send_Script**: The shell script that handles sending code to Stata
- **Zed_Task**: A Zed task definition that executes shell commands with editor context variables
- **Installer_Script**: The shell script that installs the send-to-stata components

## Requirements

### Requirement 1: Send Current Statement to Stata

**User Story:** As a Stata user, I want to send the current statement to the Stata GUI application, so that I can execute code without leaving Zed.

#### Acceptance Criteria

1. WHEN text is selected, THE Send_Script SHALL send the selected text (uses Zed's `$ZED_SELECTED_TEXT`)
2. WHEN no text is selected, THE Send_Script SHALL identify the current statement at the cursor position from the file
3. WHEN the current line contains a Continuation_Marker (`///`), THE Send_Script SHALL include all continuation lines as part of the statement
4. WHEN the current line is a continuation of a previous line, THE Send_Script SHALL include the entire multi-line statement from its beginning
5. THE Send_Script SHALL write the statement to a Temp_File with `.do` extension
6. THE Send_Script SHALL send the `do "/path/to/temp.do"` command to Stata_GUI via AppleScript
7. THE Send_Script SHALL properly escape backslashes and double quotes for AppleScript

### Requirement 2: Send Entire File to Stata

**User Story:** As a Stata user, I want to send the entire file to the Stata GUI application, so that I can run complete do-files.

#### Acceptance Criteria

1. THE Send_Script SHALL read the file contents
2. THE Send_Script SHALL write the file contents to a Temp_File with `.do` extension
3. THE Send_Script SHALL send the `do "/path/to/temp.do"` command to Stata_GUI via AppleScript
4. THE Send_Script SHALL always use a Temp_File to prevent issues if the user edits the original file while Stata is executing
5. THE Send_Script SHALL handle files with special characters in their content

### Requirement 3: Stata Application Detection

**User Story:** As a Stata user, I want the script to automatically detect my installed Stata variant, so that I don't need to manually configure the application name.

#### Acceptance Criteria

1. THE Send_Script SHALL support configuring the Stata application name via `STATA_APP` environment variable
2. WHEN no environment variable is set, THE Send_Script SHALL auto-detect by checking `/Applications/Stata/` for StataMP, StataSE, StataIC, or Stata (in that order)
3. THE Send_Script SHALL use the first Stata variant found during auto-detection
4. IF no Stata installation is found, THEN THE Send_Script SHALL report an error with installation guidance

### Requirement 4: Statement Detection Logic

**User Story:** As a Stata user, I want accurate detection of multi-line statements, so that continuation lines are handled correctly.

#### Acceptance Criteria

1. THE Send_Script SHALL detect `///` at the end of a line (ignoring trailing whitespace) as a Continuation_Marker
2. WHEN on a continuation line, THE Send_Script SHALL search backwards to find the statement start
3. WHEN on a line with `///`, THE Send_Script SHALL search forwards to find all continuation lines
4. THE Send_Script SHALL handle nested or chained continuation markers correctly

**Note:** The implementation uses a simple regex pattern (`///[[:space:]]*$`) for continuation detection. It does not parse Stata syntax, so `///` at the end of a line inside a string or comment will still be treated as a continuation marker. This is a known limitation chosen for simplicity and reliability.

### Requirement 5: Installation

**User Story:** As a Stata user, I want a simple installation process, so that I can quickly set up the send-to-stata feature.

#### Acceptance Criteria

1. THE Installer_Script SHALL check for macOS (required for AppleScript)
2. THE Installer_Script SHALL check for `jq` dependency and provide installation guidance if missing
3. THE Installer_Script SHALL copy Send_Script to `~/.local/bin/` and make it executable
4. THE Installer_Script SHALL merge Zed task definitions into `~/.config/zed/tasks.json`
5. THE Installer_Script SHALL merge keybindings into `~/.config/zed/keymap.json`
6. THE Installer_Script SHALL detect installed Stata variant and report it
7. THE Installer_Script SHALL warn if `~/.local/bin` is not in PATH
8. THE Installer_Script SHALL support `--uninstall` to remove all installed components

### Requirement 6: Zed Task Configuration

**User Story:** As a Stata user, I want pre-configured Zed tasks, so that I can use keyboard shortcuts to send code.

#### Acceptance Criteria

1. THE Installer_Script SHALL create two Zed tasks:
   - "Stata: Send Statement" (using `$ZED_SELECTED_TEXT`, `$ZED_FILE`, `$ZED_ROW`)
   - "Stata: Send File" (using `$ZED_FILE`)
2. THE Installer_Script SHALL create keybindings for `.do` files:
   - `cmd-enter`: Send statement to Stata
   - `shift-cmd-enter`: Send file to Stata

### Requirement 7: Error Handling

**User Story:** As a Stata user, I want clear error messages when something goes wrong, so that I can troubleshoot issues.

#### Acceptance Criteria

1. IF Stata is not installed, THEN THE Send_Script SHALL display an error message with expected installation paths
2. IF the AppleScript command fails, THEN THE Send_Script SHALL report the error from osascript
3. IF the file cannot be read, THEN THE Send_Script SHALL report a file access error
4. IF the Temp_File cannot be created, THEN THE Send_Script SHALL report a temp file creation error

### Requirement 8: Temporary File Management

**User Story:** As a Stata user, I want temporary files to be managed properly, so that they don't cause issues.

#### Acceptance Criteria

1. THE Send_Script SHALL create Temp_Files in the system temporary directory (`$TMPDIR` or `/tmp`)
2. THE Send_Script SHALL use unique filenames to avoid conflicts with concurrent executions
3. THE Send_Script SHALL NOT delete Temp_Files immediately (Stata needs time to read them)
4. THE documentation SHALL explain that temp files accumulate and may need periodic cleanup

### Requirement 9: Documentation

**User Story:** As a Stata user, I want clear documentation, so that I can set up and use the send-to-stata feature.

#### Acceptance Criteria

1. THE documentation SHALL explain how to run the installer script
2. THE documentation SHALL explain how to configure the Stata application variant via environment variable
3. THE documentation SHALL explain the keybinding behaviors
4. THE documentation SHALL provide troubleshooting guidance
5. THE documentation SHALL explain how to uninstall
6. THE documentation SHALL be provided in a `SEND-TO-STATA.md` file in the repository
