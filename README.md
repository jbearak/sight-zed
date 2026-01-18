# Sight - Zed Extension for Stata

A Zed editor extension providing Stata language support using the [Sight LSP](https://github.com/jbearak/sight).

## Features

- Syntax highlighting via tree-sitter grammar
- Language server integration with Sight LSP
- Code completion, hover information, and diagnostics

## Installation

Install from the Zed extension marketplace by searching for "Sight" or "Stata".

## Building from Source

```bash
# Build the extension
cargo build --release --target wasm32-wasip1

# The extension.wasm will be in target/wasm32-wasip1/release/
```

## Related Projects

- [Sight LSP](https://github.com/jbearak/sight) - A language server protocol implementation for the Stata statistical programming language
- [tree-sitter-stata](https://github.com/jbearak/tree-sitter-stata) - Tree-sitter grammar for Stata

## License

GPL-3.0
