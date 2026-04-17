#!/bin/bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════════
# Demo: Parallel merge queue with scopes — 3 scopes, 5 PRs
#
# Scopes (from .mergify.yml):
#   backend:  main*.py
#   frontend: frontend/**
#   api:      api/**
#
# DAG:
#   back1 ──→ back+front ──→ release (all 3)
#   front1 ─↗
#   api1 ──────────────────→ release (all 3)
#
# Wave 1: 3 independent PRs — all run in parallel
# Wave 2: 1 cross-scope PR — fan-in from backend + frontend
# Wave 3: 1 bottleneck PR — touches all 3 scopes
# ══════════════════════════════════════════════════════════════════

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

echo "╔══════════════════════════════════════════════════════╗"
echo "║  Parallel Merge Queue Demo — 3 scopes, 5 PRs       ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Close existing PRs ──────────────────────────────────────────
echo "==> Closing all open PRs..."
gh pr list --state open --json number --jq '.[].number' | while read -r pr; do
  gh pr close "$pr" --delete-branch 2>/dev/null || true
done

# ── Reset main to clean state ───────────────────────────────────
echo "==> Resetting main to clean state..."
git checkout main
git reset --hard origin/main
cp -a reset/* .
git add -A
git diff --cached --quiet || git commit -m "chore: reset to clean state"
git push origin main -f

# ── Helpers ──────────────────────────────────────────────────────
prep() {
  local branch="$1"
  git checkout main
  git pull origin main --rebase
  git push origin ":$branch" 2>/dev/null || true
  git branch -D "$branch" 2>/dev/null || true
  git checkout -b "$branch"
}

pr() {
  local branch="$1"
  local title="$2"
  git push -u origin "$branch"
  gh pr create --title "$title" --body "Parallel merge queue demo"
}

# ════════════════════════════════════════════════════════════════
# Wave 1: Three independent scopes — ALL run in parallel
# ════════════════════════════════════════════════════════════════
echo ""
echo "━━━ Wave 1: Independent PRs in 3 different scopes ━━━"
echo "    back1, front1, api1 — all test in PARALLEL"
echo ""

prep "demo/back1"
sed -i 's/hello world/hello universe/g' main1.py
git add main1.py
git commit -m "backend: greeting -> universe"
pr "demo/back1" "backend: greeting -> universe"

prep "demo/front1"
sed -i 's/Arial/Helvetica/g' frontend/styles.css
git add frontend/styles.css
git commit -m "frontend: switch to Helvetica font"
pr "demo/front1" "frontend: switch to Helvetica font"

prep "demo/api1"
sed -i 's/0.1.0/0.2.0/g' api/openapi.yaml
git add api/openapi.yaml
git commit -m "api: bump spec to v0.2.0"
pr "demo/api1" "api: bump spec to v0.2.0"

# ════════════════════════════════════════════════════════════════
# Wave 2: Cross-scope fan-in — waits for backend AND frontend
# ════════════════════════════════════════════════════════════════
echo ""
echo "━━━ Wave 2: Cross-scope PR (fan-in from backend + frontend) ━━━"
echo "    back+front waits for back1 AND front1"
echo ""

prep "demo/back-front"
sed -i 's/hello world/hello fullstack/g' main3.py
sed -i 's/capitalize/titleCase/g' frontend/utils.js
git add main3.py frontend/utils.js
git commit -m "backend+frontend: fullstack greeting + rename util"
pr "demo/back-front" "backend+frontend: fullstack greeting + rename util"

# ════════════════════════════════════════════════════════════════
# Wave 3: Bottleneck PR — touches all 3 scopes
# ════════════════════════════════════════════════════════════════
echo ""
echo "━━━ Wave 3: Release PR touching all 3 scopes (bottleneck) ━━━"
echo "    release waits for back+front (backend+frontend) AND api1 (api)"
echo ""

prep "demo/release"
sed -i 's/hello world/hello v2/g' main.py
sed -i 's/development/production/g' frontend/config.js
sed -i 's/expiry: 3600/expiry: 7200/g' api/config.yaml
git add main.py frontend/config.js api/config.yaml
git commit -m "release: v2 across all components"
pr "demo/release" "release: v2 across all components"

# ── Done ─────────────────────────────────────────────────────────
git checkout main

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Done! 5 PRs created across 3 scopes                      ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                            ║"
echo "║  Per-scope chains:                                         ║"
echo "║   backend:  back1 → back+front ──→ release                ║"
echo "║   frontend: front1 → back+front ──→ release               ║"
echo "║   api:      api1 ─────────────────→ release               ║"
echo "║                                                            ║"
echo "║  DAG:                                                      ║"
echo "║   back1 ──→ back+front ──→ release (all 3)                ║"
echo "║   front1 ─↗                                               ║"
echo "║   api1 ──────────────────→ release (all 3)                ║"
echo "║                                                            ║"
echo "║  Wave 1 (parallel):    back1, front1, api1                ║"
echo "║  Wave 2 (fan-in):      back+front                         ║"
echo "║  Wave 3 (bottleneck):  release                            ║"
echo "║                                                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Run ./show-dag.sh from the engine repo to see the live DAG"
echo ""
