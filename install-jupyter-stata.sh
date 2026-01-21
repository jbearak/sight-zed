#!/bin/bash
#
# install-jupyter-stata.sh - Install stata_kernel for Zed Jupyter integration
#
# Usage:
#   ./install-jupyter-stata.sh                    Install stata_kernel
#   ./install-jupyter-stata.sh --uninstall        Remove installation
#   ./install-jupyter-stata.sh --uninstall --remove-config  Remove including config

set -euo pipefail

# Pin ipykernel for Zed compatibility / cross-platform consistency.
# If you change this, also update the Windows installer.
IPYKERNEL_VERSION="6.28.0"

# ============================================================================
# Configuration Constants
# ============================================================================
VENV_DIR="$HOME/.local/share/stata_kernel/venv"
CONFIG_FILE="$HOME/.stata_kernel.conf"
KERNEL_DIR="$HOME/Library/Jupyter/kernels/stata"
WORKSPACE_KERNEL_DIR="$HOME/Library/Jupyter/kernels/stata_workspace"

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
# Sets PYTHON_CMD to the best available python.
PYTHON_CMD=""

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

  # Determine best Python to use
  PYTHON_CMD="python3"
  local py_version
  py_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
  local py_major py_minor
  py_major=$(echo "$py_version" | cut -d. -f1)
  py_minor=$(echo "$py_version" | cut -d. -f2)

  # stata_kernel works best with Python 3.9-3.11
  # Python 3.12+ removed the 'imp' module that old ipykernel versions need
  if [[ "$py_major" -eq 3 ]] && [[ "$py_minor" -ge 12 ]]; then
    print_info "Python $py_version detected. Installer will upgrade ipykernel for compatibility."
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
# Preserve STATA_PATH if set by user as environment variable
STATA_PATH="${STATA_PATH:-}"
STATA_EDITION=""

# Detects Stata installation and determines edition.
# Sets: STATA_PATH, STATA_EDITION
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

  # Always use automation mode - this allows stata_kernel to connect to an
  # already-running Stata instance. This is the only mode supported for Zed's
  # Jupyter integration. Console mode launches a new Stata process which
  # conflicts with the running Stata GUI.
}

# ============================================================================
# Virtual Environment Management
# ============================================================================

# Creates virtual environment if it doesn't exist.
# Recreates if Python version mismatch detected.
create_venv() {
  local needs_recreate=false

  if [[ -x "$VENV_DIR/bin/python" ]]; then
    # Check if venv Python version matches system Python
    local venv_version system_version
    venv_version=$("$VENV_DIR/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "unknown")
    system_version=$("$PYTHON_CMD" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')

    if [[ "$venv_version" != "$system_version" ]]; then
      print_warning "Python version mismatch: venv=$venv_version, system=$system_version"
      print_info "Recreating virtual environment..."
      rm -rf "$VENV_DIR"
      needs_recreate=true
    else
      print_info "Virtual environment already exists at $VENV_DIR"
      return 0
    fi
  else
    needs_recreate=true
  fi

  if [[ "$needs_recreate" == true ]]; then
    print_info "Creating virtual environment..."
    mkdir -p "$(dirname "$VENV_DIR")"
    if ! "$PYTHON_CMD" -m venv "$VENV_DIR"; then
      print_error "Failed to create virtual environment"
      exit 2
    fi
    print_success "Created virtual environment at $VENV_DIR"
  fi
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

  # stata_kernel pins old ipykernel (<5.0.0) which uses the deprecated 'imp' module
  # removed in Python 3.12. Upgrade ipykernel to fix compatibility.
  local py_version py_major py_minor
  py_version=$("$VENV_DIR/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
  py_major=$(echo "$py_version" | cut -d. -f1)
  py_minor=$(echo "$py_version" | cut -d. -f2)

  if [[ "$py_major" -eq 3 ]] && [[ "$py_minor" -ge 12 ]]; then
    print_info "Installing ipykernel==$IPYKERNEL_VERSION for Zed compatibility..."
    if ! "$VENV_DIR/bin/pip" install --upgrade "ipykernel==$IPYKERNEL_VERSION" &>/dev/null; then
      print_warning "Failed to install pinned ipykernel - kernel may not start correctly"
    else
      print_success "Installed ipykernel==$IPYKERNEL_VERSION"
    fi
  fi
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

# execution_mode: How stata_kernel communicates with Stata
# Always set to 'automation' to connect to your running Stata instance.
execution_mode = automation

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

# Escapes a string for use in sed replacement.
# Handles: \ (escape char), & (match ref), | (delimiter)
escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/[&|]/\\&/g'
}

# Updates a single setting in the config file, adding it if missing.
# Args: $1=key, $2=value
update_config_setting() {
  local key="$1" value="$2"
  local escaped_value tmp_file
  escaped_value=$(escape_sed_replacement "$value")
  tmp_file=$(mktemp)
  # shellcheck disable=SC2064  # Intentional: expand now, not at signal time (local var)
  trap "rm -f '$tmp_file'" RETURN

  if grep -q "^${key}[[:space:]]*=" "$CONFIG_FILE"; then
    sed "s|^${key}[[:space:]]*=.*|${key} = ${escaped_value}|" "$CONFIG_FILE" > "$tmp_file"
    mv "$tmp_file" "$CONFIG_FILE"
  elif grep -q "^#[[:space:]]*${key}[[:space:]]*=" "$CONFIG_FILE"; then
    sed "s|^#[[:space:]]*${key}[[:space:]]*=.*|${key} = ${escaped_value}|" "$CONFIG_FILE" > "$tmp_file"
    mv "$tmp_file" "$CONFIG_FILE"
  else
    # Setting doesn't exist - add after [stata_kernel] section header
    sed "/^\[stata_kernel\]/a\\
${key} = ${escaped_value}" "$CONFIG_FILE" > "$tmp_file"
    mv "$tmp_file" "$CONFIG_FILE"
  fi
}

# Writes or updates the configuration file.
write_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    # Create new config from template
    local escaped_stata_path
    escaped_stata_path=$(escape_sed_replacement "$STATA_PATH")
    get_config_template | \
      sed "s|STATA_PATH_PLACEHOLDER|$escaped_stata_path|" > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    print_success "Created configuration at $CONFIG_FILE"
  else
    # Update existing config - preserve user settings
    update_config_setting "stata_path" "$STATA_PATH"
    update_config_setting "execution_mode" "automation"
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
# Workspace Kernel (changes to workspace root before starting Stata)
# ============================================================================

# The wrapper kernel Python script (embedded)
get_workspace_kernel_script() {
  cat << 'PYTHON_EOF'
#!/usr/bin/env python3
"""
Wrapper kernel for stata_kernel that changes to workspace root before starting.

This kernel finds the workspace root by looking for marker files (.git, .stata-project)
and changes to that directory before delegating to stata_kernel.
"""

import os
import sys
from pathlib import Path


def find_workspace_root(start_path: Path) -> Path:
    """
    Walk up from start_path looking for workspace markers.
    Returns the workspace root, or start_path if no marker found.
    """
    markers = ['.git', '.stata-project', '.project']

    current = start_path.resolve()

    # Don't go above home directory
    # Resolve home to handle symlinks like /var -> /private/var on macOS
    home = Path.home().resolve()

    while current != current.parent:
        # Stop if we've gone above home
        try:
            current.relative_to(home)
        except ValueError:
            break

        for marker in markers:
            if (current / marker).exists():
                return current
        current = current.parent

    # No marker found, return original (resolved)
    return start_path.resolve()


def main():
    # Get the current working directory (set by Zed to file's directory)
    cwd = Path.cwd()

    # Find workspace root
    workspace_root = find_workspace_root(cwd)

    # Change to workspace root
    os.chdir(workspace_root)

    # Now import and run stata_kernel
    from stata_kernel import kernel
    from ipykernel.kernelapp import IPKernelApp

    IPKernelApp.launch_instance(kernel_class=kernel.StataKernel)


if __name__ == '__main__':
    main()
PYTHON_EOF
}

# Installs the workspace kernel alongside the standard stata kernel.
install_workspace_kernel() {
  print_info "Installing workspace kernel..."

  # Create kernel directory
  mkdir -p "$WORKSPACE_KERNEL_DIR"

  # Write the wrapper script
  local wrapper_script="$WORKSPACE_KERNEL_DIR/stata_workspace_kernel.py"
  get_workspace_kernel_script > "$wrapper_script"
  chmod +x "$wrapper_script"

  # Create kernel.json
  local kernel_json="$WORKSPACE_KERNEL_DIR/kernel.json"
  cat > "$kernel_json" << EOF
{
  "argv": [
    "$VENV_DIR/bin/python",
    "$wrapper_script",
    "-f", "{connection_file}"
  ],
  "display_name": "Stata (Workspace)",
  "language": "stata"
}
EOF

  print_success "Installed workspace kernel at $WORKSPACE_KERNEL_DIR"
}

# Removes the workspace kernel.
uninstall_workspace_kernel() {
  if [[ -d "$WORKSPACE_KERNEL_DIR" ]]; then
    rm -rf "$WORKSPACE_KERNEL_DIR"
    print_success "Removed workspace kernel"
  else
    print_info "Workspace kernel not found (already removed)"
  fi
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

  # Remove workspace kernel
  uninstall_workspace_kernel

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
  echo "  Execution Mode:   automation"
  echo "  Configuration:    $CONFIG_FILE"
  echo ""
  echo "  Two kernels are installed:"
  echo ""
  echo "    Stata             Starts in the file's directory"
  echo "                      Use for scripts with paths relative to the script"
  echo ""
  echo "    Stata (Workspace) Starts in the workspace root (looks for .git)"
  echo "                      Use for scripts with paths relative to the project"
  echo ""
  echo "  The workspace kernel walks up from the file's directory looking for"
  echo "  .git, .stata-project, or .project markers to find the project root."
  echo ""
  echo "  Usage in Zed:"
  echo "    1. Open a .do file"
  echo "    2. Select 'stata' or 'stata_workspace' as the kernel"
  echo "    3. Click the 🔄 icon in the editor toolbar to execute code"
  echo "       or use Control+Shift+Enter keyboard shortcut"
  echo ""
  echo "  To set a default kernel, add to ~/.config/zed/settings.json:"
  echo ""
  echo "    \"jupyter\": {"
  echo "      \"kernel_selections\": {"
  echo "        \"stata\": \"stata_workspace\""
  echo "      }"
  echo "    }"
  echo ""
}

# Main entry point.
main() {
  local do_uninstall=false
  local remove_config=false
  local quiet=false

  # Parse arguments
  for arg in "$@"; do
    case "$arg" in
      --uninstall) do_uninstall=true ;;
      --remove-config) remove_config=true ;;
      --quiet) quiet=true ;;
      --help|-h)
        echo "Usage: $0 [--uninstall] [--remove-config] [--quiet]"
        echo ""
        echo "Options:"
        echo "  --uninstall       Remove stata_kernel installation"
        echo "  --remove-config   Also remove config file (with --uninstall)"
        echo "  --quiet           Suppress summary output"
        exit 0
        ;;
    esac
  done

  if [[ "$do_uninstall" == "true" ]]; then
    uninstall "$remove_config"
    exit 0
  fi

  if [[ "$quiet" == "false" ]]; then
    echo "Installing stata_kernel for Zed Jupyter integration..."
    echo ""
  fi

  check_prerequisites
  detect_stata_app

  if [[ "$quiet" == "false" ]]; then
    print_info "Detected Stata $STATA_EDITION at $STATA_PATH"
  fi

  create_venv
  install_packages
  write_config
  register_kernel
  verify_kernel_spec
  install_workspace_kernel

  if [[ "$quiet" == "false" ]]; then
    print_summary
  fi
}

# Entry point guard - run main if executed directly
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]] || [[ -z "${BASH_SOURCE[0]:-}" ]]; then
  main "$@"
fi
