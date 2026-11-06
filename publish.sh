#!/usr/bin/env bash
# Pushes this prepared repository to GitHub.
# Usage: ./publish.sh
set -euo pipefail
cd "$(dirname "$0")"

REMOTE="https://github.com/lixiang0106/omlx-monitor.git"

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE"
else
  git remote add origin "$REMOTE"
fi

echo "==> Repository: $REMOTE"
echo "==> Branch:     $(git branch --show-current)"
echo "==> Files:      $(git ls-files | wc -l | tr -d ' ')"
echo
git push -u origin HEAD

echo
echo "Done. Open https://github.com/lixiang0106/omlx-monitor"
