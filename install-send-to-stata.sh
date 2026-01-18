#!/bin/bash
#
# install-send-to-stata.sh - Install send-to-stata for Zed editor
#
# Usage:
#   ./install-send-to-stata.sh           Install components
#   ./install-send-to-stata.sh --uninstall   Remove components

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.local/bin"
ZED_CONFIG_DIR="$HOME/.config/zed"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Prints an error message in red.
print_error() { echo -e "${RED}Error:${NC} $1" >&2; }
# Prints a success message with green checkmark.
print_success() { echo -e "${GREEN}✓${NC} $1"; }
# Prints a warning message in yellow.
print_warning() { echo -e "${YELLOW}Warning:${NC} $1"; }
# Prints an info message.
print_info() { echo "$1"; }

# ============================================================================
# Prerequisite Checks
# ============================================================================

# Verifies the script is running on macOS.
check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        print_error "This script requires macOS (for AppleScript support)"
        exit 1
    fi
}

# Verifies jq is installed.
check_jq() {
    if ! command -v jq &> /dev/null; then
        print_error "jq is required but not installed"
        echo ""
        echo "Install with Homebrew:"
        echo "  brew install jq"
        echo ""
        echo "Or visit: https://stedolan.github.io/jq/download/"
        exit 1
    fi
}

# Runs all prerequisite checks.
check_prerequisites() {
    check_macos
    check_jq
}

# ============================================================================
# Script Installation
# ============================================================================

# Installs send-to-stata.sh to ~/.local/bin.
install_script() {
    # Create install directory if needed
    if [[ ! -d "$INSTALL_DIR" ]]; then
        mkdir -p "$INSTALL_DIR"
        print_success "Created $INSTALL_DIR"
    fi
    
    # Copy script
    cp "$SCRIPT_DIR/send-to-stata.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/send-to-stata.sh"
    print_success "Installed send-to-stata.sh to $INSTALL_DIR"
    
    # Check PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        print_warning "$INSTALL_DIR is not in your PATH"
        echo "  Add to your shell config (~/.zshrc or ~/.bashrc):"
        echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

# ============================================================================
# Zed Tasks Installation
# ============================================================================

# Task definitions to install
# Note: Args must be in command string, not args array (Zed doesn't pass args array correctly)
# Note: Zed uses ${VAR:default} syntax (no dash), not shell's ${VAR:-default}
# Note: Send Statement uses stdin mode for robust compound string handling.
# IMPORTANT: Do NOT inline selected text into the command via ${ZED_SELECTED_TEXT:}.
# Zed's interpolation happens before the shell parses the command; if the selection
# contains backticks (e.g. Stata compound strings), zsh will treat them as command
# substitution and the task will fail to parse. Use the environment variable
# $ZED_SELECTED_TEXT instead.
STATA_TASKS=$(cat <<'EOF'
[
  {
    "label": "Stata: Send Statement",
    "command": "if [ -n \"$ZED_SELECTED_TEXT\" ]; then printf '%s' \"$ZED_SELECTED_TEXT\" | send-to-stata.sh --statement --stdin --file \"$ZED_FILE\"; else send-to-stata.sh --statement --file \"$ZED_FILE\" --row \"$ZED_ROW\"; fi",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "never",
    "hide": "on_success"
  },
  {
    "label": "Stata: Send File",
    "command": "send-to-stata.sh --file --file \"$ZED_FILE\"",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "never",
    "hide": "on_success"
  }
]
EOF
)

# Installs Stata tasks to Zed's tasks.json.
install_tasks() {
    local tasks_file="$ZED_CONFIG_DIR/tasks.json"
    
    # Create config dir if needed
    mkdir -p "$ZED_CONFIG_DIR"
    
    # Create or update tasks.json
    if [[ ! -f "$tasks_file" ]]; then
        echo "$STATA_TASKS" > "$tasks_file"
    else
        # Remove existing Stata tasks, then add new ones
        jq --argjson new "$STATA_TASKS" '
            [.[] | select(.label | startswith("Stata:") | not)] + $new
        ' "$tasks_file" > "${tasks_file}.tmp" && mv "${tasks_file}.tmp" "$tasks_file"
    fi
    print_success "Installed Zed tasks to $tasks_file"
}

# ============================================================================
# Keybindings Installation
# ============================================================================

# Keybinding definitions to install
# Uses action::Sequence to save the file before spawning the task
# Nullifies the default cmd-enter binding in the broader context to prevent newline insertion

# Installs Stata keybindings to Zed's keymap.json.
install_keybindings() {
    local keymap_file="$ZED_CONFIG_DIR/keymap.json"
    
    # Define keybindings JSON inline to avoid shell escaping issues
    local stata_keybindings
    stata_keybindings=$(cat << 'EOF'
[
  {
    "context": "Editor && extension == do",
    "bindings": {
      "cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Send Statement"}]]],
      "shift-cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Send File"}]]]
    }
  }
]
EOF
)
    
    # Create config dir if needed
    mkdir -p "$ZED_CONFIG_DIR"
    
    # Create or update keymap.json
    if [[ ! -f "$keymap_file" ]] || [[ ! -s "$keymap_file" ]]; then
        # File doesn't exist or is empty
        echo "$stata_keybindings" > "$keymap_file"
    else
        # Try to parse existing file; if it fails (e.g., JSON5 with trailing commas),
        # filter out Stata entries manually or just merge
        local filtered
        if filtered=$(jq '[.[] | select((.context | test("extension == do$")) | not)]' "$keymap_file" 2>/dev/null); then
            # Successfully parsed, merge with new keybindings
            echo "$stata_keybindings" | jq -s '.[0] + .[1]' <(echo "$filtered") - > "${keymap_file}.tmp" && mv "${keymap_file}.tmp" "$keymap_file"
        else
            # Parse failed (likely JSON5), just overwrite with our keybindings
            # User will need to re-add any custom keybindings
            echo "$stata_keybindings" > "$keymap_file"
        fi
    fi
    print_success "Installed keybindings to $keymap_file"
}

# ============================================================================
# Stata Detection
# ============================================================================

# Detects installed Stata variant in /Applications/Stata/.
detect_stata() {
    local found=""
    for app in StataMP StataSE StataIC Stata; do
        if [[ -d "/Applications/Stata/${app}.app" ]]; then
            found="$app"
            break
        fi
    done
    
    if [[ -n "$found" ]]; then
        print_success "Detected Stata: $found"
    else
        print_warning "No Stata installation found in /Applications/Stata/"
        echo "  Set STATA_APP environment variable if Stata is installed elsewhere"
    fi
}

# ============================================================================
# Installation Summary
# ============================================================================

# Prints post-installation usage summary.
print_summary() {
    echo ""
    echo "Installation complete!"
    echo ""
    echo "Keybindings (in .do files):"
    echo "  cmd-enter        Send current statement (or selection) to Stata"
    echo "  shift-cmd-enter  Send entire file to Stata"
    echo ""
    echo "Configuration:"
    echo "  Set STATA_APP environment variable to override Stata variant detection"
    echo ""
}

# ============================================================================
# Uninstall
# ============================================================================

# Removes installed script, tasks, and keybindings.
uninstall() {
    local removed=false
    check_jq
    
    # Remove script
    if [[ -f "$INSTALL_DIR/send-to-stata.sh" ]]; then
        rm "$INSTALL_DIR/send-to-stata.sh"
        print_success "Removed $INSTALL_DIR/send-to-stata.sh"
        removed=true
    fi
    
    # Remove tasks from tasks.json
    local tasks_file="$ZED_CONFIG_DIR/tasks.json"
    if [[ -f "$tasks_file" ]]; then
        local before_count
        before_count=$(jq 'length' "$tasks_file")
        jq '[.[] | select(.label | startswith("Stata:") | not)]' "$tasks_file" > "${tasks_file}.tmp"
        local after_count
        after_count=$(jq 'length' "${tasks_file}.tmp")
        mv "${tasks_file}.tmp" "$tasks_file"
        if [[ "$before_count" != "$after_count" ]]; then
            print_success "Removed Stata tasks from $tasks_file"
            removed=true
        fi
    fi
    
    # Remove keybindings from keymap.json
    local keymap_file="$ZED_CONFIG_DIR/keymap.json"
    if [[ -f "$keymap_file" ]]; then
        local before_count
        before_count=$(jq 'length' "$keymap_file")
        jq '[.[] | select((.context | test("extension == do$")) | not)]' "$keymap_file" > "${keymap_file}.tmp"
        local after_count
        after_count=$(jq 'length' "${keymap_file}.tmp")
        mv "${keymap_file}.tmp" "$keymap_file"
        if [[ "$before_count" != "$after_count" ]]; then
            print_success "Removed Stata keybindings from $keymap_file"
            removed=true
        fi
    fi
    
    if [[ "$removed" == true ]]; then
        echo ""
        echo "Uninstall complete!"
    else
        print_info "Nothing to uninstall"
    fi
}

# ============================================================================
# Main
# ============================================================================

# Main entry point. Handles --uninstall flag or runs installation.
main() {
    if [[ "${1:-}" == "--uninstall" ]]; then
        uninstall
        exit 0
    fi
    
    echo "Installing send-to-stata for Zed..."
    echo ""
    
    check_prerequisites
    install_script
    install_tasks
    install_keybindings
    detect_stata
    print_summary
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
