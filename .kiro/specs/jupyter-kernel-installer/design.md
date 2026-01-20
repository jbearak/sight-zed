# Design Document: Jupyter Kernel Installer

## Overview

This design describes a self-contained bash installer script (`install-jupyter-stata.sh`) that sets up stata_kernel for Jupyter integration with Zed. The installer follows the same patterns established by `install-send-to-stata.sh`, supporting both local execution and curl-pipe installation.

The installer creates an isolated Python virtual environment, installs stata_kernel and jupyter, auto-detects the Stata installation, configures the kernel appropriately based on Stata edition, and registers it with Jupyter so Zed can discover and use it.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    install-jupyter-stata.sh                      │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Prerequisite │  │    Stata     │  │   Virtual Env        │  │
│  │   Checks     │──│  Detection   │──│   Management         │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│         │                 │                     │               │
│         ▼                 ▼                     ▼               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   Config     │  │   Kernel     │  │    Installation      │  │
│  │   Writer     │──│ Registration │──│     Summary          │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Installed Components                        │
├─────────────────────────────────────────────────────────────────┤
│  ~/.local/share/stata_kernel/venv/    (Python virtual env)      │
│  ~/.stata_kernel.conf                  (Kernel configuration)   │
│  ~/Library/Jupyter/kernels/stata/      (Kernel spec for Zed)    │
└─────────────────────────────────────────────────────────────────┘
```

### Execution Flow

1. **Prerequisite Validation**: Check macOS, python3, Stata installation
2. **Stata Detection**: Find Stata path and determine edition (MP/SE/IC/BE)
3. **Virtual Environment**: Create or reuse venv, install packages
4. **Configuration**: Write `~/.stata_kernel.conf` with detected settings
5. **Kernel Registration**: Run `stata_kernel.install` to register with Jupyter
6. **Summary**: Display success message with usage instructions

## Components and Interfaces

### Main Script Structure

```bash
#!/bin/bash
# install-jupyter-stata.sh - Install stata_kernel for Zed Jupyter integration

set -euo pipefail

# ============================================================================
# Configuration Constants
# ============================================================================
VENV_DIR="$HOME/.local/share/stata_kernel/venv"
CONFIG_FILE="$HOME/.stata_kernel.conf"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/jbearak/sight-zed"
GITHUB_REF="${SIGHT_GITHUB_REF:-main}"

# ============================================================================
# Output Helpers
# ============================================================================
# print_error(), print_success(), print_warning(), print_info()

# ============================================================================
# Prerequisite Checks
# ============================================================================
# check_macos(), check_python3(), check_prerequisites()

# ============================================================================
# Stata Detection
# ============================================================================
# detect_stata_app() -> sets STATA_PATH, STATA_EDITION, EXECUTION_MODE

# ============================================================================
# Virtual Environment Management
# ============================================================================
# create_venv(), install_packages()

# ============================================================================
# Configuration Management
# ============================================================================
# write_config(), update_config_setting()

# ============================================================================
# Kernel Registration
# ============================================================================
# register_kernel(), verify_kernel_spec()

# ============================================================================
# Uninstallation
# ============================================================================
# uninstall()

# ============================================================================
# Main
# ============================================================================
# main()
```

### Component: Prerequisite Checks

```bash
PYTHON_CMD=""  # Set by check_python3()

check_macos() {
  # Verify running on macOS (required for Stata path conventions)
  # Exit with error if not Darwin
}

check_python3() {
  # Verify python3 is available
  # Check that python3 can create venv (venv module available)
  # Exit with helpful error if missing
  
  # Set PYTHON_CMD to "python3"
  # Detect Python version (major.minor)
  # If Python 3.12+, warn about compatibility (handled automatically)
}

check_prerequisites() {
  check_macos
  check_python3
}
```

### Component: Stata Detection

```bash
detect_stata_app() {
  # Priority:
  # 1. STATA_PATH environment variable (if set)
  # 2. Auto-detect from /Applications/Stata/
  
  # Auto-detection order: StataMP, StataSE, StataIC, StataBE, Stata
  # For each, check /Applications/Stata/{App}.app/Contents/MacOS/{app}
  
  # Determine edition from app name:
  # - StataMP -> MP
  # - StataSE -> SE  
  # - StataIC -> IC
  # - StataBE -> BE
  # - Stata -> IC (default assumption)
  
  # Determine execution mode:
  # - MP, SE: console (supports multiple sessions, faster)
  # - IC, BE: automation (no console version on macOS)
  
  # Allow STATA_EXECUTION_MODE override
  
  # Sets global variables:
  # - STATA_PATH: full path to executable
  # - STATA_EDITION: MP, SE, IC, or BE
  # - EXECUTION_MODE: console or automation
}
```

### Component: Virtual Environment Management

```bash
create_venv() {
  # Create venv directory parent if needed
  # If venv already exists and is valid, reuse it
  # Otherwise create new venv with: $PYTHON_CMD -m venv "$VENV_DIR"
  # Return success/failure
}

install_packages() {
  # Activate venv
  # pip install --upgrade pip
  # pip install --upgrade stata_kernel jupyter
  # Verify installation succeeded
  
  # Python 3.12+ compatibility fix:
  # stata_kernel pins ipykernel <5.0.0, which uses the deprecated 'imp' module
  # removed in Python 3.12. Detect venv Python version and upgrade ipykernel
  # if running Python 3.12+ to fix the compatibility issue.
}
```

### Component: Configuration Management

```bash
write_config() {
  # If file doesn't exist, create with full documentation template:
  # - Header comment with documentation link
  # - [stata_kernel] section
  # - stata_path and execution_mode uncommented with detected values
  # - All other settings commented out with descriptions and possible values
  
  # If file exists, update only stata_path and execution_mode
  # Preserve all other settings (commented or uncommented) and user comments
  # Use update_config_setting() for each setting
}

update_config_setting() {
  local key="$1"
  local value="$2"
  local config_file="$3"
  
  # If key exists (commented or uncommented), update its value
  # If key doesn't exist, add it under [stata_kernel] section
  # Preserve other settings and comments
}

get_config_template() {
  # Returns the full config file template with:
  # - Documentation header
  # - All settings documented with comments
  # - Only stata_path and execution_mode uncommented
  # Template includes: stata_path, execution_mode, cache_directory,
  # graph_format, graph_scale, graph_width, graph_height,
  # autocomplete_closing_symbol, user_graph_keywords
}
```

### Component: Kernel Registration

```bash
register_kernel() {
  # Run: $VENV_DIR/bin/python -m stata_kernel.install
  # This creates kernel spec at ~/Library/Jupyter/kernels/stata/
  # Verify kernel.json has language: stata (lowercase)
}

verify_kernel_spec() {
  local kernel_dir="$HOME/Library/Jupyter/kernels/stata"
  
  # Check kernel.json exists
  # Verify language field is "stata" (lowercase)
  # Return success/failure
}
```

### Component: Uninstallation

```bash
uninstall() {
  # Remove virtual environment directory
  # Remove kernel spec: jupyter kernelspec uninstall stata
  # Optionally remove config file (with --remove-config flag)
  # Display what was removed
}
```

## Data Models

### Configuration File Format (~/.stata_kernel.conf)

```ini
# stata_kernel configuration file
# Documentation: https://kylebarron.dev/stata_kernel/using_stata_kernel/configuration/

[stata_kernel]

# stata_path: Full path to your Stata executable
# This is auto-detected during installation but can be changed manually
# Example: /Applications/Stata/StataMP.app/Contents/MacOS/stata-mp
stata_path = /Applications/Stata/StataMP.app/Contents/MacOS/stata-mp

# execution_mode: How stata_kernel communicates with Stata (macOS only)
# Values: console, automation
# - console: Uses console version of Stata (faster, supports multiple sessions)
#            Only available for Stata MP and SE on macOS
# - automation: Uses Stata Automation (required for Stata IC and BE on macOS)
execution_mode = console

# cache_directory: Directory for temporary log files and graphs
# Default: ~/.stata_kernel_cache
# cache_directory = ~/.stata_kernel_cache

# graph_format: Format for exported graphs
# Values: svg, png, eps
# Default: svg (png on Windows with Stata 14 and below)
# graph_format = svg

# graph_scale: Scale factor for graph dimensions
# Default: 1.0
# graph_scale = 1.0

# graph_width: Width of graphs in pixels
# Default: 600
# graph_width = 600

# graph_height: Height of graphs in pixels (optional, Stata determines optimal if not set)
# graph_height = 400

# autocomplete_closing_symbol: Include closing symbol in autocompletions
# Values: True, False
# Default: False
# autocomplete_closing_symbol = False

# user_graph_keywords: Additional commands that generate graphs (comma-separated)
# Example: coefplot,bindline,binscatter
# user_graph_keywords =
```

The configuration file uses INI format with a `[stata_kernel]` section header. The installer creates this file with documentation comments for all available settings, with only the essential settings uncommented.

Key settings:

| Setting | Type | Description |
|---------|------|-------------|
| `stata_path` | string | Full path to Stata executable |
| `execution_mode` | string | Either `console` or `automation` |
| `cache_directory` | string | Directory for temp files (optional) |
| `graph_format` | string | svg, png, or eps (optional) |
| `graph_scale` | float | Scale factor for graphs (optional) |
| `graph_width` | int | Graph width in pixels (optional) |
| `graph_height` | int | Graph height in pixels (optional) |
| `autocomplete_closing_symbol` | bool | Include closing symbols (optional) |
| `user_graph_keywords` | string | Additional graph commands (optional) |

### Kernel Spec Format (kernel.json)

```json
{
  "argv": [
    "/Users/username/.local/share/stata_kernel/venv/bin/python",
    "-m",
    "stata_kernel",
    "-f",
    "{connection_file}"
  ],
  "display_name": "Stata",
  "language": "stata",
  "interrupt_mode": "message"
}
```

Critical: The `language` field must be `stata` (lowercase) for Zed to match it with `.do` files.

### Stata Edition to Execution Mode Mapping

| Edition | Executable Name | Execution Mode | Reason |
|---------|-----------------|----------------|--------|
| MP | stata-mp | console | Has console version |
| SE | stata-se | console | Has console version |
| IC | stata-ic | automation | No console on macOS |
| BE | stata-be | automation | No console on macOS |

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `STATA_PATH` | (auto-detect) | Override Stata executable path |
| `STATA_EXECUTION_MODE` | (auto-detect) | Override execution mode |
| `SIGHT_GITHUB_REF` | `main` | GitHub ref for curl-pipe install |

### Python Version Compatibility

stata_kernel pins `ipykernel <5.0.0`, which uses the deprecated `imp` module that was removed in Python 3.12. This causes the kernel to fail silently on startup with Python 3.12+.

The installer handles this automatically:
1. Detects the Python version during prerequisite checks
2. Warns users about Python 3.12+ compatibility
3. After installing stata_kernel, upgrades ipykernel to a compatible version

This ensures the kernel works regardless of which Python version the user has installed.



## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Installation Creates All Required Components

*For any* successful installation run, the following components SHALL exist:
- Virtual environment at `~/.local/share/stata_kernel/venv` with `bin/python` and `bin/pip`
- Configuration file at `~/.stata_kernel.conf` with `[stata_kernel]` section
- Kernel spec directory at `~/Library/Jupyter/kernels/stata/` with `kernel.json`

**Validates: Requirements 1.1, 4.1, 5.2**

### Property 2: Installation Is Idempotent

*For any* system state, running the installer twice SHALL produce the same end state as running it once. Specifically:
- Existing virtual environment is reused (marker files preserved)
- Configuration file is updated, not recreated
- Kernel registration succeeds without error
- Exit code is 0 for both runs

**Validates: Requirements 1.2, 5.5, 8.1, 8.2, 8.3**

### Property 3: Configuration Files Contain Correct Settings

*For any* successful installation with detected Stata at path P and edition E:
- `~/.stata_kernel.conf` SHALL contain `stata_path = P`
- `~/.stata_kernel.conf` SHALL contain `execution_mode = M` where M is derived from E
- `kernel.json` SHALL contain `"language": "stata"` (lowercase)

**Validates: Requirements 4.2, 4.3, 5.3**

### Property 4: Edition Determines Execution Mode

*For any* detected Stata edition:
- If edition is MP or SE, execution_mode SHALL be `console`
- If edition is IC or BE, execution_mode SHALL be `automation`

This mapping is deterministic and based on whether the edition ships with a console version on macOS.

**Validates: Requirements 2.5, 3.1, 3.2, 3.3**

### Property 5: Environment Variables Override Auto-Detection

*For any* installation where environment variables are set:
- If `STATA_PATH` is set, that path SHALL be used regardless of auto-detection results
- If `STATA_EXECUTION_MODE` is set, that mode SHALL be used regardless of edition

**Validates: Requirements 2.3, 3.4**

### Property 6: Config File Preserves User Customizations

*For any* existing `~/.stata_kernel.conf` with custom settings (e.g., `graph_format`, `cache_directory`), running the installer SHALL:
- Update `stata_path` and `execution_mode` to current values
- Preserve all other settings unchanged

**Validates: Requirements 4.4**

### Property 7: Uninstall Removes Installed Components

*For any* system with installed components, running with `--uninstall` SHALL:
- Remove `~/.local/share/stata_kernel/venv` directory
- Remove `~/Library/Jupyter/kernels/stata/` directory
- With `--remove-config`: remove `~/.stata_kernel.conf`
- Without `--remove-config`: preserve `~/.stata_kernel.conf`

**Validates: Requirements 9.1, 9.2, 9.3**

### Property 8: Prerequisites Checked Before System Changes

*For any* installation attempt where prerequisites fail (no python3, no Stata, not macOS):
- No files SHALL be created or modified
- Exit code SHALL be non-zero
- Error message SHALL be displayed

**Validates: Requirements 7.5**

### Property 9: Curl-Pipe Installation Parity

*For any* installation, running via curl-pipe SHALL produce identical results to running locally:
- Same files created in same locations
- Same configuration values written
- Same kernel registration

**Validates: Requirements 6.2**

## Error Handling

### Prerequisite Failures

| Condition | Error Message | Exit Code |
|-----------|---------------|-----------|
| Not macOS | "This script requires macOS" | 1 |
| No python3 | "python3 is required but not installed" + install instructions | 1 |
| No Stata found | "No Stata installation found" + instructions | 1 |
| python3 venv module missing | "python3 venv module is required" + install instructions | 1 |

### Installation Failures

| Condition | Error Message | Exit Code |
|-----------|---------------|-----------|
| Cannot create venv directory | "Failed to create virtual environment" | 2 |
| pip install fails | "Failed to install packages" | 2 |
| Kernel registration fails | "Failed to register kernel" | 3 |
| Config file write fails | "Failed to write configuration" | 2 |

### Recovery Behavior

- If installation fails partway through, partial state may remain
- Re-running the installer should recover from partial state
- `--uninstall` can be used to clean up before retrying

## Testing Strategy

### Unit Tests

Unit tests verify specific functions in isolation:

1. **Stata Detection Tests**
   - Test detection priority order with mock directories
   - Test STATA_PATH override
   - Test edition extraction from app names
   - Test execution mode mapping

2. **Config File Tests**
   - Test INI file parsing and writing
   - Test setting updates preserve other settings
   - Test handling of missing/malformed config files

3. **Path Construction Tests**
   - Test executable path construction for each edition
   - Test kernel spec path construction

### Property-Based Tests

Property-based tests verify universal properties across generated inputs:

- Minimum 100 iterations per property test
- Tag format: **Feature: jupyter-kernel-installer, Property {number}: {property_text}**

1. **Property 4 Test: Edition to Mode Mapping**
   - Generate random edition values from {MP, SE, IC, BE}
   - Verify mapping function returns correct mode
   - Edge case: unknown edition defaults to automation

2. **Property 6 Test: Config Preservation**
   - Generate random INI files with various settings
   - Apply update function
   - Verify non-updated settings preserved exactly

### Integration Tests

Integration tests verify end-to-end behavior:

1. **Fresh Installation Test**
   - Start with clean state (no venv, no config, no kernel)
   - Run installer
   - Verify all components created correctly

2. **Idempotency Test**
   - Run installer twice
   - Verify second run succeeds
   - Verify state unchanged after second run

3. **Uninstall Test**
   - Install, then uninstall
   - Verify components removed
   - Verify config preserved (without --remove-config)

4. **Curl-Pipe Test**
   - Run via curl-pipe
   - Compare results to local installation

### Test Environment

- Tests should use temporary directories to avoid affecting real installations
- Mock Stata detection by creating fake app directories
- Use environment variables to control paths during testing

## Documentation

### README.md Updates

#### New Section: "Jupyter REPL (Optional)"

Add after the "Send to Stata" section:

```markdown
## Jupyter REPL (Optional)

The Sight extension supports Zed's built-in Jupyter integration through [stata_kernel](https://kylebarron.dev/stata_kernel/). This lets you execute Stata code directly in Zed's REPL panel without switching to the Stata application.

### Why Use the Jupyter Kernel?

- **Interactive REPL**: Execute code snippets and see results inline
- **No context switching**: Stay in Zed while running Stata commands
- **Output capture**: View command output, tables, and graphs in Zed

### Quick Install

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jbearak/sight-zed/main/install-jupyter-stata.sh)"
```

### Configuration

The installer creates `~/.stata_kernel.conf` with your Stata settings. The file includes documentation for all available options. Key settings:

- `stata_path`: Path to your Stata executable (auto-detected)
- `execution_mode`: `console` (MP/SE) or `automation` (IC/BE)

For all configuration options, see the [stata_kernel documentation](https://kylebarron.dev/stata_kernel/using_stata_kernel/configuration/).

### Usage in Zed

1. Open a `.do` file
2. Select "stata" as the kernel
3. Click the 🔄 icon in the editor toolbar to execute code
   or use Control+Shift+Enter keyboard shortcut
4. Execute code with the REPL keybindings

### Uninstall

```bash
./install-jupyter-stata.sh --uninstall
```
```

#### Update "Building from Source" Section

Add a "Jupyter Kernel" subsection alongside the existing source install instructions:

```markdown
### Jupyter Kernel

Install from a local clone:

```bash
git clone https://github.com/jbearak/sight-zed
cd sight-zed
./install-jupyter-stata.sh
```
```

### Documentation Placement

The README.md structure should be:
1. Overview / Features
2. Installation (Zed extension)
3. Send to Stata (Optional) - curl install here
4. **Jupyter REPL (Optional)** - curl install here ← New section
5. Building from Source
   - Zed Extension
   - Send-to-Stata - git clone install here
   - **Jupyter Kernel** - git clone install here ← New subsection
6. License
