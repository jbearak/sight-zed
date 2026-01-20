# Agent Instructions

## Updating the LSP Version

When a new version of the Sight LSP is released:

1. Edit `src/lib.rs`
2. Update `SERVER_VERSION` constant to the new tag (e.g., `"v0.1.12"`)
3. The extension downloads binaries from GitHub releases at `jbearak/sight`

## Jupyter Stata Kernel on Windows

**IMPORTANT:** Zed's built-in REPL currently only supports Python, TypeScript (Deno), R, Julia, and Scala. Stata is not yet supported as a first-class REPL language. The installation scripts below set up `stata_kernel` for use in external Jupyter clients (Jupyter Lab, Jupyter Notebook, etc.). Zed may still be able to discover and connect to the kernels via its Jupyter integration, but behavior can vary across versions and often requires a restart (see notes below).

**PowerShell requirement:** These scripts require **PowerShell 7+** (`pwsh`). If you run them with Windows PowerShell 5.1, they will:
1. Automatically re-launch with `pwsh` if it's installed
2. Otherwise, display instructions to install PowerShell 7

To install PowerShell 7:
```powershell
winget install Microsoft.PowerShell
```

Install on Windows:

```powershell
pwsh -File .\install-jupyter-stata.ps1
```

What the installer does (Windows):
- Creates (or recreates) an isolated virtual environment at `%LOCALAPPDATA%\stata_kernel\venv`
- Installs `stata_kernel` plus a minimal, pinned Jupyter runtime needed for kernels
- Registers two kernels: **Stata** and **Stata (Workspace)**
- Writes/updates `%USERPROFILE%\.stata_kernel.conf`
- Ensures kernels are placed where Zed can discover them reliably

**Important:** After installation or upgrades, **restart Zed**. Kernel discovery/connection state can be cached; a restart is often required before the kernels can connect.

### Windows-Specific Learnings / Gotchas (Why the Script Looks “Hacky”)

#### 1) Avoid Microsoft Store Python (`WindowsApps`) for kernel discovery
Windows “App Execution Aliases” can cause `python` to resolve to the Microsoft Store shim under:
- `...\AppData\Local\Microsoft\WindowsApps\python.exe`

This can redirect Jupyter’s data dir to a non-standard location (e.g. `...\LocalCache\Roaming\jupyter`) and break kernel discovery.

**What we do:** On Windows, prefer `py -3.11` via the Python Launcher (`C:\Windows\py.exe`) so we can reliably target a real Python installation even when `python` points at the Store shim.

#### 2) Pin to Python 3.11 (especially on Windows/ARM64)
`stata_kernel` has historically worked best on Python 3.9–3.11. Newer versions (3.12/3.13) have caused repeated dependency and kernelspec issues on Windows.

**What we do:** Prefer **Python 3.11** via `py -3.11`. If the existing venv was created with a different Python, the installer **forcefully recreates** the venv to ensure consistency.

#### 3) Do NOT install the full `jupyter` meta-package on Windows
Installing the `jupyter` meta-package can pull in `notebook`/`jupyterlab` and transitive dependencies like `pywinpty`, which may require native builds (NuGet/Rust toolchain) and can fail—especially on Windows/ARM64.

**What we do:** Install only the minimal components needed for kernelspecs and kernel launching, plus only the runtime deps that `stata_kernel` actually imports:
- `jupyter-core`
- `jupyter-client`
- `ipykernel` (pinned to a Zed-compatible version)

#### 4) `stata_kernel` dependency pins are too old—install it with `--no-deps`
`stata_kernel` pins some dependencies to very old versions (e.g., `ipykernel<5`, `packaging<18`). On modern Python/Jupyter stacks this causes pip resolver backtracking and can force native builds that fail.

**What we do:** Install `stata_kernel` with `--no-deps` and then install a modern, pinned set of runtime deps explicitly (including the pinned `ipykernel`). On Windows this also includes dependencies required for imports and startup like:
- `pywin32` (provides `win32com` for Automation mode)
- `beautifulsoup4` (provides `bs4`)
- `fake-useragent`

#### 5) Avoid installing `notebook` (prevents `pywinpty` build failures)
`stata_kernel` tries to copy a CodeMirror mode file into the `notebook` package at runtime (`importlib.resources.files("notebook")...`). Installing `notebook` on Windows can pull in `pywinpty`, which may require native builds and fail (especially on Windows/ARM64).

**What we do:** Do **not** install `notebook`. Instead, the kernelspec wrappers **monkey-patch** `importlib.resources.files("notebook")` to point at a small stub directory so `stata_kernel` can start without `notebook`.

**Important:** This patch must be applied in **both** kernels:
- `stata` (standard kernel wrapper)
- `stata_workspace` (workspace wrapper)

If the workspace kernel wrapper does not include the notebook stub patch, it will hang/fail at startup with `ModuleNotFoundError: No module named 'notebook'`.

#### 6) Deterministic kernelspec registration (always write `kernel.json`)
On some Windows setups, `stata_kernel.install` can produce an incomplete kernelspec directory (e.g., `stata` exists but `kernel.json` is missing), which breaks both Jupyter and Zed discovery.

**What we do:** The installer writes the kernelspecs directly into:
- `%APPDATA%\jupyter\kernels\stata`
- `%APPDATA%\jupyter\kernels\stata_workspace`

This includes:
- `kernel.json` (required)
- small Python wrapper scripts that launch `stata_kernel` via `ipykernel` (and apply the `notebook` stub patch above)

This approach is intentionally “dumb but reliable”.

#### 7) When changing Python versions, you must rebuild the venv
If you switch Python versions (or fix Store-Python alias issues), the existing venv won’t magically follow. The installer recreates the venv automatically when it detects a non-preferred version.


### Kernel Differences

| Kernel | Working Directory | Use Case |
|--------|-------------------|----------|
| **Stata** | File's directory | Scripts with paths relative to the script location |
| **Stata (Workspace)** | Workspace root | Scripts with paths relative to the project root |

### Workspace Detection

The "Stata (Workspace)" kernel walks up from the file's directory looking for these marker files:
1. `.git` — Git repository root
2. `.stata-project` — Stata-specific project marker
3. `.project` — Generic project marker

### Using the Kernels

Since Zed doesn't support Stata REPL yet, use the installed kernels with external Jupyter clients:

```bash
# Start Jupyter Lab
jupyter lab

# Or Jupyter Notebook
jupyter notebook
```

Both kernels (stata and stata_workspace) will be available in the kernel selection menu.

### Uninstallation

To uninstall:
```powershell
.\install-jupyter-stata.ps1 --uninstall
```

To uninstall including config:
```powershell
.\install-jupyter-stata.ps1 --uninstall --remove-config
```

## Updating the Tree-Sitter Grammar

When the tree-sitter-stata grammar is updated:

1. Edit `extension.toml`
2. Update the `rev` field under `[grammars.stata]` to the new commit SHA
3. The grammar is fetched from `https://github.com/jbearak/tree-sitter-stata`

## Building the Extension

### macOS / Linux

```bash
cargo build --release --target wasm32-wasip1
cp target/wasm32-wasip1/release/sight_extension.wasm extension.wasm
```

### Windows

Use the PowerShell setup script:

```powershell
.\setup.ps1 -Yes
```

This handles:
- Installing build dependencies (Rust, MSVC, WASI SDK)
- Building the extension WASM
- Downloading the pre-built grammar WASM
- Installing to Zed's extensions directory

## Why extension.wasm is Committed

Unlike typical build artifacts, `extension.wasm` is intentionally tracked in git. Zed extensions are distributed directly from git repositories — when users install an extension, Zed clones the repo and expects the pre-built WASM binary to be present. There's no build step during installation.

The `.gitignore` reflects this:
```
*.wasm
!extension.wasm
!/grammars/stata.wasm
```

This excludes all `.wasm` files except `extension.wasm` and the pre-built grammar. After building, you must commit the updated WASM files for users to receive the new version.

## Windows Architecture

Windows requires special handling due to several platform-specific limitations:

### Problem 1: Sight LSP Binary Crashes on Windows

The pre-built `sight-windows-x64.exe` binary from the Sight releases crashes immediately on startup (exits with no output). This appears to be a bug in how the Sight LSP is compiled for Windows.

**Solution**: On Windows, the extension uses Zed's embedded Node.js to run `sight-server.js` (a bundled JavaScript version of the LSP) instead of the native binary.

```rust
// In src/lib.rs
if platform == zed::Os::Windows {
    let node_path = zed::node_binary_path()?;
    let server_script = self.get_node_server_path()?;
    // Run: node sight-server.js --stdio
}
```

The `sight-server.js` file is downloaded from the same GitHub release as the native binaries.

### Problem 2: Zed Cannot Compile Tree-Sitter Grammars on Windows

Zed compiles tree-sitter grammars to WASM internally, but this compilation fails on Windows. The grammar compilation requires a working WASM toolchain that Zed doesn't have access to on Windows.

**Solution**: We pre-build the grammar WASM and distribute it with the extension.

The grammar WASM is:
1. Built on macOS/Linux using the WASI SDK
2. Published to tree-sitter-stata releases as `tree-sitter-stata.wasm`
3. Downloaded by `setup.ps1` and placed in `grammars/stata.wasm`
4. Committed to git (exception in `.gitignore`)
5. Referenced in `extension.toml` with `[grammars.stata]` and `path = "grammars/stata.wasm"`

**Critical**: The `extension.toml` must include:
```toml
[grammars.stata]
path = "grammars/stata.wasm"
```

This tells Zed to use the pre-built WASM instead of compiling from source. Without this section, Zed won't load the grammar even if the WASM file is present.

### Problem 3: Extension WASM Compilation on Windows

Building Rust to `wasm32-wasip1` on Windows requires:
- MSVC build tools (for the linker)
- WASI SDK (for WASM-specific libc)
- Rust with the `wasm32-wasip1` target

The `setup.ps1` script handles installing all these dependencies via Chocolatey.

### Windows File Layout

After running `setup.ps1`, the extension includes:

```
sight-zed/
├── extension.wasm          # Rust extension compiled to WASM
├── grammars/
│   └── stata.wasm          # Pre-built tree-sitter grammar (downloaded)
├── languages/
│   └── stata/
│       └── *.scm           # Syntax highlighting queries
└── extension.toml          # Extension manifest
```

When installed to Zed:
```
%APPDATA%\Zed\extensions\installed\sight\
├── extension.wasm
├── grammars/
│   └── stata.wasm
├── languages/
│   └── stata/
│       └── *.scm
└── extension.toml
```

### LSP Binary Resolution by Platform

| Platform | LSP Approach |
|----------|--------------|
| macOS (ARM64) | Native binary: `sight-darwin-arm64` |
| macOS (x64) | Native binary: `sight-darwin-arm64` (via Rosetta) |
| Linux (ARM64) | Native binary: `sight-linux-arm64` |
| Linux (x64) | Native binary: `sight-linux-x64` |
| Windows | Node.js: `node sight-server.js --stdio` |

### Updating for Windows

When releasing a new version:

1. Update `SERVER_VERSION` in `src/lib.rs`
2. Ensure the release includes `sight-server.js` (for Windows Node.js fallback)
3. If the grammar changed, rebuild and publish `tree-sitter-stata.wasm`
4. Run `setup.ps1` on Windows to verify everything works

## Installing the Extension Locally

For development/testing in Zed:

1. Build the extension (see above)
2. Open Zed
3. Use "zed: Install Dev Extension" command
4. Select this directory

Or symlink to Zed's extensions directory:
```bash
ln -s $(pwd) ~/.local/share/zed/extensions/installed/sight
```

## Depth Colorization (Not Currently Functional)

The `highlights.scm` file contains depth-based captures for nested strings and macros:
- `@string.depth.1` through `@string.depth.6` for compound strings
- `@variable.macro.local.depth.1` through `@variable.macro.local.depth.6` for local macros

**These captures currently do nothing in Zed.** Zed themes only support a fixed set of highlight captures (`@string`, `@variable`, `@keyword`, etc.). Custom captures like `@string.depth.1` fall back to the base capture or are ignored entirely.

The depth-aware node types in the grammar (`compound_string_depth_1-6`, `local_macro_depth_1-6`) are **shared with the VS Code extension**, which does support depth colorization via TextMate scope injection. Don't remove these from the grammar.

The depth captures in `highlights.scm` are kept as:
1. Documentation of intended behavior
2. Future-proofing if Zed adds custom capture support
3. They're harmless - just fall back to base styling

If Zed adds support for custom theme captures in the future, these would enable depth-based colorization without grammar changes.

## Auto-Closing Pairs Limitation

The `not_in = ["string"]` constraint on double quotes prevents auto-closing inside strings, including compound strings. This means when typing `` `"text"' ``, you must manually type the closing `"`.

**Do not remove this constraint.** Without it, typing `"` inside a compound string produces broken behavior where the first quote does nothing, then typing a second quote produces `"""`, requiring backspace to fix.

This is a Zed API limitation - extensions cannot distinguish between regular strings and compound strings, or programmatically control auto-closing behavior. The current configuration is the least-bad option.

## Extension Build Validation

### Prerequisites

- Rust toolchain with wasm32-wasip1 target (`rustup target add wasm32-wasip1`)
- tree-sitter CLI (`npm install -g tree-sitter-cli`)
- curl
- git

### Running Validation

Full validation suite:
```bash
./validate.sh
```

Individual checks:
```bash
./validate.sh --lsp          # Check LSP version
./validate.sh --grammar-rev  # Check grammar revision
./validate.sh --build        # Test extension build
./validate.sh --grammar-build # Test grammar build
```

### Environment Variables

- `GITHUB_TOKEN`: Optional, prevents API rate limiting when checking versions


## Zed Tasks Gotchas

When creating Zed tasks (`~/.config/zed/tasks.json`):

### Args Array Does Not Work

**Do not use the `args` array.** Zed does not reliably pass the `args` array to the command. Put all arguments in the `command` string instead.

Bad (args not passed):
```json
{
  "label": "My Task",
  "command": "my-script.sh",
  "args": ["--file", "$ZED_FILE"]
}
```

Good (args in command string):
```json
{
  "label": "My Task",
  "command": "my-script.sh --file \"$ZED_FILE\""
}
```

### Variable Default Syntax

Zed uses `${VAR:default}` (no dash) for default values, not shell's `${VAR:-default}`.

- Shell syntax: `${ZED_SELECTED_TEXT:-}` ❌
- Zed syntax: `${ZED_SELECTED_TEXT:}` ✓

### Task Filtering

Zed filters out tasks when referenced variables are not available. Use default values to ensure tasks always appear:

```json
{
  "command": "echo \"${ZED_SELECTED_TEXT:no selection}\""
}
```

Without the default, this task would only appear when text is selected.

### Quoting & Compound Strings (Critical)

When tasks run through `/bin/zsh -i -c`, there are two easy ways to break quoting:

1. Do not double-escape quotes inside the JSON `command`.
   - Correct (JSON contains `\"` to produce a literal `"` in the command string): `\"$ZED_FILE\"`
   - Incorrect: `\\\"$ZED_FILE\\\"` (the backslashes become literal characters, so the script receives a filename that includes `"` and file checks fail).

2. Do not inline the selected text into the command using Zed interpolation (`${ZED_SELECTED_TEXT:}`) when you need to support backticks.
   - Zed interpolation happens before the shell parses the command; if the selection contains backticks (Stata compound strings like `` `\"1234\"' ``), zsh will attempt command substitution and you can get parse errors like `parse error near else`.
   - **CRITICAL**: You MUST use python3 to read `$ZED_SELECTED_TEXT` without shell interpretation:
     - `python3 -c 'import os,sys; sys.stdout.write(os.environ.get("ZED_SELECTED_TEXT",""))'`
   - **DO NOT** use shell variable expansion like `printf '%s' "$ZED_SELECTED_TEXT"` or `[ -n "$ZED_SELECTED_TEXT" ]`. The shell will interpret quotes, backticks, and special characters in the variable, breaking compound strings.
   - Python3 reads the raw bytes from the environment without any parsing. This is the only safe approach.

## Send-to-Stata Keybindings

In `.do` files:

| Shortcut | Action |
|----------|--------|
| `cmd-enter` | Send statement to Stata (uses `do`) |
| `shift-cmd-enter` | Send file to Stata (uses `do`) |
| `alt-cmd-enter` | Include statement (preserves local macros) |
| `alt-shift-cmd-enter` | Include file (preserves local macros) |
| `shift-enter` | Send selection to Stata terminal (quick paste) |
| `alt-enter` | Send current line to Stata terminal (quick paste) |

In user-facing docs, we write "opt" instead of "alt" because that is how the "alt" key is labeled on Mac keyboards.

See [SEND-TO-STATA.md](SEND-TO-STATA.md) for full documentation.

## Updating send-to-stata.sh

The installer (`install-send-to-stata.sh`) embeds a SHA-256 checksum of `send-to-stata.sh` for integrity verification during curl-pipe installation. When modifying `send-to-stata.sh`:

1. Make your changes to `send-to-stata.sh`
2. Run `./update-checksum.sh` — this updates the checksum in the installer and commits the change
3. Commit `send-to-stata.sh` separately (or amend the checksum commit)

The checksum ensures the two scripts stay in sync and detects accidental mismatches or CDN caching issues. It doesn't protect against a compromised GitHub account (an attacker could modify both files). Verification is skipped when users specify a custom `SIGHT_GITHUB_REF` for testing branches.

If you forget to update the checksum, curl-pipe installations will fail with a checksum mismatch error.

## Updating send-to-stata executables checksum on Windows

Use `update-checksum.ps1` (PowerShell 7+):

1. Rebuild the executables (see "Building the Native Executable" below)
2. Run `pwsh -File update-checksum.ps1` from repo root
3. It recalculates SHA-256 for both `send-to-stata-arm64.exe` and `send-to-stata-x64.exe`, updates `install-send-to-stata.ps1`, and auto-commits
4. Use `-DryRun` to see the new hashes without modifying files

The installer verifies checksums when downloading from GitHub. Verification is skipped when users specify a custom `SIGHT_GITHUB_REF` for testing branches.

## Updating setup.ps1 dependency checksums

Use `update-setup-checksums.ps1` (PowerShell 7+) when upstream dependencies release new versions:

1. Run `pwsh -File update-setup-checksums.ps1` from repo root
2. It downloads WASI SDK, tree-sitter-stata grammar, and Sight language server
3. Calculates SHA-256 checksums and updates `setup.ps1`
4. Auto-commits the changes
5. Use `-DryRun` to see the new hashes without modifying files

The checksums are verified during `setup.ps1` execution to detect corrupted downloads.

## Windows Send-to-Stata Architecture

On Windows, Send-to-Stata uses a native C# executable (`send-to-stata.exe`) instead of PowerShell for fast startup (~10x faster than PowerShell).

### Building the Native Executable

The source is in `send-to-stata/`. To rebuild:

```powershell
cd send-to-stata
dotnet publish -c Release -r win-x64    # For Intel/AMD
dotnet publish -c Release -r win-arm64  # For ARM64

# Copy to repo root
cp bin/Release/net8.0-windows/win-x64/publish/send-to-stata.exe ../send-to-stata-x64.exe
cp bin/Release/net8.0-windows/win-arm64/publish/send-to-stata.exe ../send-to-stata-arm64.exe
```

Both binaries are committed to the repo. The installer detects architecture and copies the correct one.

After rebuilding, run `pwsh -File update-checksum.ps1` to update the checksums in `install-send-to-stata.ps1`.

### Executable Parameters

| Parameter | Description |
|-----------|-------------|
| `-Statement` | Send single statement mode |
| `-FileMode` | Send entire file mode |
| `-Include` | Use `include` instead of `do` |
| `-File <path>` | Path to .do file (required) |
| `-Row <n>` | Line number for statement mode |
| `-ReturnFocus` | Return focus to Zed after sending |
| `-ClipPause <ms>` | Delay after clipboard copy (default: 10) |
| `-WinPause <ms>` | Delay between window operations (default: 10) |
| `-KeyPause <ms>` | Delay between keystrokes (default: 1) |

### Installer Parameters

The `install-send-to-stata.ps1` script accepts:

| Parameter | Description |
|-----------|-------------|
| `-Uninstall` | Remove Send-to-Stata |
| `-RegisterAutomation` | Force re-register Stata automation |
| `-SkipAutomationCheck` | Skip Stata automation registration check |
| `-ReturnFocus <value>` | Focus behavior: `true`, `false`, or omit to prompt |

For CI/CD, pass `-ReturnFocus true` or `-ReturnFocus false` to skip the interactive prompt:

```powershell
# Non-interactive install with return focus enabled
.\install-send-to-stata.ps1 -SkipAutomationCheck -ReturnFocus true

# Non-interactive install with return focus disabled
.\install-send-to-stata.ps1 -SkipAutomationCheck -ReturnFocus false
```

## Jupyter Stata Kernel Variants

The `install-jupyter-stata.sh` installer creates two Jupyter kernels:

| Kernel | Working Directory | Use Case |
|--------|-------------------|----------|
| **Stata** | File's directory | Scripts that use paths relative to the script location |
| **Stata (Workspace)** | Workspace root | Scripts that use paths relative to the project root |

### How Workspace Detection Works

The "Stata (Workspace)" kernel walks up from the file's directory looking for these marker files (in order):
1. `.git` — Git repository root
2. `.stata-project` — Stata-specific project marker
3. `.project` — Generic project marker

If no marker is found, it falls back to the file's directory (same as the standard kernel).

### Setting a Default Kernel

Users can set a default kernel in `~/.config/zed/settings.json`:

```json
{
  "jupyter": {
    "kernel_selections": {
      "stata": "stata_workspace"
    }
  }
}
```

### Why Two Kernels?

Zed's REPL starts kernels in the file's directory, not the workspace root. This breaks Stata code that uses relative paths expecting to run from the project root (e.g., `use "data/mydata.dta"`). The workspace kernel solves this by changing to the project root before starting Stata.

The standard kernel is kept for scripts that intentionally use paths relative to the script's location.
