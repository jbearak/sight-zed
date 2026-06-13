# Development Setup Tools

This directory contains scripts for setting up a development environment to build and test the Stata Zed extension.

## Overview

The dev setup scripts automate the installation of build dependencies, compile the extension, and configure the local development environment. They also install the Send-to-Stata and Jupyter kernel integrations for testing.

## Prerequisites

### macOS

- **Rust toolchain**: Install via [rustup](https://rustup.rs/)
  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  ```
- **WASM target**: Required for building Zed extensions
  ```bash
  rustup target add wasm32-wasip1
  ```
- **Homebrew**: Required for installing tree-sitter CLI
  ```bash
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```

### Windows

- **PowerShell 7+**: Required for the setup script
  ```powershell
  winget install Microsoft.PowerShell
  ```
- The setup script will automatically install other dependencies via Chocolatey:
  - Rust toolchain
  - Visual Studio 2022 Build Tools (C++ workload)
  - WASI SDK
  - Git, CMake, Ninja, Python, LLVM (for tree-sitter)

## Running the Dev Setup

### macOS

```bash
./tools/dev/dev-setup-macos.sh
```

This will:
1. Check prerequisites (Rust, WASM target, tree-sitter)
2. Build the extension WASM (`extension.wasm`)
3. Build the tree-sitter grammar (`grammars/stata/stata.wasm`)
4. Create a symlink in Zed's extensions directory
5. Install Send-to-Stata keybindings and tasks
6. Install Jupyter Stata kernel

To uninstall:
```bash
./tools/dev/dev-setup-macos.sh --uninstall
```

### Windows

```powershell
pwsh -File .\tools\dev\dev-setup-windows.ps1
```

Or with auto-confirmation for all prompts:
```powershell
pwsh -File .\tools\dev\dev-setup-windows.ps1 -Yes
```

This will:
1. Install build dependencies (Chocolatey, Rust, MSVC, WASI SDK, etc.)
2. Build the extension WASM (`extension.wasm`)
3. Download pre-built tree-sitter grammar (Windows cannot compile grammars) from
   the [tree-sitter-stata releases](https://github.com/jbearak/tree-sitter-stata/releases),
   pinned to a known tag (currently `v0.1.1`) and checksum-verified
4. Download the language server for dev testing
5. Copy extension files to Zed's extensions directory
6. Install Send-to-Stata integration

To uninstall:
```powershell
pwsh -File .\tools\dev\dev-setup-windows.ps1 -Uninstall
```

#### Windows Script Options

| Parameter | Description |
|-----------|-------------|
| `-Yes` | Auto-confirm all prompts |
| `-SkipBuild` | Skip building the extension |
| `-SkipExtensionInstall` | Skip installing to Zed |
| `-SkipSendToStata` | Skip Send-to-Stata installation |
| `-RegisterAutomation` | Force re-register Stata automation |
| `-SkipAutomationCheck` | Skip Stata automation check |

## Building the Extension Manually

> **Note:** `extension.wasm` is gitignored and is **not** committed — Zed compiles
> it from source (the marketplace CI runs `extension_cli` against the repo, and
> `zed: install dev extension` compiles locally via rustup). You build it locally
> here only because the dev-setup scripts symlink/copy the repo into Zed's
> `extensions/installed` directory, where Zed loads the pre-built file directly
> instead of recompiling.

If you prefer to build manually without running the full setup:

### macOS

```bash
# Build extension WASM
cargo build --release --target wasm32-wasip1
cp target/wasm32-wasip1/release/zed_stata.wasm extension.wasm

# Build grammar (requires tree-sitter CLI)
cd grammars/stata
tree-sitter build --wasm -o stata.wasm
```

### Windows

```powershell
# Build extension WASM (requires MSVC environment)
cargo build --release --target wasm32-wasip2
copy target\wasm32-wasip2\release\zed_stata.wasm extension.wasm

# Grammar must be downloaded (Windows cannot compile tree-sitter grammars).
# dev-setup-windows.ps1 fetches the pre-built grammars/stata.wasm from
# https://github.com/jbearak/tree-sitter-stata/releases (pinned to v0.1.1,
# checksum-verified) and removes any grammars/stata/ source dir so Zed won't
# try to compile it.
```

## Installing the Extension Locally

After building, you can install the extension in Zed:

1. Open Zed
2. Run command: `zed: Install Dev Extension`
3. Select this repository directory

Or create a symlink manually:

**macOS:**
```bash
ln -s "$(pwd)" "$HOME/Library/Application Support/Zed/extensions/installed/stata"
```

**Windows:**
The setup script copies files to `%LOCALAPPDATA%\Zed\extensions\installed\stata\`

## Checksum Update Scripts

These scripts update embedded checksums when dependencies change.

### update-send-to-stata-checksum.sh (macOS)

Run this after modifying `tools/send-to-stata/send-to-stata.sh`:

```bash
./tools/dev/update-send-to-stata-checksum.sh
```

This updates the SHA-256 checksum in `tools/send-to-stata/install-macos.sh` and commits the change. The checksum is verified during curl-pipe installation to ensure integrity.

### update-dev-checksums.ps1 (Windows)

Run this when upstream dependencies release new versions:

```powershell
pwsh -File .\tools\dev\update-dev-checksums.ps1
```

Or preview changes without modifying files:
```powershell
pwsh -File .\tools\dev\update-dev-checksums.ps1 -DryRun
```

This downloads and checksums:
- WASI SDK
- tree-sitter-stata grammar WASM
- Sight language server

Then updates `dev-setup-windows.ps1` and commits the changes.

## Troubleshooting

### macOS: "wasm32-wasip1 target not installed"

```bash
rustup target add wasm32-wasip1
```

### macOS: "tree-sitter not found"

```bash
brew install tree-sitter
```

### Windows: "PowerShell 7+ required"

```powershell
winget install Microsoft.PowerShell
```

Then run with `pwsh` instead of `powershell`.

### Windows: "MSVC build tools not found"

The setup script should install these automatically. If it fails, install manually:
1. Download [Visual Studio Build Tools](https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022)
2. Select "Desktop development with C++" workload
3. Restart your terminal and re-run the setup script

### Extension not loading in Zed

1. Restart Zed completely (Cmd+Q / Alt+F4)
2. Check Zed's extension logs for errors
3. Verify `extension.wasm` exists in the repo root
4. On Windows, verify `grammars/stata.wasm` exists
