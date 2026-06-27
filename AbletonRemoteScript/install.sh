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

# Remove stale in-bundle copies that shadow the User Library script.
removed_any=false
remove_if_present() {
  local path="$1"
  if [[ -d "$path" ]]; then
    rm -rf "$path"
    echo "warning: removed stale in-bundle copy: $path"
    removed_any=true
  fi
}

for app_root in "/Applications" "$HOME/Desktop"; do
  [[ -d "$app_root" ]] || continue
  while IFS= read -r -d '' live_app; do
    remove_if_present "$live_app/Contents/App-Resources/MIDI Remote Scripts/SessionPad"
    remove_if_present "$live_app/SessionPad"
  done < <(find "$app_root" -maxdepth 1 -name 'Ableton Live*.app' -print0 2>/dev/null)
done

if [[ "$removed_any" == true ]]; then
  echo ""
  echo "Removed stale SessionPad copies from Ableton app bundles."
  echo "Live loads only the User Library copy above after you fully quit and reopen Live."
fi

echo "Installed SessionPad Remote Script to:"
echo "  $DEST"
echo ""
echo "Next steps:"
echo "  1. Launch SessionPad Bridge on your Mac (menu bar app)"
echo "  2. Fully quit Ableton Live (Cmd+Q) and reopen — toggling the control surface does NOT reload Python code"
echo "  3. Live → Preferences → Link, Tempo & MIDI → Control Surface: SessionPad"
echo "     (Use only ONE SessionPad entry — prefer the User Library copy)"
echo "  4. Open SessionPad on iOS (same Wi-Fi)"
