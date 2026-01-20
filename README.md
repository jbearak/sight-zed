# Sight - Zed Extension for Stata

A Zed editor extension providing Stata language support using the [Sight LSP](https://github.com/jbearak/sight).

## Features

- Syntax highlighting via tree-sitter grammar
- Language server integration with Sight LSP
- Code completion, hover information, and diagnostics
- Send code to Stata with keyboard shortcuts (requires additional setup—see below)

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

Requires PowerShell 5.0+ (included with Windows 10/11).

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

**Focus behavior:** The installer prompts whether to return focus to Zed after sending code to Stata. For CI/CD or scripted installs, use `-ReturnFocus`:

```powershell
# Return focus to Zed (recommended for iterative coding)
irm .../install-send-to-stata.ps1 -OutFile i.ps1; .\i.ps1 -ReturnFocus true

# Stay in Stata (useful for inspecting output)
irm .../install-send-to-stata.ps1 -OutFile i.ps1; .\i.ps1 -ReturnFocus false
```

> **Why a separate install?** Zed extensions can't register custom keybindings or tasks—those must live in user config files. The send-to-stata functionality requires both, so it can't be bundled into the extension itself.

See [SEND-TO-STATA.md](SEND-TO-STATA.md) for full documentation, configuration options, and troubleshooting.

## Jupyter REPL (Not Yet Supported)

**Note:** Zed's built-in REPL currently only supports Python, TypeScript (Deno), R, Julia, and Scala. Stata is not yet supported, even with the Jupyter kernels installed.

However, you can still install [stata_kernel](https://kylebarron.dev/stata_kernel/) for use in Jupyter Lab/Notebook or other Jupyter clients outside of Zed.

### Windows Notes (Installer Behavior)

On Windows, `install-jupyter-stata.ps1` is intentionally opinionated to be reliable across Python/Jupyter setups:

- **Uses Python 3.11 via the Python Launcher (`py -3.11`)** when available (stata_kernel is most stable on 3.9–3.11; newer versions have caused dependency and kernelspec issues).
- **Recreates the venv if needed** to ensure the venv is actually using Python 3.11.
- **Installs only minimal Jupyter components** (`jupyter-core`, `jupyter-client`, and a pinned `ipykernel`) instead of the full `jupyter` meta-package to avoid pulling in `notebook`/`jupyterlab` and native build dependencies (e.g. `pywinpty`).
- **Writes kernelspecs deterministically** into `%APPDATA%\jupyter\kernels\...` (including `kernel.json`) so Zed can discover them reliably.

### macOS

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jbearak/sight-zed/main/install-jupyter-stata.sh)"
```

### Windows

Requires **PowerShell 7+** (`pwsh`). Windows PowerShell 5.1 may fail to parse the installer.

```powershell
irm https://raw.githubusercontent.com/jbearak/sight-zed/main/install-jupyter-stata.ps1 | pwsh -NoProfile -ExecutionPolicy Bypass -File -
```

**Important:** After installing or updating the Jupyter kernels, **restart Zed**. Kernel discovery/connection state can be cached, and a restart is often required before the kernels can connect successfully. The installer adds the Jupyter virtual environment to your PATH so Zed can discover the kernels.

After installation, you can use the kernels with `jupyter lab` or `jupyter notebook`:

```bash
# Start Jupyter Lab with access to Stata kernels
jupyter lab
```

### Available Kernels

| Kernel | Working Directory | Use Case |
|--------|-------------------|----------|
| Stata | File's directory | Scripts with paths relative to the script location |
| Stata (Workspace) | Project root | Scripts with paths relative to the project root |

The workspace kernel walks up from the file's directory looking for `.git`, `.stata-project`, or `.project` markers to find the project root.

**Configuration:** The installer creates `~/.stata_kernel.conf` (or `%USERPROFILE%\.stata_kernel.conf` on Windows) with auto-detected settings. Edit this file to customize graph format, cache directory, and other options.

> **Future Support:** If you'd like to see Stata REPL support added to Zed, consider opening a feature request on the [Zed GitHub repository](https://github.com/zed-industries/zed/issues).


## Building from Source

### Zed Extension

```bash
cargo build --release --target wasm32-wasip1

# The extension.wasm will be in target/wasm32-wasip1/release/
```

### Send-to-Stata

If you prefer to install from a local clone instead of curl-pipe:

```bash
git clone https://github.com/jbearak/sight-zed
cd sight-zed
./install-send-to-stata.sh
```

### Jupyter Kernel

Install stata_kernel from a local clone:

```bash
git clone https://github.com/jbearak/sight-zed
cd sight-zed
./install-jupyter-stata.sh
```

## Related Projects

- [Sight LSP](https://github.com/jbearak/sight) - The Stata language server
- [tree-sitter-stata](https://github.com/jbearak/tree-sitter-stata) - Tree-sitter grammar for Stata

## License

GPL-3.0
