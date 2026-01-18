# Implementation Tasks: Send-to-Stata Windows

## Task 1: Create Core Script Infrastructure

- [ ] 1.1 Create `send-to-stata.ps1` with parameter block and basic structure
  - Define parameters: `-Statement`, `-FileMode`, `-Include`, `-Stdin`, `-File`, `-Row`
  - Add parameter validation (mutually exclusive modes, required `-File`)
  - Implement exit code constants matching design (0-5)
  - **Validates: Requirements 11.1, 11.2**

- [ ] 1.2 Implement `Find-StataInstallation` function
  - Check `$env:STATA_PATH` first and return if valid
  - Search versions 19→13 in order
  - Search paths: Program Files → Program Files (x86) → C:\
  - Search StataNow variants in same order
  - Search variants: StataMP-64 → StataSE-64 → StataBE-64 → StataIC-64 → StataMP → StataSE → StataBE → StataIC
  - Add fallback to `C:\Stata\` without version number
  - Return `$null` if not found
  - **Validates: Requirements 1.1, 1.2, 1.3, 1.5**

- [ ] 1.3 Implement `Find-StataWindow` function
  - Get processes matching `Stata*` pattern
  - Filter by window title containing "Stata/"
  - Return process object with `MainWindowHandle`, or `$null`
  - **Validates: Requirements 5.3, 5.7**

## Task 2: Implement Statement Detection

- [ ] 2.1 Implement `Get-StatementAtRow` function
  - Accept `$FilePath` and `$Row` (1-indexed) parameters
  - Read file lines into array
  - Search backwards from cursor row to find statement start (line not preceded by `///`)
  - Search forwards to find statement end (line not ending with `///` followed by optional whitespace)
  - Join lines with preserved line breaks
  - Return complete statement text
  - **Validates: Requirements 2.2, 2.3, 2.4, 2.5**

- [ ] 2.2 Write property test for multi-line statement detection (Property 3)
  - Generate random Stata files with continuation markers
  - For each cursor position within a multi-line statement, verify complete statement is returned
  - Run 100+ iterations
  - **Validates: Design Property 3**

## Task 3: Implement File Operations

- [ ] 3.1 Implement `New-TempDoFile` function
  - Use `[System.IO.Path]::GetTempFileName()` for unique filename
  - Rename to `.do` extension
  - Write content with UTF-8 encoding (no BOM)
  - Return full path to temp file
  - Handle errors and return `$null` on failure
  - **Validates: Requirements 6.1, 6.2, 6.3**

- [ ] 3.2 Implement file reading for File Mode
  - Read entire source file content
  - Preserve all line breaks and formatting
  - Exit with code 2 if file not found or unreadable
  - **Validates: Requirements 3.1, 3.2, 3.3**

- [ ] 3.3 Implement stdin reading for Statement Mode
  - Read selected text from `$input` (PowerShell stdin)
  - Preserve compound strings with backticks and quotes exactly
  - Fall back to row-based detection if stdin is empty
  - **Validates: Requirements 2.1, 2.6, 2.7, 12.1, 12.2**

- [ ] 3.4 Write property test for stdin content round-trip (Property 4)
  - Generate random text including compound strings
  - Pipe through stdin, write to temp file, verify byte-for-byte match
  - Run 100+ iterations
  - **Validates: Design Property 4**

- [ ] 3.5 Write property test for file content round-trip (Property 5)
  - Generate random source files with special characters
  - Read in file mode, write to temp, verify exact match
  - Run 100+ iterations
  - **Validates: Design Property 5**

## Task 4: Implement Windows Automation

- [ ] 4.1 Add Win32 API type definitions
  - Add `System.Windows.Forms` assembly
  - Add P/Invoke for `SetForegroundWindow`
  - Add P/Invoke for `ShowWindow`
  - **Validates: Requirements 13.4**

- [ ] 4.2 Implement `Send-ToStata` function
  - Build command string: `do "{path}"` or `include "{path}"`
  - Copy command to clipboard via `[System.Windows.Forms.Clipboard]::SetText()`
  - Find Stata window using `Find-StataWindow`
  - Activate window using `SetForegroundWindow`
  - Wait configurable delay (default 100ms, `$env:STATA_ACTIVATION_DELAY`)
  - Send `Ctrl+V` via `SendKeys::SendWait("^v")`
  - Wait inter-key delay (default 50ms, `$env:STATA_INTERKEY_DELAY`)
  - Send `Ctrl+D` via `SendKeys::SendWait("^d")`
  - Handle errors and exit with code 5 on failure
  - **Validates: Requirements 5.1, 5.2, 5.4, 5.5, 5.6, 5.8**

- [ ] 4.3 Write property test for command format by mode (Property 6)
  - Generate random temp file paths
  - Verify `do "{path}"` when Include=false, `include "{path}"` when Include=true
  - Run 100+ iterations
  - **Validates: Design Property 6**

## Task 5: Implement Main Script Logic

- [ ] 5.1 Implement main execution flow
  - Parse arguments and validate
  - Determine mode (Statement vs File, Include vs Do)
  - Read content (stdin → row detection → file)
  - Create temp file
  - Send to Stata
  - Exit with appropriate code
  - **Validates: Requirements 2.1, 2.2, 3.1, 4.1, 4.2, 4.3**

- [ ] 5.2 Implement error handling with descriptive messages
  - Exit 1: Invalid arguments with specific message
  - Exit 2: File not found with path in message
  - Exit 3: Temp file creation failed
  - Exit 4: Stata not found (installation or running instance)
  - Exit 5: SendKeys execution failed
  - All errors to stderr
  - **Validates: Requirements 11.1-11.7**

- [ ] 5.3 Write property test for STATA_PATH override (Property 1)
  - Set `$env:STATA_PATH` to various valid paths
  - Verify auto-detection is skipped entirely
  - Run 100+ iterations
  - **Validates: Design Property 1**

- [ ] 5.4 Write property test for Stata search order (Property 2)
  - Mock filesystem with multiple Stata installations
  - Verify correct priority: versions → paths → variants → fallback
  - Run 100+ iterations
  - **Validates: Design Property 2**

## Task 6: Create Installer Script

- [ ] 6.1 Create `install-send-to-stata.ps1` with parameter block
  - Define `-Uninstall` switch parameter
  - Define `-RegisterAutomation` switch parameter
  - Define `-SkipAutomationCheck` switch parameter
  - Detect local vs web installation mode
  - **Validates: Requirements 7.7, 7.8, 17.4, 17.5**

- [ ] 6.2 Implement `Install-Script` function
  - Create `$env:APPDATA\Zed\stata\` directory if needed
  - Copy `send-to-stata.ps1` from local or fetch from GitHub
  - For web installation: verify SHA-256 checksum (skip if `$env:SIGHT_GITHUB_REF` is set)
  - **Validates: Requirements 7.1, 7.9, 7.10, 7.11**

- [ ] 6.3 Implement `Install-Tasks` function
  - Read existing `$env:APPDATA\Zed\tasks.json` or create empty array
  - Remove existing tasks with labels starting with "Stata:"
  - Add four tasks: Send Statement, Send File, Include Statement, Include File
  - Configure: `use_new_terminal: false`, `allow_concurrent_runs: true`, `reveal: never`, `hide: on_success`
  - Write back preserving non-Stata tasks
  - **Validates: Requirements 7.2, 7.5, 8.1-8.5**

- [ ] 6.4 Implement `Install-Keybindings` function
  - Read existing `$env:APPDATA\Zed\keymap.json` or create empty array
  - Remove existing `.do` file keybindings
  - Add standard keybindings with `workspace::Save` before task spawn:
    - `ctrl-enter` → Stata: Send Statement
    - `shift-ctrl-enter` → Stata: Send File
    - `alt-ctrl-enter` → Stata: Include Statement
    - `alt-shift-ctrl-enter` → Stata: Include File
  - Add terminal keybindings using `SendKeystrokes`:
    - `shift-enter` → copy selection, switch terminal, paste, execute
    - `alt-enter` → select line, copy, switch terminal, paste, execute
  - Write back preserving non-Stata keybindings
  - **Validates: Requirements 7.3, 7.6, 9.1-9.5, 10.1-10.5**

- [ ] 6.5 Implement Stata detection and reporting
  - Call `Find-StataInstallation` and report found variant
  - Display installation summary
  - **Validates: Requirements 7.4**

- [ ] 6.6 Implement uninstall functionality
  - Remove `$env:APPDATA\Zed\stata\` directory
  - Remove Stata tasks from `tasks.json`
  - Remove Stata keybindings from `keymap.json`
  - **Validates: Requirements 7.7**

- [ ] 6.7 Write property test for config file preservation (Property 8)
  - Generate tasks.json/keymap.json with random non-Stata entries
  - Run installer, verify non-Stata entries preserved
  - Run 100+ iterations
  - **Validates: Design Property 8**

- [ ] 6.8 Write property test for checksum verification (Property 9)
  - Mock web download with correct/incorrect checksums
  - Verify pass/fail behavior
  - Verify skip when `SIGHT_GITHUB_REF` is set
  - Run 100+ iterations
  - **Validates: Design Property 9**

- [ ] 6.9 Implement `Test-StataAutomationRegistered` function
  - Query registry for `stata.StataOLEApp` ProgID at `HKEY_CLASSES_ROOT`
  - Get CLSID and read `LocalServer32` value to get registered executable path
  - Strip any arguments (e.g., `/Automation`) from the path
  - Return hashtable with `IsRegistered` boolean and `RegisteredPath` string
  - **Validates: Requirements 17.1, 17.10, 17.11**

- [ ] 6.10 Implement `Register-StataAutomation` function
  - Accept Stata executable path as parameter
  - Launch elevated PowerShell process using `Start-Process -Verb RunAs`
  - Execute `{StataExecutable} /Register`
  - Capture and return exit code
  - Handle UAC cancellation gracefully
  - **Validates: Requirements 17.3, 17.6, 17.7**

- [ ] 6.11 Implement `Show-RegistrationPrompt` function
  - Accept message and title parameters
  - Display popup dialog using `System.Windows.Forms.MessageBox`
  - Use Yes/No buttons and Question icon
  - Return `$true` if user clicks Yes, `$false` if No
  - **Validates: Requirements 17.12, 17.13, 17.14, 17.15**

- [ ] 6.12 Implement `Invoke-AutomationRegistrationCheck` function
  - Check if `-SkipAutomationCheck` is set, skip if so
  - Call `Test-StataAutomationRegistered` to get registration status and path
  - Compare registered path against detected Stata path for version mismatch
  - If version mismatch, show popup with old vs new paths and ask to update
  - If not registered, show popup asking to register
  - Call `Register-StataAutomation` if user confirms or `-RegisterAutomation` is set
  - Display manual registration instructions on failure
  - **Validates: Requirements 17.2, 17.4, 17.5, 17.6, 17.7, 17.11, 17.12, 17.13, 17.14, 17.15**

- [ ] 6.13 Integrate automation registration into installer main flow
  - Call `Invoke-AutomationRegistrationCheck` after Stata detection
  - Pass `-Force` when `-RegisterAutomation` is specified
  - Pass `-Skip` when `-SkipAutomationCheck` is specified
  - **Validates: Requirements 17.2, 17.4, 17.5**

## Task 7: Implement Cross-Platform Test Infrastructure

- [ ] 7.1 Create mockable wrapper functions
  - `Set-ClipboardContent` - wraps clipboard operations
  - `Invoke-WindowActivation` - wraps SetForegroundWindow
  - `Send-Keystrokes` - wraps SendKeys
  - `Get-StataProcesses` - wraps process enumeration
  - Add `$script:Mock*` flags for test mode
  - **Validates: Requirements 14.1, 14.2**

- [ ] 7.2 Create `tests/Mocks.ps1` with mock implementations
  - Mock clipboard that stores content in variable
  - Mock window activation that records calls
  - Mock SendKeys that records keystrokes
  - Mock process list for Stata window detection
  - **Validates: Requirements 14.2**

- [ ] 7.3 Create `tests/Generators.ps1` with random data generators
  - `New-RandomStataFile` - generates files with optional continuations
  - `New-RandomCompoundString` - generates backtick/quote strings
  - `New-RandomTasksJson` - generates tasks.json with random entries
  - `New-RandomKeymapJson` - generates keymap.json with random entries
  - **Validates: Requirements 14.4**

- [ ] 7.4 Create `tests/CrossPlatform.ps1` with platform detection
  - Detect Windows vs macOS/Linux
  - Export `$IsWindowsPlatform` variable
  - Provide `Skip-WindowsOnly` helper for integration tests
  - **Validates: Requirements 14.5, 14.6**

- [ ] 7.5 Write property test for platform-independent logic isolation (Property 10)
  - Run all platform-independent functions on current platform
  - Verify no Windows API calls when mocks are enabled
  - Run 100+ iterations
  - **Validates: Design Property 10**

## Task 8: Create Unit Test Suite

- [ ] 8.1 Create `tests/send-to-stata.Tests.ps1`
  - Test argument parsing with valid/invalid inputs
  - Test exit codes for each error condition
  - Test `Find-StataInstallation` with mocked filesystem
  - Test `Find-StataWindow` with mocked process list
  - Test `Get-StatementAtRow` with example files
  - Test `New-TempDoFile` characteristics
  - **Validates: Requirements 14.4**

- [ ] 8.2 Create `tests/install-send-to-stata.Tests.ps1`
  - Test local vs web installation detection
  - Test tasks.json creation and update
  - Test keymap.json creation and update
  - Test uninstall removes all components
  - Test checksum verification logic
  - **Validates: Requirements 14.4**

- [ ] 8.3 Write property test for temp file characteristics (Property 7)
  - Create many temp files
  - Verify: (a) in system temp directory, (b) `.do` extension, (c) unique filenames
  - Run 100+ iterations
  - **Validates: Design Property 7**

## Task 9: Documentation

- [ ] 9.1 Create Windows section in SEND-TO-STATA.md
  - Installation instructions using `irm | iex`
  - Keybinding reference table
  - Terminal shortcuts documentation with limitations
  - Troubleshooting guide
  - **Validates: Requirements 10.6, 10.7, 10.8**

- [ ] 9.2 Add Windows-specific notes to README.md
  - Link to SEND-TO-STATA.md Windows section
  - Note PowerShell 5.0+ requirement
  - **Validates: Requirements 13.1, 13.2**

- [ ] 9.3 Document Stata Automation type library registration
  - Explain that registration is a one-time setup step
  - Document the `-RegisterAutomation` and `-SkipAutomationCheck` flags
  - Include manual registration instructions:
    - Open Command Prompt or PowerShell as Administrator
    - Navigate to Stata installation directory
    - Run `StataSE.exe /Register` (or appropriate variant)
  - Note that registration requires elevation (UAC prompt)
  - In troubleshooting section: if send-to-stata stops working after upgrading Stata, re-run the installer to fix
  - **Validates: Requirements 17.8, 17.9, 17.16**
