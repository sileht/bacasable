#!/bin/bash
set -euo pipefail

# Close all open PRs
gh pr list --state open --json number --jq '.[].number' | while read -r pr_number; do
  gh pr close "$pr_number"
done

for i in $(seq 1 5); do
  BRANCH="test-queue-status-$i"
  git checkout main
  git pull origin main
  git branch -D "$BRANCH" || true
  git checkout -b "$BRANCH"
  echo "# Change $i" >> "main${i}.py"
  git add "main${i}.py"
  if [[ $i -eq 2 ]]; then
      echo "MAKE CI FAIL" > make-ci-fail
      git add make-ci-fail
  fi
  git commit -m "feat: test queue PR $i"
  git push -u origin "$BRANCH" -f
  gh pr create --title "test queue PR $i" --body "Test PR $i for merge queue"
done

git checkout main
