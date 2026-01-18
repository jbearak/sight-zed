# Requirements Document

## Introduction

This feature adds support for installing send-to-stata via curl-pipe-to-bash, enabling Homebrew-style installation directly from GitHub without requiring a local clone. The installer will detect its execution context and fetch required files from GitHub when running in a piped context.

## Glossary

- **Installer**: The `install-send-to-stata.sh` script that installs send-to-stata components
- **Script_File**: The `send-to-stata.sh` file that performs the actual Stata communication
- **Local_Clone**: Running the installer from a cloned git repository where files exist on disk
- **Curl_Pipe**: Running the installer via `/bin/bash -c "$(curl ...)"`  where no local files exist
- **GitHub_Raw_URL**: The raw.githubusercontent.com URL for fetching files directly from GitHub

## Requirements

### Requirement 1: Execution Context Detection

**User Story:** As a user, I want the installer to automatically detect how it's being run, so that it can choose the appropriate method to obtain required files.

#### Acceptance Criteria

1. WHEN the Installer is executed from a Local_Clone, THE Installer SHALL detect that `send-to-stata.sh` exists in the same directory
2. WHEN the Installer is executed via Curl_Pipe, THE Installer SHALL detect that no local `send-to-stata.sh` file exists
3. THE Installer SHALL use the presence or absence of the local Script_File as the detection mechanism

### Requirement 2: Local File Installation

**User Story:** As a user running from a local clone, I want the installer to copy the local file, so that I get the version matching my clone.

#### Acceptance Criteria

1. WHEN the local Script_File exists, THE Installer SHALL copy it from the local directory to the installation location
2. WHEN copying from local, THE Installer SHALL preserve the current behavior exactly

### Requirement 3: Remote File Fetching

**User Story:** As a user installing via curl-pipe, I want the installer to fetch the script from GitHub, so that I can install without cloning the repository.

#### Acceptance Criteria

1. WHEN the local Script_File does not exist, THE Installer SHALL fetch `send-to-stata.sh` from the GitHub_Raw_URL
2. THE Installer SHALL construct the URL from base `https://raw.githubusercontent.com/jbearak/sight` and a configurable ref (default: `main`)
3. WHEN fetching from GitHub, THE Installer SHALL verify the download succeeded before proceeding
4. IF the download fails, THEN THE Installer SHALL display an error message including the attempted URL and exit with non-zero status
5. WHERE the `SIGHT_GITHUB_REF` environment variable is set, THE Installer SHALL use that value instead of `main` for the GitHub ref

### Requirement 4: Curl-Pipe Installation Command

**User Story:** As a user, I want to install with a single curl command, so that I can quickly set up send-to-stata without cloning.

#### Acceptance Criteria

1. THE Installer SHALL support execution via `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jbearak/sight/main/install-send-to-stata.sh)"`
2. WHEN executed via Curl_Pipe, THE Installer SHALL complete all installation steps identically to Local_Clone installation

### Requirement 5: Installation Parity

**User Story:** As a user, I want both installation methods to produce identical results, so that I have the same experience regardless of how I install.

#### Acceptance Criteria

1. WHEN installation completes via either method, THE Installer SHALL install the same Script_File to `~/.local/bin/`
2. WHEN installation completes via either method, THE Installer SHALL configure the same Zed tasks
3. WHEN installation completes via either method, THE Installer SHALL configure the same keybindings
4. THE Installer SHALL display the same success messages and summary for both methods
