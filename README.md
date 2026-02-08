# Zed Extension for Stata

A [Zed](https://zed.dev) extension providing support for the Stata statistical programming language.

## Features

- Code completion
- Diagnostics (e.g., detects syntax errors and undefined macros)
- Syntax highlighting
- Run Stata code from the editor (requires additional setup—see below)
  - [Send to Stata](#send-to-stata-optional)
  - [Jupyter REPL](#jupyter-repl-optional)

> **⚠️ Development Status:** This is an early-stage implementation. While functional, it requires substantial testing and code review. Contributions and feedback are welcome!

> **Related Repositories:**
>
> - [Sight](https://github.com/jbearak/sight) - A language server and VS Code extension for Stata
> - [tree-sitter-stata](https://github.com/jbearak/tree-sitter) - A tree-sitter grammar
> - [send-to-stata](https://github.com/jbearak/send-to-stata) - A utility for sending Stata code to the Stata application
> This Zed extension uses the tree-sitter grammar and language server from those repositories to provide syntax highlighting and diagnostics. The send-to-stata utility sends code to Stata on Windows; macOS uses AppleScript.

> [!TIP]
> The Zed extension does not include send-to-stata; run the installer below for your platform.

## Installation

Install from the Zed extension marketplace by searching for "Sight" or "Stata".

Syntax highlighting, completions, and diagnostics will work immediately once you open a ".do" file.

## Send to Stata (Optional)

Execute Stata code directly from Zed with keyboard shortcuts. Works with both the Stata application and terminal sessions.

> [!NOTE]
> **Why a separate install?** Zed extensions can't register custom keybindings or tasks—those must live in user config files. The send-to-stata functionality requires both, so it can't be bundled into the extension itself.

See [tools/send-to-stata/README.md](tools/send-to-stata/README.md) for full documentation, configuration options, and troubleshooting.

### Keyboard Shortcuts

| Mac                   | Windows                | Action                                 |
|-----------------------|------------------------|----------------------------------------|
| `cmd-enter`           | `ctrl-enter`           | Send statement to Stata app            |
| `shift-cmd-enter`     | `shift-ctrl-enter`     | Send file to Stata app                 |
| `opt-cmd-enter`       | `alt-ctrl-enter`       | Include statement (preserves locals)   |
| `opt-shift-cmd-enter` | `alt-shift-ctrl-enter` | Include file (preserves locals)        |
| `shift-enter`         | `shift-enter`          | Paste selection to terminal            |
| `opt-enter`           | `alt-enter`            | Paste current line to terminal         |


### macOS

**Run the installer in Terminal:**
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jbearak/zed-stata/main/tools/send-to-stata/install-macos.sh)"
```

### Windows

> [!IMPORTANT]
> The Windows scripts require **PowerShell 7+** (`pwsh`).
> **Install PowerShell 7** (if not already installed):
> ```powershell
> winget install Microsoft.PowerShell
> ```

**Run the installer in PowerShell:**
```powershell
irm https://raw.githubusercontent.com/jbearak/zed-stata/main/tools/send-to-stata/install-windows.ps1 | iex
```

> [!TIP]
> **Focus behavior:** The installer prompts whether to return focus to Zed after sending code to Stata. 

## Jupyter REPL (Optional)

The installer creates two Jupyter kernels:

| Kernel | Working Directory | Use Case |
|--------|-------------------|----------|
| **Stata** | File's directory | Scripts with paths relative to the script location |
| **Stata (Workspace)** | Workspace root | Scripts with paths relative to the project root |

The workspace kernel walks up from the file's directory looking for `.git`, `.stata-project`, or `.project` markers to find the project root. If no marker is found, it falls back to the file's directory.

Usage in Zed:
1. Open a `.do` file
2. Select `stata` or `stata_workspace` as the kernel
3. Click the 🔄 icon in the editor toolbar to execute code
   or use Control+Shift+Enter keyboard shortcut

> **Note:** stata_kernel works well for interactive exploration but can hang on long-running loops or operations taking more than several seconds. For batch scripts or iterative workflows, use [Send to Stata](#send-to-stata-optional) instead. See [comparison table](#choosing-between-send-to-stata-and-jupyter-repl) below.

### macOS

**Run the installer in Terminal:**
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jbearak/zed-stata/main/tools/jupyter-kernel/install-macos.sh)"
```

### Windows

> [!IMPORTANT]
> The Windows scripts require **PowerShell 7+** (`pwsh`).
> **Install PowerShell 7** (if not already installed):
> ```powershell
> winget install Microsoft.PowerShell
> ```

**Run the installer in PowerShell:**
```powershell
irm https://raw.githubusercontent.com/jbearak/zed-stata/main/tools/jupyter-kernel/install-windows.ps1 | iex
```

> [!IMPORTANT]
> After installing or updating the Jupyter kernels, **restart Zed**. Kernel discovery/connection state can be cached, and a restart is often required before the kernels can connect successfully. The installer adds the Jupyter virtual environment to your PATH so Zed can discover the kernels.

> [!CAUTION]
> The Windows installer is intentionally opinionated to work reliably:
> - **Uses Python 3.11 via the Python Launcher (`py -3.11`)** (newer versions have caused dependency and kernelspec issues).
> - **Recreates the venv if needed** to ensure the venv is actually using Python 3.11.
> - **Installs only minimal Jupyter components** (`jupyter-core`, `jupyter-client`, and a pinned `ipykernel`) instead of the full `jupyter` meta-package to avoid pulling in `notebook`/`jupyterlab` and native build dependencies (e.g. `pywinpty`).
> - **Writes kernelspecs deterministically** into `%APPDATA%\jupyter\kernels\...` (including `kernel.json`) so Zed can discover them.

> [!WARNING]
> **Start the kernel before opening Stata.** On Windows, if Stata is already running when you launch a Jupyter kernel, the kernel will close your Stata application. This is a fundamental limitation of Stata's Windows architecture. Start the kernel first, then open Stata if needed. This issue does not affect macOS.

## Choosing Between Send-to-Stata and Jupyter REPL

| Scenario | Recommended | Why |
|----------|-------------|-----|
| Quick data exploration | Jupyter REPL | Inline results, fast iteration |
| Testing individual commands | Jupyter REPL | Interactive feedback |
| Loops with many iterations | Send to Stata | Avoids kernel hang issues |
| Operations > several seconds | Send to Stata | Avoids potential instability |
| Graph-heavy workflows | Send to Stata | Graphs can trigger kernel hangs |
| Production batch jobs | Send to Stata | Reliable unattended execution |

> [!TIP]
> The installer creates `~/.stata_kernel.conf` (or `%USERPROFILE%\.stata_kernel.conf` on Windows) with auto-detected settings. Edit this file to customize graph format, cache directory, and other options.

## What the Install Scripts Do

### Why Install Scripts Are Required

The extension provides basic tasks that show installation instructions, but full Send-to-Stata and Jupyter REPL functionality requires running the installers because:

- **Temp file management**: Stata executes code from `.do` files, so the script creates temp files and manages cleanup
- **Statement detection**: Multi-line statements with `///` continuations require parsing logic
- **Stata variant detection**: The script auto-detects which Stata variant (MP, SE, IC) is installed
- **Keybindings**: Zed extensions cannot register keybindings; they must be added to user config files
- **Platform-specific binaries**: Windows requires a native executable for clipboard/SendKeys automation

### Send-to-Stata Installer

The send-to-stata installer configures keyboard shortcuts to send code from Zed to Stata.

**What It Does NOT Do:**
- Does not modify Stata installation
- Does not require admin/sudo privileges
- Does not install system-wide packages

#### Files Created (macOS)

| File | Purpose |
|------|---------|
| `~/.local/bin/send-to-stata.sh` | Main script that communicates with Stata via AppleScript |
| `~/.config/zed/tasks.json` | Updated with Stata task definitions |
| `~/.config/zed/keymap.json` | Updated with keyboard shortcuts |

#### Files Created (Windows)

| File | Purpose |
|------|---------|
| `%APPDATA%\Zed\stata\send-to-stata.exe` | Native executable for Stata automation |
| `%APPDATA%\Zed\tasks.json` | Updated with Stata task definitions |
| `%APPDATA%\Zed\keymap.json` | Updated with keyboard shortcuts |

### Jupyter Kernel Installer

The Jupyter kernel installer sets up stata_kernel for use with Zed's REPL.

#### Files Created (macOS)

| File | Purpose |
|------|---------|
| `~/.local/share/jupyter/kernels/stata/` | Standard kernel specification |
| `~/.local/share/jupyter/kernels/stata_workspace/` | Workspace kernel specification |
| `~/.stata_kernel.conf` | Kernel configuration (Stata path, graph format, etc.) |

#### Files Created (Windows)

| File | Purpose |
|------|---------|
| `%APPDATA%\jupyter\kernels\stata\` | Standard kernel specification |
| `%APPDATA%\jupyter\kernels\stata_workspace\` | Workspace kernel specification |
| `%LOCALAPPDATA%\stata_kernel\venv\` | Isolated Python virtual environment |
| `%USERPROFILE%\.stata_kernel.conf` | Kernel configuration |

## Manual Keybindings Setup

If you prefer to configure keybindings manually instead of running the installer, add the following to your Zed keymap file.

### macOS

Add to `~/.config/zed/keymap.json`:

```json
[
  {
    "context": "Editor && extension == do",
    "bindings": {
      "cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Do Statement"}]]],
      "shift-cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Do File"}]]],
      "alt-cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Include Statement"}]]],
      "alt-shift-cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Include File"}]]],
      "shift-enter": ["workspace::SendKeystrokes", "cmd-c ctrl-` cmd-v enter"],
      "alt-enter": ["workspace::SendKeystrokes", "cmd-left shift-cmd-right cmd-c ctrl-` cmd-v enter"],
      "ctrl-shift-w": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: CD to Workspace"}]]],
      "ctrl-shift-f": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: CD to File Directory"}]]]
    }
  }
]
```

### Windows

Add to `%APPDATA%\Zed\keymap.json`:

```json
[
  {
    "context": "Editor && extension == do",
    "bindings": {
      "ctrl-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Do Statement"}]]],
      "shift-ctrl-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Do File"}]]],
      "alt-ctrl-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Include Statement"}]]],
      "alt-shift-ctrl-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Include File"}]]],
      "shift-enter": ["workspace::SendKeystrokes", "ctrl-c ctrl-` ctrl-v enter"],
      "alt-enter": ["workspace::SendKeystrokes", "home shift-end ctrl-c ctrl-` ctrl-v enter"],
      "ctrl-shift-w": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: CD to Workspace"}]]],
      "ctrl-shift-f": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: CD to File Directory"}]]]
    }
  }
]
```

> [!NOTE]
> Manual keybindings require the send-to-stata script/executable to be installed. The keybindings trigger tasks that call the script. Run the installer to install the script, or see [tools/send-to-stata/README.md](tools/send-to-stata/README.md) for manual script installation.

## Building from Source

See [DEVELOPMENT.md](DEVELOPMENT.md) for detailed development setup, directory structure, and workflows.

### Send-to-Stata

Install from a local clone:

```bash
git clone https://github.com/jbearak/zed-stata
cd zed-stata

# macOS
./tools/send-to-stata/install-macos.sh

# Windows (PowerShell 7+)
pwsh -File .\tools\send-to-stata\install-windows.ps1
```

### Jupyter Kernel

Install stata_kernel from a local clone:

```bash
git clone https://github.com/jbearak/zed-stata
cd zed-stata

# macOS
./tools/jupyter-kernel/install-macos.sh

# Windows (PowerShell 7+)
pwsh -File .\tools\jupyter-kernel\install-windows.ps1
```

## Related Projects

- [Sight LSP](https://github.com/jbearak/sight) - A language server protocol implementation for the Stata statistical programming language
- [tree-sitter-stata](https://github.com/jbearak/tree-sitter-stata) - Tree-sitter grammar for Stata

## License

Copyright © 2026 Jonathan Marc Bearak

[GPLv3](LICENSE) - This project is open source software. You can use, modify, and distribute it with attribution, but any derivative works must also be open source under GPLv3.
