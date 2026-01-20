# Implementation Tasks: Send-to-Stata Windows

## Task 1: Create Core Script Infrastructure

- [x] 1.1 Create `send-to-stata.ps1` with parameter block and basic structure
- [x] 1.2 Implement `Find-StataInstallation` function
- [x] 1.3 Implement `Find-StataWindow` function

## Task 2: Implement Statement Detection

- [x] 2.1 Implement `Get-StatementAtRow` function
- [x] 2.2 Write property test for multi-line statement detection (Property 3)

## Task 3: Implement File Operations

- [x] 3.1 Implement `New-TempDoFile` function
- [x] 3.2 Implement file reading for File Mode
- [x] 3.3 Implement stdin reading for Statement Mode
- [x] 3.4 Write property test for stdin content round-trip (Property 4)
- [x] 3.5 Write property test for file content round-trip (Property 5)

## Task 4: Implement Windows Automation

- [x] 4.1 Add Win32 API type definitions
- [x] 4.2 Implement `Invoke-FocusAcquisition` function
- [x] 4.3 Implement `Send-ToStata` function
- [x] 4.4 Write property test for command format by mode (Property 6)
- [x] 4.5 Write property test for focus acquisition reliability (Property 11)
- [x] 4.6 Write property test for STA mode enforcement (Property 12)
- [x] 4.7 Write property test for Command window focus (Property 13)

## Task 5: Implement Main Script Logic

- [x] 5.1 Implement main execution flow
- [x] 5.2 Implement error handling with descriptive messages
- [x] 5.3 Write property test for STATA_PATH override (Property 1)
- [x] 5.4 Write property test for Stata search order (Property 2)

## Task 6: Create Installer Script

- [x] 6.1 Create `install-send-to-stata.ps1` with parameter block
- [x] 6.2 Implement `Install-Script` function
- [x] 6.3 Implement `Install-Tasks` function
- [x] 6.4 Implement `Install-Keybindings` function
- [x] 6.5 Implement Stata detection and reporting
- [x] 6.6 Implement uninstall functionality
- [x] 6.7 Write property test for config file preservation (Property 8)
- [x] 6.8 Write property test for checksum verification (Property 9)
- [x] 6.9 Implement `Test-StataAutomationRegistered` function
- [x] 6.10 Implement `Register-StataAutomation` function
- [x] 6.11 Implement `Show-RegistrationPrompt` function
- [x] 6.12 Implement `Invoke-AutomationRegistrationCheck` function
- [x] 6.13 Integrate automation registration into installer main flow
- [x] 6.14 Write property test for automation registration idempotency (Property 14)
- [x] 6.15 Write property test for version mismatch detection (Property 15)

## Task 7: Implement Cross-Platform Test Infrastructure

- [x] 7.1 Create mockable wrapper functions in `send-to-stata.ps1`
- [x] 7.2 Create `tests/Mocks.ps1` with mock implementations
- [x] 7.3 Create `tests/Generators.ps1` with random data generators
- [x] 7.4 Create `tests/CrossPlatform.ps1` with platform detection
- [x] 7.5 Write property test for platform-independent logic isolation (Property 10)

## Task 8: Create Unit Test Suite

- [x] 8.1 Create `tests/send-to-stata.Tests.ps1`
- [x] 8.2 Create `tests/install-send-to-stata.Tests.ps1`
- [x] 8.3 Write property test for temp file characteristics (Property 7)

## Task 9: Documentation

- [x] 9.1 Create Windows section in SEND-TO-STATA.md
- [x] 9.2 Add Windows-specific notes to README.md
- [x] 9.3 Document Stata Automation type library registration
- [x] 9.4 Document timing configuration
