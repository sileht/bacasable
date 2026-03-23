#!/bin/bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════════
# Demo: Parallel merge queue with scopes — 6 scopes, 21 PRs
#
# Scopes (from .mergify.yml):
#   docker:   Dockerfile
#   backend:  main*.py
#   frontend: frontend/**
#   docs:     docs/**
#   infra:    infra/**
#   api:      api/**
#
# Edge cases demonstrated:
#   - Independent scopes running fully in parallel (6-way)
#   - Same-scope PRs forming linear chains (2 deep per scope)
#   - Cross-scope PRs creating fan-in from 2 scopes
#   - Diamond dependency pattern (fan-out then fan-in)
#   - Mega bottleneck PR touching ALL 6 scopes
#   - No-scope PRs in isolated lanes
#   - Batching (batch_size=2 groups pairs of same-scope PRs)
#
# Per-scope chains:
#   docker:   docker1 → docker2 → infra+docker ─────────────────────────→ release
#   backend:  back1 → back2 → back+front → back+infra ──────────────────→ release
#   frontend: front1 → front2 → back+front → front+api ─────────────────→ release
#   api:      api1 → api2 → api+docs → front+api → api+infra ───────────→ release
#   docs:     docs1 → docs2 → api+docs ─────────────────────────────────→ release
#   infra:    infra1 → infra2 → infra+docker → back+infra → api+infra ──→ release
#   (none):   misc1, misc2
#
# Diamond dependency (wave 4–5):
#              ╭──→ front+api ──╮
#   back+front─┤                ├──→ api+infra → release
#              ╰──→ back+infra ─╯
#
# ══════════════════════════════════════════════════════════════════

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Parallel Merge Queue Demo — 6 scopes, 21 PRs, diamond DAG    ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
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
# Wave 1: Six independent scopes — ALL run in parallel
# ════════════════════════════════════════════════════════════════
echo ""
echo "━━━ Wave 1: Independent PRs in 6 different scopes ━━━"
echo "    docker1, back1, front1, docs1, infra1, api1 — all test in PARALLEL"
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

prep "demo/infra1"
sed -i 's/replicas: 2/replicas: 3/g' infra/k8s-deployment.yaml
git add infra/k8s-deployment.yaml
git commit -m "infra: scale to 3 replicas"
pr "demo/infra1" "infra: scale to 3 replicas"

prep "demo/api1"
sed -i 's/0.1.0/0.2.0/g' api/openapi.yaml
git add api/openapi.yaml
git commit -m "api: bump spec to v0.2.0"
pr "demo/api1" "api: bump spec to v0.2.0"

# ════════════════════════════════════════════════════════════════
# Wave 2: Same-scope chains — queued behind wave 1
# ════════════════════════════════════════════════════════════════
echo ""
echo "━━━ Wave 2: Second PRs in same scopes (6 chains) ━━━"
echo "    Each waits for its wave-1 sibling in the same scope"
echo ""

prep "demo/docker2"
sed -i 's/worker/server/g' Dockerfile
git add Dockerfile
git commit -m "docker: use server entrypoint"
pr "demo/docker2" "docker: use server entrypoint"

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

prep "demo/infra2"
sed -i 's/t3.micro/t3.small/g' infra/terraform.tf
git add infra/terraform.tf
git commit -m "infra: upgrade to t3.small"
pr "demo/infra2" "infra: upgrade to t3.small"

prep "demo/api2"
sed -i 's/255/512/g' api/schema.json
git add api/schema.json
git commit -m "api: increase name max length"
pr "demo/api2" "api: increase name max length"

# ════════════════════════════════════════════════════════════════
# Wave 3: Cross-scope pairs — fan-in from 2 scopes each
# ════════════════════════════════════════════════════════════════
echo ""
echo "━━━ Wave 3: Cross-scope PRs (3 pairs, fan-in from 2 scopes each) ━━━"
echo "    back+front waits for back2 AND front2"
echo "    infra+docker waits for infra2 AND docker2"
echo "    api+docs waits for api2 AND docs2"
echo ""

prep "demo/back-front"
sed -i 's/hello world/hello fullstack/g' main3.py
sed -i 's/capitalize/titleCase/g' frontend/utils.js
git add main3.py frontend/utils.js
git commit -m "backend+frontend: fullstack greeting + rename util"
pr "demo/back-front" "backend+frontend: fullstack greeting + rename util"

prep "demo/infra-docker"
sed -i 's/ClusterIP/LoadBalancer/g' infra/k8s-service.yaml
sed -i 's|WORKDIR /app|WORKDIR /opt/app|g' Dockerfile
git add infra/k8s-service.yaml Dockerfile
git commit -m "infra+docker: expose LoadBalancer + move workdir"
pr "demo/infra-docker" "infra+docker: expose LoadBalancer + move workdir"

prep "demo/api-docs"
sed -i 's/Internal server error/Internal service error/g' api/errors.yaml
sed -i 's/Initial release/Initial public release/g' docs/changelog.md
git add api/errors.yaml docs/changelog.md
git commit -m "api+docs: fix error message + update changelog"
pr "demo/api-docs" "api+docs: fix error message + update changelog"

# ════════════════════════════════════════════════════════════════
# Wave 4: Diamond fan-out — two arms diverge from back+front
# ════════════════════════════════════════════════════════════════
echo ""
echo "━━━ Wave 4: Diamond arms (fan-out from back+front) ━━━"
echo "    front+api waits for back+front (frontend) AND api+docs (api)"
echo "    back+infra waits for back+front (backend) AND infra+docker (infra)"
echo ""

prep "demo/front-api"
sed -i 's/primary/secondary/g' frontend/components.js
sed -i 's/page_size: 25/page_size: 50/g' api/responses.yaml
git add frontend/components.js api/responses.yaml
git commit -m "frontend+api: update components + pagination"
pr "demo/front-api" "frontend+api: update components + pagination"

prep "demo/back-infra"
sed -i 's/hello world/hello devops/g' main4.py
sed -i 's/scrape_interval: 30s/scrape_interval: 15s/g' infra/monitoring.yaml
git add main4.py infra/monitoring.yaml
git commit -m "backend+infra: devops greeting + faster scraping"
pr "demo/back-infra" "backend+infra: devops greeting + faster scraping"

# ════════════════════════════════════════════════════════════════
# Wave 5: Diamond apex — fan-in from both arms
# ════════════════════════════════════════════════════════════════
echo ""
echo "━━━ Wave 5: Diamond apex (fan-in from both arms) ━━━"
echo "    api+infra waits for front+api (api) AND back+infra (infra)"
echo ""

prep "demo/api-infra"
sed -i 's/rate_limit: 100/rate_limit: 200/g' api/config.yaml
sed -i 's/256Mi/512Mi/g' infra/k8s-deployment.yaml
git add api/config.yaml infra/k8s-deployment.yaml
git commit -m "api+infra: increase rate limit + pod memory"
pr "demo/api-infra" "api+infra: increase rate limit + pod memory"

# ════════════════════════════════════════════════════════════════
# Wave 6: Mega PR — touches ALL 6 scopes (ultimate bottleneck)
# ════════════════════════════════════════════════════════════════
echo ""
echo "━━━ Wave 6: Mega PR touching ALL 6 scopes (bottleneck) ━━━"
echo "    release waits for the entire DAG to resolve"
echo ""

prep "demo/release"
sed -i 's/hello world/hello v2/g' main.py
sed -i 's/peotry/poetry/g' Dockerfile
sed -i 's/development/production/g' frontend/config.js
sed -i 's/false/true/g' docs/guide.md
sed -i 's/500m/1000m/g' infra/k8s-deployment.yaml
sed -i 's/expiry: 3600/expiry: 7200/g' api/config.yaml
git add main.py Dockerfile frontend/config.js docs/guide.md infra/k8s-deployment.yaml api/config.yaml
git commit -m "release: v2 across all components"
pr "demo/release" "release: v2 across all components"

# ════════════════════════════════════════════════════════════════
# Wave 7: No-scope PRs (isolated lanes)
# ════════════════════════════════════════════════════════════════
echo ""
echo "━━━ Wave 7: No-scope PRs (isolated lanes) ━━━"
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
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Done! 21 PRs created across 6 scopes + 2 isolated                ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║                                                                    ║"
echo "║  Per-scope chains:                                                 ║"
echo "║   docker:   docker1 → docker2 → infra+docker ──────────→ release  ║"
echo "║   backend:  back1 → back2 → back+front → back+infra ───→ release  ║"
echo "║   frontend: front1 → front2 → back+front → front+api ──→ release  ║"
echo "║   api:      api1 → api2 → api+docs → front+api                    ║"
echo "║                                      → api+infra ──────→ release  ║"
echo "║   docs:     docs1 → docs2 → api+docs ──────────────────→ release  ║"
echo "║   infra:    infra1 → infra2 → infra+docker → back+infra           ║"
echo "║                                      → api+infra ──────→ release  ║"
echo "║   (none):   misc1, misc2                                          ║"
echo "║                                                                    ║"
echo "║  Diamond dependency:                                               ║"
echo "║              ╭──→ front+api ──╮                                    ║"
echo "║   back+front─┤                ├──→ api+infra → release            ║"
echo "║              ╰──→ back+infra ─╯                                    ║"
echo "║                                                                    ║"
echo "║  Wave 1 (parallel):  docker1, back1, front1, docs1, infra1, api1  ║"
echo "║  Wave 2 (chained):   docker2, back2, front2, docs2, infra2, api2  ║"
echo "║  Wave 3 (2-scope):   back+front, infra+docker, api+docs           ║"
echo "║  Wave 4 (diamond):   front+api, back+infra                        ║"
echo "║  Wave 5 (apex):      api+infra                                    ║"
echo "║  Wave 6 (mega):      release (all 6 scopes)                       ║"
echo "║  Wave 7 (isolated):  misc1, misc2                                 ║"
echo "║                                                                    ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Run ./show-dag.sh from the engine repo to see the live DAG"
echo ""
