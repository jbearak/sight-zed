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

> **Note:** stata_kernel works well for interactive exploration but can hang on long-running loops or operations taking more than several seconds. For batch scripts or iterative workflows, use [Send to Stata](#send-to-stata-optional) instead. See [comparison table](#choosing-between-send-to-stata-and-jupyter-repl) below.

**Install (macOS only):**

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jbearak/sight-zed/main/install-jupyter-stata.sh)"
```

**Usage:**
1. Open a `.do` file
2. Open the REPL panel (View → Toggle REPL)
3. Select a kernel:
   - **Stata** — starts in the file's directory
   - **Stata (Workspace)** — starts in the workspace root (looks for project markers)

### Choosing a Kernel

| Kernel | Working Directory | Best For |
|--------|-------------------|----------|
| Stata | File's directory | Scripts with paths relative to the script |
| Stata (Workspace) | Project root | Scripts with paths relative to the project root |

The workspace kernel walks up from the file's directory looking for `.git`, `.stata-project`, or `.project` markers to find the project root. If no marker is found, it falls back to the file's directory.

### Setting a Default Kernel

Add to `~/.config/zed/settings.json`:

```json
{
  "jupyter": {
    "kernel_selections": {
      "stata": "stata_workspace"
    }
  }
}
```

**Configuration:** The installer creates `~/.stata_kernel.conf` with auto-detected settings. Edit this file to customize graph format, cache directory, and other options.

## Choosing Between Send-to-Stata and Jupyter REPL

| Scenario | Recommended | Why |
|----------|-------------|-----|
| Quick data exploration | Jupyter REPL | Inline results, fast iteration |
| Testing individual commands | Jupyter REPL | Interactive feedback |
| Loops with many iterations | Send to Stata | Avoids kernel hang issues |
| Operations > several seconds | Send to Stata | No completion detection overhead |
| Graph-heavy workflows | Send to Stata | Graphs can trigger kernel hangs |
| Production batch jobs | Send to Stata | Reliable unattended execution |

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
