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

Execute Stata code directly from Zed with keyboard shortcuts. Works with both the Stata application (via AppleScript) and terminal sessions (via paste).

**Install (macOS only):**

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

> **Why a separate install?** Zed extensions can't register custom keybindings or tasks—those must live in user config files (`~/.config/zed/`). The send-to-stata functionality requires both, so it can't be bundled into the extension itself.

See [SEND-TO-STATA.md](SEND-TO-STATA.md) for full documentation, configuration options, and troubleshooting.

## Jupyter REPL (Optional)

Execute Stata code in Zed's built-in REPL panel using [stata_kernel](https://kylebarron.dev/stata_kernel/). This provides an interactive environment without switching to the Stata application.

**Install (macOS only):**

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jbearak/sight-zed/main/install-jupyter-stata.sh)"
```

**Usage:**
1. Open a `.do` file
2. Open the REPL panel (View → Toggle REPL)
3. Select "Stata" as the kernel

**Configuration:** The installer creates `~/.stata_kernel.conf` with auto-detected settings. Edit this file to customize graph format, cache directory, and other options. See the [stata_kernel documentation](https://kylebarron.dev/stata_kernel/using_stata_kernel/configuration/) for all options.

**Uninstall:**

```bash
./install-jupyter-stata.sh --uninstall
```

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
