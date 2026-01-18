#!/bin/bash
#
# install-jupyter-stata.sh - Install stata_kernel for Zed Jupyter integration
#
# Usage:
#   ./install-jupyter-stata.sh                    Install stata_kernel
#   ./install-jupyter-stata.sh --uninstall        Remove installation
#   ./install-jupyter-stata.sh --uninstall --remove-config  Remove including config

set -euo pipefail

# ============================================================================
# Configuration Constants
# ============================================================================
VENV_DIR="$HOME/.local/share/stata_kernel/venv"
CONFIG_FILE="$HOME/.stata_kernel.conf"
KERNEL_DIR="$HOME/Library/Jupyter/kernels/stata"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/jbearak/sight-zed"
GITHUB_REF="${SIGHT_GITHUB_REF:-main}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# Output Helpers
# ============================================================================

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
    print_error "This script requires macOS"
    exit 1
  fi
}

# Verifies python3 is installed with venv module.
check_python3() {
  if ! command -v python3 &>/dev/null; then
    print_error "python3 is required but not installed"
    echo ""
    echo "Install with Homebrew:"
    echo "  brew install python3"
    echo ""
    echo "Or download from: https://www.python.org/downloads/"
    exit 1
  fi
  if ! python3 -m venv --help &>/dev/null; then
    print_error "python3 venv module is required but not available"
    echo ""
    echo "On some systems, install with:"
    echo "  brew install python3"
    echo "  # or"
    echo "  apt install python3-venv"
    exit 1
  fi
}

# Runs all prerequisite checks.
check_prerequisites() {
  check_macos
  check_python3
}

# ============================================================================
# Stata Detection
# ============================================================================

# Global variables set by detect_stata_app
STATA_PATH=""
STATA_EDITION=""
EXECUTION_MODE=""

# Detects Stata installation and determines edition/execution mode.
# Sets: STATA_PATH, STATA_EDITION, EXECUTION_MODE
detect_stata_app() {
  # Check environment variable override first
  if [[ -n "${STATA_PATH:-}" ]]; then
    if [[ ! -x "$STATA_PATH" ]]; then
      print_error "STATA_PATH is set but not executable: $STATA_PATH"
      exit 1
    fi
    # Extract edition from path
    case "$STATA_PATH" in
      *stata-mp*|*StataMP*) STATA_EDITION="MP" ;;
      *stata-se*|*StataSE*) STATA_EDITION="SE" ;;
      *stata-ic*|*StataIC*) STATA_EDITION="IC" ;;
      *stata-be*|*StataBE*) STATA_EDITION="BE" ;;
      *) STATA_EDITION="IC" ;;  # Default assumption
    esac
  else
    # Auto-detect from /Applications/Stata/
    local apps=("StataMP" "StataSE" "StataIC" "StataBE" "Stata")
    local executables=("stata-mp" "stata-se" "stata-ic" "stata-be" "stata")
    local editions=("MP" "SE" "IC" "BE" "IC")
    
    for i in "${!apps[@]}"; do
      local app_path="/Applications/Stata/${apps[$i]}.app/Contents/MacOS/${executables[$i]}"
      if [[ -x "$app_path" ]]; then
        STATA_PATH="$app_path"
        STATA_EDITION="${editions[$i]}"
        break
      fi
    done
    
    if [[ -z "$STATA_PATH" ]]; then
      print_error "No Stata installation found in /Applications/Stata/"
      echo ""
      echo "Either install Stata or set STATA_PATH environment variable:"
      echo "  export STATA_PATH=/path/to/stata"
      exit 1
    fi
  fi
  
  # Determine execution mode (allow override)
  if [[ -n "${STATA_EXECUTION_MODE:-}" ]]; then
    EXECUTION_MODE="$STATA_EXECUTION_MODE"
  else
    case "$STATA_EDITION" in
      MP|SE) EXECUTION_MODE="console" ;;
      *)     EXECUTION_MODE="automation" ;;
    esac
  fi
}

# ============================================================================
# Virtual Environment Management
# ============================================================================

# Creates virtual environment if it doesn't exist.
create_venv() {
  if [[ -x "$VENV_DIR/bin/python" ]]; then
    print_info "Virtual environment already exists at $VENV_DIR"
    return 0
  fi
  
  print_info "Creating virtual environment..."
  mkdir -p "$(dirname "$VENV_DIR")"
  if ! python3 -m venv "$VENV_DIR"; then
    print_error "Failed to create virtual environment"
    exit 2
  fi
  print_success "Created virtual environment at $VENV_DIR"
}

# Installs stata_kernel and jupyter into the virtual environment.
install_packages() {
  print_info "Installing packages..."
  if ! "$VENV_DIR/bin/pip" install --upgrade pip &>/dev/null; then
    print_error "Failed to upgrade pip"
    exit 2
  fi
  if ! "$VENV_DIR/bin/pip" install --upgrade stata_kernel jupyter &>/dev/null; then
    print_error "Failed to install stata_kernel and jupyter"
    exit 2
  fi
  print_success "Installed stata_kernel and jupyter"
}

# ============================================================================
# Configuration Management
# ============================================================================

# Returns the config file template with documentation.
get_config_template() {
  cat << 'EOF'
# stata_kernel configuration file
# Documentation: https://kylebarron.dev/stata_kernel/using_stata_kernel/configuration/

[stata_kernel]

# stata_path: Full path to your Stata executable
stata_path = STATA_PATH_PLACEHOLDER

# execution_mode: How stata_kernel communicates with Stata (macOS only)
# Values: console (MP/SE), automation (IC/BE)
execution_mode = EXECUTION_MODE_PLACEHOLDER

# cache_directory: Directory for temporary log files and graphs
# cache_directory = ~/.stata_kernel_cache

# graph_format: Format for exported graphs (svg, png, eps)
# graph_format = svg

# graph_scale: Scale factor for graph dimensions
# graph_scale = 1.0

# graph_width: Width of graphs in pixels
# graph_width = 600

# graph_height: Height of graphs in pixels
# graph_height = 400

# autocomplete_closing_symbol: Include closing symbol in autocompletions
# autocomplete_closing_symbol = False

# user_graph_keywords: Additional commands that generate graphs
# user_graph_keywords =
EOF
}

# Updates a single setting in the config file, adding it if missing.
# Args: $1=key, $2=value
update_config_setting() {
  local key="$1" value="$2"
  local tmp_file
  tmp_file=$(mktemp)
  trap "rm -f '$tmp_file'" RETURN
  
  if grep -q "^${key}[[:space:]]*=" "$CONFIG_FILE"; then
    sed "s|^${key}[[:space:]]*=.*|${key} = ${value}|" "$CONFIG_FILE" > "$tmp_file"
    mv "$tmp_file" "$CONFIG_FILE"
  elif grep -q "^#[[:space:]]*${key}[[:space:]]*=" "$CONFIG_FILE"; then
    sed "s|^#[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$CONFIG_FILE" > "$tmp_file"
    mv "$tmp_file" "$CONFIG_FILE"
  else
    # Setting doesn't exist - add after [stata_kernel] section header
    sed "/^\[stata_kernel\]/a\\
${key} = ${value}" "$CONFIG_FILE" > "$tmp_file"
    mv "$tmp_file" "$CONFIG_FILE"
  fi
}

# Writes or updates the configuration file.
write_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    # Create new config from template
    get_config_template | \
      sed "s|STATA_PATH_PLACEHOLDER|$STATA_PATH|" | \
      sed "s|EXECUTION_MODE_PLACEHOLDER|$EXECUTION_MODE|" > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    print_success "Created configuration at $CONFIG_FILE"
  else
    # Update existing config - preserve user settings
    update_config_setting "stata_path" "$STATA_PATH"
    update_config_setting "execution_mode" "$EXECUTION_MODE"
    chmod 600 "$CONFIG_FILE"
    print_success "Updated configuration at $CONFIG_FILE"
  fi
}

# ============================================================================
# Kernel Registration
# ============================================================================

# Registers the stata_kernel with Jupyter.
register_kernel() {
  print_info "Registering kernel with Jupyter..."
  if ! "$VENV_DIR/bin/python" -m stata_kernel.install &>/dev/null; then
    print_error "Failed to register kernel"
    exit 3
  fi
  print_success "Registered stata kernel"
}

# Verifies the kernel spec was created correctly.
verify_kernel_spec() {
  if [[ ! -f "$KERNEL_DIR/kernel.json" ]]; then
    print_error "Kernel spec not found at $KERNEL_DIR/kernel.json"
    exit 3
  fi
  
  # Verify language is "stata" (lowercase) for Zed matching
  if ! grep -q '"language"[[:space:]]*:[[:space:]]*"stata"' "$KERNEL_DIR/kernel.json"; then
    print_warning "Kernel language may not be set correctly for Zed"
  fi
  
  print_success "Verified kernel spec at $KERNEL_DIR"
}

# ============================================================================
# Uninstallation
# ============================================================================

# Removes installed components.
# Args: $1 - "true" to also remove config file
uninstall() {
  local remove_config="${1:-false}"
  
  print_info "Uninstalling stata_kernel..."
  
  # Remove virtual environment
  if [[ -d "$VENV_DIR" ]]; then
    rm -rf "$VENV_DIR"
    print_success "Removed virtual environment"
  else
    print_info "Virtual environment not found (already removed)"
  fi
  
  # Remove kernel spec
  if [[ -d "$KERNEL_DIR" ]]; then
    rm -rf "$KERNEL_DIR"
    print_success "Removed kernel spec"
  else
    print_info "Kernel spec not found (already removed)"
  fi
  
  # Optionally remove config
  if [[ "$remove_config" == "true" ]]; then
    if [[ -f "$CONFIG_FILE" ]]; then
      rm -f "$CONFIG_FILE"
      print_success "Removed configuration file"
    else
      print_info "Configuration file not found (already removed)"
    fi
  else
    print_info "Configuration preserved at $CONFIG_FILE (use --remove-config to delete)"
  fi
  
  print_success "Uninstallation complete"
}

# ============================================================================
# Main
# ============================================================================

# Prints installation summary with usage instructions.
print_summary() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  stata_kernel installed successfully!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  Stata Edition:    $STATA_EDITION"
  echo "  Execution Mode:   $EXECUTION_MODE"
  echo "  Configuration:    $CONFIG_FILE"
  echo ""
  echo "  Usage in Zed:"
  echo "    1. Open a .do file"
  echo "    2. Open the REPL panel (View → Toggle REPL)"
  echo "    3. Select 'Stata' as the kernel"
  echo ""
  echo "  Documentation: https://kylebarron.dev/stata_kernel/"
  echo ""
}

# Main entry point.
main() {
  local do_uninstall=false
  local remove_config=false
  
  # Parse arguments
  for arg in "$@"; do
    case "$arg" in
      --uninstall) do_uninstall=true ;;
      --remove-config) remove_config=true ;;
      --help|-h)
        echo "Usage: $0 [--uninstall] [--remove-config]"
        echo ""
        echo "Options:"
        echo "  --uninstall       Remove stata_kernel installation"
        echo "  --remove-config   Also remove config file (with --uninstall)"
        exit 0
        ;;
    esac
  done
  
  if [[ "$do_uninstall" == "true" ]]; then
    uninstall "$remove_config"
    exit 0
  fi
  
  echo "Installing stata_kernel for Zed Jupyter integration..."
  echo ""
  
  check_prerequisites
  detect_stata_app
  
  print_info "Detected Stata $STATA_EDITION at $STATA_PATH"
  
  create_venv
  install_packages
  write_config
  register_kernel
  verify_kernel_spec
  
  print_summary
}

# Entry point guard - run main if executed directly
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]] || [[ -z "${BASH_SOURCE[0]:-}" ]]; then
  main "$@"
fi
