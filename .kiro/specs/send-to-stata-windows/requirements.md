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
- **SendKeys**: Windows API for simulating keyboard input to applications (via System.Windows.Forms)
- **Clipboard**: Windows system clipboard used to transfer code to Stata
- **Stdin_Mode**: Mode where selected text is read from standard input instead of command-line arguments
- **STA_Mode**: Single-Threaded Apartment mode required for clipboard operations in PowerShell
- **UIPI**: User Interface Privilege Isolation - Windows security feature that blocks input from lower to higher integrity processes
- **Command_Window**: Stata's command input pane, accessible via Ctrl+1

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
3. WHEN sending code to Stata, THE Send_Script SHALL find the Stata window by searching for processes matching "Stata*" or "StataNow*" with window titles matching the pattern `Stata/(MP|SE|BE|IC)` or `StataNow/(MP|SE|BE|IC)`
4. WHEN a Stata window is found, THE Send_Script SHALL activate (bring to foreground) that window
5. WHEN the Stata window is activated, THE Send_Script SHALL simulate Ctrl+1 to focus the Command window before pasting
6. WHEN the Command window is focused, THE Send_Script SHALL simulate Ctrl+V to paste the command
7. WHEN the command is pasted, THE Send_Script SHALL simulate Enter to execute the command in Stata
8. IF no running Stata instance is found, THEN THE Send_Script SHALL exit with error code 4 and display an error message
9. WHEN simulating keystrokes, THE Send_Script SHALL use hardcoded timing delays (see Requirement 16)
10. WHEN activating the Stata window, THE Send_Script SHALL first restore the window if minimized using ShowWindow with SW_RESTORE
11. WHEN activating the Stata window, THE Send_Script SHALL simulate an ALT keypress before calling SetForegroundWindow to satisfy Windows focus-stealing prevention requirements
12. AFTER calling SetForegroundWindow, THE Send_Script SHALL verify the foreground window matches the target Stata window before sending keystrokes
13. IF focus verification fails after 3 retry attempts, THE Send_Script SHALL exit with error code 5 and display an error message

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
6. WHEN tasks are created, THE Installer SHALL configure them to launch PowerShell with the `-sta` flag to enable STA threading mode required for clipboard operations
7. WHEN tasks are created, THE Installer SHALL configure them with `-ExecutionPolicy Bypass` to allow script execution without requiring system-wide policy changes

### Requirement 9: Keybindings Configuration

**User Story:** As a Zed user, I want keyboard shortcuts for sending code to Stata, so that I can work efficiently.

#### Acceptance Criteria

1. THE Installer SHALL bind `ctrl-enter` to "Stata: Send Statement" in .do files
2. THE Installer SHALL bind `shift-ctrl-enter` to "Stata: Send File" in .do files
3. THE Installer SHALL bind `alt-ctrl-enter` to "Stata: Include Statement" in .do files
4. THE Installer SHALL bind `alt-shift-ctrl-enter` to "Stata: Include File" in .do files
5. WHEN keybindings are created, THE Installer SHALL save the file before executing the task

### Requirement 10: Quick Terminal Keybindings Configuration

**User Story:** As a Zed user who works with Stata in terminal sessions (SSH, WSL, or multiple Stata instances), I want quick keyboard shortcuts to paste code directly into the active terminal panel.

#### Acceptance Criteria

1. THE Installer SHALL bind `shift-enter` to paste the current selection to the terminal in .do files
2. THE Installer SHALL bind `alt-enter` to select and paste the current line to the terminal in .do files
3. WHEN `shift-enter` is pressed, THE keybinding SHALL copy the selection, switch to terminal, paste, and execute
4. WHEN `alt-enter` is pressed, THE keybinding SHALL select the current line, copy it, switch to terminal, paste, and execute
5. THE keybindings SHALL use Zed's `SendKeystrokes` action with Windows-appropriate key sequences (ctrl-c, ctrl-`, ctrl-v, enter)
6. THE documentation SHALL note that terminal shortcuts are useful for:
   - SSH sessions to remote machines running Stata
   - WSL environments
   - Multiple concurrent Stata terminal sessions
7. THE documentation SHALL note that `alt-enter` sends only the current line and does not detect multi-line statements with `///` continuations
8. THE documentation SHALL note that `///` continuation syntax cannot be pasted directly to Stata's console—users should use `ctrl-enter` for multi-line statements

### Requirement 11: Error Handling and Exit Codes

**User Story:** As a user, I want clear error messages and consistent exit codes, so that I can troubleshoot issues.

#### Acceptance Criteria

1. THE Send_Script SHALL exit with code 0 on success
2. THE Send_Script SHALL exit with code 1 for invalid arguments
3. THE Send_Script SHALL exit with code 2 when the source file is not found or unreadable
4. THE Send_Script SHALL exit with code 3 when temp file creation fails
5. THE Send_Script SHALL exit with code 4 when Stata is not found (installation or running instance)
6. THE Send_Script SHALL exit with code 5 when SendKeys execution fails or window activation fails after retries
7. WHEN an error occurs, THE Send_Script SHALL display a descriptive error message to stderr
8. WHEN window activation fails, THE Send_Script SHALL include diagnostic information about whether Stata may be running with elevated privileges

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
5. THE Send_Script SHALL require STA (Single-Threaded Apartment) mode for clipboard operations, which SHALL be enforced by launching PowerShell with the `-sta` flag

### Requirement 14: Cross-Platform Testability

**User Story:** As a developer working on macOS, I want to run unit tests for the PowerShell scripts without a Windows machine, so that I can iterate quickly during development.

#### Acceptance Criteria

1. THE Send_Script SHALL separate platform-independent logic (argument parsing, statement detection, file operations) from Windows-specific APIs (clipboard, SendKeys, window activation)
2. THE Send_Script SHALL expose Windows-specific operations through mockable functions that can be stubbed during testing
3. THE test suite SHALL use Pester (PowerShell's testing framework) which runs on both Windows and macOS/Linux via `pwsh`
4. THE test suite SHALL include unit tests for:
   - Argument parsing and validation
   - Statement detection with continuation markers
   - File reading and temp file creation
   - Include vs do mode selection
   - Error handling and exit codes
5. THE test suite SHALL skip Windows-specific integration tests when running on non-Windows platforms
6. THE test suite SHALL be runnable via `pwsh -Command "Invoke-Pester"` on macOS
7. THE CI pipeline SHALL run unit tests on macOS and full integration tests on Windows

### Requirement 15: Windows Security Model Compatibility

**User Story:** As a Windows user, I want the script to work reliably within Windows security constraints, so that code is sent to Stata without manual intervention.

#### Acceptance Criteria

1. THE Send_Script SHALL handle Windows focus-stealing prevention by simulating an ALT keypress via keybd_event before calling SetForegroundWindow
2. THE Send_Script SHALL restore minimized Stata windows using ShowWindow with SW_RESTORE (9) before attempting to activate
3. THE Send_Script SHALL verify focus acquisition by checking GetForegroundWindow after SetForegroundWindow and retry up to 3 times with increasing delays
4. THE documentation SHALL clearly state that Stata must NOT be running with elevated privileges ("Run as Administrator") for the script to work, due to UIPI restrictions
5. THE Send_Script SHALL detect if the target Stata window appears to be elevated and display a helpful error message suggesting the user restart Stata without elevation
6. THE Send_Script SHALL NOT require elevation itself and SHALL work when run as a standard user

### Requirement 16: Timing Configuration

**User Story:** As a user, I want reliable keystroke timing that works on most systems, with the ability to adjust if needed.

#### Acceptance Criteria

1. THE Send_Script SHALL use hardcoded timing values at the top of the script:
   - `$clipPause = 10` (milliseconds after clipboard copy)
   - `$winPause = 10` (milliseconds between window operations)
   - `$keyPause = 1` (milliseconds between keystrokes)
2. THE README SHALL document these timing values and their purpose
3. THE README SHALL explain when users might need to increase timing values (older machines, slow systems)
4. THE README SHALL explain how to locate and modify the timing values in the script
5. THE Send_Script SHALL use `$winPause` for delays after ShowWindow and SetForegroundWindow
6. THE Send_Script SHALL use `$clipPause` for delay after clipboard copy before sending keys
7. THE Send_Script SHALL use `$keyPause` for delays between Ctrl+1, Ctrl+V, and Enter keystrokes

## Out of Scope

The following items are explicitly out of scope for this implementation:

1. Support for PowerShell versions prior to 5.0
2. Support for Stata console/batch mode (only GUI mode is supported)
3. Remote Stata execution (only local Stata instances)
4. Integration with other editors besides Zed
5. Automatic Stata installation or configuration
6. Sending code to an elevated Stata instance from a non-elevated script (Windows UIPI limitation)
7. COM Automation approach (requires persistent process to maintain connection)
8. External configuration files (timing values are hardcoded; see Requirement 16)

## Appendix: Design Rationale

**Why Clipboard + SendKeys Instead of COM Automation?**

Stata provides COM Automation on Windows (`stata.StataOLEApp`), which would seem ideal for programmatic control. However, Stata's COM server is documented as "single-use out-of-process," meaning each `CreateObject()` call launches a *new* Stata instance rather than connecting to an existing one. The COM reference is tied to the calling process's lifetime—when the PowerShell script exits, the reference is released and Stata closes. Sublime Text plugins work around this by keeping Python running persistently, but Zed tasks spawn independent processes for each invocation with no shared state. A daemon-based architecture could maintain a persistent COM connection, but this adds significant complexity (startup management, crash recovery, IPC) that outweighs the benefits for this use case.

**Why Clipboard Transfer Instead of Typing via SendKeys?**

SendKeys can simulate typing character-by-character, but this approach is fragile and slow. SendKeys uses special escape sequences (`^` for Ctrl, `+` for Shift, `%` for Alt, `{}` for special keys), which conflict with characters common in Stata code. Compound strings containing backticks and braces would require complex escaping that is error-prone. Clipboard transfer is atomic—the entire command arrives intact regardless of special characters—and is significantly faster. The tradeoff is requiring STA (Single-Threaded Apartment) mode for clipboard access, which is trivially addressed by launching PowerShell with the `-sta` flag.

**Why Not Shell Execute (Opening .do Files Directly)?**

Double-clicking a `.do` file or using `Start-Process` on it causes Windows to launch a *new* Stata instance rather than sending the file to an existing session. This would discard the user's loaded data, working directory, and defined macros. The clipboard + SendKeys approach targets the user's existing Stata session where their work is already in progress.
