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

## Why extension.wasm is Committed

Unlike typical build artifacts, `extension.wasm` is intentionally tracked in git. Zed extensions are distributed directly from git repositories — when users install an extension, Zed clones the repo and expects the pre-built WASM binary to be present. There's no build step during installation.

The `.gitignore` reflects this:
```
*.wasm
!extension.wasm
```

This excludes all `.wasm` files except `extension.wasm`. After building, you must commit the updated `extension.wasm` for users to receive the new version.

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
   - To avoid this, read the environment variable at runtime using shell test and printf:
     - `if [ -n "$ZED_SELECTED_TEXT" ]; then printf '%s' "$ZED_SELECTED_TEXT" | ...; fi`
