#!/bin/bash
set -euo pipefail

# Demo: Parallel merge queue with scopes
#
# This script creates PRs in different scopes to demonstrate that
# PRs with non-overlapping scopes are tested in parallel, while
# PRs sharing a scope wait for each other.
#
# Scopes (defined in .mergify.yml):
#   - docker: Dockerfile
#   - python: main*.py
#   - (no scope): other files like new*
#
# Expected behavior:
#   1. docker1 and python1 test in PARALLEL (independent scopes)
#   2. python2 waits for python1 (same scope)
#   3. cross1 (docker+python) waits for both docker1 and python1
#   4. noise PRs (no scope) run in their own lane

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

# ── Close existing PRs ──────────────────────────────────────────
echo "==> Closing all open PRs..."
gh pr list --state open --json number --jq '.[].number' | while read -r pr; do
  gh pr close "$pr" --delete-branch 2>/dev/null || true
done

# ── Reset main to clean state ───────────────────────────────────
echo "==> Resetting main to clean state..."
git checkout main
git reset --hard
cp -a reset/* .
git add Dockerfile main*.py new
git diff --cached --quiet || git commit -m "chore: reset to clean state"
git push origin main -f

# ── Helpers ──────────────────────────────────────────────────────
prep_branch() {
  local branch="$1"
  git checkout main
  git pull origin main --rebase
  git push origin ":$branch" 2>/dev/null || true
  git branch -D "$branch" 2>/dev/null || true
  git checkout -b "$branch"
}

create_pr() {
  local branch="$1"
  local title="$2"
  git push -u origin "$branch"
  gh pr create --title "$title" --body "Demo PR for parallel merge queue"
}

# ── Wave 1: Independent scopes (should test in parallel) ────────
echo ""
echo "==> Wave 1: Creating PRs in independent scopes (docker + python)"
echo "    These should be tested in PARALLEL"
echo ""

prep_branch "demo/docker1"
sed -i 's/3.14/3.15/g' Dockerfile
git add Dockerfile
git commit -m "docker: upgrade python to 3.15"
create_pr "demo/docker1" "docker: upgrade python to 3.15"

prep_branch "demo/python1"
sed -i 's/hello world/hello universe/g' main1.py
git add main1.py
git commit -m "python: change greeting to universe"
create_pr "demo/python1" "python: change greeting to universe"

# ── Wave 2: Same scope (should wait for wave 1) ─────────────────
echo ""
echo "==> Wave 2: Creating another python PR (same scope as python1)"
echo "    This should WAIT for python1 to finish"
echo ""

prep_branch "demo/python2"
sed -i 's/hello world/hello cosmos/g' main2.py
git add main2.py
git commit -m "python: change greeting to cosmos"
create_pr "demo/python2" "python: change greeting to cosmos"

# ── Wave 3: Cross-scope PR (depends on both docker and python) ──
echo ""
echo "==> Wave 3: Creating a cross-scope PR (touches both docker + python)"
echo "    This should WAIT for both docker1 and python2"
echo ""

prep_branch "demo/cross1"
sed -i 's/worker/app/g' Dockerfile
sed -i 's/hello world/hello cross/g' main3.py
git add Dockerfile main3.py
git commit -m "all: rename worker to app and update greeting"
create_pr "demo/cross1" "all: rename worker to app and update greeting"

# ── Wave 4: No-scope PR (independent of everything) ─────────────
echo ""
echo "==> Wave 4: Creating a no-scope PR"
echo "    This runs in the merge-queue scope lane"
echo ""

prep_branch "demo/noise1"
echo "updated" > new1
git add new1
git commit -m "chore: update new1"
create_pr "demo/noise1" "chore: update new1"

# ── Done ─────────────────────────────────────────────────────────
git checkout main

echo ""
echo "==> Done! PRs created. Watch the merge queue to see parallel behavior:"
echo ""
echo "    Expected parallel lanes:"
echo "      docker:  docker1 ──────────────────> cross1"
echo "      python:  python1 ──> python2 ──────> cross1"
echo "      other:   noise1"
echo ""
echo "    docker1 and python1 should start testing at the same time."
echo "    python2 waits for python1. cross1 waits for both docker1 and python2."
echo ""
