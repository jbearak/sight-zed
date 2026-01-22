#!/bin/bash
#
# setup.sh - Build and install Sight Zed extension for local development
#
# Usage:
#   ./setup.sh              Build extension, install symlink, run installers
#   ./setup.sh --uninstall  Remove extension symlink and uninstall components

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZED_EXT_DIR="$HOME/Library/Application Support/Zed/extensions/installed"
SYMLINK_PATH="$ZED_EXT_DIR/sight"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_error() { echo -e "${RED}Error:${NC} $1" >&2; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}Warning:${NC} $1"; }

# ============================================================================
# Prerequisite Checks
# ============================================================================

check_macos() {
  if [[ "$(uname)" != "Darwin" ]]; then
    print_error "This script requires macOS"
    exit 1
  fi
}

check_rust() {
  if ! command -v rustc &>/dev/null || ! command -v cargo &>/dev/null; then
    print_error "Rust toolchain is required but not installed"
    echo ""
    echo "Install with:"
    echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
  fi
}

check_wasm_target() {
  if ! rustup target list --installed | grep -q wasm32-wasip1; then
    print_error "wasm32-wasip1 target is required but not installed"
    echo ""
    echo "Install with:"
    echo "  rustup target add wasm32-wasip1"
    exit 1
  fi
}

check_tree_sitter() {
  if ! command -v tree-sitter &>/dev/null; then
    echo "tree-sitter CLI not found, installing via Homebrew..."
    if ! command -v brew &>/dev/null; then
      print_error "Homebrew is required to install tree-sitter"
      echo ""
      echo "Install Homebrew first:"
      echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
      exit 1
    fi
    brew install tree-sitter
    print_success "Installed tree-sitter"
  fi
}

check_prerequisites() {
  check_macos
  check_rust
  check_wasm_target
  check_tree_sitter
}

# ============================================================================
# Build
# ============================================================================

build_extension() {
  echo "Building extension..."
  cargo build --release --target wasm32-wasip1
  cp "$SCRIPT_DIR/target/wasm32-wasip1/release/sight_extension.wasm" "$SCRIPT_DIR/extension.wasm"
  print_success "Built extension.wasm"
}

build_grammar() {
  echo "Building grammar..."
  cd "$SCRIPT_DIR/grammars/stata"
  tree-sitter build --wasm -o stata.wasm
  cd "$SCRIPT_DIR"
  print_success "Built grammars/stata/stata.wasm"
}

# ============================================================================
# Symlink Installation
# ============================================================================

install_symlink() {
  mkdir -p "$ZED_EXT_DIR"

  if [[ -L "$SYMLINK_PATH" ]]; then
    rm "$SYMLINK_PATH"
  elif [[ -e "$SYMLINK_PATH" ]]; then
    print_error "$SYMLINK_PATH exists and is not a symlink"
    echo "Remove it manually if you want to proceed"
    exit 1
  fi

  ln -s "$SCRIPT_DIR" "$SYMLINK_PATH"
  print_success "Installed extension symlink at $SYMLINK_PATH"
}

uninstall_symlink() {
  if [[ -L "$SYMLINK_PATH" ]]; then
    rm "$SYMLINK_PATH"
    print_success "Removed extension symlink"
  elif [[ -e "$SYMLINK_PATH" ]]; then
    print_warning "$SYMLINK_PATH exists but is not a symlink, skipping"
  else
    print_warning "Extension symlink not found, skipping"
  fi
}

# ============================================================================
# Main
# ============================================================================

uninstall() {
  echo "Uninstalling Sight Zed extension..."
  echo ""
  uninstall_symlink
  echo ""
  "$SCRIPT_DIR/install-send-to-stata.sh" --uninstall
  echo ""
  "$SCRIPT_DIR/install-jupyter-stata.sh" --uninstall
}

install() {
  echo "Setting up Sight Zed extension..."
  echo ""
  check_prerequisites
  build_extension
  build_grammar
  install_symlink
  echo ""
  "$SCRIPT_DIR/install-send-to-stata.sh" --quiet
  echo ""
  "$SCRIPT_DIR/install-jupyter-stata.sh" --quiet
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Sight Zed extension setup complete!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  Extension:        Installed at $SYMLINK_PATH"
  echo "  Send-to-Stata:    Configured (keybindings + tasks)"
  echo "  Jupyter Kernel:   Installed (Stata + Stata Workspace)"
  echo ""
  echo "  Keyboard shortcuts (.do files):"
  echo "    cmd-enter              Send statement to Stata"
  echo "    shift-cmd-enter        Send file to Stata"
  echo "    opt-cmd-enter          Include statement (preserves locals)"
  echo "    opt-shift-cmd-enter    Include file (preserves locals)"
  echo "    ctrl-shift-w           CD into workspace folder"
  echo "    ctrl-shift-f           CD into file folder"
  echo "    ctrl-shift-up          Do upward lines (line 1 to cursor)"
  echo "    ctrl-shift-down        Do downward lines (cursor to end)"
  echo "    shift-enter            Paste selection to terminal"
  echo "    opt-enter              Paste current line to terminal"
  echo "    ctrl-shift-enter       Run in Jupyter REPL"
  echo ""
  echo "  Next steps:"
  echo "    1. Restart Zed (Cmd+Q, then reopen)"
  echo "    2. Open a .do file to verify syntax highlighting"
  echo "    3. Try cmd-enter to send code to Stata"
  echo ""
}

main() {
  if [[ "${1:-}" == "--uninstall" ]]; then
    uninstall
  else
    install
  fi
}

main "$@"
