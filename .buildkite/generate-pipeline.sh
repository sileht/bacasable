#!/bin/bash
set -euo pipefail

# Read scopes detected by the mergify-ci plugin
SCOPES=$(buildkite-agent meta-data get mergify-ci.scopes)

BACKEND=$(echo "$SCOPES" | jq -r '.backend // "false"')
FRONTEND=$(echo "$SCOPES" | jq -r '.frontend // "false"')
DOCKER=$(echo "$SCOPES" | jq -r '.docker // "false"')
DOCS=$(echo "$SCOPES" | jq -r '.docs // "false"')

cat <<'HEADER'
steps:
HEADER

# Backend
if [ "$BACKEND" = "true" ]; then
  cat <<'EOF'
  - label: ":python: Backend"
    command: |
      echo "Running backend tests..."
      sleep 120
      echo "Backend tests passed"

EOF
fi

# Frontend
if [ "$FRONTEND" = "true" ]; then
  cat <<'EOF'
  - label: ":javascript: Frontend"
    command: |
      echo "Running frontend build & tests..."
      sleep 120
      echo "Frontend tests passed"

EOF
fi

# Docker
if [ "$DOCKER" = "true" ]; then
  cat <<'EOF'
  - label: ":docker: Docker"
    command: |
      echo "Building Docker image..."
      sleep 60
      echo "Docker build passed"

EOF
fi

# Docs
if [ "$DOCS" = "true" ]; then
  cat <<'EOF'
  - label: ":books: Docs"
    command: |
      echo "Checking docs..."
      sleep 30
      echo "Docs check passed"

EOF
fi

# Check merge queue — only if the PR title contains "merge queue:"
if [[ "${BUILDKITE_MESSAGE:-}" == *"merge queue:"* ]]; then
  cat <<'EOF'
  - label: ":warning: Check merge queue"
    command: |
      git fetch origin "${BUILDKITE_PULL_REQUEST_BASE_BRANCH:-main}"
      if git diff --name-only "origin/${BUILDKITE_PULL_REQUEST_BASE_BRANCH:-main}...HEAD" | grep -q '^make-ci-fail$$'; then
        echo "CI failure triggered by make-ci-fail file"
        exit 1
      fi

EOF
fi

# If no scope matched, emit a no-op so the pipeline isn't empty
if [ "$BACKEND" = "false" ] && [ "$FRONTEND" = "false" ] && [ "$DOCKER" = "false" ] && [ "$DOCS" = "false" ]; then
  cat <<'EOF'
  - label: ":white_check_mark: No changes detected"
    command: echo "No relevant changes detected, skipping CI."

EOF
fi
