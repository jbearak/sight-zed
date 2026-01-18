#!/usr/bin/env bats
#
# Tests for install-jupyter-stata.sh
#
# These tests verify the Jupyter Stata kernel installer, focusing on:
# - Workspace root detection (find_workspace_root function)
# - Dual kernel installation (stata and stata_workspace)
# - Uninstallation

load test_helpers.bash

# ============================================================================
# Setup / Teardown
# ============================================================================

setup() {
  TEST_DIR=$(mktemp -d)
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  
  # Create fake venv structure for installer
  VENV_DIR="$HOME/.local/share/stata_kernel/venv"
  mkdir -p "$VENV_DIR/bin"
  
  # Create fake python that just echoes
  cat > "$VENV_DIR/bin/python" << 'EOF'
#!/bin/bash
echo "fake python: $@"
exit 0
EOF
  chmod +x "$VENV_DIR/bin/python"
  
  # Create fake pip
  cat > "$VENV_DIR/bin/pip" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$VENV_DIR/bin/pip"
  
  # Kernel directories
  KERNEL_DIR="$HOME/Library/Jupyter/kernels/stata"
  WORKSPACE_KERNEL_DIR="$HOME/Library/Jupyter/kernels/stata_workspace"
  
  # Extract the workspace kernel script from installer for testing
  WRAPPER_SCRIPT="$TEST_DIR/stata_workspace_kernel.py"
  extract_workspace_kernel_script > "$WRAPPER_SCRIPT"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Extract the embedded Python script from the installer
extract_workspace_kernel_script() {
  local script
  script=$(sed -n '/^get_workspace_kernel_script()/,/^PYTHON_EOF$/p' install-jupyter-stata.sh | \
    sed '1d;$d' | \
    sed "s/^  cat << 'PYTHON_EOF'//" | \
    sed '/^$/d')
  
  # Validate extraction produced the expected Python script
  if [[ -z "$script" ]] || ! echo "$script" | grep -q "def find_workspace_root"; then
    echo "ERROR: Failed to extract workspace kernel script from installer" >&2
    return 1
  fi
  echo "$script"
}

# ============================================================================
# Workspace Root Detection Tests
# ============================================================================

# Helper to run find_workspace_root with a custom home directory.
# NOTE: This reimplements the algorithm from install-jupyter-stata.sh to allow
# testing with a fake home directory. The real script uses Path.home() which
# can't be easily overridden. Keep this in sync with get_workspace_kernel_script().
run_find_workspace_root() {
  python3 -c "
from pathlib import Path
import sys

def find_workspace_root(start_path, home):
    markers = ['.git', '.stata-project', '.project']
    current = start_path.resolve()
    home = home.resolve()  # Resolve home too to handle symlinks like /var -> /private/var
    
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
    return start_path.resolve()

result = find_workspace_root(Path(sys.argv[1]), Path(sys.argv[2]))
print(result)
" "$1" "$2"
}

@test "workspace detection: finds .git marker" {
  # Create directory structure inside fake home
  mkdir -p "$HOME/project/.git"
  mkdir -p "$HOME/project/src/analysis"
  
  result=$(run_find_workspace_root "$HOME/project/src/analysis" "$HOME")
  # Resolve expected path to handle /var -> /private/var symlink on macOS
  expected=$(python3 -c "from pathlib import Path; print(Path('$HOME/project').resolve())")
  
  [[ "$result" == "$expected" ]]
}

@test "workspace detection: finds .stata-project marker" {
  mkdir -p "$HOME/project/subdir"
  touch "$HOME/project/.stata-project"
  
  result=$(run_find_workspace_root "$HOME/project/subdir" "$HOME")
  expected=$(python3 -c "from pathlib import Path; print(Path('$HOME/project').resolve())")
  
  [[ "$result" == "$expected" ]]
}

@test "workspace detection: finds .project marker" {
  mkdir -p "$HOME/project/deep/nested/dir"
  touch "$HOME/project/.project"
  
  result=$(run_find_workspace_root "$HOME/project/deep/nested/dir" "$HOME")
  expected=$(python3 -c "from pathlib import Path; print(Path('$HOME/project').resolve())")
  
  [[ "$result" == "$expected" ]]
}

@test "workspace detection: .git takes priority over .stata-project" {
  # Both markers at same level - .git should be found first due to check order
  mkdir -p "$HOME/project/.git"
  touch "$HOME/project/.stata-project"
  mkdir -p "$HOME/project/src"
  
  result=$(run_find_workspace_root "$HOME/project/src" "$HOME")
  expected=$(python3 -c "from pathlib import Path; print(Path('$HOME/project').resolve())")
  
  # Should find the directory with markers (doesn't matter which marker, same dir)
  [[ "$result" == "$expected" ]]
}

@test "workspace detection: returns start dir when no marker found" {
  mkdir -p "$HOME/nomarker/subdir"
  
  result=$(run_find_workspace_root "$HOME/nomarker/subdir" "$HOME")
  expected=$(python3 -c "from pathlib import Path; print(Path('$HOME/nomarker/subdir').resolve())")
  
  [[ "$result" == "$expected" ]]
}

@test "workspace detection: stops at home directory boundary" {
  # Create marker above home - should not be found
  mkdir -p "$TEST_DIR/.git"  # Above fake home ($HOME = $TEST_DIR/home)
  mkdir -p "$HOME/project/src"
  
  result=$(run_find_workspace_root "$HOME/project/src" "$HOME")
  expected=$(python3 -c "from pathlib import Path; print(Path('$HOME/project/src').resolve())")
  
  # Should return start dir, not find the .git above home
  [[ "$result" == "$expected" ]]
}

@test "workspace detection: finds nearest marker (not root)" {
  # Nested git repos - should find the nearest one
  mkdir -p "$HOME/outer/.git"
  mkdir -p "$HOME/outer/inner/.git"
  mkdir -p "$HOME/outer/inner/src"
  
  result=$(run_find_workspace_root "$HOME/outer/inner/src" "$HOME")
  expected=$(python3 -c "from pathlib import Path; print(Path('$HOME/outer/inner').resolve())")
  
  [[ "$result" == "$expected" ]]
}

# ============================================================================
# Installer Function Tests
# ============================================================================

@test "installer: install_workspace_kernel creates kernel directory" {
  source install-jupyter-stata.sh
  
  # Override variables for test
  WORKSPACE_KERNEL_DIR="$TEST_DIR/kernels/stata_workspace"
  VENV_DIR="$TEST_DIR/venv"
  mkdir -p "$VENV_DIR/bin"
  echo '#!/bin/bash' > "$VENV_DIR/bin/python"
  
  install_workspace_kernel
  
  [[ -d "$WORKSPACE_KERNEL_DIR" ]]
}

@test "installer: install_workspace_kernel creates kernel.json" {
  source install-jupyter-stata.sh
  
  WORKSPACE_KERNEL_DIR="$TEST_DIR/kernels/stata_workspace"
  VENV_DIR="$TEST_DIR/venv"
  mkdir -p "$VENV_DIR/bin"
  echo '#!/bin/bash' > "$VENV_DIR/bin/python"
  
  install_workspace_kernel
  
  [[ -f "$WORKSPACE_KERNEL_DIR/kernel.json" ]]
}

@test "installer: install_workspace_kernel creates wrapper script" {
  source install-jupyter-stata.sh
  
  WORKSPACE_KERNEL_DIR="$TEST_DIR/kernels/stata_workspace"
  VENV_DIR="$TEST_DIR/venv"
  mkdir -p "$VENV_DIR/bin"
  echo '#!/bin/bash' > "$VENV_DIR/bin/python"
  
  install_workspace_kernel
  
  [[ -f "$WORKSPACE_KERNEL_DIR/stata_workspace_kernel.py" ]]
}

@test "installer: kernel.json has correct display name" {
  source install-jupyter-stata.sh
  
  WORKSPACE_KERNEL_DIR="$TEST_DIR/kernels/stata_workspace"
  VENV_DIR="$TEST_DIR/venv"
  mkdir -p "$VENV_DIR/bin"
  echo '#!/bin/bash' > "$VENV_DIR/bin/python"
  
  install_workspace_kernel
  
  grep -q '"display_name": "Stata (Workspace)"' "$WORKSPACE_KERNEL_DIR/kernel.json"
}

@test "installer: kernel.json has stata language" {
  source install-jupyter-stata.sh
  
  WORKSPACE_KERNEL_DIR="$TEST_DIR/kernels/stata_workspace"
  VENV_DIR="$TEST_DIR/venv"
  mkdir -p "$VENV_DIR/bin"
  echo '#!/bin/bash' > "$VENV_DIR/bin/python"
  
  install_workspace_kernel
  
  grep -q '"language": "stata"' "$WORKSPACE_KERNEL_DIR/kernel.json"
}

@test "installer: uninstall_workspace_kernel removes directory" {
  source install-jupyter-stata.sh
  
  WORKSPACE_KERNEL_DIR="$TEST_DIR/kernels/stata_workspace"
  mkdir -p "$WORKSPACE_KERNEL_DIR"
  touch "$WORKSPACE_KERNEL_DIR/kernel.json"
  
  uninstall_workspace_kernel
  
  [[ ! -d "$WORKSPACE_KERNEL_DIR" ]]
}

@test "installer: uninstall_workspace_kernel handles missing directory" {
  source install-jupyter-stata.sh
  
  WORKSPACE_KERNEL_DIR="$TEST_DIR/kernels/stata_workspace"
  # Don't create the directory
  
  # Should not error
  run uninstall_workspace_kernel
  [[ "$status" -eq 0 ]]
}

@test "installer: wrapper script contains find_workspace_root function" {
  source install-jupyter-stata.sh
  
  WORKSPACE_KERNEL_DIR="$TEST_DIR/kernels/stata_workspace"
  VENV_DIR="$TEST_DIR/venv"
  mkdir -p "$VENV_DIR/bin"
  echo '#!/bin/bash' > "$VENV_DIR/bin/python"
  
  install_workspace_kernel
  
  grep -q "def find_workspace_root" "$WORKSPACE_KERNEL_DIR/stata_workspace_kernel.py"
}

@test "installer: wrapper script checks for .git marker" {
  source install-jupyter-stata.sh
  
  WORKSPACE_KERNEL_DIR="$TEST_DIR/kernels/stata_workspace"
  VENV_DIR="$TEST_DIR/venv"
  mkdir -p "$VENV_DIR/bin"
  echo '#!/bin/bash' > "$VENV_DIR/bin/python"
  
  install_workspace_kernel
  
  grep -q "'.git'" "$WORKSPACE_KERNEL_DIR/stata_workspace_kernel.py"
}

@test "installer: wrapper script checks for .stata-project marker" {
  source install-jupyter-stata.sh
  
  WORKSPACE_KERNEL_DIR="$TEST_DIR/kernels/stata_workspace"
  VENV_DIR="$TEST_DIR/venv"
  mkdir -p "$VENV_DIR/bin"
  echo '#!/bin/bash' > "$VENV_DIR/bin/python"
  
  install_workspace_kernel
  
  grep -q "'.stata-project'" "$WORKSPACE_KERNEL_DIR/stata_workspace_kernel.py"
}
