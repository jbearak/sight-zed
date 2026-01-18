# Requirements Document

## Introduction

This document specifies the requirements for implementing send-to-stata functionality on Windows using a clipboard and SendKeys approach. The feature enables Zed editor users on Windows to send Stata code directly to a running Stata GUI instance for execution, providing feature parity with the existing macOS implementation.

## Glossary

- **Send_Script**: The PowerShell script (`send-to-stata.ps1`) that handles sending code to Stata
- **Installer**: The PowerShell script (`install-send-to-stata.ps1`) that sets up the environment
- **Statement_Mode**: Mode where only the current statement (or selection) is sent to Stata
- **File_Mode**: Mode where the entire file is sent to Stata
- **Include_Mode**: A modifier that uses Stata's `include` command instead of `do` to preserve local macro scope
- **Continuation_Marker**: The `///` sequence that indicates a Stata statement continues on the next line
- **Compound_String**: Stata string syntax using backticks and quotes (e.g., `` `"text"' ``)
- **SendKeys**: Windows API for simulating keyboard input to applications (via System.Windows.Forms or Microsoft.VisualBasic)
- **Clipboard**: Windows system clipboard used to transfer code to Stata
- **Stdin_Mode**: Mode where selected text is read from standard input instead of command-line arguments

## Requirements

### Requirement 1: Stata Installation Detection

**User Story:** As a Windows user, I want the script to automatically detect my Stata installation, so that I don't have to manually configure the path.

#### Acceptance Criteria

1. WHEN the Send_Script starts, THE Send_Script SHALL search for Stata installations in the following directories for versions 19 down to 13:
   - `C:\Program Files\Stata{version}\`
   - `C:\Program Files (x86)\Stata{version}\`
   - `C:\Stata{version}\`
   - `C:\Program Files\StataNow{version}\`
   - `C:\Program Files (x86)\StataNow{version}\`
   - `C:\StataNow{version}\`
2. WHEN searching for Stata, THE Send_Script SHALL check for executable variants in order: StataMP-64.exe, StataSE-64.exe, StataBE-64.exe, StataIC-64.exe, StataMP.exe, StataSE.exe, StataBE.exe, StataIC.exe
3. WHEN the STATA_PATH environment variable is set, THE Send_Script SHALL use that path instead of auto-detection
4. IF no Stata installation is found and STATA_PATH is not set, THEN THE Send_Script SHALL exit with error code 4 and display an error message
5. THE Send_Script SHALL also search for Stata in `C:\Stata\` (without version number) as a fallback location

### Requirement 2: Statement Mode Execution

**User Story:** As a Stata user, I want to send the current statement to Stata, so that I can execute code incrementally while developing.

#### Acceptance Criteria

1. WHEN invoked with --statement mode and selected text is provided via --stdin, THE Send_Script SHALL send the selected text to Stata
2. WHEN invoked with --statement mode and no selection but a row number is provided, THE Send_Script SHALL detect and send the statement at that cursor position
3. WHEN detecting a statement, THE Send_Script SHALL include all lines connected by continuation markers (`///`)
4. WHEN a line ends with `///` followed by optional whitespace, THE Send_Script SHALL treat the next line as part of the same statement
5. WHEN the cursor is on any line of a multi-line statement, THE Send_Script SHALL detect and send the entire statement
6. WHEN --stdin is provided, THE Send_Script SHALL read selected text from standard input to avoid shell interpretation of special characters
7. IF stdin is empty and --row is provided, THE Send_Script SHALL fall back to row-based statement detection

### Requirement 3: File Mode Execution

**User Story:** As a Stata user, I want to send an entire file to Stata, so that I can execute complete scripts.

#### Acceptance Criteria

1. WHEN invoked with --file-mode, THE Send_Script SHALL read the entire source file
2. WHEN sending file content, THE Send_Script SHALL preserve all line breaks and formatting
3. IF the source file does not exist or is unreadable, THEN THE Send_Script SHALL exit with error code 2

### Requirement 4: Include Mode Support

**User Story:** As a Stata user, I want to use include mode to preserve local macros, so that I can debug code that uses local variables.

#### Acceptance Criteria

1. WHEN the --include flag is provided, THE Send_Script SHALL use Stata's `include` command instead of `do`
2. WHEN using include mode, THE Send_Script SHALL create a temp file and execute `include "{temp_file_path}"`
3. WHEN using do mode (default), THE Send_Script SHALL create a temp file and execute `do "{temp_file_path}"`

### Requirement 5: Clipboard and SendKeys Execution

**User Story:** As a Windows user, I want the script to send code to an already-running Stata instance, so that I can work with my existing Stata session.

#### Acceptance Criteria

1. WHEN sending code to Stata, THE Send_Script SHALL first write the code to a temp .do file
2. WHEN sending code to Stata, THE Send_Script SHALL copy the Stata command (`do "{temp_file}"` or `include "{temp_file}"`) to the Windows clipboard
3. WHEN sending code to Stata, THE Send_Script SHALL find the Stata window by searching for processes with window titles matching "Stata/*"
4. WHEN a Stata window is found, THE Send_Script SHALL activate (bring to foreground) that window
5. WHEN the Stata window is activated, THE Send_Script SHALL simulate Ctrl+V to paste the command into Stata's command window
6. WHEN the command is pasted, THE Send_Script SHALL simulate Ctrl+D to execute the command in Stata
7. IF no running Stata instance is found, THEN THE Send_Script SHALL exit with error code 4 and display an error message
8. WHEN simulating keystrokes, THE Send_Script SHALL include appropriate delays to ensure reliable execution

### Requirement 6: Temp File Management

**User Story:** As a user, I want temp files to be created reliably, so that code execution works consistently.

#### Acceptance Criteria

1. WHEN creating temp files, THE Send_Script SHALL use the system temp directory with a unique filename
2. WHEN creating temp files, THE Send_Script SHALL use the `.do` extension
3. IF temp file creation fails, THEN THE Send_Script SHALL exit with error code 3

### Requirement 7: Installer Script

**User Story:** As a Windows user, I want an easy installation process, so that I can quickly set up send-to-stata.

#### Acceptance Criteria

1. WHEN the Installer runs, THE Installer SHALL copy send-to-stata.ps1 to `$env:APPDATA\Zed\stata\`
2. WHEN the Installer runs, THE Installer SHALL create or update Zed tasks in `$env:APPDATA\Zed\tasks.json`
3. WHEN the Installer runs, THE Installer SHALL create or update keybindings in `$env:APPDATA\Zed\keymap.json`
4. WHEN the Installer runs, THE Installer SHALL detect and report the installed Stata variant
5. WHEN updating tasks.json, THE Installer SHALL preserve existing non-Stata tasks
6. WHEN updating keymap.json, THE Installer SHALL preserve existing non-Stata keybindings
7. WHEN invoked with -Uninstall, THE Installer SHALL remove all installed components
8. THE Installer SHALL support one-line web installation via `irm | iex` pattern (Invoke-RestMethod piped to Invoke-Expression)
9. WHEN running via web installation, THE Installer SHALL fetch send-to-stata.ps1 from GitHub
10. WHEN running via web installation from the main branch, THE Installer SHALL verify the SHA-256 checksum of send-to-stata.ps1
11. THE Installer SHALL support a SIGHT_GITHUB_REF environment variable to override the branch/tag for testing

### Requirement 8: Zed Tasks Configuration

**User Story:** As a Zed user, I want tasks configured for all send modes, so that I can use the task picker or keybindings.

#### Acceptance Criteria

1. THE Installer SHALL create a task named "Stata: Send Statement" for statement mode
2. THE Installer SHALL create a task named "Stata: Send File" for file mode
3. THE Installer SHALL create a task named "Stata: Include Statement" for include statement mode
4. THE Installer SHALL create a task named "Stata: Include File" for include file mode
5. WHEN tasks are created, THE Installer SHALL configure them to hide on success and not use a new terminal

### Requirement 9: Keybindings Configuration

**User Story:** As a Zed user, I want keyboard shortcuts for sending code to Stata, so that I can work efficiently.

#### Acceptance Criteria

1. THE Installer SHALL bind `ctrl-enter` to "Stata: Send Statement" in .do files
2. THE Installer SHALL bind `shift-ctrl-enter` to "Stata: Send File" in .do files
3. THE Installer SHALL bind `alt-ctrl-enter` to "Stata: Include Statement" in .do files
4. THE Installer SHALL bind `alt-shift-ctrl-enter` to "Stata: Include File" in .do files
5. WHEN keybindings are created, THE Installer SHALL save the file before executing the task

### Requirement 10: Terminal Keybindings Configuration

**User Story:** As a Zed user who SSHs into remote machines or uses WSL, I want terminal-compatible keyboard shortcuts, so that I can send code to Stata from terminal contexts.

#### Acceptance Criteria

1. THE Installer SHALL bind `alt-enter` to "Stata: Send Statement" in .do files (terminal-compatible)
2. THE Installer SHALL bind `shift-alt-enter` to "Stata: Send File" in .do files (terminal-compatible)
3. THE documentation SHALL note that terminal keybindings are useful for SSH sessions to Linux/Mac machines or when using WSL

### Requirement 11: Error Handling and Exit Codes

**User Story:** As a user, I want clear error messages and consistent exit codes, so that I can troubleshoot issues.

#### Acceptance Criteria

1. THE Send_Script SHALL exit with code 0 on success
2. THE Send_Script SHALL exit with code 1 for invalid arguments
3. THE Send_Script SHALL exit with code 2 when the source file is not found or unreadable
4. THE Send_Script SHALL exit with code 3 when temp file creation fails
5. THE Send_Script SHALL exit with code 4 when Stata is not found (installation or running instance)
6. THE Send_Script SHALL exit with code 5 when SendKeys execution fails
7. WHEN an error occurs, THE Send_Script SHALL display a descriptive error message to stderr

### Requirement 12: Compound String Safety

**User Story:** As a Stata user, I want compound strings to be handled correctly, so that my code with backticks and quotes executes properly.

#### Acceptance Criteria

1. WHEN handling selected text containing compound strings (backticks, quotes), THE Send_Script SHALL preserve them exactly
2. WHEN reading environment variables, THE Send_Script SHALL avoid shell interpretation of special characters
3. WHEN writing to temp files, THE Send_Script SHALL preserve all special characters in the code

### Requirement 13: PowerShell Compatibility

**User Story:** As a Windows user, I want the scripts to work with the PowerShell version that ships with Windows, so that I don't need additional installations.

#### Acceptance Criteria

1. THE Send_Script SHALL be compatible with PowerShell 5.0 and later
2. THE Installer SHALL be compatible with PowerShell 5.0 and later
3. THE Send_Script SHALL NOT require any compiled executables or external dependencies beyond PowerShell
4. THE Send_Script SHALL use only built-in .NET assemblies (System.Windows.Forms, Microsoft.VisualBasic)

## Out of Scope

The following items are explicitly out of scope for this implementation:

1. Support for PowerShell versions prior to 5.0
2. Support for Stata console/batch mode (only GUI mode is supported)
3. Remote Stata execution (only local Stata instances)
4. Integration with other editors besides Zed
5. Automatic Stata installation or configuration
