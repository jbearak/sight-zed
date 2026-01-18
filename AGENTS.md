# Agent Instructions

## Updating the LSP Version

When a new version of the Sight LSP is released:

1. Edit `src/lib.rs`
2. Update `SERVER_VERSION` constant to the new tag (e.g., `"v0.1.12"`)
3. The extension downloads binaries from GitHub releases at `jbearak/sight`

## Updating the Tree-Sitter Grammar

When the tree-sitter-stata grammar is updated:

1. Edit `extension.toml`
2. Update the `rev` field under `[grammars.stata]` to the new commit SHA
3. The grammar is fetched from `https://github.com/jbearak/tree-sitter-stata`

## Building the Extension

```bash
cargo build --release --target wasm32-wasip1
```

The compiled extension will be at `target/wasm32-wasip1/release/sight_extension.wasm`.

Copy to project root:
```bash
cp target/wasm32-wasip1/release/sight_extension.wasm extension.wasm
```

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

## Extension Build Validation

### Prerequisites

- Rust toolchain with wasm32-wasip1 target
- tree-sitter CLI
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
