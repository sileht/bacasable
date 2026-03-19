#!/bin/bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════════
# Demo: Parallel merge queue with scopes — comprehensive edition
#
# Scopes (from .mergify.yml):
#   docker:   Dockerfile
#   backend:  main*.py
#   frontend: frontend/**
#   docs:     docs/**
#
# CI durations (simulated):
#   docs:     ~5s   (fast)
#   backend:  ~15s  (medium)
#   frontend: ~25s  (slow)
#   docker:   ~30s  (slowest)
#
# Edge cases demonstrated:
#   - Independent scopes running fully in parallel
#   - Same-scope PRs forming a linear chain
#   - Cross-scope PRs creating DAG fan-in dependencies
#   - PRs touching ALL scopes (bottleneck node)
#   - No-scope PRs (isolated lane)
#   - Batching (batch_size=2 groups pairs of same-scope PRs)
#   - CI failure in one scope (make-ci-fail file)
#
# Expected DAG (10 PRs):
#
#   docker:   [docker1] ──────────────────────────> [fullstack1]
#   backend:  [back1] ──> [back2] ──> [back+front] > [fullstack1]
#   frontend: [front1] ──> [front2] ──> [back+front] > [fullstack1]
#   docs:     [docs1] ──> [docs2]
#   isolated: [misc1]
#
# ══════════════════════════════════════════════════════════════════

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Parallel Merge Queue Demo — 4 scopes, 12 PRs              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
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
# Wave 1: Four independent scopes — ALL run in parallel
# ════════════════════════════════════════════════════════════════
echo ""
echo "━━━ Wave 1: Independent PRs in 4 different scopes ━━━"
echo "    docker1, back1, front1, docs1 — all test in PARALLEL"
echo ""

prep "demo/docker1"
sed -i 's/3.14/3.15/g' Dockerfile
git add Dockerfile
git commit -m "docker: upgrade python to 3.15"
pr "demo/docker1" "docker: upgrade python to 3.15"

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

prep "demo/docs1"
sed -i 's/8080/3000/g' docs/guide.md
git add docs/guide.md
git commit -m "docs: update default port to 3000"
pr "demo/docs1" "docs: update default port to 3000"

# ════════════════════════════════════════════════════════════════
# Wave 2: Same-scope chains — queued behind wave 1
# ════════════════════════════════════════════════════════════════
echo ""
echo "━━━ Wave 2: Second PRs in same scopes ━━━"
echo "    back2 waits for back1, front2 waits for front1, docs2 waits for docs1"
echo ""

prep "demo/back2"
sed -i 's/hello world/hello cosmos/g' main2.py
git add main2.py
git commit -m "backend: greeting -> cosmos"
pr "demo/back2" "backend: greeting -> cosmos"

prep "demo/front2"
sed -i 's/1.0.0/2.0.0/g' frontend/app.js
git add frontend/app.js
git commit -m "frontend: bump version to 2.0.0"
pr "demo/front2" "frontend: bump version to 2.0.0"

prep "demo/docs2"
sed -i 's/Submit new data/Create new data/g' docs/api.md
git add docs/api.md
git commit -m "docs: update API wording"
pr "demo/docs2" "docs: update API wording"

# ════════════════════════════════════════════════════════════════
# Wave 3: Cross-scope PR — fan-in from 2 scopes
# ════════════════════════════════════════════════════════════════
echo ""
echo "━━━ Wave 3: Cross-scope PR (backend + frontend) ━━━"
echo "    back+front waits for BOTH back2 and front2"
echo ""

prep "demo/back-front"
sed -i 's/hello world/hello fullstack/g' main3.py
sed -i 's/capitalize/titleCase/g' frontend/utils.js
git add main3.py frontend/utils.js
git commit -m "fullstack: update greeting + rename util"
pr "demo/back-front" "fullstack: update greeting + rename util"

# ════════════════════════════════════════════════════════════════
# Wave 4: Mega cross-scope — touches ALL scopes (bottleneck)
# ════════════════════════════════════════════════════════════════
echo ""
echo "━━━ Wave 4: PR touching ALL scopes (bottleneck node) ━━━"
echo "    fullstack1 waits for docker1, back+front, AND docs2"
echo ""

prep "demo/fullstack1"
sed -i 's/worker/server/g' Dockerfile
sed -i 's/hello world/hello everything/g' main.py
sed -i 's/#f5f5f5/#ffffff/g' frontend/styles.css
sed -i 's/development/staging/g' docs/guide.md
git add Dockerfile main.py frontend/styles.css docs/guide.md
git commit -m "release: update all components for v2"
pr "demo/fullstack1" "release: update all components for v2"

# ════════════════════════════════════════════════════════════════
# Wave 5: No-scope PR (isolated lane)
# ════════════════════════════════════════════════════════════════
echo ""
echo "━━━ Wave 5: No-scope PRs (isolated lanes) ━━━"
echo "    misc1 and misc2 run independently of everything"
echo ""

prep "demo/misc1"
echo "v2" > new1
git add new1
git commit -m "chore: bump new1"
pr "demo/misc1" "chore: bump new1"

prep "demo/misc2"
echo "v2" > new2
git add new2
git commit -m "chore: bump new2"
pr "demo/misc2" "chore: bump new2"

# ── Done ─────────────────────────────────────────────────────────
git checkout main

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Done! 12 PRs created across 4 scopes + 2 isolated         ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                             ║"
echo "║  Expected DAG:                                              ║"
echo "║                                                             ║"
echo "║  docker:   docker1 ─────────────────────────┐               ║"
echo "║  backend:  back1 → back2 ──→ back+front ──→ fullstack1     ║"
echo "║  frontend: front1 → front2 ─→ back+front ──┘  ↑            ║"
echo "║  docs:     docs1 → docs2 ──────────────────────┘            ║"
echo "║  isolated: misc1                                            ║"
echo "║  isolated: misc2                                            ║"
echo "║                                                             ║"
echo "║  Wave 1 (parallel): docker1, back1, front1, docs1          ║"
echo "║  Wave 2 (chained):  back2, front2, docs2                   ║"
echo "║  Wave 3 (fan-in):   back+front (waits back2 + front2)      ║"
echo "║  Wave 4 (mega):     fullstack1 (waits docker1 + all above) ║"
echo "║  Wave 5 (isolated): misc1, misc2 (no scope dependencies)   ║"
echo "║                                                             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Run ./show-dag.sh from the engine repo to see the live DAG"
echo ""
