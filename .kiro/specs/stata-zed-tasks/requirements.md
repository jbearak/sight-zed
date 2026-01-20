# Requirements Document

## Introduction

This feature adds four new Zed Tasks for Stata on both macOS and Windows:
1. **CD into Workspace Folder** - Changes Stata's working directory to the workspace root
2. **CD into File Folder** - Changes Stata's working directory to the current file's directory
3. **Do Upward Lines** - Executes all lines from the start of the file to the current cursor position
4. **Do Downward Lines** - Executes all lines from the current cursor position to the end of the file

These commands complement the existing "Send Statement" and "Send File" tasks, providing more granular control over code execution and working directory management.

## Glossary

- **Send_To_Stata_Script**: The shell script (`send-to-stata.sh` on macOS) or executable (`send-to-stata.exe` on Windows) that sends Stata code to the Stata application
- **Zed_Task**: A task definition in Zed's `tasks.json` that executes a shell command
- **Continuation_Marker**: The `///` sequence at the end of a Stata line indicating the statement continues on the next line
- **Workspace_Root**: The root directory of the currently open workspace in Zed, available as `$ZED_WORKTREE_ROOT`
- **File_Directory**: The directory containing the currently active file
- **Compound_String**: Stata's syntax for strings containing double quotes, using backtick-quote delimiters: `` `"..."' ``
- **Path_Escaping**: The process of escaping special characters in file paths for Stata compatibility

## Requirements

### Requirement 1: CD into Workspace Folder

**User Story:** As a Stata developer, I want to change Stata's working directory to my workspace root, so that I can use relative paths in my scripts that reference project files.

#### Acceptance Criteria

1. WHEN the user invokes "Stata: CD into Workspace Folder" THEN the Send_To_Stata_Script SHALL generate a `cd` command with the workspace root path
2. WHEN the workspace path contains double quotes THEN the Send_To_Stata_Script SHALL use Compound_String syntax `` `"path"' `` for the cd command
3. WHEN the workspace path contains backslashes (Windows) THEN the Send_To_Stata_Script SHALL double the backslashes for Stata compatibility
4. WHEN no workspace is open THEN the Send_To_Stata_Script SHALL exit with an error message
5. THE Send_To_Stata_Script SHALL send the generated cd command to Stata using the existing AppleScript (macOS) or SendKeys (Windows) mechanism

### Requirement 2: CD into File Folder

**User Story:** As a Stata developer, I want to change Stata's working directory to my current file's directory, so that I can use relative paths that reference files near my script.

#### Acceptance Criteria

1. WHEN the user invokes "Stata: CD into File Folder" THEN the Send_To_Stata_Script SHALL generate a `cd` command with the file's parent directory path
2. WHEN the file path contains double quotes THEN the Send_To_Stata_Script SHALL use Compound_String syntax `` `"path"' `` for the cd command
3. WHEN the file path contains backslashes (Windows) THEN the Send_To_Stata_Script SHALL double the backslashes for Stata compatibility
4. WHEN no file is open THEN the Send_To_Stata_Script SHALL exit with an error message
5. THE Send_To_Stata_Script SHALL send the generated cd command to Stata using the existing AppleScript (macOS) or SendKeys (Windows) mechanism

### Requirement 3: Do Upward Lines

**User Story:** As a Stata developer, I want to execute all code from the beginning of my file to my current cursor position, so that I can run setup code and reach a specific point in my script.

#### Acceptance Criteria

1. WHEN the user invokes "Stata: Do Upward Lines" THEN the Send_To_Stata_Script SHALL extract lines from line 1 to the cursor's current line (inclusive)
2. WHEN the cursor is on a line that is part of a multi-line statement (continuation with `///`) THEN the Send_To_Stata_Script SHALL extend the selection to include the complete statement
3. WHEN the cursor is on line 1 THEN the Send_To_Stata_Script SHALL send only line 1 (extended if it has continuations)
4. THE Send_To_Stata_Script SHALL write the extracted lines to a temporary file and execute via `do` command
5. THE Send_To_Stata_Script SHALL preserve line breaks in the extracted content

### Requirement 4: Do Downward Lines

**User Story:** As a Stata developer, I want to execute all code from my current cursor position to the end of my file, so that I can run the remainder of my script from a specific point.

#### Acceptance Criteria

1. WHEN the user invokes "Stata: Do Downward Lines" THEN the Send_To_Stata_Script SHALL extract lines from the cursor's current line to the last line of the file (inclusive)
2. WHEN the cursor is on a continuation line (previous line ends with `///`) THEN the Send_To_Stata_Script SHALL find the statement start and include from there
3. WHEN the cursor is on the last line THEN the Send_To_Stata_Script SHALL send only that line (finding statement start if on continuation)
4. THE Send_To_Stata_Script SHALL write the extracted lines to a temporary file and execute via `do` command
5. THE Send_To_Stata_Script SHALL preserve line breaks in the extracted content

### Requirement 5: Path Escaping

**User Story:** As a Stata developer, I want paths to be properly escaped for Stata, so that cd commands work correctly regardless of special characters in my directory names.

#### Acceptance Criteria

1. THE Path_Escaping function SHALL return the escaped path and a flag indicating whether compound string syntax is needed
2. WHEN a path contains double quote characters THEN the Path_Escaping function SHALL set the compound string flag to true
3. WHEN a path contains backslash characters THEN the Path_Escaping function SHALL double each backslash in the output
4. THE cd command formatter SHALL use `` cd `"path"' `` when compound string flag is true
5. THE cd command formatter SHALL use `cd "path"` when compound string flag is false

### Requirement 6: Zed Task Integration

**User Story:** As a Stata developer, I want the new commands available as Zed tasks with keybindings, so that I can quickly invoke them while editing.

#### Acceptance Criteria

1. THE installer SHALL add four new tasks to Zed's tasks.json: "Stata: CD into Workspace Folder", "Stata: CD into File Folder", "Stata: Do Upward Lines", "Stata: Do Downward Lines"
2. THE installer SHALL add keybindings for the new tasks in Zed's keymap.json
3. THE tasks SHALL only be visible when editing `.do` files (context: `Editor && extension == do`)
4. THE tasks SHALL respect the existing focus behavior configuration (ACTIVATE_STATA setting)
5. THE installer uninstall function SHALL remove the new tasks and keybindings

### Requirement 7: Cross-Platform Support

**User Story:** As a Stata developer on either macOS or Windows, I want the new commands to work on my platform, so that I have a consistent experience.

#### Acceptance Criteria

1. THE macOS implementation SHALL add new modes to `send-to-stata.sh`: `--cd-workspace`, `--cd-file`, `--upward`, `--downward`
2. THE Windows implementation SHALL add new parameters to `SendToStata.cs`: `-CDWorkspace`, `-CDFile`, `-Upward`, `-Downward`
3. WHEN running on macOS THEN the Send_To_Stata_Script SHALL use AppleScript to send commands to Stata
4. WHEN running on Windows THEN the Send_To_Stata_Script SHALL use clipboard and SendKeys to send commands to Stata
5. THE macOS installer (`install-send-to-stata.sh`) SHALL be updated to include the new tasks and keybindings
6. THE Windows installer (`install-send-to-stata.ps1`) SHALL be updated to include the new tasks and keybindings
