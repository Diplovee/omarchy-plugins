#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for d in ~/.config/omarchy/plugins/inkay.*; do
  [[ -d "$d" ]] || continue
  name="$(basename "$d")"
  echo "sync $name"
  rm -rf "$REPO_DIR/plugins/$name"
  cp -R "$d" "$REPO_DIR/plugins/$name"
  # strip .git if any
  rm -rf "$REPO_DIR/plugins/$name/.git"
done
echo "synced. commit when ready."
