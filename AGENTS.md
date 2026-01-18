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
