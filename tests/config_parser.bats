#!/usr/bin/env bats

load test_helpers

#
# config_parser.bats - Property-based tests for configuration parser functions
#
# Tests Property 1: Version extraction consistency
# Tests Property 2: Revision extraction consistency
#
# **Validates: Requirements 1.1, 6.1, 6.2**

# Setup - load test helpers and source validation functions
setup() {
    # Get the directory containing this test file
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    
    # Create temp directory for test files
    TEMP_DIR=$(mktemp -d)
    
    # Source the validation script functions (without running main)
    # Create a temporary file that sources validate.sh but doesn't run main
    local tmp_source=$(mktemp)
    sed '/^main "\$@"$/d' "$PROJECT_DIR/validate.sh" > "$tmp_source"
    # Override SCRIPT_DIR to use our temp directory
    sed -i.bak "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$TEMP_DIR\"|" "$tmp_source"
    source "$tmp_source"
    rm -f "$tmp_source" "$tmp_source.bak"
}

# Teardown - cleanup temp files
teardown() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Helper: Create a lib.rs file with a specific version
create_lib_rs() {
    local version="$1"
    mkdir -p "$TEMP_DIR/src"
    cat > "$TEMP_DIR/src/lib.rs" << EOF
use zed_extension_api::{self as zed, DownloadedFileType, Result};

const SERVER_VERSION: &str = "$version";

struct SightExtension {
    cached_binary_path: Option<String>,
}

impl zed::Extension for SightExtension {
    fn new() -> Self {
        Self { cached_binary_path: None }
    }
}

zed::register_extension!(SightExtension);
EOF
}

# Helper: Create an extension.toml file with a specific revision
create_extension_toml() {
    local revision="$1"
    cat > "$TEMP_DIR/extension.toml" << EOF
id = "sight"
name = "Sight - Stata Language Server"
description = "Language support for Stata using LSP"
version = "0.1.10"
schema_version = 1
authors = ["Jonathan Marc Bearak"]
repository = "https://github.com/jbearak/sight-zed"

[lib]
kind = "Rust"
version = "0.7.0"

[grammars.stata]
repository = "https://github.com/jbearak/tree-sitter-stata"
rev = "$revision"

[language_servers.sight]
name = "Sight"
language = "Stata"
EOF
}

#######################################
# Property 1: Version extraction consistency
# For any valid src/lib.rs file containing a SERVER_VERSION constant with
# arbitrary version strings, the extracted version string SHALL exactly
# match the literal value between the quotes in the source file.
# **Validates: Requirements 1.1, 6.1**
#######################################

# Test: Extract version with 'v' prefix
@test "Property 1: extract version with v prefix - v1.2.3" {
    local version="v1.2.3"
    create_lib_rs "$version"
    
    local extracted
    extracted=$(extract_server_version)
    
    [ "$extracted" = "$version" ]
}

# Test: Extract version without 'v' prefix
@test "Property 1: extract version without v prefix - 1.2.3" {
    local version="1.2.3"
    create_lib_rs "$version"
    
    local extracted
    extracted=$(extract_server_version)
    
    [ "$extracted" = "$version" ]
}

# Test: Extract version with double-digit components
@test "Property 1: extract version with double-digit components - v10.20.30" {
    local version="v10.20.30"
    create_lib_rs "$version"
    
    local extracted
    extracted=$(extract_server_version)
    
    [ "$extracted" = "$version" ]
}

# Test: Extract version with pre-release suffix
@test "Property 1: extract version with pre-release suffix - v1.0.0-beta.1" {
    local version="v1.0.0-beta.1"
    create_lib_rs "$version"
    
    local extracted
    extracted=$(extract_server_version)
    
    [ "$extracted" = "$version" ]
}

# Test: Extract version with build metadata
@test "Property 1: extract version with build metadata - v1.0.0+build.123" {
    local version="v1.0.0+build.123"
    create_lib_rs "$version"
    
    local extracted
    extracted=$(extract_server_version)
    
    [ "$extracted" = "$version" ]
}

# Property-based test: Random versions (run 10 iterations)
@test "Property 1: version extraction consistency - random versions" {
    for i in {1..10}; do
        local version
        version=$(generate_random_version)
        
        create_lib_rs "$version"
        
        local extracted
        extracted=$(extract_server_version)
        
        if [ "$extracted" != "$version" ]; then
            echo "Failed for version: $version, got: $extracted"
            return 1
        fi
    done
}

# Test: Error on missing file
@test "Property 1: error on missing src/lib.rs" {
    # Don't create the file
    rm -rf "$TEMP_DIR/src"
    
    run extract_server_version
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: File not found"* ]]
}

# Test: Error on missing SERVER_VERSION constant
@test "Property 1: error on missing SERVER_VERSION constant" {
    mkdir -p "$TEMP_DIR/src"
    cat > "$TEMP_DIR/src/lib.rs" << 'EOF'
use zed_extension_api::{self as zed, Result};

struct SightExtension {}

impl zed::Extension for SightExtension {
    fn new() -> Self {
        Self {}
    }
}
EOF
    
    run extract_server_version
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: SERVER_VERSION not found"* ]]
}

#######################################
# Property 2: Revision extraction consistency
# For any valid extension.toml file containing a [grammars.stata] section
# with a rev field, the extracted revision SHALL exactly match the literal
# commit SHA value in the file.
# **Validates: Requirements 2.1, 6.2**
#######################################

# Test: Extract standard 40-character SHA
@test "Property 2: extract standard 40-char SHA" {
    local revision="872da1d652dd32cc871ea4a3c3f84bdea7c68c8c"
    create_extension_toml "$revision"
    
    local extracted
    extracted=$(extract_grammar_revision)
    
    [ "$extracted" = "$revision" ]
}

# Test: Extract SHA with all lowercase hex
@test "Property 2: extract SHA with lowercase hex" {
    local revision="abcdef0123456789abcdef0123456789abcdef01"
    create_extension_toml "$revision"
    
    local extracted
    extracted=$(extract_grammar_revision)
    
    [ "$extracted" = "$revision" ]
}

# Test: Extract SHA with all uppercase hex
@test "Property 2: extract SHA with uppercase hex" {
    local revision="ABCDEF0123456789ABCDEF0123456789ABCDEF01"
    create_extension_toml "$revision"
    
    local extracted
    extracted=$(extract_grammar_revision)
    
    [ "$extracted" = "$revision" ]
}

# Test: Extract SHA with mixed case hex
@test "Property 2: extract SHA with mixed case hex" {
    local revision="AbCdEf0123456789aBcDeF0123456789AbCdEf01"
    create_extension_toml "$revision"
    
    local extracted
    extracted=$(extract_grammar_revision)
    
    [ "$extracted" = "$revision" ]
}

# Test: Extract SHA with all zeros
@test "Property 2: extract SHA with all zeros" {
    local revision="0000000000000000000000000000000000000000"
    create_extension_toml "$revision"
    
    local extracted
    extracted=$(extract_grammar_revision)
    
    [ "$extracted" = "$revision" ]
}

# Property-based test: Random SHAs (run 10 iterations)
@test "Property 2: revision extraction consistency - random SHAs" {
    for i in {1..10}; do
        local revision
        revision=$(generate_random_sha)
        
        create_extension_toml "$revision"
        
        local extracted
        extracted=$(extract_grammar_revision)
        
        if [ "$extracted" != "$revision" ]; then
            echo "Failed for revision: $revision, got: $extracted"
            return 1
        fi
    done
}

# Test: Error on missing file
@test "Property 2: error on missing extension.toml" {
    # Don't create the file
    rm -f "$TEMP_DIR/extension.toml"
    
    run extract_grammar_revision
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: File not found"* ]]
}

# Test: Error on missing grammars.stata section
@test "Property 2: error on missing grammars.stata section" {
    cat > "$TEMP_DIR/extension.toml" << 'EOF'
id = "sight"
name = "Sight - Stata Language Server"
version = "0.1.10"

[lib]
kind = "Rust"
version = "0.7.0"
EOF
    
    run extract_grammar_revision
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: Grammar revision not found"* ]]
}

# Test: Error on missing rev field in grammars.stata section
@test "Property 2: error on missing rev field" {
    cat > "$TEMP_DIR/extension.toml" << 'EOF'
id = "sight"
name = "Sight - Stata Language Server"
version = "0.1.10"

[grammars.stata]
repository = "https://github.com/jbearak/tree-sitter-stata"
EOF
    
    run extract_grammar_revision
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: Grammar revision not found"* ]]
}

# Test: Extract revision when there are multiple grammar sections
@test "Property 2: extract revision with multiple grammar sections" {
    local revision="872da1d652dd32cc871ea4a3c3f84bdea7c68c8c"
    cat > "$TEMP_DIR/extension.toml" << EOF
id = "sight"
name = "Sight - Stata Language Server"
version = "0.1.10"

[grammars.other]
repository = "https://github.com/example/tree-sitter-other"
rev = "1111111111111111111111111111111111111111"

[grammars.stata]
repository = "https://github.com/jbearak/tree-sitter-stata"
rev = "$revision"

[grammars.another]
repository = "https://github.com/example/tree-sitter-another"
rev = "2222222222222222222222222222222222222222"
EOF
    
    local extracted
    extracted=$(extract_grammar_revision)
    
    [ "$extracted" = "$revision" ]
}
