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

| Shortcut | Action |
|----------|--------|
| `cmd-enter` | Send statement to Stata app |
| `shift-cmd-enter` | Send file to Stata app |
| `opt-cmd-enter` | Include statement (preserves locals) |
| `opt-shift-cmd-enter` | Include file (preserves locals) |
| `shift-enter` | Paste selection to terminal |
| `opt-enter` | Paste current line to terminal |

### Why Separate Installation?

Zed extensions can't register custom keybindings or tasks—those must live in user config files (`~/.config/zed/`). The send-to-stata functionality requires both, so it can't be bundled into the extension itself.

### Quick Install (macOS only)

```bash
git clone https://github.com/jbearak/sight-zed
cd sight-zed
./install-send-to-stata.sh
```

See [SEND-TO-STATA.md](SEND-TO-STATA.md) for full documentation, configuration options, and troubleshooting.

## Building from Source

```bash
# Build the extension
cargo build --release --target wasm32-wasip1

# The extension.wasm will be in target/wasm32-wasip1/release/
```

## Related Projects

- [Sight LSP](https://github.com/jbearak/sight) - The Stata language server
- [tree-sitter-stata](https://github.com/jbearak/tree-sitter-stata) - Tree-sitter grammar for Stata

## License

GPL-3.0
