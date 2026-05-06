#!/usr/bin/env bash
# Sync OpenRow.spoon into Hammerspoon's spoons dir and reload Hammerspoon config.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPOON_SRC="$REPO_ROOT/OpenRow.spoon"
SPOON_DST="$HOME/.hammerspoon/Spoons/OpenRow.spoon"

if [[ ! -d "$SPOON_SRC" ]]; then
  echo "error: $SPOON_SRC not found" >&2
  exit 1
fi

mkdir -p "$HOME/.hammerspoon/Spoons"
rm -rf "$SPOON_DST"
cp -R "$SPOON_SRC" "$SPOON_DST"
echo "Installed OpenRow.spoon to $SPOON_DST"

# Reload Hammerspoon config if Hammerspoon is running.
if pgrep -x "Hammerspoon" >/dev/null 2>&1; then
  if /usr/bin/osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"' >/dev/null; then
    echo "Reloaded Hammerspoon config"
  else
    echo "Hammerspoon AppleScript support is disabled; reload Hammerspoon manually"
  fi
else
  echo "Hammerspoon not running; skipping reload"
fi
