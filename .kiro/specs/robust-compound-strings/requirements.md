# Requirements Document

## Introduction

This feature addresses the problem of passing Stata code containing shell metacharacters (backticks, quotes) from Zed editor to Stata via the `send-to-stata.sh` script. The current implementation passes selected text via command-line argument (`--text`), which breaks when the text contains Stata compound strings (e.g., `` `"1234"' ``) because backticks trigger shell command substitution and nested quotes break the quoting structure.

The solution must provide a robust mechanism to transfer arbitrary Stata code from Zed to the script without shell interpretation issues.

## Glossary

- **Send_To_Stata_Script**: The `send-to-stata.sh` bash script that sends Stata code to the Stata GUI application
- **Zed_Task**: A task definition in Zed's `tasks.json` that invokes the Send_To_Stata_Script
- **Compound_String**: A Stata string literal using backtick-quote delimiters (e.g., `` `"text"' ``)
- **Shell_Metacharacter**: Characters with special meaning in shell (backticks, quotes, dollar signs, etc.)
- **Stdin_Mode**: A mode where the script reads text input from standard input instead of command-line arguments
- **Temp_File**: A temporary file created in `$TMPDIR` to hold Stata code for execution

## Requirements

### Requirement 1: Stdin Input Mode

**User Story:** As a Zed user, I want to send Stata code containing compound strings to Stata, so that I can execute any valid Stata code without shell interpretation errors.

#### Acceptance Criteria

1. WHEN the Send_To_Stata_Script receives the `--stdin` flag THEN the Send_To_Stata_Script SHALL read text content from standard input instead of the `--text` argument
2. WHEN using stdin mode THEN the Send_To_Stata_Script SHALL accept arbitrary byte sequences including all Shell_Metacharacters without interpretation
3. WHEN stdin mode is used with `--statement` mode THEN the Send_To_Stata_Script SHALL use the stdin content as the statement to send
4. WHEN stdin is empty in stdin mode THEN the Send_To_Stata_Script SHALL fall back to using `--row` for statement detection
5. IF both `--stdin` and `--text` are provided THEN the Send_To_Stata_Script SHALL return an error indicating the options are mutually exclusive

### Requirement 2: Backward Compatibility

**User Story:** As an existing user, I want my current workflow to continue working, so that I don't have to reconfigure anything unless I need the new functionality.

#### Acceptance Criteria

1. WHEN the `--text` argument is provided without `--stdin` THEN the Send_To_Stata_Script SHALL behave identically to the current implementation
2. WHEN neither `--stdin` nor `--text` is provided THEN the Send_To_Stata_Script SHALL use `--row` for statement detection as before
3. THE Send_To_Stata_Script SHALL maintain all existing exit codes and error messages for current functionality

### Requirement 3: Zed Task Integration

**User Story:** As a Zed user, I want the keybinding to automatically use the robust method for selected text, so that compound strings work without manual intervention.

#### Acceptance Criteria

1. WHEN the Zed_Task for "Send Statement" is invoked with selected text THEN the Zed_Task SHALL pipe the selected text to the Send_To_Stata_Script via stdin
2. WHEN the Zed_Task for "Send Statement" is invoked without selected text THEN the Zed_Task SHALL use the `--row` argument for statement detection
3. THE installer SHALL update the Zed_Task definition to use the stdin-based approach

### Requirement 4: Content Preservation

**User Story:** As a Stata developer, I want my code to be sent exactly as written, so that macros, compound strings, and special characters execute correctly in Stata.

#### Acceptance Criteria

1. WHEN text is read from stdin THEN the Send_To_Stata_Script SHALL preserve all characters exactly as received
2. WHEN text containing Compound_Strings is sent THEN the Temp_File SHALL contain the exact same byte sequence
3. WHEN text containing newlines is sent via stdin THEN the Send_To_Stata_Script SHALL preserve all newlines in the output

### Requirement 5: Error Handling

**User Story:** As a user, I want clear error messages when something goes wrong, so that I can diagnose and fix issues.

#### Acceptance Criteria

1. IF stdin read fails THEN the Send_To_Stata_Script SHALL exit with a distinct error code and descriptive message
2. IF the stdin content exceeds a reasonable size limit THEN the Send_To_Stata_Script SHALL handle it gracefully
3. WHEN an error occurs during stdin processing THEN the Send_To_Stata_Script SHALL clean up any partial Temp_Files created

