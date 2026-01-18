# Requirements Document

## Introduction

This feature adds a self-contained installer script for setting up stata_kernel with Jupyter, enabling Stata REPL support in Zed's built-in Jupyter integration. The installer creates a dedicated Python virtual environment, installs stata_kernel, auto-detects the Stata installation, configures the kernel appropriately, and registers it with Jupyter so Zed can discover and use it.

## Glossary

- **Installer**: The `install-jupyter-stata.sh` script that sets up stata_kernel
- **stata_kernel**: A Jupyter kernel that enables Stata code execution in Jupyter environments
- **Virtual_Environment**: An isolated Python environment at `~/.local/share/stata_kernel/venv`
- **Kernel_Spec**: The Jupyter kernel specification directory containing `kernel.json`
- **Kernel_Config**: The `~/.stata_kernel.conf` configuration file for stata_kernel settings
- **Stata_Edition**: The Stata variant (MP, SE, IC, BE) which determines execution mode
- **Execution_Mode**: Either `console` (for SE/MP) or `automation` (for IC/BE)
- **Curl_Pipe**: Running the installer via `/bin/bash -c "$(curl ...)"`

## Requirements

### Requirement 1: Virtual Environment Management

**User Story:** As a user, I want stata_kernel installed in an isolated environment, so that it doesn't conflict with my other Python installations.

#### Acceptance Criteria

1. THE Installer SHALL create a Python virtual environment at `~/.local/share/stata_kernel/venv`
2. WHEN the virtual environment already exists, THE Installer SHALL reuse it without recreating
3. THE Installer SHALL install `stata_kernel` and `jupyter` packages into the Virtual_Environment
4. THE Installer SHALL use `pip install --upgrade` to ensure latest versions are installed
5. IF virtual environment creation fails, THEN THE Installer SHALL display an error and exit with non-zero status

### Requirement 2: Stata Installation Detection

**User Story:** As a user, I want the installer to automatically find my Stata installation, so that I don't have to manually configure paths.

#### Acceptance Criteria

1. THE Installer SHALL search for Stata in `/Applications/Stata/` checking for StataMP, StataSE, StataIC, StataBE, and Stata in that order
2. WHEN a Stata installation is found, THE Installer SHALL extract the full path to the executable
3. WHERE the `STATA_PATH` environment variable is set, THE Installer SHALL use that value instead of auto-detection
4. IF no Stata installation is found and `STATA_PATH` is not set, THEN THE Installer SHALL display an error with instructions and exit with non-zero status
5. THE Installer SHALL determine the Stata_Edition from the detected application name

### Requirement 3: Execution Mode Configuration

**User Story:** As a user, I want the correct execution mode configured automatically, so that stata_kernel works optimally with my Stata edition.

#### Acceptance Criteria

1. WHEN Stata_Edition is MP or SE, THE Installer SHALL configure Execution_Mode as `console`
2. WHEN Stata_Edition is IC or BE, THE Installer SHALL configure Execution_Mode as `automation`
3. THE Installer SHALL write the Execution_Mode to the Kernel_Config file
4. WHERE the `STATA_EXECUTION_MODE` environment variable is set, THE Installer SHALL use that value instead of auto-detection

### Requirement 4: Kernel Configuration File

**User Story:** As a user, I want stata_kernel properly configured, so that it can communicate with my Stata installation.

#### Acceptance Criteria

1. THE Installer SHALL create or update `~/.stata_kernel.conf` with the detected settings
2. THE Kernel_Config SHALL contain the `stata_path` setting pointing to the Stata executable
3. THE Kernel_Config SHALL contain the `execution_mode` setting
4. WHEN the Kernel_Config already exists, THE Installer SHALL update only the relevant settings while preserving other user customizations
5. THE Installer SHALL set appropriate file permissions on the Kernel_Config

### Requirement 5: Jupyter Kernel Registration

**User Story:** As a user, I want the kernel registered with Jupyter, so that Zed can discover and use it.

#### Acceptance Criteria

1. THE Installer SHALL run `python -m stata_kernel.install` from the Virtual_Environment to register the kernel
2. THE Installer SHALL verify the kernel was registered by checking for the kernel spec directory
3. THE Kernel_Spec SHALL have `language` set to `stata` (lowercase) for Zed language matching
4. IF kernel registration fails, THEN THE Installer SHALL display an error and exit with non-zero status
5. WHEN the kernel is already registered, THE Installer SHALL update the registration

### Requirement 6: Curl-Pipe Installation Support

**User Story:** As a user, I want to install via a single curl command, so that I can quickly set up Jupyter Stata support.

#### Acceptance Criteria

1. THE Installer SHALL support execution via `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jbearak/sight-zed/main/install-jupyter-stata.sh)"`
2. WHEN executed via Curl_Pipe, THE Installer SHALL complete all installation steps identically to local execution
3. THE Installer SHALL handle the curl-pipe context where `BASH_SOURCE` may be empty

### Requirement 7: Prerequisite Validation

**User Story:** As a user, I want clear feedback if prerequisites are missing, so that I know what to install first.

#### Acceptance Criteria

1. THE Installer SHALL verify macOS is the operating system
2. THE Installer SHALL verify `python3` is available
3. THE Installer SHALL verify Stata is installed (or `STATA_PATH` is set)
4. IF any prerequisite is missing, THEN THE Installer SHALL display a helpful error message with installation instructions
5. THE Installer SHALL check prerequisites before making any changes to the system

### Requirement 8: Idempotent Installation

**User Story:** As a user, I want to safely re-run the installer, so that I can update or fix my installation without issues.

#### Acceptance Criteria

1. WHEN the Installer is run multiple times, THE Installer SHALL produce the same end state
2. THE Installer SHALL not fail if components already exist
3. THE Installer SHALL update existing components to the latest configuration
4. THE Installer SHALL display appropriate messages indicating what was updated vs created

### Requirement 9: Uninstallation Support

**User Story:** As a user, I want to cleanly remove the installation, so that I can free up space or troubleshoot issues.

#### Acceptance Criteria

1. WHEN the `--uninstall` flag is provided, THE Installer SHALL remove the Virtual_Environment directory
2. WHEN uninstalling, THE Installer SHALL remove the Kernel_Spec from Jupyter
3. WHEN uninstalling, THE Installer SHALL optionally remove the Kernel_Config (with user confirmation or flag)
4. THE Installer SHALL display what was removed during uninstallation
5. IF components don't exist during uninstall, THEN THE Installer SHALL skip them gracefully

### Requirement 10: Installation Feedback

**User Story:** As a user, I want clear feedback during installation, so that I know what's happening and if it succeeded.

#### Acceptance Criteria

1. THE Installer SHALL display progress messages for each major step
2. THE Installer SHALL use colored output for success (green), warnings (yellow), and errors (red)
3. WHEN installation completes successfully, THE Installer SHALL display a summary with usage instructions
4. THE Installer SHALL display the detected Stata edition and configured execution mode
5. THE Installer SHALL display instructions for using the kernel in Zed

### Requirement 11: Documentation

**User Story:** As a user, I want clear documentation about the Jupyter kernel, so that I understand what it does and how to use it.

#### Acceptance Criteria

1. THE README.md SHALL include a "Jupyter REPL (Optional)" section explaining what the stata_kernel integration provides
2. THE README.md SHALL explain why a user might want to install the Jupyter kernel (REPL support in Zed)
3. THE README.md SHALL include the curl-pipe installation command in the "Jupyter REPL (Optional)" section
4. THE README.md SHALL include the git clone installation command in the "Building from Source" section under a "Jupyter Kernel" subsection
5. THE README.md SHALL document where the configuration file is located (`~/.stata_kernel.conf`)
6. THE README.md SHALL explain that settings can be customized by editing the config file
7. THE README.md SHALL include a URL to the stata_kernel documentation (https://kylebarron.dev/stata_kernel/)

