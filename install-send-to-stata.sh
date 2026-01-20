#!/bin/bash
#
# install-send-to-stata.sh - Install send-to-stata for Zed editor
#
# Usage:
#   ./install-send-to-stata.sh                    Install components (prompts for focus behavior)
#   ./install-send-to-stata.sh --activate-stata   Install with focus switch to Stata
#   ./install-send-to-stata.sh --stay-in-zed      Install with focus staying in Zed (default)
#   ./install-send-to-stata.sh --uninstall        Remove components

set -euo pipefail

# Handle curl-pipe context where BASH_SOURCE is empty
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  # Curl-pipe context: no local directory
  SCRIPT_DIR=""
fi
INSTALL_DIR="$HOME/.local/bin"
ZED_CONFIG_DIR="$HOME/.config/zed"

# GitHub raw URL for curl-pipe installation
GITHUB_RAW_BASE="https://raw.githubusercontent.com/jbearak/sight-zed"
GITHUB_REF="${SIGHT_GITHUB_REF:-main}"

# Expected SHA-256 checksum of send-to-stata.sh (updated by update-checksum.sh)
SEND_TO_STATA_SHA256="139a7687e49d80ac87ccaf5faa358296678419aa40f61e8ce99dc756fc8ac998"

# Focus behavior configuration (set by command-line flags or interactive prompt)
# true = switch focus to Stata after sending code
# false = stay in Zed (default)
ACTIVATE_STATA=false

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
  if ! command -v jq &>/dev/null; then
    print_error "jq is required but not installed"
    echo ""
    echo "Install with Homebrew:"
    echo "  brew install jq"
    echo ""
    echo "Or visit: https://jqlang.org/download/"
    exit 1
  fi
}

# Verifies python3 is installed.
# Python3 is required by the Zed task to read ZED_SELECTED_TEXT from the
# environment without shell interpretation. Using shell variable expansion
# would cause the shell to interpret quotes and special characters in the
# selection, breaking compound strings like `"text"'.
check_python3() {
  if ! command -v python3 &>/dev/null; then
    print_error "python3 is required but not installed"
    echo ""
    echo "Install with Homebrew:"
    echo "  brew install python3"
    echo ""
    echo "Or download from: https://www.python.org/downloads/"
    echo ""
    echo "Note: python3 is used to read ZED_SELECTED_TEXT without shell"
    echo "interpretation. Shell expansion would break Stata compound strings."
    exit 1
  fi
}

# Runs all prerequisite checks.
check_prerequisites() {
  check_macos
  check_jq
  check_python3
}

# ============================================================================
# Script Installation
# ============================================================================

# Fetches send-to-stata.sh from GitHub when running via curl-pipe.
# Used when no local send-to-stata.sh exists (curl-pipe installation context).
fetch_script_from_github() {
  local url="$GITHUB_RAW_BASE/$GITHUB_REF/send-to-stata.sh"
  local temp_file
  temp_file=$(mktemp)
  
  print_info "Fetching send-to-stata.sh from GitHub ($GITHUB_REF)..."
  
  if ! curl -fsSL "$url" -o "$temp_file"; then
    rm -f "$temp_file"
    print_error "Failed to download send-to-stata.sh from GitHub"
    echo ""
    echo "URL: $url"
    echo ""
    echo "Check your internet connection and try again, or install from a local clone:"
    echo "  git clone https://github.com/jbearak/sight-zed.git"
    echo "  cd sight-zed && ./install-send-to-stata.sh"
    exit 1
  fi
  
  # Verify checksum (skip if using non-main ref or checksum not set)
  if [[ "$GITHUB_REF" == "main" && "$SEND_TO_STATA_SHA256" != "CHECKSUM_NOT_SET" ]]; then
    local actual_hash
    actual_hash=$(shasum -a 256 "$temp_file" | cut -d' ' -f1)
    if [[ "$actual_hash" != "$SEND_TO_STATA_SHA256" ]]; then
      rm -f "$temp_file"
      print_error "Checksum verification failed!"
      echo ""
      echo "Expected: $SEND_TO_STATA_SHA256"
      echo "Got:      $actual_hash"
      echo ""
      echo "This could indicate tampering or a version mismatch."
      echo "Install from a local clone to bypass:"
      echo "  git clone https://github.com/jbearak/sight-zed.git"
      echo "  cd sight-zed && ./install-send-to-stata.sh"
      exit 1
    fi
    print_success "Checksum verified"
  fi
  
  mv "$temp_file" "$INSTALL_DIR/send-to-stata.sh"
  print_success "Installed send-to-stata.sh to $INSTALL_DIR (from GitHub)"
}

# Installs send-to-stata.sh to ~/.local/bin.
install_script() {
  # Create install directory if needed
  if [[ ! -d "$INSTALL_DIR" ]]; then
    mkdir -p "$INSTALL_DIR"
    print_success "Created $INSTALL_DIR"
  fi

  # Determine source: local file or GitHub
  # In curl-pipe context, SCRIPT_DIR is empty so we fetch from GitHub
  local source_script="${SCRIPT_DIR:+$SCRIPT_DIR/}send-to-stata.sh"
  
  if [[ -n "$SCRIPT_DIR" && -f "$source_script" ]]; then
    # Local clone: copy from directory
    cp "$source_script" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/send-to-stata.sh"
    print_success "Installed send-to-stata.sh to $INSTALL_DIR (from local)"
  else
    # Curl-pipe: fetch from GitHub
    fetch_script_from_github
    chmod +x "$INSTALL_DIR/send-to-stata.sh"
  fi

  # Check if binary is findable; if not, configure PATH
  if ! command -v send-to-stata.sh &>/dev/null; then
    local path_line='export PATH="$HOME/.local/bin:$PATH"'
    local added_to=""
    # Determine primary shell config (create if needed)
    local primary_rc="$HOME/.zshrc"
    local current_shell=$(ps -p $$ -o comm=)
    [[ "$SHELL" == */bash || "$current_shell" == *bash* ]] && primary_rc="$HOME/.bashrc"
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
      [[ ! -f "$rc" && "$rc" == "$primary_rc" ]] && touch "$rc"
      if [[ -f "$rc" ]] && ! grep -q '\.local/bin' "$rc"; then
        echo "" >> "$rc"
        echo "# Added by send-to-stata installer" >> "$rc"
        echo "$path_line" >> "$rc"
        added_to="$added_to $rc"
      fi
    done
    if [[ -n "$added_to" ]]; then
      print_success "Added $INSTALL_DIR to PATH in:$added_to"
      print_warning "Restart your terminal or run: source ~/.zshrc"
    else
      print_warning "$INSTALL_DIR is not in your PATH"
      echo "  Add to your shell config (~/.zshrc or ~/.bashrc):"
      echo "    $path_line"
    fi
  fi
}

# ============================================================================
# Zed Tasks Installation
# ============================================================================

# Generates task definitions based on focus behavior setting.
# When ACTIVATE_STATA is true, appends osascript activation command.
generate_stata_tasks() {
  local activate_suffix=""
  
  if [[ "$ACTIVATE_STATA" == "true" ]]; then
    # Detect Stata variant for activation command
    local stata_app
    stata_app=$(detect_stata_app) || stata_app="Stata"
    
    # Use STATA_APP environment variable if set, otherwise use detected app
    stata_app="${STATA_APP:-$stata_app}"
    
    # Build activation suffix - will be appended to command strings
    activate_suffix=" && osascript -e 'tell application \\\"${stata_app}\\\" to activate'"
  fi
  
  # Generate tasks JSON directly with the suffix embedded
  cat <<EOF
[
  {
    "label": "Stata: Send Statement",
    "command": "python3 -c 'import os,sys; sys.exit(0 if os.environ.get(\"ZED_SELECTED_TEXT\", \"\") else 1)' && python3 -c 'import os,sys; sys.stdout.write(os.environ.get(\"ZED_SELECTED_TEXT\", \"\"))' | send-to-stata.sh --statement --stdin --file \"\$ZED_FILE\" || send-to-stata.sh --statement --file \"\$ZED_FILE\" --row \"\$ZED_ROW\"${activate_suffix}",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "never",
    "hide": "on_success"
  },
  {
    "label": "Stata: Send File",
    "command": "send-to-stata.sh --file-mode --file \"\$ZED_FILE\"${activate_suffix}",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "never",
    "hide": "on_success"
  },
  {
    "label": "Stata: Include Statement",
    "command": "python3 -c 'import os,sys; sys.exit(0 if os.environ.get(\"ZED_SELECTED_TEXT\", \"\") else 1)' && python3 -c 'import os,sys; sys.stdout.write(os.environ.get(\"ZED_SELECTED_TEXT\", \"\"))' | send-to-stata.sh --statement --include --stdin --file \"\$ZED_FILE\" || send-to-stata.sh --statement --include --file \"\$ZED_FILE\" --row \"\$ZED_ROW\"${activate_suffix}",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "never",
    "hide": "on_success"
  },
  {
    "label": "Stata: Include File",
    "command": "send-to-stata.sh --file-mode --include --file \"\$ZED_FILE\"${activate_suffix}",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "never",
    "hide": "on_success"
  }
]
EOF
}

# Task definitions to install (legacy, kept for backward compatibility in tests)
# Note: Args must be in command string, not args array (Zed doesn't pass args array correctly)
# Note: Zed uses ${VAR:default} syntax (no dash), not shell's ${VAR:-default}
# Note: Send Statement uses stdin mode for robust compound string handling.
# IMPORTANT: Do NOT inline selected text into the command via ${ZED_SELECTED_TEXT:}.
# Zed's interpolation happens before the shell parses the command; if the selection
# contains backticks (e.g. Stata compound strings), zsh will treat them as command
# substitution and the task will fail to parse.
# CRITICAL: python3 is REQUIRED to read $ZED_SELECTED_TEXT without shell interpretation.
# DO NOT use shell expansion like printf '%s' "$ZED_SELECTED_TEXT" - the shell will
# interpret quotes, backticks, and special characters, breaking compound strings.
# Python reads raw bytes from the environment without parsing.
STATA_TASKS=$(
  cat <<'EOF'
[
  {
    "label": "Stata: Send Statement",
    "command": "python3 -c 'import os,sys; sys.exit(0 if os.environ.get(\"ZED_SELECTED_TEXT\", \"\") else 1)' && python3 -c 'import os,sys; sys.stdout.write(os.environ.get(\"ZED_SELECTED_TEXT\", \"\"))' | send-to-stata.sh --statement --stdin --file \"$ZED_FILE\" || send-to-stata.sh --statement --file \"$ZED_FILE\" --row \"$ZED_ROW\"",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "never",
    "hide": "on_success"
  },
  {
    "label": "Stata: Send File",
    "command": "send-to-stata.sh --file-mode --file \"$ZED_FILE\"",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "never",
    "hide": "on_success"
  },
  {
    "label": "Stata: Include Statement",
    "command": "python3 -c 'import os,sys; sys.exit(0 if os.environ.get(\"ZED_SELECTED_TEXT\", \"\") else 1)' && python3 -c 'import os,sys; sys.stdout.write(os.environ.get(\"ZED_SELECTED_TEXT\", \"\"))' | send-to-stata.sh --statement --include --stdin --file \"$ZED_FILE\" || send-to-stata.sh --statement --include --file \"$ZED_FILE\" --row \"$ZED_ROW\"",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "never",
    "hide": "on_success"
  },
  {
    "label": "Stata: Include File",
    "command": "send-to-stata.sh --file-mode --include --file \"$ZED_FILE\"",
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

  # Generate tasks based on current ACTIVATE_STATA setting
  local stata_tasks
  stata_tasks=$(generate_stata_tasks)

  # Create or update tasks.json
  if [[ ! -f "$tasks_file" ]]; then
    echo "$stata_tasks" >"$tasks_file"
  else
    # Remove existing Stata tasks, then add new ones
    jq --argjson new "$stata_tasks" '
            [.[] | select(.label | startswith("Stata:") | not)] + $new
        ' "$tasks_file" >"${tasks_file}.tmp" && mv "${tasks_file}.tmp" "$tasks_file"
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
  stata_keybindings=$(
    cat <<'EOF'
[
  {
    "context": "Editor && extension == do",
    "bindings": {
      "cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Send Statement"}]]],
      "shift-cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Send File"}]]],
      "alt-cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Include Statement"}]]],
      "alt-shift-cmd-enter": ["action::Sequence", ["workspace::Save", ["task::Spawn", {"task_name": "Stata: Include File"}]]],
      "shift-enter": ["workspace::SendKeystrokes", "cmd-c ctrl-` cmd-v enter"],
      "alt-enter": ["workspace::SendKeystrokes", "cmd-left shift-cmd-right cmd-c ctrl-` cmd-v enter"]
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
    echo "$stata_keybindings" >"$keymap_file"
  else
    # Try to parse existing file; if it fails (e.g., JSON5 with trailing commas),
    # filter out Stata entries manually or just merge
    local filtered
    if filtered=$(jq '[.[] | select((.context | test("extension == do$")) | not)]' "$keymap_file" 2>/dev/null); then
      # Successfully parsed, merge with new keybindings
      echo "$stata_keybindings" | jq -s '.[0] + .[1]' <(echo "$filtered") - >"${keymap_file}.tmp" && mv "${keymap_file}.tmp" "$keymap_file"
    else
      # Parse failed (likely JSON5), just overwrite with our keybindings
      # User will need to re-add any custom keybindings
      echo "$stata_keybindings" >"$keymap_file"
    fi
  fi
  print_success "Installed keybindings to $keymap_file"
}

# ============================================================================
# Stata Detection
# ============================================================================

# Detects installed Stata variant and returns the app name.
# Returns: StataMP, StataSE, StataIC, Stata, or empty string if not found.
detect_stata_app() {
  for app in StataMP StataSE StataIC Stata; do
    if [[ -d "/Applications/Stata/${app}.app" ]]; then
      echo "$app"
      return 0
    fi
  done
  echo ""
  return 1
}

# Detects installed Stata variant in /Applications/Stata/.
detect_stata() {
  local found
  found=$(detect_stata_app) || true

  if [[ -n "$found" ]]; then
    print_success "Detected Stata: $found"
  else
    print_warning "No Stata installation found in /Applications/Stata/"
    echo "  Set STATA_APP environment variable if Stata is installed elsewhere"
  fi
}

# ============================================================================
# Focus Behavior Configuration
# ============================================================================

# Prompts user for focus behavior preference.
# Sets ACTIVATE_STATA global variable based on user input.
prompt_focus_behavior() {
  echo ""
  echo "Focus behavior after sending code to Stata:"
  echo "  [Y] Switch to Stata (see output immediately)"
  echo "  [N] Stay in Zed (keep typing without switching windows)"
  echo ""
  
  local response
  if read -r -p "Switch to Stata after sending code? [y/N] " response; then
    case "$response" in
      [yY]|[yY][eE][sS])
        ACTIVATE_STATA=true
        print_success "Focus will switch to Stata after sending code"
        ;;
      *)
        ACTIVATE_STATA=false
        print_success "Focus will stay in Zed after sending code"
        ;;
    esac
  else
    # EOF or read failure (non-interactive) - default to staying in Zed
    ACTIVATE_STATA=false
    print_success "Focus will stay in Zed after sending code (default)"
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
    echo "  cmd-enter            Send current statement (or selection) to Stata"
    echo "  shift-cmd-enter      Send entire file to Stata"
    echo "  opt-cmd-enter        Include statement (preserves local macros)"
    echo "  opt-shift-cmd-enter  Include file (preserves local macros)"
    echo "  shift-enter          Send selection to Stata terminal (quick paste)"
    echo "  opt-enter            Send current line to Stata terminal (quick paste)"
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
    local filtered
    if filtered=$(jq '[.[] | select(.label | startswith("Stata:") | not)]' "$tasks_file" 2>/dev/null); then
      local before_count after_count
      before_count=$(jq 'length' "$tasks_file" 2>/dev/null || echo 0)
      after_count=$(echo "$filtered" | jq 'length')
      echo "$filtered" >"$tasks_file"
      if [[ "$before_count" != "$after_count" ]]; then
        print_success "Removed Stata tasks from $tasks_file"
        removed=true
      fi
    else
      print_warning "Could not parse $tasks_file (invalid JSON?), skipping task removal"
    fi
  fi

  # Remove keybindings from keymap.json
  local keymap_file="$ZED_CONFIG_DIR/keymap.json"
  if [[ -f "$keymap_file" ]]; then
    local filtered
    if filtered=$(jq '[.[] | select((.context | test("extension == do$")) | not)]' "$keymap_file" 2>/dev/null); then
      local before_count after_count
      before_count=$(jq 'length' "$keymap_file" 2>/dev/null || echo 0)
      after_count=$(echo "$filtered" | jq 'length')
      echo "$filtered" >"$keymap_file"
      if [[ "$before_count" != "$after_count" ]]; then
        print_success "Removed Stata keybindings from $keymap_file"
        removed=true
      fi
    else
      print_warning "Could not parse $keymap_file (invalid JSON?), skipping keybinding removal"
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
  local quiet=false
  local activate_stata_flag=""
  local stay_in_zed_flag=""
  
  for arg in "$@"; do
    case "$arg" in
      --uninstall)
        uninstall
        exit 0
        ;;
      --quiet)
        quiet=true
        ;;
      --activate-stata)
        activate_stata_flag=true
        ;;
      --stay-in-zed)
        stay_in_zed_flag=true
        ;;
    esac
  done

  # Validate mutual exclusivity of focus flags
  if [[ "$activate_stata_flag" == "true" && "$stay_in_zed_flag" == "true" ]]; then
    print_error "Cannot specify both --activate-stata and --stay-in-zed"
    exit 1
  fi

  # Set focus behavior from flags or prompt
  if [[ "$activate_stata_flag" == "true" ]]; then
    ACTIVATE_STATA=true
  elif [[ "$stay_in_zed_flag" == "true" ]]; then
    ACTIVATE_STATA=false
  fi

  if [[ "$quiet" == "false" ]]; then
    echo "Installing send-to-stata for Zed..."
    echo ""
  fi

  check_prerequisites
  install_script
  
  # Prompt for focus behavior if not specified via flags (and not quiet mode)
  if [[ "$activate_stata_flag" != "true" && "$stay_in_zed_flag" != "true" && "$quiet" == "false" ]]; then
    prompt_focus_behavior
  fi
  
  install_tasks
  install_keybindings
  detect_stata
  
  if [[ "$quiet" == "false" ]]; then
    print_summary
  fi
}

# Only run main if script is executed directly (not sourced)
# In curl-pipe context, BASH_SOURCE is empty, so always run main
if [[ -z "${BASH_SOURCE[0]:-}" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
