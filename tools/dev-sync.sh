#!/usr/bin/env bash
# Developer helper: copy this working tree into the Omarchy plugin directory
# and restart the shell so QML changes take effect. End users do not need
# this — they get the plugin with `omarchy plugin add` (see README).
set -euo pipefail

ID="io.github.pixdevsapps.scarlett-control"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$ID"

if [[ -d "$DEST/.git" ]]; then
  echo "$DEST is a git checkout (installed with omarchy plugin add); edit it there instead." >&2
  exit 1
fi

mkdir -p "$DEST"
# Only runtime files; the shell's inotify watcher does not follow symlinks,
# so the plugin is copied rather than linked.
for f in manifest.json *.qml Model.js scarlett-ctl README.md LICENSE; do
  cp "$SRC/$f" "$DEST/"
done
chmod 755 "$DEST/scarlett-ctl"

if omarchy plugin list 2>/dev/null | grep -q "^$ID .*enabled"; then
  # Qt keeps instantiated plugin types cached across a hot reload.
  omarchy restart shell >/dev/null 2>&1 || true
else
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  sleep 1
  omarchy plugin enable "$ID" --section right >/dev/null
  omarchy bar move "$ID" --before omarchy.audio >/dev/null 2>&1 || true
fi
echo "Synced $ID → $DEST"
