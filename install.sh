#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}/.config/omarchy/plugins"

mkdir -p "$TARGET_DIR"

link_plugin() {
  local src="$1"
  local name
  name="$(basename "$src")"
  local dst="${TARGET_DIR}/${name}"

  if [[ -e "$dst" && ! -L "$dst" ]]; then
    echo "backup $dst → ${dst}.bak.$(date +%s)"
    mv "$dst" "${dst}.bak.$(date +%s)"
  fi
  # remove stale symlink
  [[ -L "$dst" ]] && rm -f "$dst"

  ln -sfn "$src" "$dst"
  echo "linked $name → $dst"
}

for plugin_dir in "$REPO_DIR"/plugins/*; do
  [[ -d "$plugin_dir" ]] || continue
  link_plugin "$plugin_dir"
done

echo ""
echo "done. now enable:"
echo "  omarchy-shell shell rescanPlugins"
echo "  omarchy-shell shell listPlugins | grep inkay"
echo "  omarchy bar put inkay.thermal --after omarchy.power"
echo "  omarchy bar put inkay.void --after omarchy.agents"
echo "  omarchy restart shell   # if needed"
