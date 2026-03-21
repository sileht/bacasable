#!/bin/bash
# Show the merge queue DAG for a given repository
# Usage: ./show-dag.sh [repo_id] [convoy_ref]
#
# Defaults to sileht/bacasable (400461739) on refs/heads/main

set -euo pipefail

REPO_ID="${1:-400461739}"
CONVOY_REF="${2:-main}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Use row_to_json to get a single clean JSON object per row
SQL="SELECT row_to_json(t) FROM (SELECT cars, scope_queues, mode, waiting_pulls FROM train_model WHERE github_repository_id = ${REPO_ID} AND convoy_ref = '${CONVOY_REF}' LIMIT 1) t"

RAW=$("$SCRIPT_DIR/.agents/skills/prod-sql-query/scripts/query-prod.sh" "$SQL")

# Pass the raw psql output to the Python renderer
python3 "$SCRIPT_DIR/render-dag.py" <<< "$RAW"
