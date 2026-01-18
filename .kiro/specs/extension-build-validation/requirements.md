# Requirements Document

## Introduction

This document defines the requirements for a test suite that validates the Sight Zed extension can build successfully with its specified LSP and tree-sitter grammar revisions. The test suite simulates how Zed would build and install the extension, ensuring all external dependencies are available and the extension compiles correctly.

## Glossary

- **Extension**: The Sight Zed extension, a Zed editor plugin providing Stata language support
- **LSP**: Language Server Protocol server (Sight) that provides language intelligence features
- **Grammar**: Tree-sitter grammar for Stata syntax parsing
- **WASM**: WebAssembly format used for Zed extensions
- **Validator**: The test suite component that performs validation checks
- **GitHub_Release**: A tagged release on GitHub containing downloadable binary assets
- **Revision**: A Git commit SHA identifying a specific version of the grammar repository

## Requirements

### Requirement 1: LSP Release Validation

**User Story:** As a developer, I want to verify that the specified LSP version exists as a GitHub release, so that I can ensure the extension will be able to download the language server.

#### Acceptance Criteria

1. WHEN the Validator checks the LSP version, THE Validator SHALL extract the SERVER_VERSION constant from `src/lib.rs`
2. WHEN the Validator queries GitHub releases, THE Validator SHALL verify a release with the extracted version tag exists at `jbearak/sight`
3. WHEN the release exists, THE Validator SHALL verify the following binary assets are present:
   - `sight-darwin-arm64`
   - `sight-linux-arm64`
   - `sight-linux-x64`
   - `sight-windows-x64.exe`
   - `sight-windows-arm64.exe`
4. IF the release does not exist, THEN THE Validator SHALL report an error indicating the missing release version
5. IF any expected binary asset is missing, THEN THE Validator SHALL report an error listing the missing assets

### Requirement 2: Grammar Revision Validation

**User Story:** As a developer, I want to verify that the specified grammar revision exists in the tree-sitter-stata repository, so that I can ensure Zed can fetch the grammar source.

#### Acceptance Criteria

1. WHEN the Validator checks the grammar revision, THE Validator SHALL extract the `rev` field from `extension.toml` under `[grammars.stata]`
2. WHEN the Validator queries the grammar repository, THE Validator SHALL verify the commit SHA exists at `jbearak/tree-sitter-stata`
3. IF the revision does not exist, THEN THE Validator SHALL report an error indicating the invalid commit SHA

### Requirement 3: Extension WASM Build Validation

**User Story:** As a developer, I want to verify that the extension builds successfully as WASM, so that I can ensure the extension is compatible with Zed's extension system.

#### Acceptance Criteria

1. WHEN the Validator builds the extension, THE Validator SHALL execute `cargo build --release --target wasm32-wasip1`
2. WHEN the build completes successfully, THE Validator SHALL verify the output WASM file exists
3. IF the build fails, THEN THE Validator SHALL report the build error output
4. WHEN the build succeeds, THE Validator SHALL report the WASM file size for informational purposes

### Requirement 4: Grammar Build Validation (Required)

**User Story:** As a developer, I want to verify that the grammar compiles successfully from the specified revision, so that I can prevent "failed to compile grammar" errors when installing the extension in Zed.

#### Acceptance Criteria

1. THE Validator SHALL clone the tree-sitter-stata repository at the specified revision to a temporary directory
2. THE Validator SHALL compile the grammar to WASM using `tree-sitter build --wasm`
3. IF the grammar build fails, THEN THE Validator SHALL report the build error with full output
4. WHEN the grammar build succeeds, THE Validator SHALL verify a valid `.wasm` file is produced
5. THE Validator SHALL clean up the temporary directory after validation

### Requirement 5: Test Suite Execution

**User Story:** As a developer, I want to run the validation suite as part of CI or locally, so that I can catch dependency issues before publishing the extension.

#### Acceptance Criteria

1. THE Validator SHALL provide a command-line interface for running validations
2. THE Validator SHALL support running individual validation checks or all checks together
3. WHEN all validations pass, THE Validator SHALL exit with code 0
4. WHEN any validation fails, THE Validator SHALL exit with a non-zero code
5. THE Validator SHALL output clear, human-readable results for each validation check

### Requirement 6: Configuration Parsing

**User Story:** As a developer, I want the test suite to automatically extract configuration from the extension files, so that I don't need to manually specify versions.

#### Acceptance Criteria

1. THE Validator SHALL parse `src/lib.rs` to extract the SERVER_VERSION constant value
2. THE Validator SHALL parse `extension.toml` to extract the grammar repository URL and revision
3. IF parsing fails due to malformed files, THEN THE Validator SHALL report a descriptive parsing error
4. THE Validator SHALL handle version strings with or without the "v" prefix consistently

### Requirement 7: Documentation

**User Story:** As a developer or AI agent, I want documentation in AGENTS.md explaining how to run the test suite, so that I can easily execute validations.

#### Acceptance Criteria

1. THE Validator documentation SHALL be added to the existing AGENTS.md file
2. THE documentation SHALL describe how to run the full validation suite
3. THE documentation SHALL describe how to run individual validation checks
4. THE documentation SHALL list any prerequisites or dependencies needed to run the tests
