#!/usr/bin/env bats

#
# install_send_to_stata.bats - Unit tests for install-send-to-stata.sh
#
# Tests prerequisite checks, JSON merging logic, and uninstall functionality.
# **Validates: Requirements 5.1-5.8, 6.1, 6.2**

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    SCRIPT="$PROJECT_DIR/install-send-to-stata.sh"
    TEMP_DIR=$(mktemp -d)
    
    # Override HOME for testing
    export HOME="$TEMP_DIR"
    export INSTALL_DIR="$HOME/.local/bin"
    export ZED_CONFIG_DIR="$HOME/.config/zed"
}

teardown() {
    [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}

# Helper to call functions from the script
call_func() {
    local func="$1"
    shift
    bash -c "source '$SCRIPT'; $func \"\$@\"" -- "$@"
}

# ============================================================================
# Prerequisite Check Tests
# ============================================================================

@test "prerequisite: check_macos passes on macOS" {
    # We're running on macOS, so this should pass
    run call_func check_macos
    [ "$status" -eq 0 ]
}

@test "prerequisite: check_jq passes when jq installed" {
    # jq should be installed for these tests to run
    run call_func check_jq
    [ "$status" -eq 0 ]
}

# ============================================================================
# Script Installation Tests
# ============================================================================

@test "install: creates ~/.local/bin directory" {
    [[ ! -d "$INSTALL_DIR" ]]
    run call_func install_script
    [ "$status" -eq 0 ]
    [ -d "$INSTALL_DIR" ]
}

@test "install: copies send-to-stata.sh to install dir" {
    run call_func install_script
    [ "$status" -eq 0 ]
    [ -f "$INSTALL_DIR/send-to-stata.sh" ]
}

@test "install: makes script executable" {
    run call_func install_script
    [ "$status" -eq 0 ]
    [ -x "$INSTALL_DIR/send-to-stata.sh" ]
}

# ============================================================================
# Tasks Installation Tests
# ============================================================================

@test "tasks: creates tasks.json if not exists" {
    [[ ! -f "$ZED_CONFIG_DIR/tasks.json" ]]
    run call_func install_tasks
    [ "$status" -eq 0 ]
    [ -f "$ZED_CONFIG_DIR/tasks.json" ]
}

@test "tasks: tasks.json contains Stata tasks" {
    run call_func install_tasks
    [ "$status" -eq 0 ]
    
    # Check for both tasks
    run jq '.[].label' "$ZED_CONFIG_DIR/tasks.json"
    [[ "$output" == *"Stata: Send Statement"* ]]
    [[ "$output" == *"Stata: Send File"* ]]
}

@test "tasks: Send Statement command preserves selection bytes (no extra quoting)" {
    # Expand STATA_TASKS inside the sourced installer script (not in this test process).
    run bash -c 'source "$1"; printf "%s\n" "$STATA_TASKS"' bash "$SCRIPT"
    [ "$status" -eq 0 ]

    # Must use shell test and printf to read ZED_SELECTED_TEXT without python3 dependency.
    [[ "$output" == *"if [ -n"* ]]
    [[ "$output" == *"ZED_SELECTED_TEXT"* ]]
    [[ "$output" == *"printf '%s'"* ]]
}

@test "tasks: merges with existing tasks" {
    mkdir -p "$ZED_CONFIG_DIR"
    echo '[{"label": "Other Task", "command": "echo"}]' > "$ZED_CONFIG_DIR/tasks.json"
    
    run call_func install_tasks
    [ "$status" -eq 0 ]
    
    # Check existing task preserved
    run jq '.[].label' "$ZED_CONFIG_DIR/tasks.json"
    [[ "$output" == *"Other Task"* ]]
    [[ "$output" == *"Stata: Send Statement"* ]]
}

@test "tasks: replaces existing Stata tasks" {
    mkdir -p "$ZED_CONFIG_DIR"
    echo '[{"label": "Stata: Old Task", "command": "old"}]' > "$ZED_CONFIG_DIR/tasks.json"
    
    run call_func install_tasks
    [ "$status" -eq 0 ]
    
    # Old Stata task should be removed
    run jq '.[].label' "$ZED_CONFIG_DIR/tasks.json"
    [[ "$output" != *"Stata: Old Task"* ]]
    [[ "$output" == *"Stata: Send Statement"* ]]
}

# ============================================================================
# Keybindings Installation Tests
# ============================================================================

@test "keybindings: creates keymap.json if not exists" {
    [[ ! -f "$ZED_CONFIG_DIR/keymap.json" ]]
    run call_func install_keybindings
    [ "$status" -eq 0 ]
    [ -f "$ZED_CONFIG_DIR/keymap.json" ]
}

@test "keybindings: keymap.json contains Stata bindings" {
    run call_func install_keybindings
    [ "$status" -eq 0 ]
    
    # Check for context and bindings
    run jq '.[0].context' "$ZED_CONFIG_DIR/keymap.json"
    [[ "$output" == *"Editor && extension == do"* ]]
    
    run jq '.[0].bindings | keys' "$ZED_CONFIG_DIR/keymap.json"
    [[ "$output" == *"cmd-enter"* ]]
    [[ "$output" == *"shift-cmd-enter"* ]]
}

@test "keybindings: merges with existing keybindings" {
    mkdir -p "$ZED_CONFIG_DIR"
    echo '[{"context": "Other", "bindings": {"a": "b"}}]' > "$ZED_CONFIG_DIR/keymap.json"
    
    run call_func install_keybindings
    [ "$status" -eq 0 ]
    
    # Check existing binding preserved
    run jq '.[].context' "$ZED_CONFIG_DIR/keymap.json"
    [[ "$output" == *"Other"* ]]
    [[ "$output" == *"Editor && extension == do"* ]]
}

@test "keybindings: replaces existing Stata keybindings" {
    mkdir -p "$ZED_CONFIG_DIR"
    echo '[{"context": "Editor && extension == do", "bindings": {"old": "binding"}}]' > "$ZED_CONFIG_DIR/keymap.json"
    
    run call_func install_keybindings
    [ "$status" -eq 0 ]
    
    # Should have new bindings, not old
    run jq '.[0].bindings | keys' "$ZED_CONFIG_DIR/keymap.json"
    [[ "$output" != *"old"* ]]
    [[ "$output" == *"cmd-enter"* ]]
}

# ============================================================================
# Stata Detection Tests
# ============================================================================

@test "detect: reports found Stata variant" {
    run call_func detect_stata
    # Either finds Stata or warns - both are valid
    [ "$status" -eq 0 ]
}

# ============================================================================
# Uninstall Tests
# ============================================================================

@test "uninstall: removes send-to-stata.sh" {
    # First install
    call_func install_script
    [ -f "$INSTALL_DIR/send-to-stata.sh" ]
    
    # Then uninstall
    run call_func uninstall
    [ "$status" -eq 0 ]
    [ ! -f "$INSTALL_DIR/send-to-stata.sh" ]
}

@test "uninstall: removes Stata tasks from tasks.json" {
    # First install
    call_func install_tasks
    
    # Verify tasks exist
    run jq '[.[] | select(.label | startswith("Stata:"))] | length' "$ZED_CONFIG_DIR/tasks.json"
    [ "$output" -gt 0 ]
    
    # Then uninstall
    run call_func uninstall
    [ "$status" -eq 0 ]
    
    # Verify Stata tasks removed
    run jq '[.[] | select(.label | startswith("Stata:"))] | length' "$ZED_CONFIG_DIR/tasks.json"
    [ "$output" -eq 0 ]
}

@test "uninstall: removes Stata keybindings from keymap.json" {
    # First install
    call_func install_keybindings
    
    # Verify keybindings exist
    run jq '[.[] | select(.context == "Editor && extension == do")] | length' "$ZED_CONFIG_DIR/keymap.json"
    [ "$output" -gt 0 ]
    
    # Then uninstall
    run call_func uninstall
    [ "$status" -eq 0 ]
    
    # Verify Stata keybindings removed
    run jq '[.[] | select(.context == "Editor && extension == do")] | length' "$ZED_CONFIG_DIR/keymap.json"
    [ "$output" -eq 0 ]
}

@test "uninstall: preserves other tasks" {
    mkdir -p "$ZED_CONFIG_DIR"
    echo '[{"label": "Other Task", "command": "echo"}]' > "$ZED_CONFIG_DIR/tasks.json"
    
    # Install Stata tasks
    call_func install_tasks
    
    # Uninstall
    run call_func uninstall
    [ "$status" -eq 0 ]
    
    # Other task should remain
    run jq '.[].label' "$ZED_CONFIG_DIR/tasks.json"
    [[ "$output" == *"Other Task"* ]]
}

@test "uninstall: preserves other keybindings" {
    mkdir -p "$ZED_CONFIG_DIR"
    echo '[{"context": "Other", "bindings": {"a": "b"}}]' > "$ZED_CONFIG_DIR/keymap.json"
    
    # Install Stata keybindings
    call_func install_keybindings
    
    # Uninstall
    run call_func uninstall
    [ "$status" -eq 0 ]
    
    # Other keybinding should remain
    run jq '.[].context' "$ZED_CONFIG_DIR/keymap.json"
    [[ "$output" == *"Other"* ]]
}
