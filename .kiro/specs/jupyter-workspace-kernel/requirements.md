# Requirements Document

## Introduction

This feature extends the Jupyter Stata kernel installer to provide a "Stata (Workspace)" kernel variant that automatically changes to the workspace root directory before starting Stata. This solves the problem where Zed's REPL starts kernels in the file's directory rather than the workspace root, which breaks relative paths in Stata code that expect to run from the project root.

## Glossary

- **Workspace_Kernel**: The "Stata (Workspace)" Jupyter kernel that changes to workspace root before starting
- **Standard_Kernel**: The original "Stata" kernel that starts in the file's directory
- **Workspace_Root**: The project root directory, identified by marker files (.git, .stata-project, .project)
- **Marker_File**: A file or directory that indicates the workspace root (.git, .stata-project, .project)
- **Wrapper_Script**: The Python script that finds workspace root and delegates to stata_kernel
- **Kernel_Spec**: The Jupyter kernel specification directory containing kernel.json

## Requirements

### Requirement 1: Workspace Root Detection

**User Story:** As a user, I want the kernel to automatically find my project root, so that relative paths in my Stata code work correctly.

#### Acceptance Criteria

1. THE Wrapper_Script SHALL walk up from the current directory looking for Marker_Files
2. THE Wrapper_Script SHALL check for `.git`, `.stata-project`, and `.project` markers in that order
3. WHEN a Marker_File is found, THE Wrapper_Script SHALL use that directory as the Workspace_Root
4. IF no Marker_File is found, THEN THE Wrapper_Script SHALL use the original directory (file's directory)
5. THE Wrapper_Script SHALL NOT search above the user's home directory

### Requirement 2: Dual Kernel Installation

**User Story:** As a user, I want both kernel variants available, so that I can choose the appropriate behavior per session.

#### Acceptance Criteria

1. THE Installer SHALL create two kernel specs: "Stata" and "Stata (Workspace)"
2. THE Standard_Kernel SHALL start in the file's directory (original behavior)
3. THE Workspace_Kernel SHALL start in the Workspace_Root
4. WHEN uninstalling, THE Installer SHALL remove both kernel specs

### Requirement 3: Kernel Selection

**User Story:** As a user, I want to easily switch between kernels, so that I can use the appropriate one for different workflows.

#### Acceptance Criteria

1. THE Installer SHALL display both kernel options in the installation summary
2. THE Installer SHALL explain the difference between the two kernels
3. THE Installer SHALL provide instructions for setting a default kernel in Zed settings

### Requirement 4: Documentation Updates

**User Story:** As a developer, I want the documentation updated, so that users understand the two kernel options.

#### Acceptance Criteria

1. THE AGENTS.md SHALL document the two kernel variants and their behavior
2. THE README.md SHALL explain the kernel selection options
3. THE Installer summary message SHALL adequately explain both kernels
