#!/usr/bin/env bash
set -euo pipefail

# Usage: ./tools/dev/update_version.sh [new_version] [--sight-version <version>]
# If new_version is not provided, the script bumps the Cargo package patch
# version and keeps extension.toml's top-level release version in sync.

usage() {
    cat <<'EOF'
Usage: ./tools/dev/update_version.sh [new_version] [--sight-version <version>]

Arguments:
  new_version              Optional extension release version (for Cargo.toml
                           [package].version and extension.toml version)

Options:
  --sight-version <value>  Optional Sight LSP release tag to set in src/lib.rs
  --help                   Show this help message

Notes:
  - extension.toml [lib].version is not changed by this script.
  - extension.toml [lib].version should continue to match Cargo.toml's
    zed_extension_api dependency.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ ! -f "Cargo.toml" || ! -f "extension.toml" ]]; then
    echo "Error: Cargo.toml and extension.toml must both exist. Run this script from the project root." >&2
    exit 1
fi

extract_manifest_release_version() {
    awk '
        /^\[/ { exit }
        /^[[:space:]]*version[[:space:]]*=/ {
            if (match($0, /"[^"]+"/)) {
                print substr($0, RSTART + 1, RLENGTH - 2)
                found = 1
                exit
            }
        }
        END { if (!found) exit 1 }
    ' extension.toml
}

extract_cargo_package_version() {
    awk '
        /^\[package\][[:space:]]*$/ { in_package = 1; next }
        /^\[/ { in_package = 0 }
        in_package && /^[[:space:]]*version[[:space:]]*=/ {
            if (match($0, /"[^"]+"/)) {
                print substr($0, RSTART + 1, RLENGTH - 2)
                found = 1
                exit
            }
        }
        END { if (!found) exit 1 }
    ' Cargo.toml
}

update_cargo_package_version() {
    local new_version="$1"

    awk -v new_version="$new_version" '
        /^\[package\][[:space:]]*$/ { in_package = 1 }
        /^\[/ && $0 !~ /^\[package\][[:space:]]*$/ { in_package = 0 }
        in_package && /^[[:space:]]*version[[:space:]]*=/ && !updated {
            sub(/"[^"]+"/, "\"" new_version "\"")
            updated = 1
        }
        { print }
        END { if (!updated) exit 1 }
    ' Cargo.toml > Cargo.toml.tmp

    mv Cargo.toml.tmp Cargo.toml
}

update_manifest_release_version() {
    local new_version="$1"

    awk -v new_version="$new_version" '
        /^\[/ { seen_table = 1 }
        !seen_table && /^[[:space:]]*version[[:space:]]*=/ && !updated {
            sub(/"[^"]+"/, "\"" new_version "\"")
            updated = 1
        }
        { print }
        END { if (!updated) exit 1 }
    ' extension.toml > extension.toml.tmp

    mv extension.toml.tmp extension.toml
}

validate_release_version_format() {
    local version="$1"
    # Strict SemVer 2.0.0: pre-release starts with '-' and build metadata with '+',
    # both composed of dot-separated identifiers of [0-9A-Za-z-].
    local semver_regex='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'

    if [[ ! "$version" =~ $semver_regex ]]; then
        echo "Error: version '$version' is not a supported semver string" >&2
        exit 1
    fi
}

NEW_VERSION=""
SIGHT_VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sight-version)
            if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
                echo "Error: --sight-version requires a non-empty value" >&2
                exit 1
            fi
            SIGHT_VERSION="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            if [[ -z "$NEW_VERSION" ]]; then
                NEW_VERSION="$1"
            else
                echo "Error: unknown argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

CURRENT_CARGO_VERSION=$(extract_cargo_package_version) || {
    echo "Error: Failed to extract Cargo.toml [package].version" >&2
    exit 1
}

CURRENT_EXTENSION_VERSION=$(extract_manifest_release_version) || {
    echo "Error: Failed to extract extension.toml top-level version" >&2
    exit 1
}

echo "Current Cargo.toml [package].version: $CURRENT_CARGO_VERSION"
echo "Current extension.toml version: $CURRENT_EXTENSION_VERSION"

if [[ -z "$NEW_VERSION" ]]; then
    if [[ "$CURRENT_CARGO_VERSION" != "$CURRENT_EXTENSION_VERSION" ]]; then
        echo "Error: release versions are out of sync." >&2
        echo "  Cargo.toml [package].version: $CURRENT_CARGO_VERSION" >&2
        echo "  extension.toml version:      $CURRENT_EXTENSION_VERSION" >&2
        echo "Provide an explicit version to resync them." >&2
        exit 1
    fi

    if ! [[ "$CURRENT_CARGO_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Current Cargo package version '$CURRENT_CARGO_VERSION' is not in MAJOR.MINOR.PATCH format" >&2
        exit 1
    fi

    IFS='.' read -r major minor patch <<< "$CURRENT_CARGO_VERSION"
    NEW_VERSION="${major}.${minor}.$((patch + 1))"
    echo "Auto-bumping patch version: $CURRENT_CARGO_VERSION -> $NEW_VERSION"
else
    validate_release_version_format "$NEW_VERSION"
    echo "Setting release version to: $NEW_VERSION"
fi

echo "Running pre-bump validation..."
./tools/dev/validate.sh --grammar-rev --api-version

if [[ -n "$SIGHT_VERSION" ]]; then
    echo "Checking if Sight release $SIGHT_VERSION exists..."
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "https://api.github.com/repos/jbearak/sight/releases/tags/$SIGHT_VERSION")
    if [[ "$http_code" != "200" ]]; then
        echo "Error: Sight release $SIGHT_VERSION not found (HTTP $http_code)" >&2
        exit 1
    fi
    echo "Sight release $SIGHT_VERSION exists."
else
    ./tools/dev/validate.sh --lsp
fi

echo "Validating send-to-stata.sh checksum..."
expected_sha=$(grep '^SEND_TO_STATA_SHA256=' tools/send-to-stata/install-macos.sh | sed 's/.*"\([^"]*\)".*/\1/')
actual_sha=$(shasum -a 256 tools/send-to-stata/send-to-stata.sh | cut -d' ' -f1)
if [[ "$expected_sha" != "$actual_sha" ]]; then
    echo "Error: send-to-stata.sh checksum mismatch" >&2
    echo "  Expected: $expected_sha" >&2
    echo "  Actual:   $actual_sha" >&2
    echo "  Run: ./tools/dev/update-send-to-stata-checksum.sh" >&2
    exit 1
fi
echo "send-to-stata.sh checksum OK"

echo "Validating Windows exe checksums..."
expected_arm64=$(grep '^\$expectedChecksumArm64' tools/send-to-stata/install-windows.ps1 | sed 's/.*"\([^"]*\)".*/\1/')
expected_x64=$(grep '^\$expectedChecksumX64' tools/send-to-stata/install-windows.ps1 | sed 's/.*"\([^"]*\)".*/\1/')
actual_arm64=$(curl -sL "https://github.com/jbearak/send-to-stata/releases/latest/download/send-to-stata-arm64.exe" | shasum -a 256 | cut -d' ' -f1)
actual_x64=$(curl -sL "https://github.com/jbearak/send-to-stata/releases/latest/download/send-to-stata-x64.exe" | shasum -a 256 | cut -d' ' -f1)
if [[ "$expected_arm64" != "$actual_arm64" ]]; then
    echo "Error: send-to-stata-arm64.exe checksum mismatch" >&2
    echo "  Expected: $expected_arm64" >&2
    echo "  Actual:   $actual_arm64" >&2
    echo "  Run the update-send-to-stata GitHub Action to update checksums" >&2
    exit 1
fi
if [[ "$expected_x64" != "$actual_x64" ]]; then
    echo "Error: send-to-stata-x64.exe checksum mismatch" >&2
    echo "  Expected: $expected_x64" >&2
    echo "  Actual:   $actual_x64" >&2
    echo "  Run the update-send-to-stata GitHub Action to update checksums" >&2
    exit 1
fi
echo "Windows exe checksums OK"

update_cargo_package_version "$NEW_VERSION"
echo "Updated Cargo.toml [package].version to $NEW_VERSION"

update_manifest_release_version "$NEW_VERSION"
echo "Updated extension.toml version to $NEW_VERSION"

if [[ -n "$SIGHT_VERSION" ]]; then
    echo "Updating SERVER_VERSION to $SIGHT_VERSION"
    sed "s/const SERVER_VERSION: \&str = \"[^\"]*\"/const SERVER_VERSION: \\&str = \"$SIGHT_VERSION\"/" src/lib.rs > src/lib.rs.tmp
    mv src/lib.rs.tmp src/lib.rs
fi

echo "Running post-bump validation..."
./tools/dev/validate.sh --release-version --api-version
if [[ -n "$SIGHT_VERSION" ]]; then
    ./tools/dev/validate.sh --lsp
fi

if command -v cargo >/dev/null 2>&1; then
    echo "Rebuilding WASM extension..."
    cargo build --release --target wasm32-wasip1
    cp target/wasm32-wasip1/release/zed_stata.wasm extension.wasm
    echo "Rebuilt extension.wasm"
else
    echo "Error: cargo not found; cannot rebuild extension.wasm" >&2
    exit 1
fi

files_to_commit=(Cargo.toml extension.toml extension.wasm)
if [[ -n "$SIGHT_VERSION" ]]; then
    files_to_commit+=(src/lib.rs)
fi

git add -f "${files_to_commit[@]}"
git commit -m "Bump version to $NEW_VERSION"
git tag "v$NEW_VERSION"
echo "Committed and tagged v$NEW_VERSION"
