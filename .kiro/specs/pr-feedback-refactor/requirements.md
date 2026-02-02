# Requirements Document

## Introduction

This specification addresses feedback received on a pull request to add the Stata extension to the Zed extensions repository. The feedback requests three main changes: renaming the extension ID from "sight" to "stata", using Zed's tasks API to improve feature discoverability, and reorganizing install scripts into a more visible structure with better documentation.

## Glossary

- **Extension**: A Zed plugin that provides language support, syntax highlighting, and LSP integration
- **Sight_LSP**: The language server protocol implementation for Stata (a separate project at github.com/jbearak/sight)
- **Tasks_API**: Zed's mechanism for extensions to provide runnable tasks via `languages/{language}/tasks.json`
- **Send_to_Stata**: Functionality that sends code from the editor to the Stata application for execution
- **Jupyter_Kernel**: A Jupyter kernel that enables REPL-style interaction with Stata
- **Install_Script**: Shell scripts (bash/PowerShell) that configure user keybindings and tasks for Send_to_Stata functionality

## Requirements

### Requirement 1: Rename Extension ID

**User Story:** As a Zed user, I want the extension to be named "stata" so that I can easily find and identify it as Stata language support.

#### Acceptance Criteria

1. THE Extension SHALL use "stata" as its `id` field in extension.toml
2. THE Extension SHALL use "Stata" as its `name` field in extension.toml
3. THE Extension SHALL retain "Sight" as the language server name since it references the separate Sight_LSP project
4. WHEN the extension is renamed THEN THE repository references SHALL be updated to reflect the new identity

### Requirement 2: Add Extension-Provided Tasks

**User Story:** As a Zed user, I want to discover Send_to_Stata features through Zed's task spawner so that I can learn about available functionality without reading documentation.

#### Acceptance Criteria

1. THE Extension SHALL provide a `languages/stata/tasks.json` file with Stata-related tasks
2. WHEN a user runs `task: spawn` in a .do file THEN THE System SHALL display available Stata tasks
3. WHEN the Send_to_Stata script is installed on macOS THEN THE tasks SHALL execute code sending operations
4. WHEN the Send_to_Stata script is not installed THEN THE tasks SHALL display a helpful error message with installation instructions
5. WHEN running on Windows THEN THE tasks SHALL display platform-appropriate installation instructions
6. THE tasks SHALL include operations for: send statement, send file, include statement, include file, CD to workspace, CD to file directory

### Requirement 3: Reorganize Scripts into Tools Directory

**User Story:** As a developer reviewing the extension, I want scripts organized in a clear folder structure so that I can understand what tools are available and their purposes.

#### Acceptance Criteria

1. THE Repository SHALL organize scripts into a `tools/` directory with subdirectories for each tool category
2. THE tools/send-to-stata/ directory SHALL contain the Send_to_Stata install scripts and main script
3. THE tools/jupyter-kernel/ directory SHALL contain the Jupyter_Kernel install scripts
4. THE tools/dev/ directory SHALL contain development environment setup scripts renamed from setup.sh/setup.ps1 to dev-setup.sh/dev-setup.ps1
5. WHEN scripts are moved THEN THE System SHALL update all references in documentation, GitHub Actions, and AGENTS.md

### Requirement 4: Improve Documentation Visibility

**User Story:** As a user considering the extension, I want clear documentation about what the install scripts do so that I can make informed decisions about running them.

#### Acceptance Criteria

1. THE README SHALL include a "What the Scripts Do" section explaining each installer's effects on the system
2. THE README SHALL document what files are created and where they are placed
3. THE tools/ subdirectories SHALL each contain a README.md with detailed documentation for that tool

### Requirement 5: Update All References

**User Story:** As a maintainer, I want all references updated consistently so that the codebase remains functional after the reorganization.

#### Acceptance Criteria

1. WHEN scripts are moved THEN THE curl/irm URLs in README SHALL be updated to new paths
2. WHEN scripts are moved THEN THE GitHub Actions workflows SHALL be updated to reference new paths
3. WHEN scripts are moved THEN THE AGENTS.md SHALL be updated with new paths and organization
4. WHEN the extension ID changes THEN THE repository description and any internal references SHALL be updated
5. THE update-checksum.sh and update-setup-checksums.ps1 scripts SHALL be renamed to clearly indicate their purpose and moved to tools/dev/ alongside the dev-setup scripts
6. THE checksum update scripts SHALL be documented in the tools/dev/ README explaining when and why to run them

### Requirement 6: Maintain Backward Compatibility for Existing Users

**User Story:** As an existing user with Send_to_Stata installed, I want the reorganization to not break my setup so that I can continue using the extension without reconfiguration.

#### Acceptance Criteria

1. WHEN a user has already installed Send_to_Stata THEN THE existing keybindings and tasks SHALL continue to work
2. THE Install_Scripts SHALL continue to install to the same user-facing locations (~/.local/bin, ~/.config/zed/)
3. IF a user re-runs the installer from new URLs THEN THE System SHALL update their configuration correctly
