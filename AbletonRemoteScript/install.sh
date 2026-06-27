#!/bin/bash
# Install SessionPad Remote Script to Ableton User Library (durable location).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/SessionPad"
DEST="$HOME/Music/Ableton/User Library/Remote Scripts/SessionPad"

if [[ ! -d "$SOURCE" ]]; then
  echo "error: SessionPad source not found at $SOURCE" >&2
  exit 1
fi

mkdir -p "$HOME/Music/Ableton/User Library/Remote Scripts"
rm -rf "$DEST"
rsync -a --exclude='__pycache__' --exclude='.DS_Store' --exclude='vendor' "$SOURCE/" "$DEST/"
find "$DEST" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

echo "Installed SessionPad Remote Script to:"
echo "  $DEST"
echo ""
echo "Next steps:"
echo "  1. Launch SessionPad Bridge on your Mac (menu bar app)"
echo "  2. Quit and reopen Ableton Live (or toggle Control Surface off/on)"
echo "  3. Live → Preferences → Link, Tempo & MIDI → Control Surface: SessionPad"
echo "     (Use only ONE SessionPad entry — prefer the User Library copy)"
echo "  4. Open SessionPad on iOS (same Wi-Fi)"
