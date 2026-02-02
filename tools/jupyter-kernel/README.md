# Jupyter Kernel for Stata

This directory contains installers for `stata_kernel`, which enables Jupyter REPL integration with Stata in Zed.

## Overview

The installer sets up `stata_kernel` for use with Zed's built-in Jupyter integration. It creates two kernels:

| Kernel | Working Directory | Use Case |
|--------|-------------------|----------|
| **Stata** | File's directory | Scripts with paths relative to the script location |
| **Stata (Workspace)** | Workspace root | Scripts with paths relative to the project root |

## Installation

### macOS

Run the installer in Terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jbearak/zed-stata/main/tools/jupyter-kernel/install-macos.sh)"
```

Or from a local clone:

```bash
./tools/jupyter-kernel/install-macos.sh
```

### Windows

> **Important:** The Windows installer requires **PowerShell 7+** (`pwsh`).
>
> Install PowerShell 7 (if not already installed):
> ```powershell
> winget install Microsoft.PowerShell
> ```

Run the installer in PowerShell:

```powershell
irm https://raw.githubusercontent.com/jbearak/zed-stata/main/tools/jupyter-kernel/install-windows.ps1 | iex
```

Or from a local clone:

```powershell
pwsh -File .\tools\jupyter-kernel\install-windows.ps1
```

> **Important:** After installing or updating the Jupyter kernels, **restart Zed**. Kernel discovery/connection state can be cached, and a restart is often required before the kernels can connect successfully.

## What the Installer Does

- Creates an isolated Python virtual environment with `stata_kernel` and its dependencies (`jupyter-core`, `jupyter-client`, `ipykernel`)
- Auto-detects your Stata installation and writes the configuration file with the detected path and execution mode
- Registers two Jupyter kernels: **Stata** and **Stata (Workspace)**

### Files Created

**macOS:**
- `~/.local/share/stata_kernel/venv/` - Python virtual environment
- `~/.stata_kernel.conf` - Kernel configuration (auto-detected settings)
- `~/Library/Jupyter/kernels/stata/` - Standard kernel specification
- `~/Library/Jupyter/kernels/stata_workspace/` - Workspace kernel specification

**Windows:**
- `%LOCALAPPDATA%\stata_kernel\venv\` - Python virtual environment
- `%USERPROFILE%\.stata_kernel.conf` - Kernel configuration (auto-detected settings)
- `%APPDATA%\jupyter\kernels\stata\` - Standard kernel specification
- `%APPDATA%\jupyter\kernels\stata_workspace\` - Workspace kernel specification
- Adds the venv Scripts directory to user PATH (required for Zed to discover the kernels)

## Kernel Differences

### Stata (Standard)

The standard kernel starts in the file's directory. Use this for scripts that reference files relative to the script location:

```stata
* If script is in /project/analysis/main.do
use "../data/mydata.dta"  // Looks in /project/data/
```

### Stata (Workspace)

The workspace kernel finds the project root before starting Stata. Use this for scripts that reference files relative to the project root:

```stata
* If script is in /project/analysis/main.do
use "data/mydata.dta"  // Looks in /project/data/
```

## Workspace Detection

The workspace kernel walks up from the file's directory looking for these marker files (in order):

1. `.git` — Git repository root
2. `.stata-project` — Stata-specific project marker
3. `.project` — Generic project marker

If no marker is found, it falls back to the file's directory (same as the standard kernel).

## Usage in Zed

1. Open a `.do` file
2. Select `stata` or `stata_workspace` as the kernel
3. Click the 🔄 icon in the editor toolbar to execute code, or use `Control+Shift+Enter`

### Setting a Default Kernel

Add to your Zed settings (`~/.config/zed/settings.json` on macOS, `%APPDATA%\Zed\settings.json` on Windows):

```json
{
  "jupyter": {
    "kernel_selections": {
      "stata": "stata_workspace"
    }
  }
}
```

## Configuration

The installer creates a configuration file at `~/.stata_kernel.conf` (or `%USERPROFILE%\.stata_kernel.conf` on Windows) with auto-detected settings.

### Configuration Options

```ini
[stata_kernel]

# Full path to your Stata executable
stata_path = /Applications/Stata/StataMP.app/Contents/MacOS/stata-mp

# How stata_kernel communicates with Stata
# Values: console (MP/SE), automation (IC/BE)
execution_mode = console

# Directory for temporary log files and graphs
# cache_directory = ~/.stata_kernel_cache

# Format for exported graphs (svg, png, eps)
# graph_format = svg

# Scale factor for graph dimensions
# graph_scale = 1.0

# Width of graphs in pixels
# graph_width = 600

# Height of graphs in pixels
# graph_height = 400
```

For full configuration documentation, see: https://kylebarron.dev/stata_kernel/using_stata_kernel/configuration/

## Limitations

> **Note:** stata_kernel works well for interactive exploration but can hang on long-running loops or operations taking more than several seconds. For batch scripts or iterative workflows, use [Send to Stata](../send-to-stata/) instead.

### Windows-Specific

> **Warning:** On Windows, if Stata is already running when you launch a Jupyter kernel, the kernel will close your Stata application. This is a fundamental limitation of Stata's Windows architecture. Start the kernel first, then open Stata if needed. This issue does not affect macOS.

The Windows installer is intentionally opinionated to work reliably:
- Uses Python 3.11 via the Python Launcher (`py -3.11`) — newer versions have caused dependency and kernelspec issues
- Recreates the venv if needed to ensure it's using Python 3.11
- Installs only minimal Jupyter components (`jupyter-core`, `jupyter-client`, and a pinned `ipykernel`) instead of the full `jupyter` meta-package to avoid pulling in `notebook`/`jupyterlab` and native build dependencies (e.g. `pywinpty`)
- Writes kernelspecs deterministically into `%APPDATA%\jupyter\kernels\...` so Zed can discover them

## Uninstallation

### macOS

```bash
./tools/jupyter-kernel/install-macos.sh --uninstall
```

To also remove the configuration file:

```bash
./tools/jupyter-kernel/install-macos.sh --uninstall --remove-config
```

### Windows

```powershell
pwsh -File .\tools\jupyter-kernel\install-windows.ps1 -Uninstall
```

To also remove the configuration file:

```powershell
pwsh -File .\tools\jupyter-kernel\install-windows.ps1 -Uninstall -RemoveConfig
```

## Troubleshooting

### Kernel not appearing in Zed

1. Restart Zed after installation
2. Verify the kernel is installed: `jupyter kernelspec list`
3. On Windows, ensure the venv Scripts directory is in your PATH

### Kernel hangs or crashes

- stata_kernel can hang on long-running operations — use Send to Stata for batch jobs
- On Windows, ensure Stata is not already running before starting the kernel
- Check `~/.stata_kernel.conf` for correct `stata_path` and `execution_mode`

### Python version issues (Windows)

The installer prefers Python 3.11. If you have issues:
1. Install Python 3.11 from python.org
2. Delete the existing venv: `Remove-Item -Recurse -Force "$env:LOCALAPPDATA\stata_kernel\venv"`
3. Re-run the installer
