# Development Guide

This document covers development setup and workflows for the zed-stata extension.

## Directory Structure

```
zed-stata/
├── .claude/                    # Claude Code settings
├── .github/
│   └── workflows/              # GitHub Actions workflows
│       ├── auto-release.yml    # Auto-release on version bump
│       ├── update-send-to-stata.yml    # Update send-to-stata from releases
│       └── update-sight-version.yml    # Update Sight LSP version
├── .kiro/                      # Kiro specs for features
├── grammars/
│   └── stata/                  # Tree-sitter grammar submodule
├── languages/
│   └── stata/
│       ├── brackets.scm        # Bracket matching rules
│       ├── config.toml         # Language configuration
│       ├── highlights.scm      # Syntax highlighting queries
│       ├── indents.scm         # Indentation rules
│       ├── outline.scm         # Code outline queries
│       ├── overrides.scm       # Scope overrides
│       └── tasks.json          # Extension-provided tasks
├── src/
│   └── lib.rs                  # Zed extension entry point
├── target/                     # Rust build artifacts (ignored)
├── tests/                      # Test suites
│   ├── *.bats                  # Bash Automated Testing System tests
│   ├── *.Tests.ps1             # Pester tests for PowerShell
│   └── fixtures/               # Test fixtures
├── tools/
│   ├── send-to-stata/
│   │   ├── README.md           # Send-to-Stata documentation
│   │   ├── install-macos.sh    # macOS installer
│   │   ├── install-windows.ps1 # Windows installer
│   │   └── send-to-stata.sh    # Main script (macOS only)
│   ├── jupyter-kernel/
│   │   ├── README.md           # Jupyter kernel documentation
│   │   ├── install-macos.sh    # macOS installer
│   │   └── install-windows.ps1 # Windows installer
│   └── dev/
│       ├── README.md           # Development setup documentation
│       ├── dev-setup-macos.sh  # macOS dev environment setup
│       ├── dev-setup-windows.ps1 # Windows dev environment setup
│       ├── update-send-to-stata-checksum.sh  # Updates checksum in installer
│       ├── update-dev-checksums.ps1          # Updates checksums in dev-setup
│       ├── update_version.sh   # Version bump automation
│       └── validate.sh         # Build and dependency validation
├── tree-sitter-stata/          # Tree-sitter grammar (git submodule)
│
├── Cargo.toml                  # Rust project manifest
├── Cargo.lock                  # Rust dependency lockfile
├── extension.toml              # Zed extension manifest
├── extension.wasm              # Built extension (gitignored; Zed builds from source)
│
├── AGENTS.md                   # AI agent instructions
├── DEVELOPMENT.md              # Development guide (this file)
├── LICENSE                     # GPLv3 license
└── README.md                   # User-facing documentation
```

## Prerequisites

### macOS/Linux

- Rust toolchain with wasm32-wasip1 target: `rustup target add wasm32-wasip1`
- tree-sitter CLI: `npm install -g tree-sitter-cli`
- For tests: [bats-core](https://github.com/bats-core/bats-core)

### Windows

- PowerShell 7+ (`winget install Microsoft.PowerShell`)
- The `tools/dev/dev-setup-windows.ps1` script handles most dependencies

## Building

### Extension WASM

```bash
# macOS/Linux
cargo build --release --target wasm32-wasip1
cp target/wasm32-wasip1/release/zed_stata.wasm extension.wasm

# Windows (via dev-setup-windows.ps1)
.\tools\dev\dev-setup-windows.ps1 -Yes
```

## Testing

### Validation Suite

```bash
# Run all validations
./tools/dev/validate.sh

# Individual checks
./tools/dev/validate.sh --lsp          # Check LSP version
./tools/dev/validate.sh --grammar-rev  # Check grammar revision
./tools/dev/validate.sh --build        # Test extension build
./tools/dev/validate.sh --grammar-build # Test grammar build
```

### BATS Tests (macOS/Linux)

```bash
# Run all tests
bats tests/

# Run specific test file
bats tests/send_to_stata.bats
```

### Pester Tests (Windows)

```powershell
Invoke-Pester tests/*.Tests.ps1
```

## Installing Locally

For development/testing:

1. Build the extension
2. In Zed, run "zed: Install Dev Extension"
3. Select this directory

Or symlink:
```bash
ln -s $(pwd) ~/.local/share/zed/extensions/installed/stata
```

## Version Management

### Updating Extension Version

Use the version bump script:
```bash
./tools/dev/update_version.sh 0.5.1
```

This updates:
- `Cargo.toml` `[package].version`
- top-level `extension.toml` `version`
- Creates a git commit and tag

It does **not** update `extension.toml [lib].version`. That field tracks the Zed
extension API version and should stay aligned with `Cargo.toml`
`zed_extension_api`.

Guardrails:
- `./tools/dev/validate.sh --release-version` checks that `Cargo.toml [package].version` and top-level `extension.toml version` match
- `./tools/dev/validate.sh --api-version` checks that `extension.toml [lib].version` matches `Cargo.toml zed_extension_api`

### Updating Sight LSP Version

1. Edit `src/lib.rs`
2. Update `SERVER_VERSION` constant (e.g., `"v0.1.21"`)

### Updating Tree-Sitter Grammar

1. Edit `extension.toml`
2. Update the `rev` field under `[grammars.stata]`

## How extension.wasm is Built

`extension.wasm` is **not** committed — Zed compiles it from source. For the
marketplace, Zed's CI runs `extension_cli` against this repo and compiles
`src/lib.rs` (and the tree-sitter grammar) to WebAssembly, packaging an archive
that users download. For `zed: install dev extension`, Zed compiles the Rust
locally via your rustup toolchain.

The dev-setup scripts build `extension.wasm` locally because they symlink/copy
the repo into Zed's `extensions/installed` directory, where Zed loads the
pre-built file instead of recompiling. The file is gitignored (`*.wasm`), so
build it locally — you don't commit it. See "How extension.wasm Is Built" in
AGENTS.md for details.

## Checksum Updates

After modifying scripts, update their checksums:

```bash
# macOS send-to-stata.sh checksum
./tools/dev/update-send-to-stata-checksum.sh

# Windows dev-setup dependency checksums
pwsh -File tools/dev/update-dev-checksums.ps1
```

## GitHub Actions

- **auto-release.yml**: Creates GitHub releases when version tags are pushed
- **update-sight-version.yml**: Monitors Sight LSP releases and creates PRs to update
- **update-send-to-stata.yml**: Monitors send-to-stata releases and updates executables

## Common Tasks

### Adding a New Highlight Query

Edit `languages/stata/highlights.scm`. See [tree-sitter query syntax](https://tree-sitter.github.io/tree-sitter/using-parsers#query-syntax).

### Modifying Language Configuration

Edit `languages/stata/config.toml` for:
- Auto-closing pairs
- Comment syntax
- Word characters

### Testing Grammar Changes

```bash
cd tree-sitter-stata
tree-sitter generate
tree-sitter test
```
