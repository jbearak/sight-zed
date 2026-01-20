# Sight - Zed Extension for Stata

A Zed editor extension providing Stata language support using the [Sight LSP](https://github.com/jbearak/sight).

## Features

- Syntax highlighting via tree-sitter grammar
- Language server integration with Sight LSP
- Code completion, hover information, and diagnostics
- Send code to Stata with keyboard shortcuts (requires additional setup—see below)

> **⚠️ Development Status:** This is an early-stage implementation. While functional, it requires substantial testing and code review. Contributions and feedback are welcome!

> **Related Repositories:**
>
> - [tree-sitter-stata](https://github.com/jbearak/tree-sitter) - A tree-sitter grammar
> - [Sight](https://github.com/jbearak/sight) - A language server and VS Code extension for Stata
> 
> This Zed extension uses the tree-sitter grammar and language server from those repositories to provide syntax highlighting and diagnostics.

## Installation

Install from the Zed extension marketplace by searching for "Sight" or "Stata".

Syntax highlighting, completions, and diagnostics will work immediately once you open a ".do" file.

## Send to Stata (Optional)

Execute Stata code directly from Zed with keyboard shortcuts. Works with both the Stata application and terminal sessions.

### macOS

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jbearak/sight-zed/main/install-send-to-stata.sh)"
```

| Shortcut | Action |
|----------|--------|
| `cmd-enter` | Send statement to Stata app |
| `shift-cmd-enter` | Send file to Stata app |
| `opt-cmd-enter` | Include statement (preserves locals) |
| `opt-shift-cmd-enter` | Include file (preserves locals) |
| `shift-enter` | Paste selection to terminal |
| `opt-enter` | Paste current line to terminal |

### Windows

> [!IMPORTANT]
> The Windows scripts require **PowerShell 7+** (`pwsh`).

**Install PowerShell 7** (if not already installed):
```powershell
winget install Microsoft.PowerShell
```

Then run the installer (works from any PowerShell version):
```powershell
irm https://raw.githubusercontent.com/jbearak/sight-zed/main/install-send-to-stata.ps1 | iex
```

| Shortcut | Action |
|----------|--------|
| `ctrl-enter` | Send statement to Stata app |
| `shift-ctrl-enter` | Send file to Stata app |
| `alt-ctrl-enter` | Include statement (preserves locals) |
| `alt-shift-ctrl-enter` | Include file (preserves locals) |
| `shift-enter` | Paste selection to terminal |
| `alt-enter` | Paste current line to terminal |

**Focus behavior:** The installer prompts whether to return focus to Zed after sending code to Stata. For CI/CD or scripted installs, pass arguments after the pipe:

```powershell
# Return focus to Zed (recommended for iterative coding)
irm https://raw.githubusercontent.com/jbearak/sight-zed/main/install-send-to-stata.ps1 | iex -ReturnFocus true

# Stay in Stata (useful for inspecting output)
irm https://raw.githubusercontent.com/jbearak/sight-zed/main/install-send-to-stata.ps1 | iex -ReturnFocus false
```

> **Why a separate install?** Zed extensions can't register custom keybindings or tasks—those must live in user config files. The send-to-stata functionality requires both, so it can't be bundled into the extension itself.

See [SEND-TO-STATA.md](SEND-TO-STATA.md) for full documentation, configuration options, and troubleshooting.

## Jupyter REPL

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

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jbearak/sight-zed/main/install-jupyter-stata.sh)"
```

### Windows

> [!IMPORTANT]
> The Windows scripts require **PowerShell 7+** (`pwsh`).

**Install PowerShell 7** (if not already installed):
```powershell
winget install Microsoft.PowerShell
```

Then run the installer (works from any PowerShell version):
```powershell
irm https://raw.githubusercontent.com/jbearak/sight-zed/main/install-jupyter-stata.ps1 | iex
```

The Windows installer is intentionally opinionated to be reliable across Python/Jupyter setups:

- **Uses Python 3.11 via the Python Launcher (`py -3.11`)** when available (stata_kernel is most stable on 3.9–3.11; newer versions have caused dependency and kernelspec issues).
- **Recreates the venv if needed** to ensure the venv is actually using Python 3.11.
- **Installs only minimal Jupyter components** (`jupyter-core`, `jupyter-client`, and a pinned `ipykernel`) instead of the full `jupyter` meta-package to avoid pulling in `notebook`/`jupyterlab` and native build dependencies (e.g. `pywinpty`).
- **Writes kernelspecs deterministically** into `%APPDATA%\jupyter\kernels\...` (including `kernel.json`) so Zed can discover them reliably.

> [!IMPORTANT]
> After installing or updating the Jupyter kernels, **restart Zed**. Kernel discovery/connection state can be cached, and a restart is often required before the kernels can connect successfully. The installer adds the Jupyter virtual environment to your PATH so Zed can discover the kernels.

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

## Building from Source

### Zed Extension

```bash
cargo build --release --target wasm32-wasip1

# The extension.wasm will be in target/wasm32-wasip1/release/
```

### Send-to-Stata

Install from a local clone:

```bash
git clone https://github.com/jbearak/sight-zed
cd sight-zed

# macOS
./install-send-to-stata.sh

# Windows (PowerShell 7+)
pwsh -File .\install-send-to-stata.ps1
```

### Jupyter Kernel

Install stata_kernel from a local clone:

```bash
git clone https://github.com/jbearak/sight-zed
cd sight-zed

# macOS
./install-jupyter-stata.sh

# Windows (PowerShell 7+)
pwsh -File .\install-jupyter-stata.ps1
```

## Related Projects

- [Sight LSP](https://github.com/jbearak/sight) - A language server protocol implementation for the Stata statistical programming language
- [tree-sitter-stata](https://github.com/jbearak/tree-sitter-stata) - Tree-sitter grammar for Stata

## License

GPL-3.0
