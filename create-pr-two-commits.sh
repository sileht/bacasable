#!/usr/bin/env bash
# Create a PR with two commits.
set -euo pipefail

BRANCH="${1:-test/two-commits-$(date +%s)}"
BASE="$(git rev-parse --abbrev-ref HEAD)"

git switch -c "$BRANCH"

# First commit
echo "change 1 - $(date)" >> two-commits.txt
git add two-commits.txt
git commit -m "test: first commit"

# Second commit
echo "change 2 - $(date)" >> two-commits.txt
git add two-commits.txt
git commit -m "test: second commit"

git push -u origin "$BRANCH"

gh pr create \
  --base "$BASE" \
  --head "$BRANCH" \
  --title "test: PR with two commits" \
  --body "Test PR containing two commits."

git main
