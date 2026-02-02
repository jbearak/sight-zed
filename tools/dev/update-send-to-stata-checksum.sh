#!/bin/bash
#
# update-send-to-stata-checksum.sh - Update the embedded checksum in install-macos.sh
#
# Run this after modifying send-to-stata.sh to update the integrity check.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALLER="$REPO_ROOT/tools/send-to-stata/install-macos.sh"
TARGET="$REPO_ROOT/tools/send-to-stata/send-to-stata.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "Error: send-to-stata.sh not found at $TARGET" >&2
  exit 1
fi

if [[ ! -f "$INSTALLER" ]]; then
  echo "Error: install-macos.sh not found at $INSTALLER" >&2
  exit 1
fi

# Compute new checksum
NEW_HASH=$(shasum -a 256 "$TARGET" | cut -d' ' -f1)

# Update the installer
if grep -q '^SEND_TO_STATA_SHA256=' "$INSTALLER"; then
  sed -i '' "s/^SEND_TO_STATA_SHA256=.*/SEND_TO_STATA_SHA256=\"$NEW_HASH\"/" "$INSTALLER"
  echo "Updated checksum: $NEW_HASH"
else
  echo "Error: SEND_TO_STATA_SHA256 variable not found in installer" >&2
  exit 1
fi

# Commit the change
git add "$INSTALLER"
git commit -m "chore: update send-to-stata.sh checksum"
echo "Committed checksum update"
