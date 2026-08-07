#!/bin/bash
set -euo pipefail

# Install the Godot editor (headless-capable) for Claude Code on the web sessions.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GODOT_VERSION="4.7.1"
GODOT_BIN="/usr/local/bin/godot"

if [ -x "$GODOT_BIN" ] && "$GODOT_BIN" --version 2>/dev/null | grep -q "^${GODOT_VERSION}\."; then
  echo "Godot ${GODOT_VERSION} already installed"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
curl -sSL --retry 3 -o "$TMP_DIR/godot.zip" "$URL"
unzip -q -o "$TMP_DIR/godot.zip" -d "$TMP_DIR"
install -m 755 "$TMP_DIR/Godot_v${GODOT_VERSION}-stable_linux.x86_64" "$GODOT_BIN"

"$GODOT_BIN" --version
