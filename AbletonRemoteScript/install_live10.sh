#!/bin/bash
# Install SessionPad10 Remote Script (Ableton Live 10) to User Library.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/SessionPad10"
DEST="$HOME/Music/Ableton/User Library/Remote Scripts/SessionPad10"

if [[ ! -d "$SOURCE" ]]; then
  echo "error: SessionPad10 source not found at $SOURCE" >&2
  exit 1
fi

mkdir -p "$HOME/Music/Ableton/User Library/Remote Scripts"
rm -rf "$DEST"
rsync -a --exclude='__pycache__' --exclude='.DS_Store' --exclude='vendor' "$SOURCE/" "$DEST/"
find "$DEST" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

echo "Installed SessionPad10 Remote Script to:"
echo "  $DEST"
echo ""
echo "Next steps:"
echo "  1. Launch SessionPad Bridge on your Mac or PC"
echo "  2. Fully quit Ableton Live 10 and reopen — toggling the control surface does NOT reload Python code"
echo "  3. Live → Preferences → Link, Tempo & MIDI → Control Surface: SessionPad10"
echo "     (Use only ONE SessionPad10 entry — do not also select SessionPad unless you intend to)"
echo "  4. Open SessionPad on iOS (same Wi-Fi)"
