#!/usr/bin/env bash
#
# validate.sh - Extension Build Validation Suite
#
# Validates that the Sight Zed extension can build successfully with its
# specified LSP and tree-sitter grammar revisions.
#
# Usage: ./validate.sh [OPTIONS]
#
# Options:
#   --all           Run all validations (default)
#   --lsp           Validate LSP release exists with required assets
#   --grammar-rev   Validate grammar revision exists
#   --build         Build extension WASM
#   --grammar-build Build grammar from specified revision
#   --help          Show this help message
#
# Environment Variables:
#   GITHUB_TOKEN    Optional GitHub token for API rate limiting

set -euo pipefail

# Script directory (for relative paths)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Result tracking
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Required LSP binary assets
REQUIRED_ASSETS=(
    "sight-darwin-arm64"
    "sight-linux-arm64"
    "sight-linux-x64"
    "sight-windows-x64.exe"
    "sight-windows-arm64.exe"
)

# GitHub repositories
LSP_REPO="jbearak/sight"
GRAMMAR_REPO="jbearak/tree-sitter-stata"

#######################################
# Print colored output
#######################################
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

#######################################
# Show usage information
#######################################
show_help() {
    cat << EOF
Extension Build Validation Suite

Validates that the Sight Zed extension can build successfully with its
specified LSP and tree-sitter grammar revisions.

Usage: ./validate.sh [OPTIONS]

Options:
  --all           Run all validations (default if no options specified)
  --lsp           Validate LSP release exists with required assets
  --grammar-rev   Validate grammar revision exists
  --build         Build extension WASM
  --grammar-build Build grammar from specified revision
  --help          Show this help message

Environment Variables:
  GITHUB_TOKEN    Optional GitHub token for API rate limiting

Examples:
  ./validate.sh                 # Run all validations
  ./validate.sh --lsp           # Only check LSP release
  ./validate.sh --build         # Only build extension WASM
  ./validate.sh --lsp --build   # Check LSP and build extension

Exit Codes:
  0   All validations passed
  1   One or more validations failed
EOF
}

#######################################
# Record a validation result
# Arguments:
#   $1 - 0 for pass, non-zero for fail
#   $2 - Description of the check
#######################################
record_result() {
    local status=$1
    local description=$2
    ((TOTAL_CHECKS++)) || true
    
    if [[ $status -eq 0 ]]; then
        ((PASSED_CHECKS++)) || true
        print_pass "$description"
    else
        ((FAILED_CHECKS++)) || true
        print_fail "$description"
    fi
}

#######################################
# Configuration Parser Functions
#######################################

# Extract SERVER_VERSION from src/lib.rs
# Output: Version string (e.g., "v0.1.11")
extract_server_version() {
    local lib_rs="${SCRIPT_DIR}/src/lib.rs"
    
    if [[ ! -f "$lib_rs" ]]; then
        echo "ERROR: File not found: $lib_rs" >&2
        return 1
    fi
    
    local version
    # Use portable sed instead of grep -P (not available on macOS)
    version=$(grep 'const SERVER_VERSION' "$lib_rs" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' || true)
    
    if [[ -z "$version" ]]; then
        echo "ERROR: SERVER_VERSION not found in $lib_rs" >&2
        return 1
    fi
    
    echo "$version"
}

# Extract grammar revision from extension.toml
# Output: Commit SHA string
extract_grammar_revision() {
    local extension_toml="${SCRIPT_DIR}/extension.toml"
    
    if [[ ! -f "$extension_toml" ]]; then
        echo "ERROR: File not found: $extension_toml" >&2
        return 1
    fi
    
    local revision
    # Use portable sed instead of grep -P (not available on macOS)
    revision=$(grep -A5 '\[grammars\.stata\]' "$extension_toml" | grep 'rev' | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null || true)
    
    if [[ -z "$revision" ]]; then
        echo "ERROR: Grammar revision not found in $extension_toml" >&2
        return 1
    fi
    
    echo "$revision"
}

# Normalize version string (ensure it has 'v' prefix)
normalize_version() {
    local version="$1"
    if [[ "$version" =~ ^v ]]; then
        echo "$version"
    else
        echo "v$version"
    fi
}

#######################################
# LSP Release Validator
#######################################

# Get GitHub API headers
get_github_headers() {
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "-H \"Authorization: token $GITHUB_TOKEN\""
    fi
    echo "-H \"Accept: application/vnd.github.v3+json\""
}

# Validate LSP release exists with required assets
# Arguments:
#   $1 - Version tag (e.g., "v0.1.11")
# Returns: 0 on success, 1 on failure
validate_lsp_release() {
    local version="$1"
    local normalized_version
    normalized_version=$(normalize_version "$version")
    
    print_info "Checking LSP release: $normalized_version"
    
    # Build curl command with optional auth
    local curl_opts=(-s -f)
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        curl_opts+=(-H "Authorization: token $GITHUB_TOKEN")
    fi
    curl_opts+=(-H "Accept: application/vnd.github.v3+json")
    
    local api_url="https://api.github.com/repos/${LSP_REPO}/releases/tags/${normalized_version}"
    
    local response
    if ! response=$(curl "${curl_opts[@]}" "$api_url" 2>&1); then
        # Try without 'v' prefix if it failed
        if [[ "$normalized_version" =~ ^v ]]; then
            local alt_version="${normalized_version#v}"
            api_url="https://api.github.com/repos/${LSP_REPO}/releases/tags/${alt_version}"
            if ! response=$(curl "${curl_opts[@]}" "$api_url" 2>&1); then
                print_fail "Release not found: $normalized_version (also tried $alt_version)"
                return 1
            fi
        else
            print_fail "Release not found: $normalized_version"
            return 1
        fi
    fi
    
    # Check for rate limiting
    if echo "$response" | grep -q "API rate limit exceeded"; then
        print_fail "GitHub API rate limit exceeded. Set GITHUB_TOKEN environment variable."
        return 1
    fi
    
    # Extract asset names from response (portable, no grep -P)
    local assets
    assets=$(echo "$response" | grep -o '"name":[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/' || true)
    
    # Check for required assets
    local missing_assets=()
    for required in "${REQUIRED_ASSETS[@]}"; do
        if ! echo "$assets" | grep -q "^${required}$"; then
            missing_assets+=("$required")
        fi
    done
    
    if [[ ${#missing_assets[@]} -gt 0 ]]; then
        print_fail "Missing assets in release $normalized_version:"
        for asset in "${missing_assets[@]}"; do
            echo "  - $asset"
        done
        return 1
    fi
    
    print_pass "LSP release $normalized_version exists with all required assets"
    return 0
}

#######################################
# Grammar Revision Validator
#######################################

# Validate grammar revision exists
# Arguments:
#   $1 - Commit SHA
# Returns: 0 on success, 1 on failure
validate_grammar_revision() {
    local revision="$1"
    
    print_info "Checking grammar revision: $revision"
    
    # Build curl command with optional auth (no -f flag to capture response body)
    local curl_opts=(-s -w "\n%{http_code}")
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        curl_opts+=(-H "Authorization: token $GITHUB_TOKEN")
    fi
    curl_opts+=(-H "Accept: application/vnd.github.v3+json")
    
    local api_url="https://api.github.com/repos/${GRAMMAR_REPO}/commits/${revision}"
    
    local response
    local http_code
    response=$(curl "${curl_opts[@]}" "$api_url" 2>&1)
    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')
    
    # Check for rate limiting (HTTP 403 with rate limit message)
    if [[ "$http_code" == "403" ]] && echo "$response" | grep -q "API rate limit exceeded"; then
        print_fail "GitHub API rate limit exceeded. Set GITHUB_TOKEN environment variable."
        return 1
    fi
    
    # Check for not found (HTTP 404) or other errors
    if [[ "$http_code" != "200" ]]; then
        print_fail "Grammar revision not found: $revision (HTTP $http_code)"
        return 1
    fi
    
    print_pass "Grammar revision $revision exists"
    return 0
}

#######################################
# Extension Build Validator
#######################################

# Build extension and verify output
# Returns: 0 on success, 1 on failure
validate_extension_build() {
    print_info "Building extension WASM..."
    
    cd "$SCRIPT_DIR"
    
    # Check if wasm32-wasip1 target is installed
    if ! rustup target list --installed 2>/dev/null | grep -q "wasm32-wasip1"; then
        print_fail "Missing Rust target: wasm32-wasip1"
        echo "  Run: rustup target add wasm32-wasip1"
        return 1
    fi
    
    # Run cargo build
    local build_output
    if ! build_output=$(cargo build --release --target wasm32-wasip1 2>&1); then
        print_fail "Extension build failed:"
        echo "$build_output"
        return 1
    fi
    
    # Check for output file
    local wasm_file="${SCRIPT_DIR}/target/wasm32-wasip1/release/sight_extension.wasm"
    if [[ ! -f "$wasm_file" ]]; then
        print_fail "WASM output file not found: $wasm_file"
        return 1
    fi
    
    # Report file size
    local file_size
    file_size=$(du -h "$wasm_file" | cut -f1)
    print_pass "Extension built successfully: $wasm_file ($file_size)"
    
    return 0
}

#######################################
# Grammar Build Validator
#######################################

# Build grammar from specified revision
# Arguments:
#   $1 - Commit SHA
# Returns: 0 on success, 1 on failure
validate_grammar_build() {
    local revision="$1"
    local tmpdir=""
    
    print_info "Building grammar from revision: $revision"
    
    # Check if tree-sitter CLI is installed
    if ! command -v tree-sitter &>/dev/null; then
        print_fail "tree-sitter CLI not found"
        echo "  Install: npm install -g tree-sitter-cli"
        return 1
    fi
    
    # Create temp directory
    tmpdir=$(mktemp -d)
    
    # Cleanup function
    cleanup_tmpdir() {
        if [[ -n "$tmpdir" && -d "$tmpdir" ]]; then
            rm -rf "$tmpdir"
        fi
    }
    
    # Set trap for cleanup on exit
    trap cleanup_tmpdir EXIT
    
    # Clone repository
    print_info "Cloning tree-sitter-stata..."
    if ! git clone --quiet "https://github.com/${GRAMMAR_REPO}" "$tmpdir/tree-sitter-stata" 2>&1; then
        print_fail "Failed to clone grammar repository"
        cleanup_tmpdir
        trap - EXIT
        return 1
    fi
    
    cd "$tmpdir/tree-sitter-stata"
    
    # Checkout specific revision
    if ! git checkout --quiet "$revision" 2>&1; then
        print_fail "Failed to checkout revision: $revision"
        cleanup_tmpdir
        trap - EXIT
        return 1
    fi
    
    # Build grammar to WASM
    print_info "Building grammar to WASM..."
    local build_output
    if ! build_output=$(tree-sitter build --wasm 2>&1); then
        print_fail "Grammar build failed:"
        echo "$build_output"
        cleanup_tmpdir
        trap - EXIT
        return 1
    fi
    
    # Verify WASM file was produced
    local wasm_files
    wasm_files=$(find . -maxdepth 1 -name "*.wasm" -type f 2>/dev/null || true)
    
    if [[ -z "$wasm_files" ]]; then
        print_fail "Grammar WASM file not produced"
        cleanup_tmpdir
        trap - EXIT
        return 1
    fi
    
    print_pass "Grammar built successfully"
    
    # Cleanup
    cleanup_tmpdir
    trap - EXIT
    
    return 0
}

#######################################
# Main Orchestration
#######################################

main() {
    local run_all=false
    local run_lsp=false
    local run_grammar_rev=false
    local run_build=false
    local run_grammar_build=false
    
    # Parse arguments
    if [[ $# -eq 0 ]]; then
        run_all=true
    else
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --all)
                    run_all=true
                    shift
                    ;;
                --lsp)
                    run_lsp=true
                    shift
                    ;;
                --grammar-rev)
                    run_grammar_rev=true
                    shift
                    ;;
                --build)
                    run_build=true
                    shift
                    ;;
                --grammar-build)
                    run_grammar_build=true
                    shift
                    ;;
                --help|-h)
                    show_help
                    exit 0
                    ;;
                *)
                    echo "Unknown option: $1"
                    show_help
                    exit 1
                    ;;
            esac
        done
    fi
    
    # If --all, enable all checks
    if [[ "$run_all" == true ]]; then
        run_lsp=true
        run_grammar_rev=true
        run_build=true
        run_grammar_build=true
    fi
    
    echo "========================================"
    echo "Extension Build Validation Suite"
    echo "========================================"
    echo ""
    
    # Extract configuration
    local server_version=""
    local grammar_revision=""
    
    if [[ "$run_lsp" == true || "$run_build" == true ]]; then
        print_info "Extracting server version from src/lib.rs..."
        if ! server_version=$(extract_server_version); then
            record_result 1 "Failed to extract server version"
        else
            print_info "Server version: $server_version"
        fi
    fi
    
    if [[ "$run_grammar_rev" == true || "$run_grammar_build" == true ]]; then
        print_info "Extracting grammar revision from extension.toml..."
        if ! grammar_revision=$(extract_grammar_revision); then
            record_result 1 "Failed to extract grammar revision"
        else
            print_info "Grammar revision: $grammar_revision"
        fi
    fi
    
    echo ""
    
    # Run validations
    if [[ "$run_lsp" == true && -n "$server_version" ]]; then
        echo "--- LSP Release Validation ---"
        if validate_lsp_release "$server_version"; then
            record_result 0 "LSP release validation"
        else
            record_result 1 "LSP release validation"
        fi
        echo ""
    fi
    
    if [[ "$run_grammar_rev" == true && -n "$grammar_revision" ]]; then
        echo "--- Grammar Revision Validation ---"
        if validate_grammar_revision "$grammar_revision"; then
            record_result 0 "Grammar revision validation"
        else
            record_result 1 "Grammar revision validation"
        fi
        echo ""
    fi
    
    if [[ "$run_build" == true ]]; then
        echo "--- Extension Build Validation ---"
        if validate_extension_build; then
            record_result 0 "Extension build validation"
        else
            record_result 1 "Extension build validation"
        fi
        echo ""
    fi
    
    if [[ "$run_grammar_build" == true && -n "$grammar_revision" ]]; then
        echo "--- Grammar Build Validation ---"
        if validate_grammar_build "$grammar_revision"; then
            record_result 0 "Grammar build validation"
        else
            record_result 1 "Grammar build validation"
        fi
        echo ""
    fi
    
    # Print summary
    echo "========================================"
    echo "Validation Summary"
    echo "========================================"
    echo "Total checks: $TOTAL_CHECKS"
    echo -e "Passed: ${GREEN}$PASSED_CHECKS${NC}"
    echo -e "Failed: ${RED}$FAILED_CHECKS${NC}"
    echo ""
    
    # Exit with appropriate code
    if [[ $FAILED_CHECKS -gt 0 ]]; then
        print_fail "Validation failed!"
        exit 1
    else
        print_pass "All validations passed!"
        exit 0
    fi
}

# Run main function
main "$@"
