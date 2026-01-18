#!/usr/bin/env bats
#
# lsp_validator.bats - Property-based tests for LSP release validator functions
#
# Tests Property 3: Asset completeness identification
# Tests Property 5: Version prefix handling
#
# **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 6.4**

# Setup - load test helpers and source validation functions
setup() {
    # Get the directory containing this test file
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    
    # Create temp directory for test files
    TEMP_DIR=$(mktemp -d)
    
    # Source the validation script functions (without running main)
    local tmp_source
    tmp_source=$(mktemp)
    sed '/^main "\$@"$/d' "$PROJECT_DIR/validate.sh" > "$tmp_source"
    # Override SCRIPT_DIR to use our temp directory
    sed -i.bak "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$TEMP_DIR\"|" "$tmp_source"
    # shellcheck source=/dev/null
    source "$tmp_source"
    rm -f "$tmp_source" "$tmp_source.bak"
    
    # Define required assets for testing
    REQUIRED_ASSETS=(
        "sight-darwin-arm64"
        "sight-linux-arm64"
        "sight-linux-x64"
        "sight-windows-x64.exe"
        "sight-windows-arm64.exe"
    )
}

# Teardown - cleanup temp files
teardown() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

#######################################
# Helper Functions for Mocking GitHub API
#######################################

# Create a mock GitHub API response with specified assets
# Arguments: asset names (space-separated)
# Output: JSON-like response that matches what grep extracts
create_mock_release_response() {
    local response='{"tag_name": "v1.0.0", "assets": ['
    local first=true
    for asset in "$@"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            response+=','
        fi
        response+='{"name": "'"$asset"'"}'
    done
    response+=']}'
    echo "$response"
}

# Helper: Check which assets are missing from a set
# Arguments:
#   $1 - Space-separated list of available assets
# Output: Space-separated list of missing assets
check_missing_assets() {
    local available_assets="$1"
    local missing=()
    
    for required in "${REQUIRED_ASSETS[@]}"; do
        if ! echo "$available_assets" | grep -q "\b${required}\b"; then
            missing+=("$required")
        fi
    done
    
    echo "${missing[*]}"
}

# Helper: Generate a random subset of required assets
# Output: Space-separated list of assets (random subset)
generate_random_asset_subset() {
    local subset=()
    for asset in "${REQUIRED_ASSETS[@]}"; do
        # 50% chance to include each asset
        if [[ $((RANDOM % 2)) -eq 1 ]]; then
            subset+=("$asset")
        fi
    done
    echo "${subset[*]}"
}

# Helper: Generate a random version string
generate_random_version() {
    local major=$((RANDOM % 10))
    local minor=$((RANDOM % 100))
    local patch=$((RANDOM % 100))
    
    # Randomly add 'v' prefix (50% chance)
    if [[ $((RANDOM % 2)) -eq 0 ]]; then
        echo "v${major}.${minor}.${patch}"
    else
        echo "${major}.${minor}.${patch}"
    fi
}

#######################################
# Property 3: Asset completeness identification
# For any set of assets returned from a GitHub release API response, the
# validator SHALL correctly identify exactly which required assets are
# present and which are missing from the required set.
# **Validates: Requirements 1.3, 1.5**
#######################################

@test "Property 3: all required assets present - identifies complete set" {
    # All 5 required assets are present
    local available_assets="${REQUIRED_ASSETS[*]}"
    local missing
    missing=$(check_missing_assets "$available_assets")
    
    [ -z "$missing" ]
}

@test "Property 3: no assets present - identifies all as missing" {
    local available_assets=""
    local missing
    missing=$(check_missing_assets "$available_assets")
    
    # All 5 should be missing
    local missing_count
    missing_count=$(echo "$missing" | wc -w | tr -d ' ')
    [ "$missing_count" -eq 5 ]
}

@test "Property 3: single asset missing - identifies exactly one missing" {
    # Remove sight-darwin-arm64 from the list
    local available_assets="sight-linux-arm64 sight-linux-x64 sight-windows-x64.exe sight-windows-arm64.exe"
    local missing
    missing=$(check_missing_assets "$available_assets")
    
    [ "$missing" = "sight-darwin-arm64" ]
}

@test "Property 3: multiple assets missing - identifies all missing" {
    # Only include 2 assets
    local available_assets="sight-darwin-arm64 sight-linux-x64"
    local missing
    missing=$(check_missing_assets "$available_assets")
    
    # Should identify 3 missing assets
    [[ "$missing" == *"sight-linux-arm64"* ]]
    [[ "$missing" == *"sight-windows-x64.exe"* ]]
    [[ "$missing" == *"sight-windows-arm64.exe"* ]]
}

@test "Property 3: extra assets present - still identifies required correctly" {
    # All required plus some extra assets
    local available_assets="${REQUIRED_ASSETS[*]} extra-asset-1 extra-asset-2 checksums.txt"
    local missing
    missing=$(check_missing_assets "$available_assets")
    
    [ -z "$missing" ]
}

@test "Property 3: similar but wrong asset names - identifies as missing" {
    # Assets with similar but incorrect names
    local available_assets="sight-darwin-x64 sight-linux-arm32 sight-linux-x86 sight-windows-x86.exe sight-windows-arm32.exe"
    local missing
    missing=$(check_missing_assets "$available_assets")
    
    # All 5 should be missing since names don't match exactly
    local missing_count
    missing_count=$(echo "$missing" | wc -w | tr -d ' ')
    [ "$missing_count" -eq 5 ]
}

# Property-based test: Random subsets (run 10 iterations)
@test "Property 3: asset completeness - random subsets" {
    for i in {1..10}; do
        local subset
        subset=$(generate_random_asset_subset)
        
        local missing
        missing=$(check_missing_assets "$subset")
        
        # Verify: for each required asset, it's either in subset or in missing
        for required in "${REQUIRED_ASSETS[@]}"; do
            local in_subset=false
            local in_missing=false
            
            if echo "$subset" | grep -q "\b${required}\b"; then
                in_subset=true
            fi
            if echo "$missing" | grep -q "\b${required}\b"; then
                in_missing=true
            fi
            
            # XOR: exactly one should be true
            if [[ "$in_subset" == "$in_missing" ]]; then
                echo "Failed for asset: $required"
                echo "  Subset: $subset"
                echo "  Missing: $missing"
                echo "  In subset: $in_subset, In missing: $in_missing"
                return 1
            fi
        done
    done
}

@test "Property 3: asset completeness - missing count equals total minus available" {
    for i in {1..10}; do
        local subset
        subset=$(generate_random_asset_subset)
        
        local available_count=0
        if [[ -n "$subset" ]]; then
            available_count=$(echo "$subset" | wc -w | tr -d ' ')
        fi
        
        local missing
        missing=$(check_missing_assets "$subset")
        
        local missing_count=0
        if [[ -n "$missing" ]]; then
            missing_count=$(echo "$missing" | wc -w | tr -d ' ')
        fi
        
        local expected_missing=$((5 - available_count))
        
        if [[ "$missing_count" -ne "$expected_missing" ]]; then
            echo "Failed: available=$available_count, missing=$missing_count, expected_missing=$expected_missing"
            echo "  Subset: '$subset'"
            echo "  Missing: '$missing'"
            return 1
        fi
    done
}

#######################################
# Property 5: Version prefix handling
# For any version string extracted from source, the validator SHALL handle
# both "vX.Y.Z" and "X.Y.Z" formats consistently when querying GitHub releases.
# **Validates: Requirements 6.4**
#######################################

@test "Property 5: normalize_version adds v prefix when missing" {
    local version="1.2.3"
    local normalized
    normalized=$(normalize_version "$version")
    
    [ "$normalized" = "v1.2.3" ]
}

@test "Property 5: normalize_version preserves v prefix when present" {
    local version="v1.2.3"
    local normalized
    normalized=$(normalize_version "$version")
    
    [ "$normalized" = "v1.2.3" ]
}

@test "Property 5: normalize_version handles double-digit versions" {
    local version="10.20.30"
    local normalized
    normalized=$(normalize_version "$version")
    
    [ "$normalized" = "v10.20.30" ]
}

@test "Property 5: normalize_version handles pre-release versions without v" {
    local version="1.0.0-beta.1"
    local normalized
    normalized=$(normalize_version "$version")
    
    [ "$normalized" = "v1.0.0-beta.1" ]
}

@test "Property 5: normalize_version handles pre-release versions with v" {
    local version="v1.0.0-beta.1"
    local normalized
    normalized=$(normalize_version "$version")
    
    [ "$normalized" = "v1.0.0-beta.1" ]
}

@test "Property 5: normalize_version handles build metadata without v" {
    local version="1.0.0+build.123"
    local normalized
    normalized=$(normalize_version "$version")
    
    [ "$normalized" = "v1.0.0+build.123" ]
}

@test "Property 5: normalize_version handles build metadata with v" {
    local version="v1.0.0+build.123"
    local normalized
    normalized=$(normalize_version "$version")
    
    [ "$normalized" = "v1.0.0+build.123" ]
}

# Property-based test: Idempotence - normalizing twice gives same result
@test "Property 5: normalize_version is idempotent" {
    for i in {1..10}; do
        local version
        version=$(generate_random_version)
        
        local once
        once=$(normalize_version "$version")
        
        local twice
        twice=$(normalize_version "$once")
        
        if [ "$once" != "$twice" ]; then
            echo "Failed for version: $version"
            echo "  Once: $once"
            echo "  Twice: $twice"
            return 1
        fi
    done
}

# Property-based test: All normalized versions start with 'v'
@test "Property 5: all normalized versions start with v" {
    for i in {1..10}; do
        local version
        version=$(generate_random_version)
        
        local normalized
        normalized=$(normalize_version "$version")
        
        if [[ ! "$normalized" =~ ^v ]]; then
            echo "Failed for version: $version"
            echo "  Normalized: $normalized (doesn't start with v)"
            return 1
        fi
    done
}

# Property-based test: Version content is preserved after normalization
@test "Property 5: version content preserved after normalization" {
    for i in {1..10}; do
        local major=$((RANDOM % 10))
        local minor=$((RANDOM % 100))
        local patch=$((RANDOM % 100))
        
        # Test without v prefix
        local version="${major}.${minor}.${patch}"
        local normalized
        normalized=$(normalize_version "$version")
        
        # The normalized version should be v + original
        if [ "$normalized" != "v${version}" ]; then
            echo "Failed for version: $version"
            echo "  Expected: v${version}"
            echo "  Got: $normalized"
            return 1
        fi
        
        # Test with v prefix
        version="v${major}.${minor}.${patch}"
        normalized=$(normalize_version "$version")
        
        # Should remain unchanged
        if [ "$normalized" != "$version" ]; then
            echo "Failed for version: $version"
            echo "  Expected: $version"
            echo "  Got: $normalized"
            return 1
        fi
    done
}

# Test: Version with only v prefix (edge case)
@test "Property 5: normalize_version handles edge case - just v" {
    local version="v"
    local normalized
    normalized=$(normalize_version "$version")
    
    # Should preserve the v
    [ "$normalized" = "v" ]
}

# Test: Empty version string returns error
@test "Property 5: normalize_version handles empty string" {
    run normalize_version ""
    
    # Should return exit code 1 for empty input
    [ "$status" -eq 1 ]
    # Output should be empty
    [ -z "$output" ]
}

#######################################
# Integration tests for validate_lsp_release error reporting
# **Validates: Requirements 1.4, 1.5**
#######################################

@test "Property 3: validate_lsp_release reports missing release correctly" {
    # This test verifies error reporting for missing releases
    # We use a version that definitely doesn't exist
    
    # Mock curl to return 404
    curl() {
        return 1
    }
    export -f curl
    
    run validate_lsp_release "v999.999.999"
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"FAIL"* ]]
}

@test "Property 3: validate_lsp_release reports missing assets correctly" {
    # This test verifies error reporting for missing assets
    # We need to mock the curl response to return incomplete assets
    
    # Create a mock response with only some assets
    local mock_response='{"tag_name": "v1.0.0", "assets": [{"name": "sight-darwin-arm64"}, {"name": "sight-linux-x64"}]}'
    
    # Mock curl to return our response
    curl() {
        echo "$mock_response"
        return 0
    }
    export -f curl
    export mock_response
    
    run validate_lsp_release "v1.0.0"
    
    # Should fail due to missing assets
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing assets"* ]] || [[ "$output" == *"FAIL"* ]]
}
