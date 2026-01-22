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
│       └── overrides.scm       # Scope overrides
├── src/
│   └── lib.rs                  # Zed extension entry point
├── target/                     # Rust build artifacts (ignored)
├── tests/                      # Test suites
│   ├── *.bats                  # Bash Automated Testing System tests
│   ├── *.Tests.ps1             # Pester tests for PowerShell
│   └── fixtures/               # Test fixtures
├── tree-sitter-stata/          # Tree-sitter grammar (git submodule)
│
├── Cargo.toml                  # Rust project manifest
├── Cargo.lock                  # Rust dependency lockfile
├── extension.toml              # Zed extension manifest
├── extension.wasm              # Built extension (committed)
│
├── install-jupyter-stata.ps1  # Windows Jupyter kernel installer
├── install-jupyter-stata.sh   # macOS/Linux Jupyter kernel installer
├── install-send-to-stata.ps1  # Windows send-to-stata installer
├── install-send-to-stata.sh   # macOS/Linux send-to-stata installer
│
├── send-to-stata.sh           # macOS send-to-stata script
│
├── setup.ps1                  # Windows full setup script
├── setup.sh                   # macOS/Linux setup script
├── validate.sh                # Build and dependency validation
│
├── update_version.sh          # Version bump automation
├── update-checksum.ps1        # Update Windows exe checksums
├── update-checksum.sh         # Update macOS script checksums
├── update-setup-checksums.ps1 # Update setup.ps1 dependency checksums
│
├── AGENTS.md                  # AI agent instructions
├── LICENSE                    # GPLv3 license
├── README.md                  # User-facing documentation
└── SEND-TO-STATA.md           # Send-to-Stata documentation
```

## Prerequisites

### macOS/Linux

- Rust toolchain with wasm32-wasip1 target: `rustup target add wasm32-wasip1`
- tree-sitter CLI: `npm install -g tree-sitter-cli`
- For tests: [bats-core](https://github.com/bats-core/bats-core)

### Windows

- PowerShell 7+ (`winget install Microsoft.PowerShell`)
- The `setup.ps1` script handles most dependencies

## Building

### Extension WASM

```bash
# macOS/Linux
cargo build --release --target wasm32-wasip1
cp target/wasm32-wasip1/release/sight_extension.wasm extension.wasm

# Windows (via setup.ps1)
.\setup.ps1 -Yes
```

## Testing

### Validation Suite

```bash
# Run all validations
./validate.sh

# Individual checks
./validate.sh --lsp          # Check LSP version
./validate.sh --grammar-rev  # Check grammar revision
./validate.sh --build        # Test extension build
./validate.sh --grammar-build # Test grammar build
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
ln -s $(pwd) ~/.local/share/zed/extensions/installed/sight
```

## Version Management

### Updating Extension Version

Use the version bump script:
```bash
./update_version.sh 0.1.18
```

This updates:
- `extension.toml` version
- `Cargo.toml` version
- Creates a git commit and tag

### Updating Sight LSP Version

1. Edit `src/lib.rs`
2. Update `SERVER_VERSION` constant (e.g., `"v0.1.21"`)

### Updating Tree-Sitter Grammar

1. Edit `extension.toml`
2. Update the `rev` field under `[grammars.stata]`

## Why extension.wasm is Committed

Zed extensions are distributed directly from git repositories. When users install an extension, Zed clones the repo and expects the pre-built WASM to be present. There's no build step during installation.

After building, commit the updated `extension.wasm` for users to receive the new version.

## Checksum Updates

After modifying scripts or executables, update their checksums:

```bash
# macOS send-to-stata.sh checksum
./update-checksum.sh

# Windows executables checksums
pwsh -File update-checksum.ps1

# Windows setup.ps1 dependency checksums
pwsh -File update-setup-checksums.ps1
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
