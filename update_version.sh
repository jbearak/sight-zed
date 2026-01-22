#!/bin/bash
set -e

# Usage: ./update_version.sh [new_version] [--sight-version <version>]
# If new_version is not provided, it bumps the patch version.

# Ensure we're in the project root
if [ ! -f "extension.toml" ]; then
    echo "Error: extension.toml not found. Run this script from the project root."
    exit 1
fi

CURRENT_VERSION=$(sed -n 's/^version = "\(.*\)"/\1/p' extension.toml | head -n 1)

if [ -z "$CURRENT_VERSION" ]; then
    echo "Error: Failed to extract version from extension.toml" >&2
    echo "Expected a line like: version = \"0.1.0\"" >&2
    exit 1
fi

NEW_VERSION=""
SIGHT_VERSION=""

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --sight-version)
      SIGHT_VERSION="$2"
      shift 2
      ;;
    *)
      if [ -z "$NEW_VERSION" ]; then
        NEW_VERSION="$1"
      else
        echo "Unknown argument: $1"
        exit 1
      fi
      shift
      ;;
  esac
done

# Run validation checks before making changes
echo "Running pre-release validation..."

# Validate grammar revision exists
if ! ./validate.sh --grammar-rev; then
    echo "Error: Grammar revision validation failed." >&2
    exit 1
fi

# Validate LSP version (use new version if provided, otherwise current)
if [ -n "$SIGHT_VERSION" ]; then
    # Check if the new sight version release exists
    echo "Checking if sight release $SIGHT_VERSION exists..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://api.github.com/repos/jbearak/sight/releases/tags/$SIGHT_VERSION")
    if [ "$HTTP_CODE" != "200" ]; then
        echo "Error: Sight release $SIGHT_VERSION not found (HTTP $HTTP_CODE)" >&2
        exit 1
    fi
    echo "Sight release $SIGHT_VERSION exists."
else
    if ! ./validate.sh --lsp; then
        echo "Error: LSP validation failed." >&2
        exit 1
    fi
fi

echo "Validation passed."
echo ""

if [ -z "$NEW_VERSION" ]; then
    # Validate semantic version format
    if ! [[ "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Current version '$CURRENT_VERSION' is not in MAJOR.MINOR.PATCH format" >&2
        exit 1
    fi
    
    # Auto-increment patch
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
    NEW_PATCH=$((PATCH + 1))
    NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH"
    echo "Auto-bumping patch version: $CURRENT_VERSION -> $NEW_VERSION"
else
    echo "Setting version to: $NEW_VERSION"
fi

# Update Cargo.toml
# Use a temporary file for sed compatibility on both macOS and Linux
sed "s/^version = \"[^\"]*\"/version = \"$NEW_VERSION\"/" Cargo.toml > Cargo.toml.tmp && mv Cargo.toml.tmp Cargo.toml
echo "Updated Cargo.toml to $NEW_VERSION"

# Update extension.toml
sed "s/^version = \"[^\"]*\"/version = \"$NEW_VERSION\"/" extension.toml > extension.toml.tmp && mv extension.toml.tmp extension.toml
echo "Updated extension.toml to $NEW_VERSION"

if [ -n "$SIGHT_VERSION" ]; then
    echo "Updating SERVER_VERSION to $SIGHT_VERSION"
    sed "s/const SERVER_VERSION: &str = \"[^\"]*\"/const SERVER_VERSION: \\\\&str = \"$SIGHT_VERSION\"/" src/lib.rs > src/lib.rs.tmp && mv src/lib.rs.tmp src/lib.rs
fi

# Rebuild WASM extension if cargo is available
if command -v cargo &> /dev/null; then
    echo "Rebuilding WASM extension..."
    cargo build --release --target wasm32-wasip1
    cp target/wasm32-wasip1/release/sight_extension.wasm extension.wasm
    echo "Rebuilt extension.wasm"
else
    echo "Warning: cargo not found, skipping WASM rebuild. You must rebuild manually before committing."
    exit 1
fi

# Commit the changes
FILES_TO_COMMIT="Cargo.toml extension.toml extension.wasm"
if [ -n "$SIGHT_VERSION" ]; then
    FILES_TO_COMMIT="$FILES_TO_COMMIT src/lib.rs"
fi

git add $FILES_TO_COMMIT
git commit -m "Bump version to $NEW_VERSION"
echo "Committed version bump to $NEW_VERSION"
