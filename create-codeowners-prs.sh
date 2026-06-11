#!/usr/bin/env bash
set -euo pipefail

# Opens two PRs to test Mergify's `github-code-owner-review-satisfied` attribute.
#
#  - "match"    : touches an owned path (frontend/), so the merge protection
#                 "Code owner review satisfied" stays RED until @sileht approves.
#  - "no-match" : touches only an unowned path (docs/), so the protection is
#                 vacuously satisfied and stays GREEN.
#
# CODEOWNERS and the merge protection rule must already be on main.

git checkout main
git pull origin main

# --- Matching PR: touches an owned path ---------------------------------
BRANCH="codeowners-match"
git branch -D "$BRANCH" 2>/dev/null || true
git checkout -b "$BRANCH"
echo "// codeowners match $(uuidgen)" >> frontend/app.js
git add frontend/app.js
git commit -m "test(codeowners): touch owned path frontend/app.js"
git push -u origin "$BRANCH" -f
gh pr create --title "codeowners: match (owned path)" \
  --body "Touches frontend/app.js (owned by @sileht in CODEOWNERS). The 'Code owner review satisfied' protection should stay RED until @sileht approves."

# --- Non-matching PR: touches only an unowned path ----------------------
git checkout main
BRANCH="codeowners-no-match"
git branch -D "$BRANCH" 2>/dev/null || true
git checkout -b "$BRANCH"
echo "<!-- codeowners no-match $(uuidgen) -->" >> docs/guide.md
git add docs/guide.md
git commit -m "test(codeowners): touch unowned path docs/guide.md"
git push -u origin "$BRANCH" -f
gh pr create --title "codeowners: no-match (unowned path)" \
  --body "Touches only docs/guide.md (no owner in CODEOWNERS). The 'Code owner review satisfied' protection should be GREEN with no code owner review required."

git checkout main
