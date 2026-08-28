#!/usr/bin/env bash
# Push each plugins/inkay.* as a standalone omarchy plugin repo via subtree.
# Usage: ./scripts/split-plugins.sh [github-user]
set -euo pipefail
OWNER="${1:-Diplovee}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for dir in "$REPO_DIR"/plugins/*; do
  [[ -d "$dir" ]] || continue
  name="$(basename "$dir")"
  remote="https://github.com/${OWNER}/${name}.git"
  echo "== $name -> $remote =="
  if gh repo view "$OWNER/$name" >/dev/null 2>&1; then
    echo "repo exists"
  else
    echo "creating $OWNER/$name"
    gh repo create "$OWNER/$name" --public --description "Omarchy plugin $name"
  fi
  # subtree push
  git subtree push --prefix="plugins/$name" "$remote" master 2>&1 || \
  git push "$remote" "$(git subtree split --prefix="plugins/$name" master):master" --force
done
