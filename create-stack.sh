#!/usr/bin/env bash
set -euo pipefail

count=${1:=3}
BRANCH_NAME="test-stack-$(date +%s)"

echo "Creating branch: $BRANCH_NAME"
git checkout -b "$BRANCH_NAME"

for i in $(seq 1 "$count"); do
  RANDOM_LINE="Random line $i: $(uuidgen)"
  echo "$RANDOM_LINE" >> README.md
  git add README.md
  git commit -m "Add random line $i to README.md

$RANDOM_LINE"
  echo "Created commit $i"
done

echo ""
echo "Running git check..."
git check

echo ""
echo "Pushing stack..."
mergify stack push

git checkout main
