# Design Document: Jupyter Workspace Kernel

## Overview

This design extends the existing `install-jupyter-stata.sh` installer to provide a second kernel variant called "Stata (Workspace)" that automatically changes to the workspace root directory before starting Stata. This solves a common pain point where Zed's REPL starts kernels in the file's directory, breaking relative paths that expect to run from the project root.

The implementation embeds a Python wrapper script in the installer that:
1. Walks up from the current directory looking for workspace markers
2. Changes to the workspace root before delegating to stata_kernel
3. Falls back to the original directory if no marker is found

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    install-jupyter-stata.sh                      │
├─────────────────────────────────────────────────────────────────┤
│  Existing Components              │  New Components              │
│  ─────────────────────            │  ──────────────              │
│  • Prerequisite checks            │  • get_workspace_kernel_     │
│  • Stata detection                │    script()                  │
│  • Virtual env management         │  • install_workspace_kernel()│
│  • Config management              │  • uninstall_workspace_      │
│  • Standard kernel registration   │    kernel()                  │
│  • Uninstallation                 │  • Updated print_summary()   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Installed Components                        │
├─────────────────────────────────────────────────────────────────┤
│  ~/Library/Jupyter/kernels/stata/           (Standard kernel)   │
│    └── kernel.json                                              │
│                                                                 │
│  ~/Library/Jupyter/kernels/stata_workspace/ (Workspace kernel)  │
│    ├── kernel.json                                              │
│    └── stata_workspace_kernel.py            (Wrapper script)    │
└─────────────────────────────────────────────────────────────────┘
```

### Kernel Selection Flow

```
User opens .do file in Zed
         │
         ▼
┌─────────────────────┐
│ Select kernel from  │
│ REPL panel dropdown │
└─────────────────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌───────┐  ┌─────────────────┐
│ Stata │  │ Stata (Workspace)│
└───────┘  └─────────────────┘
    │              │
    ▼              ▼
Starts in      Wrapper script
file's dir     finds workspace root
               then starts Stata
```

## Components and Interfaces

### Wrapper Script: stata_workspace_kernel.py

The wrapper script is embedded in the installer and written to the kernel directory during installation.

```python
#!/usr/bin/env python3
"""
Wrapper kernel for stata_kernel that changes to workspace root before starting.
"""

import os
from pathlib import Path


def find_workspace_root(start_path: Path) -> Path:
    """
    Walk up from start_path looking for workspace markers.
    Returns the workspace root, or start_path if no marker found.
    
    Markers checked (in order): .git, .stata-project, .project
    Stops at home directory to avoid searching system directories.
    """
    markers = ['.git', '.stata-project', '.project']
    current = start_path.resolve()
    home = Path.home().resolve()  # Resolve to handle macOS symlinks like /var -> /private/var
    
    while current != current.parent:
        # Stop if we've gone above home
        try:
            current.relative_to(home)
        except ValueError:
            break
            
        for marker in markers:
            if (current / marker).exists():
                return current
        current = current.parent
    
    return start_path


def main():
    cwd = Path.cwd()
    workspace_root = find_workspace_root(cwd)
    os.chdir(workspace_root)
    
    from stata_kernel import kernel
    from ipykernel.kernelapp import IPKernelApp
    IPKernelApp.launch_instance(kernel_class=kernel.StataKernel)


if __name__ == '__main__':
    main()
```

### Installer Functions

#### get_workspace_kernel_script()

Returns the embedded Python wrapper script as a heredoc string.

```bash
get_workspace_kernel_script() {
  cat << 'PYTHON_EOF'
#!/usr/bin/env python3
# ... wrapper script content ...
PYTHON_EOF
}
```

#### install_workspace_kernel()

Creates the workspace kernel spec directory and files.

```bash
install_workspace_kernel() {
  # Create kernel directory
  mkdir -p "$WORKSPACE_KERNEL_DIR"
  
  # Write wrapper script
  get_workspace_kernel_script > "$WORKSPACE_KERNEL_DIR/stata_workspace_kernel.py"
  chmod +x "$WORKSPACE_KERNEL_DIR/stata_workspace_kernel.py"
  
  # Create kernel.json
  cat > "$WORKSPACE_KERNEL_DIR/kernel.json" << EOF
{
  "argv": [
    "$VENV_DIR/bin/python",
    "$WORKSPACE_KERNEL_DIR/stata_workspace_kernel.py",
    "-f", "{connection_file}"
  ],
  "display_name": "Stata (Workspace)",
  "language": "stata"
}
EOF
}
```

#### uninstall_workspace_kernel()

Removes the workspace kernel directory.

```bash
uninstall_workspace_kernel() {
  if [[ -d "$WORKSPACE_KERNEL_DIR" ]]; then
    rm -rf "$WORKSPACE_KERNEL_DIR"
    print_success "Removed workspace kernel"
  fi
}
```

### Updated Installation Summary

The `print_summary()` function is updated to explain both kernels:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  stata_kernel installed successfully!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Stata Edition:    MP
  Execution Mode:   console
  Configuration:    ~/.stata_kernel.conf

  Two kernels are now available:

    Stata             Starts in the file's directory
    Stata (Workspace) Starts in the workspace root (looks for .git)

  Usage in Zed:
    1. Open a .do file
    2. Select 'stata' or 'stata_workspace' as the kernel
    3. Click the 🔄 icon in the editor toolbar to execute code
       or use Control+Shift+Enter keyboard shortcut

  To set a default kernel, add to ~/.config/zed/settings.json:

    "jupyter": {
      "kernel_selections": {
        "stata": "stata_workspace"
      }
    }

  Documentation: https://kylebarron.dev/stata_kernel/
```

## Data Models

### Workspace Kernel Spec (kernel.json)

```json
{
  "argv": [
    "/Users/username/.local/share/stata_kernel/venv/bin/python",
    "/Users/username/Library/Jupyter/kernels/stata_workspace/stata_workspace_kernel.py",
    "-f",
    "{connection_file}"
  ],
  "display_name": "Stata (Workspace)",
  "language": "stata"
}
```

Key differences from standard kernel:
- `argv[1]` points to the wrapper script instead of `-m stata_kernel`
- `display_name` is "Stata (Workspace)" to distinguish in UI

### Marker File Priority

| Priority | Marker | Description |
|----------|--------|-------------|
| 1 | `.git` | Git repository root |
| 2 | `.stata-project` | Stata-specific project marker |
| 3 | `.project` | Generic project marker |

The first marker found (walking up) determines the workspace root.

### Directory Constants

| Constant | Value |
|----------|-------|
| `KERNEL_DIR` | `~/Library/Jupyter/kernels/stata` |
| `WORKSPACE_KERNEL_DIR` | `~/Library/Jupyter/kernels/stata_workspace` |



## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Workspace Root Finding

*For any* directory tree where a marker file (.git, .stata-project, or .project) exists at some ancestor directory, `find_workspace_root()` SHALL return the path to the nearest ancestor containing a marker.

**Validates: Requirements 1.1, 1.3**

### Property 2: Marker Priority

*For any* directory that contains multiple marker files, `find_workspace_root()` SHALL return that directory (not continue searching), and the marker check order (.git, .stata-project, .project) SHALL be consistent.

**Validates: Requirements 1.2**

### Property 3: Fallback Behavior

*For any* directory tree with no marker files between the start directory and home, `find_workspace_root()` SHALL return the original start directory unchanged.

**Validates: Requirements 1.4**

### Property 4: Home Directory Boundary

*For any* directory tree where markers exist only above the home directory, `find_workspace_root()` SHALL return the original start directory (not the marker above home).

**Validates: Requirements 1.5**

### Property 5: Dual Kernel Installation

*For any* successful installation, both kernel spec directories SHALL exist:
- `~/Library/Jupyter/kernels/stata/kernel.json`
- `~/Library/Jupyter/kernels/stata_workspace/kernel.json`

**Validates: Requirements 2.1**

### Property 6: Complete Uninstallation

*For any* uninstallation after a successful installation, both kernel spec directories SHALL be removed.

**Validates: Requirements 2.4**

## Error Handling

### Wrapper Script Errors

| Condition | Behavior |
|-----------|----------|
| Cannot determine home directory | Falls back to start directory |
| Permission denied reading directory | Falls back to start directory |
| Marker file is a broken symlink | Treated as non-existent |

The wrapper script is designed to fail gracefully—any error in workspace detection results in using the original directory, which is the same behavior as the standard kernel.

### Installation Errors

| Condition | Behavior |
|-----------|----------|
| Cannot create workspace kernel directory | Display error, continue with standard kernel only |
| Cannot write wrapper script | Display error, continue with standard kernel only |

The workspace kernel is an enhancement; failure to install it should not prevent the standard kernel from working.

## Testing Strategy

### Unit Tests

Unit tests verify the `find_workspace_root()` function in isolation:

1. **Basic marker detection**: Directory with .git returns that directory
2. **Nested directory**: Subdirectory of git repo returns repo root
3. **Multiple markers**: Directory with both .git and .stata-project returns that directory
4. **No markers**: Directory with no markers returns itself
5. **Home boundary**: Markers above home are ignored

### Property-Based Tests

Property-based tests verify universal properties across generated inputs:

- Minimum 100 iterations per property test
- Tag format: **Feature: jupyter-workspace-kernel, Property {number}: {property_text}**

1. **Property 1 Test: Workspace Root Finding**
   - Generate random directory trees with markers at various depths
   - Verify `find_workspace_root()` returns the nearest ancestor with a marker

2. **Property 3 Test: Fallback Behavior**
   - Generate random directory trees without any markers
   - Verify `find_workspace_root()` returns the start directory

### Integration Tests

Integration tests verify end-to-end behavior:

1. **Dual kernel installation**: Run installer, verify both kernel specs exist
2. **Kernel spec content**: Verify kernel.json files have correct content
3. **Uninstallation**: Run uninstall, verify both kernel specs removed

### Manual Testing

Since the kernel runs inside Zed's REPL, some testing must be manual:

1. Open a .do file in a git repository subdirectory
2. Start "Stata (Workspace)" kernel
3. Run `pwd` to verify working directory is repo root
4. Compare with "Stata" kernel which should show file's directory
