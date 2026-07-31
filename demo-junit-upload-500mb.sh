#!/usr/bin/env bash
#
# Demo: uploading a 500 MB JUnit report to Mergify CI Insights
# -----------------------------------------------------------
# Generates a huge but perfectly valid JUnit XML report, then feeds it to
# `mergify ci junit-process`, which parses it and ships every test as an OTLP
# span to CI Insights. The point is to see what a 500 MB report does end to end:
# generation time, parse time, upload time, peak memory, and whether the API
# takes it.
#
# Everything lives in the gitignored scratch dir .junit-500mb-demo/, and no
# tracked file is touched.
#
#   Phase 1  generate the report (--mode tests | payload)
#   Phase 2  upload it with `mergify ci junit-process`, timed and measured
#
# Requirements: MERGIFY_TOKEN with CI Insights access to the target repository.
#
# Usage:
#   MERGIFY_TOKEN=... ./demo-junit-upload-500mb.sh
#   ./demo-junit-upload-500mb.sh --size 1GB --mode payload
#   ./demo-junit-upload-500mb.sh --generate-only     # no API call
#   ./demo-junit-upload-500mb.sh --keep              # reuse a report already generated
#   ./demo-junit-upload-500mb.sh --with-failures     # 1 test in 97 fails
#   ./demo-junit-upload-500mb.sh --pipeline 'Nightly'  # pipeline name in the UI
#   ./demo-junit-upload-500mb.sh --no-ci-env         # upload with no CI context
#
# Heads-up: the CLI loads the whole report before uploading. Measured at ~23x
# the file size in RSS (11.3 GB for 500 MB), so a 500 MB report needs a machine
# with enough RAM. Failures default to a sparse 1 in 50000 (~68 of them at
# 500 MB): enough to see individual tests in the dashboard, few enough that the
# CLI does not dump tens of thousands of failure blocks in the terminal.
#
# What a local upload needs to reach Test Insights > Detection
# ------------------------------------------------------------
# 1. A CI provider. Outside a runner the CLI detects none, so the spans carry
#    no `cicd.pipeline.name` / `cicd.pipeline.task.name` — both required fields
#    of a test span, so every span is dropped at validation. We fake a GitHub
#    Actions env to supply them (--no-ci-env reproduces the failure).
# 2. The default branch, and nothing else. Rollups are skipped unless the head
#    ref equals the repo's default branch (`_insert_default_branch_rollup_data`),
#    and the search query filters on it again. A feature branch means an empty
#    page, whatever else is right.
# 3. Fresh timestamps: rollup staging drops executions older than 24 h.
#
# The workflow run id only matters for CI Insights > Jobs, which keys the trace
# on it. Test Insights ignores it entirely.
#
# Health status: a JUnit upload can only ever produce `healthy` or `broken`.
# `calculate_health_status` counts an execution as flaky when the span carries
# `cicd.test.flaky`, and the CLI never emits it — its parser only knows
# testsuite/testcase/failure/error/skipped, no rerun markers. So the Flaky tab
# the page opens on stays empty; the failing tests are under Broken.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$ROOT/.junit-500mb-demo"
REPORT="$WORK/big-junit.xml"
GENERATOR="$ROOT/generate_junit.py"

SIZE="500MB"
MODE="tests"
REPOSITORY="${MERGIFY_DEMO_REPOSITORY:-sileht/bacasable}"
BRANCH="${MERGIFY_DEMO_BRANCH:-}"
BRANCH_EXPLICIT=false
GENERATE_ONLY=false
KEEP=false
# Passing tests are folded into summary counts; only tests with a diagnostic
# category (status/slow/new/flaky) are persisted as their own row. A sparse
# default gives a few dozen failures to look at without the CLI printing tens
# of thousands of failure blocks. --with-failures makes it 1 in 97.
FAILURE_EVERY=50000
FAKE_CI_ENV=true
RUN_ID=""
PIPELINE_NAME="${MERGIFY_DEMO_PIPELINE:-Big JUnit demo}"

while [ $# -gt 0 ]; do
  case "$1" in
    --size)          SIZE="$2"; shift 2 ;;
    --mode)          MODE="$2"; shift 2 ;;
    --repository|-r) REPOSITORY="$2"; shift 2 ;;
    --branch|-b)     BRANCH="$2"; BRANCH_EXPLICIT=true; shift 2 ;;
    --generate-only) GENERATE_ONLY=true; shift ;;
    --keep)          KEEP=true; shift ;;
    --with-failures) FAILURE_EVERY=97; shift ;;
    --run-id)        RUN_ID="$2"; shift 2 ;;
    --pipeline)      PIPELINE_NAME="$2"; shift 2 ;;
    --no-ci-env)     FAKE_CI_ENV=false; shift ;;
    -h|--help)       sed -n '2,53p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# --- colours / helpers ------------------------------------------------------
if [ -t 1 ]; then B=$'\033[1m'; C=$'\033[36m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'; else B=; C=; G=; Y=; R=; N=; fi
step() { printf '\n%s=== %s ===%s\n' "$B$C" "$1" "$N"; }
note() { printf '%s%s%s\n' "$Y" "$1" "$N"; }

command -v mergify >/dev/null 2>&1 || { echo "${R}mergify CLI not found. See https://docs.mergify.com/cli/${N}" >&2; exit 1; }
if command -v uv >/dev/null 2>&1; then GEN=(uv run --quiet "$GENERATOR")
else GEN=(python3 "$GENERATOR"); fi

if [ "$GENERATE_ONLY" = false ] && [ -z "${MERGIFY_TOKEN:-}" ]; then
  echo "${R}MERGIFY_TOKEN is not set.${N} It needs CI Insights access to $REPOSITORY." >&2
  echo "Run with --generate-only to build the report without uploading it." >&2
  exit 1
fi

# ===========================================================================
step "Phase 1 - Generate a $SIZE JUnit report (mode: $MODE)"
case "$MODE" in
  tests)   note "Millions of tiny <testcase> elements: maximum test cardinality, maximum span count." ;;
  payload) note "Fewer tests, each with a ~15 KiB <system-out> body: few spans, very fat attributes." ;;
  *) echo "unknown mode: $MODE (expected 'tests' or 'payload')" >&2; exit 2 ;;
esac

mkdir -p "$WORK"
if [ "$KEEP" = true ] && [ -s "$REPORT" ]; then
  note "Reusing the existing report (--keep)."
else
  rm -f "$REPORT"
  "${GEN[@]}" --out "$REPORT" --size "$SIZE" --mode "$MODE" \
    --failure-every "$FAILURE_EVERY"
fi

BYTES=$(wc -c < "$REPORT" | tr -d ' ')
TESTS=$(grep -c '<testcase ' "$REPORT" || true)
FAILURES=$(grep -c '<failure ' "$REPORT" || true)
printf '\n%sreport: %s%s\n' "$G" "$REPORT" "$N"
printf '  size : %s bytes (%s)\n' "$BYTES" "$(du -h "$REPORT" | cut -f1)"
printf '  tests: %s (%s failing)\n' "$TESTS" "$FAILURES"
if [ "$FAILURES" -eq 0 ]; then
  note "No failing test: only the summary counts will be visible, since a test"
  note "needs a diagnostic category to be stored as its own row."
fi

if [ "$GENERATE_ONLY" = true ]; then
  step "Done (--generate-only, nothing uploaded)"
  exit 0
fi

# ===========================================================================
step "Phase 2 - Upload it to CI Insights"
note "This is the exact command a CI job runs after its test step."
# --test-exit-code must match what the report actually contains, not what we
# asked for: a small report can be too short to hold a single failure at the
# configured rate, and a non-zero code with a clean XML is reported as a silent
# runner crash.
[ "$FAILURES" -eq 0 ] && TEST_EXIT_CODE=0 || TEST_EXIT_CODE=1

# The CLI reads its CI context from the runner's env vars. On a laptop nothing
# is set, so it emits a trace with no pipeline, run id, branch or commit. We
# borrow a real workflow run so the trace id matches one the dashboard knows.
CI_ENV=()
if [ "$FAKE_CI_ENV" = true ]; then
  command -v gh >/dev/null 2>&1 || { echo "${R}gh CLI is needed to resolve the default branch.${N}" >&2; exit 1; }

  # The branch is the one thing that decides whether Test Insights sees these
  # tests: rollups are dropped unless the head ref equals the repository's
  # default branch, and the search query re-checks it
  # (`TestMetricsSummary.branch_name == GitHubRepository.default_branch`).
  DEFAULT_BRANCH=$(gh repo view "$REPOSITORY" --json defaultBranchRef --jq '.defaultBranchRef.name') \
    || { echo "${R}Cannot resolve the default branch of $REPOSITORY.${N}" >&2; exit 1; }
  if [ "$BRANCH_EXPLICIT" = true ] && [ "$BRANCH" != "$DEFAULT_BRANCH" ]; then
    note "Branch '$BRANCH' is not the default branch ('$DEFAULT_BRANCH'): the rollups"
    note "will be dropped and Test Insights will stay empty. Keeping it as asked."
  else
    BRANCH="$DEFAULT_BRANCH"
  fi

  # Only the Jobs view needs a run id that exists; Test Insights ignores it.
  # Borrow one from the default branch when there is one, otherwise synthesize.
  if [ -z "$RUN_ID" ]; then
    RUN_ID=$(gh run list --repo "$REPOSITORY" --branch "$BRANCH" --limit 1 --status completed \
      --json databaseId --jq '.[0].databaseId // empty')
  fi
  if [ -z "$RUN_ID" ]; then
    RUN_ID="$(date +%s)"
    note "No completed run on $BRANCH: using a synthetic run id, so the tests"
    note "will show in Test Insights but link to no job."
  fi

  CI_ENV=(
    GITHUB_ACTIONS=true
    GITHUB_EVENT_NAME=push
    "GITHUB_REPOSITORY=$REPOSITORY"
    # pipeline_name and job_name are required fields of a test span: a span
    # without them is dropped at validation. They are also the two columns the
    # Detection table groups on, so give them names worth reading.
    "GITHUB_WORKFLOW=$PIPELINE_NAME"
    "GITHUB_JOB=big-junit-$SIZE-$MODE"
    "GITHUB_RUN_ID=$RUN_ID"
    GITHUB_RUN_ATTEMPT=1
    "GITHUB_REF_NAME=$BRANCH"
    "GITHUB_SHA=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo 0000000000000000000000000000000000000000)"
    GITHUB_SERVER_URL=https://github.com
    "RUNNER_NAME=$(hostname -s)"
  )
  note "Reporting on branch '$BRANCH' (the default branch, mandatory for Test Insights),"
  note "pipeline '$PIPELINE_NAME', job 'big-junit-$SIZE-$MODE'."
else
  BRANCH="${BRANCH:-main}"
  note "No CI env (--no-ci-env): the spans carry no pipeline or job name, so the"
  note "backend drops every one of them at validation. The invisible case, on purpose."
fi
echo
echo "  \$ mergify ci junit-process \\"
echo "      --repository $REPOSITORY \\"
echo "      --tests-target-branch $BRANCH \\"
echo "      --test-framework pytest --test-language python \\"
echo "      --test-exit-code $TEST_EXIT_CODE \\"
echo "      $REPORT"
echo
note "The CLI parses the whole report, then streams every test as an OTLP span."
echo

# /usr/bin/time -l on macOS (BSD) reports peak RSS; -v on GNU. Either way the
# CLI's own exit code is what decides the demo's outcome, so keep it.
TIMER=(/usr/bin/time -l)
if ! /usr/bin/time -l true >/dev/null 2>&1; then TIMER=(/usr/bin/time); fi

LOG="$WORK/upload.log"
started=$(date +%s)
set +e
"${TIMER[@]}" env "${CI_ENV[@]}" mergify ci junit-process \
  --repository "$REPOSITORY" \
  --tests-target-branch "$BRANCH" \
  --test-framework pytest \
  --test-language python \
  --test-exit-code "$TEST_EXIT_CODE" \
  "$REPORT" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e
elapsed=$(( $(date +%s) - started ))

step "Result"
# `junit-process` exits 0 even when the API refuses the spans: ingestion is
# best effort, only the quarantine verdict drives the exit code. So a rejected
# upload looks exactly like a successful demo unless we look at the output.
UPLOAD_OK=true
if grep -qE 'not uploaded|Failed to upload' "$LOG"; then
  UPLOAD_OK=false
  printf '%sUPLOAD REJECTED — nothing will show up in the dashboard.%s\n' "$R" "$N"
  grep -E 'Failed to export|reason:' "$LOG" | sed 's/^ *│ */  /' | head -3
  echo "  Check that MERGIFY_TOKEN is a CI Insights application key for $REPOSITORY,"
  echo "  not a GitHub token: https://docs.mergify.com/ci-insights/setup"
  echo
  rc=1
fi
# The CLI exits 1 on any non-quarantined failure, which is exactly what the
# demo asks for. That says nothing about whether the upload landed.
printf 'exit code    : %s%s\n' "$rc" \
  "$([ "$rc" -ne 0 ] && [ "$UPLOAD_OK" = true ] && echo '  (the seeded failures are blocking, as intended)')"
printf 'wall clock   : %ss for %s bytes (%s tests)\n' "$elapsed" "$BYTES" "$TESTS"
if [ "$elapsed" -gt 0 ]; then
  printf 'throughput   : ~%s MB/s\n' "$(( BYTES / elapsed / 1000000 ))"
fi
echo
note "Peak memory is the 'maximum resident set size' line printed just above."
echo
if [ "$UPLOAD_OK" = true ] && [ "$FAKE_CI_ENV" = true ]; then
  note "Ingestion is asynchronous: the API stores the gzip blob and a worker"
  note "processes it after, so give it a moment before looking."
  echo
  ORG="${REPOSITORY%%/*}"; REPO="${REPOSITORY##*/}"
  BASE="https://dashboard.mergify.com/orgs/$ORG/repos/$REPO/test-insights/detection"
  if [ "$FAILURES" -gt 0 ]; then
    # A single execution per test means a failing test is classified `broken`,
    # never `flaky`: `calculate_health_status` only counts an execution as
    # flaky when the span carries `cicd.test.flaky`, which a JUnit upload
    # never sets. The page opens on the flaky tab, which will stay empty.
    printf 'Broken tests : %s?health=broken\n' "$BASE"
    printf '               the %s failing tests land there, not under Flaky\n' "$FAILURES"
  fi
  printf 'Healthy      : %s?health=healthy\n' "$BASE"
  printf 'Filter on    : job big-junit-%s-%s, pipeline %s\n' "$SIZE" "$MODE" "$PIPELINE_NAME"
fi
exit "$rc"
