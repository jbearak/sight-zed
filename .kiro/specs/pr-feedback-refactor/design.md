# Design Document: PR Feedback Refactor

## Overview

This design addresses PR feedback for the Zed Stata extension by:
1. Renaming the extension ID from "sight" to "stata"
2. Adding extension-provided tasks via `languages/stata/tasks.json`
3. Reorganizing scripts into a `tools/` directory structure
4. Improving documentation visibility

The changes maintain backward compatibility for existing users while improving discoverability and organization for new users and reviewers.

## Architecture

### Current State

```
sight-zed/
├── extension.toml              # id="sight", name="Sight - Stata Language Server"
├── install-send-to-stata.sh    # macOS installer (root level)
├── install-send-to-stata.ps1   # Windows installer (root level)
├── install-jupyter-stata.sh    # macOS Jupyter installer
├── install-jupyter-stata.ps1   # Windows Jupyter installer
├── setup.sh                    # Dev environment setup (macOS)
├── setup.ps1                   # Dev environment setup (Windows)
├── update-checksum.sh          # Updates send-to-stata checksum
├── update-setup-checksums.ps1  # Updates setup.ps1 checksums
├── send-to-stata.sh            # Main send-to-stata script
├── languages/stata/
│   ├── config.toml
│   ├── highlights.scm
│   └── ...                     # No tasks.json
└── ...
```

### Target State

```
sight-zed/
├── extension.toml              # id="stata", name="Stata"
├── languages/stata/
│   ├── config.toml
│   ├── highlights.scm
│   ├── tasks.json              # NEW: Extension-provided tasks
│   └── ...
├── tools/
│   ├── send-to-stata/
│   │   ├── README.md           # Moved from SEND-TO-STATA.md
│   │   ├── install-macos.sh    # Renamed from install-send-to-stata.sh
│   │   ├── install-windows.ps1 # Renamed from install-send-to-stata.ps1
│   │   └── send-to-stata.sh    # Moved from root
│   ├── jupyter-kernel/
│   │   ├── README.md           # NEW: Jupyter-specific docs
│   │   ├── install-macos.sh    # Renamed from install-jupyter-stata.sh
│   │   └── install-windows.ps1 # Renamed from install-jupyter-stata.ps1
│   └── dev/
│       ├── README.md           # NEW: Dev setup docs
│       ├── dev-setup-macos.sh  # Renamed from setup.sh
│       ├── dev-setup-windows.ps1 # Renamed from setup.ps1
│       ├── update-send-to-stata-checksum.sh  # Renamed, clearer purpose
│       └── update-dev-checksums.ps1          # Renamed, clearer purpose
└── ...
```

## Components and Interfaces

### Component 1: Extension Identity (extension.toml)

**Changes:**
- `id`: "sight" → "stata"
- `name`: "Sight - Stata Language Server" → "Stata"
- `description`: Keep or update to "Stata language support for Zed"

**Interface:** No API changes; this is metadata only.

```toml
id = "stata"
name = "Stata"
description = "Stata language support for Zed"
version = "0.1.19"
# ... rest unchanged
```

### Component 2: Extension-Provided Tasks (languages/stata/tasks.json)

**Purpose:** Allow users to discover Send-to-Stata functionality via `task: spawn` without running install scripts.

**Design Decisions:**

1. **Platform Detection**: Tasks cannot conditionally show/hide based on platform. All tasks are visible on all platforms.

2. **Script Detection**: Tasks detect the OS and check for the appropriate tool (`send-to-stata.sh` on macOS, `send-to-stata.exe` on Windows), showing platform-specific installation instructions if not found.

3. **All Operations Require Script**: All send-to-stata operations require the installed script/executable because they need to create temp files, detect Stata variants, handle statement boundaries, etc.

**Task Structure:**

```json
[
  {
    "label": "Stata: Send File to Stata",
    "command": "...",
    "shell": { "program": "bash" },
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "never",
    "hide": "on_success"
  }
]
```

- `shell`: Specifies bash explicitly so the command works on both macOS and Windows (with Git Bash)
- `allow_concurrent_runs`: Allows multiple instances of the same task to run simultaneously (e.g., sending code while a previous send is still executing)

**Task Commands:**

Extension-provided tasks serve two purposes:
1. **Discoverability**: Users see "Stata: Send File" etc. in `task: spawn` and learn the feature exists
2. **Guidance**: When run without the installer, tasks show installation instructions

**Workflow:**
1. User opens a `.do` file and runs `task: spawn`
2. User sees "Stata: Send File to Stata" and other Stata tasks
3. User runs the task
4. **If installer not run yet**: Task shows "Send-to-Stata not installed" with installation instructions
5. **After running installer**: Task executes the send-to-stata operation

**Platform Details:**
- **macOS**: `send-to-stata.sh` script installed to `~/.local/bin/`
- **Windows**: `send-to-stata.exe` binary installed to `%APPDATA%\Zed\stata\`

**Platform Challenge**: Zed tasks use the system's default shell:
- macOS: bash/zsh (via `"shell": "system"`)
- Windows: PowerShell (via `"shell": "system"`)

Since bash and PowerShell have incompatible syntax, a single command cannot work on both platforms with the default shell.

**Design Decision**: Specify bash as the shell for extension-provided tasks using the `shell` field:

```json
{
  "label": "Stata: Send File to Stata",
  "command": "...",
  "shell": { "program": "bash" }
}
```

This approach:
- **macOS**: Works perfectly (bash is always available)
- **Windows with Git Bash**: Works if `bash` is in PATH (common for developers)
- **Windows without bash**: Shows "bash not found" error (clearer than PowerShell syntax errors)

**Task Shadowing Behavior:**

When users run the installer, it adds tasks to the user's `tasks.json` with the **same labels** as the extension-provided tasks. Zed's task precedence is:

1. Workspace tasks (`.zed/tasks.json`)
2. **User tasks** (`~/.config/zed/tasks.json` or `%APPDATA%\Zed\tasks.json`) ← installer adds here
3. Extension-provided tasks

This means:
- **Before installer**: User sees extension-provided bash tasks (for discoverability)
- **After installer**: User's tasks shadow the extension tasks

**Both macOS and Windows installers** add tasks with the same labels to the user's `tasks.json`. This:
- Shadows the extension-provided tasks completely
- Eliminates the overhead of the inline bash script's `command -v` check on every invocation
- Uses the native shell directly (bash on macOS, PowerShell on Windows)
- Calls the installed script/executable without the "is it installed?" logic

The extension-provided tasks serve purely as "placeholder" tasks that advertise available functionality to users who haven't run the installer yet.

**Task Command Pattern:**
```bash
if command -v send-to-stata.sh &>/dev/null; then
  send-to-stata.sh --file-mode --file "$ZED_FILE"
else
  echo "Send-to-Stata not installed."
  echo ""
  echo "Install with:"
  echo "  macOS:   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/jbearak/sight-zed/main/tools/send-to-stata/install-macos.sh)\""
  echo "  Windows: irm https://raw.githubusercontent.com/jbearak/sight-zed/main/tools/send-to-stata/install-windows.ps1 | iex"
  echo ""
  echo "Documentation: https://github.com/jbearak/sight-zed/tree/main/tools/send-to-stata"
  exit 1
fi
```

The error message includes both macOS and Windows install commands since the bash task may run on either platform (via Git Bash on Windows).

**Tasks to Include:**
- Stata: Send File to Stata
- Stata: Send Statement to Stata (requires script)
- Stata: Include File (requires script)
- Stata: Include Statement (requires script)
- Stata: CD to Workspace
- Stata: CD to File Directory

### Component 3: Tools Directory Structure

**Directory Layout:**

```
tools/
├── send-to-stata/
│   ├── README.md              # Full documentation (from SEND-TO-STATA.md)
│   ├── install-macos.sh       # macOS installer
│   ├── install-windows.ps1    # Windows installer
│   └── send-to-stata.sh       # Main script (macOS only)
├── jupyter-kernel/
│   ├── README.md              # Jupyter kernel documentation
│   ├── install-macos.sh       # macOS installer
│   └── install-windows.ps1    # Windows installer
└── dev/
    ├── README.md              # Development setup documentation
    ├── dev-setup-macos.sh     # macOS dev environment setup
    ├── dev-setup-windows.ps1  # Windows dev environment setup
    ├── update-send-to-stata-checksum.sh  # Updates checksum in installer
    └── update-dev-checksums.ps1          # Updates checksums in dev-setup
```

**Script Renaming:**

| Old Name | New Name | New Location |
|----------|----------|--------------|
| install-send-to-stata.sh | install-macos.sh | tools/send-to-stata/ |
| install-send-to-stata.ps1 | install-windows.ps1 | tools/send-to-stata/ |
| send-to-stata.sh | send-to-stata.sh | tools/send-to-stata/ |
| install-jupyter-stata.sh | install-macos.sh | tools/jupyter-kernel/ |
| install-jupyter-stata.ps1 | install-windows.ps1 | tools/jupyter-kernel/ |
| setup.sh | dev-setup-macos.sh | tools/dev/ |
| setup.ps1 | dev-setup-windows.ps1 | tools/dev/ |
| update-checksum.sh | update-send-to-stata-checksum.sh | tools/dev/ |
| update-setup-checksums.ps1 | update-dev-checksums.ps1 | tools/dev/ |

### Component 4: Documentation Updates

**README.md Changes:**

Add a "What the Scripts Do" section:

```markdown
## What the Install Scripts Do

### Why Install Scripts Are Required

The extension provides basic tasks that show installation instructions, but full Send-to-Stata functionality requires running the installer because:

- **Temp file management**: Stata executes code from `.do` files, so the script creates temp files and manages cleanup
- **Statement detection**: Multi-line statements with `///` continuations require parsing logic
- **Stata variant detection**: The script auto-detects which Stata variant (MP, SE, IC) is installed
- **Keybindings**: Zed extensions cannot register keybindings; they must be added to user config files
- **Platform-specific binaries**: Windows requires a native executable for clipboard/SendKeys automation

### Send-to-Stata Installer

The send-to-stata installer configures keyboard shortcuts to send code from Zed to Stata.

**Files Created:**
- `~/.local/bin/send-to-stata.sh` - The main script that communicates with Stata
- Updates `~/.config/zed/tasks.json` - Adds Stata task definitions
- Updates `~/.config/zed/keymap.json` - Adds keyboard shortcuts

**What It Does NOT Do:**
- Does not modify Stata installation
- Does not require admin/sudo privileges
- Does not install system-wide packages

### Jupyter Kernel Installer

The Jupyter kernel installer sets up stata_kernel for use with Zed's REPL.

**Files Created:**
- `~/.local/share/jupyter/kernels/stata/` - Kernel specification
- `~/.local/share/jupyter/kernels/stata_workspace/` - Workspace kernel specification
- `~/.stata_kernel.conf` - Kernel configuration

### Development Setup

The dev setup script installs build dependencies for extension development.

**macOS:** Installs Rust toolchain and WASM target via rustup
**Windows:** Installs Chocolatey, Rust, MSVC build tools, and WASI SDK
```

**tools/send-to-stata/README.md:**
- Move content from SEND-TO-STATA.md
- Update any path references

**tools/jupyter-kernel/README.md:**
- Extract Jupyter-specific content from README.md
- Add detailed kernel configuration options

**tools/dev/README.md:**
- Document what each dev script does
- Explain when to run checksum update scripts
- List prerequisites for development

### Component 5: Reference Updates

**Files Requiring Updates:**

1. **README.md**: Update curl/irm URLs to new paths
2. **AGENTS.md**: Update all script path references
3. **.github/workflows/update-send-to-stata.yml**: Update path to `install-send-to-stata.ps1`
4. **install-macos.sh** (send-to-stata): Update `GITHUB_RAW_BASE` path for fetching `send-to-stata.sh`
5. **update-send-to-stata-checksum.sh**: Update path to `send-to-stata.sh`

**URL Changes:**

| Old URL | New URL |
|---------|---------|
| `.../main/install-send-to-stata.sh` | `.../main/tools/send-to-stata/install-macos.sh` |
| `.../main/install-send-to-stata.ps1` | `.../main/tools/send-to-stata/install-windows.ps1` |
| `.../main/install-jupyter-stata.sh` | `.../main/tools/jupyter-kernel/install-macos.sh` |
| `.../main/install-jupyter-stata.ps1` | `.../main/tools/jupyter-kernel/install-windows.ps1` |
| `.../main/send-to-stata.sh` | `.../main/tools/send-to-stata/send-to-stata.sh` |

## Data Models

### Task Definition Schema

Extension-provided tasks follow Zed's task schema:

```typescript
interface Task {
  label: string;           // Display name in task picker
  command: string;         // Shell command to execute
  tags?: string[];         // Optional tags for filtering
  use_new_terminal?: boolean;
  allow_concurrent_runs?: boolean;
  reveal?: "always" | "never";
  hide?: "always" | "never" | "on_success";
}
```

### Extension Manifest Schema

```typescript
interface ExtensionManifest {
  id: string;              // Unique identifier (changing to "stata")
  name: string;            // Display name (changing to "Stata")
  description: string;
  version: string;
  schema_version: number;
  authors: string[];
  repository: string;
  // ... other fields unchanged
}
```



## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

Based on the prework analysis, the following properties can be verified:

### Property 1: Extension Identity Consistency

*For any* file in the repository that references the extension identity, the extension ID SHALL be "stata" (not "sight") except where "Sight" refers to the separate LSP project.

**Validates: Requirements 1.1, 1.2, 1.4, 5.4**

This property ensures that after renaming:
- `extension.toml` uses `id = "stata"`
- No stale references to `id = "sight"` remain in configuration files
- The LSP name "Sight" is preserved where it refers to the external project

### Property 2: Path Reference Consistency

*For any* URL or file path reference in documentation (README.md), GitHub Actions workflows, or AGENTS.md, the paths SHALL point to the new `tools/` directory structure.

**Validates: Requirements 3.5, 5.1, 5.2, 5.3**

This property ensures that after reorganization:
- README.md curl/irm URLs use `tools/send-to-stata/install-macos.sh` (not `install-send-to-stata.sh`)
- GitHub Actions reference `tools/send-to-stata/install-windows.ps1` (not `install-send-to-stata.ps1`)
- AGENTS.md documents the new `tools/` structure

### Property 3: Task Completeness

*For any* valid `languages/stata/tasks.json` file, the task list SHALL include tasks for all required operations: send statement, send file, include statement, include file, CD to workspace, and CD to file directory.

**Validates: Requirements 2.6**

This property ensures the extension-provided tasks cover all documented functionality.

### Property 4: Install Target Consistency

*For any* install script (send-to-stata or jupyter-kernel), the target installation directories SHALL remain unchanged at `~/.local/bin` (macOS) and `~/.config/zed/` for configuration files.

**Validates: Requirements 6.2**

This property ensures backward compatibility—existing users' installations continue to work because the scripts install to the same locations.

## Error Handling

### Extension Tasks Error Handling

When extension-provided tasks detect that `send-to-stata.sh` is not installed:

1. **Detection**: Check if `send-to-stata.sh` is in PATH using `command -v`
2. **Error Message**: Display installation instructions for both platforms
3. **Exit Code**: Return non-zero to indicate failure

Example error output:
```
Send-to-Stata not installed.

Install with:
  macOS:   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jbearak/sight-zed/main/tools/send-to-stata/install-macos.sh)"
  Windows: irm https://raw.githubusercontent.com/jbearak/sight-zed/main/tools/send-to-stata/install-windows.ps1 | iex

Documentation: https://github.com/jbearak/sight-zed/tree/main/tools/send-to-stata
```

### Script Migration Error Handling

During the reorganization:

1. **Old URLs**: Old URLs will return 404 after migration. Users with cached/bookmarked URLs will see GitHub's 404 page.
2. **Mitigation**: Update documentation immediately; consider adding redirect instructions to README.

### Backward Compatibility

Existing installations are unaffected because:
1. Installed scripts remain at `~/.local/bin/send-to-stata.sh`
2. User keybindings in `~/.config/zed/keymap.json` reference task names, not script paths
3. User tasks in `~/.config/zed/tasks.json` call `send-to-stata.sh` by name (found via PATH)

## Testing Strategy

### Unit Tests

Unit tests verify specific examples and edge cases:

1. **extension.toml validation**: Verify `id = "stata"` and `name = "Stata"`
2. **tasks.json validation**: Verify JSON is valid and contains required task labels
3. **README.md content**: Verify "What the Scripts Do" section exists
4. **File existence**: Verify all expected files exist in `tools/` subdirectories

### Property-Based Tests

Property tests verify universal properties across all inputs:

1. **Identity consistency test**: Search all relevant files for extension ID references, verify consistency
2. **Path reference test**: Extract all URLs/paths from docs, verify they point to `tools/` structure
3. **Task completeness test**: Parse tasks.json, verify all required operations are present
4. **Install target test**: Parse install scripts, verify target directories are unchanged

### Test Configuration

- Property tests should run with minimum 100 iterations where applicable
- Each property test should be tagged with: **Feature: pr-feedback-refactor, Property N: [property name]**

### Manual Testing Checklist

Since some requirements involve Zed integration:

1. [ ] Install extension in Zed, verify it appears as "Stata"
2. [ ] Open a .do file, run `task: spawn`, verify Stata tasks appear
3. [ ] Run a task without send-to-stata installed, verify error message shows
4. [ ] Run install script from new URL, verify installation succeeds
5. [ ] Verify existing keybindings still work after extension update
