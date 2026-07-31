#!/usr/bin/env bash
#
# Demo: Mergify merge-queue "Re-running Only the Previously Failed Tests"
# ----------------------------------------------------------------------
# When Mergify splits a failed batch, every split is a subset of the batch that
# failed. Instead of re-running the whole suite on each split, Mergify exposes
# the parent batches (`mergify ci queue-info` -> previous_failed_batches) so the
# CI can pull the parent's failed tests (extracted from its JUnit XML report)
# and re-run ONLY those. Passing tests stay green; only the still-suspect tests
# are worth re-checking to isolate the culprit PR.
#
# This script demonstrates that end to end, fully locally: no GitHub, no
# network, and it touches NO tracked file (everything lives in the gitignored
# scratch dir .junit-split-demo/, wiped on each run).
#
#   Phase 1  parent batch: run the FULL suite -> JUnit XML -> failed-tests.txt
#   Phase 2  a split of that batch: read queue metadata, reuse the parent's
#            failed-tests artifact, re-run ONLY the previously failed tests.
#
# Docs: repos/docs -> merge-queue/batches "Re-running Only the Previously Failed Tests"

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$ROOT/.junit-split-demo"
SUITE="$WORK/suite"
PARSER="$ROOT/junit_to_failed_tests.py"

# --- colours / helpers ------------------------------------------------------
if [ -t 1 ]; then B=$'\033[1m'; C=$'\033[36m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'; else B=; C=; G=; Y=; R=; N=; fi
step() { printf '\n%s=== %s ===%s\n' "$B$C" "$1" "$N"; }
note() { printf '%s%s%s\n' "$Y" "$1" "$N"; }

# --- pick a pytest runner (local binary first, else ephemeral uvx) ----------
if command -v pytest >/dev/null 2>&1; then PYTEST=(pytest)
elif command -v uvx  >/dev/null 2>&1; then PYTEST=(uvx pytest)
else echo "This demo needs pytest (or uv). Install one and retry." >&2; exit 1; fi

rm -rf "$WORK"; mkdir -p "$SUITE"

# --- the app's test suite: 7 tests, test_division is the culprit ------------
cat > "$SUITE/test_math.py" <<'PY'
def test_addition():        assert 1 + 1 == 2
def test_subtraction():     assert 5 - 2 == 3
def test_multiplication():  assert 3 * 4 == 12
def test_division():        assert 6 / 3 == 3   # BUG: 6/3 == 2, this one fails
PY
cat > "$SUITE/test_strings.py" <<'PY'
def test_upper():   assert "ci".upper() == "CI"
def test_concat():  assert "a" + "b" == "ab"
def test_split():   assert "a,b".split(",") == ["a", "b"]
PY
# Empty config pins pytest's rootdir to the suite dir, so JUnit `classname` is
# the bare module name (test_math) instead of a dotted path from some ancestor
# rootdir. That keeps the reconstructed node ids relative and re-runnable.
: > "$SUITE/pytest.ini"

# ===========================================================================
step "Phase 1 - Parent batch (draft PR #980, batches PRs #123-#126)"
note "Runs the FULL suite (7 tests). Mimics the batch CI run before it fails."
echo

set +e
( cd "$SUITE" && "${PYTEST[@]}" -q -c pytest.ini --junit-xml="$WORK/parent-junit.xml" )
parent_rc=$?
set -e
printf '\npytest exit code: %s  (%s)\n' "$parent_rc" "$([ $parent_rc -eq 0 ] && echo all green || echo batch FAILED)"

step "Extract failed tests from the parent's JUnit XML"
note "A CI step turns junit.xml into the failed-tests artifact the split reuses:"
echo "  \$ python3 junit_to_failed_tests.py parent-junit.xml > failed-tests.txt"
echo
python3 "$PARSER" "$WORK/parent-junit.xml" > "$WORK/failed-tests.txt"
printf '%sfailed-tests.txt (uploaded as the `failed-tests` artifact of #980):%s\n' "$G" "$N"
sed 's/^/  - /' "$WORK/failed-tests.txt"

# ===========================================================================
step "Phase 2 - A split of that batch (current draft PR, tests #123-#124)"
note "Mergify split the failed batch. The split job asks Mergify what it descends from."

# What `mergify ci queue-info` prints on this split's draft PR. Faked here so the
# demo stays offline; on a real queue draft PR the CLI produces exactly this shape.
cat > "$WORK/queue_metadata.json" <<'JSON'
{
  "checking_base_sha": "f4a9c1e9b2d34c5a6f7081923abcde4567890123",
  "pull_requests": [
    { "number": 123 },
    { "number": 124 }
  ],
  "previous_failed_batches": [
    { "draft_pr_number": 980, "checked_pull_requests": [123, 124, 125, 126] }
  ]
}
JSON
echo
echo "  \$ mergify ci queue-info   # -> queue_metadata step output"
sed 's/^/  /' "$WORK/queue_metadata.json"

step "Narrow the split to only the parent's failed tests"
# The batch this split came from is the LAST entry of previous_failed_batches.
draft_pr=$(jq -r '.previous_failed_batches[-1].draft_pr_number // empty' "$WORK/queue_metadata.json")
if [ -z "$draft_pr" ]; then
  note "No previous failed batch -> would run the full suite (safe fallback)."
  ONLY_TESTS=""
else
  echo "  previous failed batch = draft PR #$draft_pr"
  echo "  \$ gh run download <#$draft_pr run> --name failed-tests   # reused locally"
  # Reuse the artifact produced in Phase 1 (what gh run download would fetch).
  ONLY_TESTS=$(paste -sd ' ' "$WORK/failed-tests.txt")
fi

echo
if [ -n "$ONLY_TESTS" ]; then
  printf '%sONLY_TESTS = %s%s\n' "$G" "$ONLY_TESTS" "$N"
  note "Re-running only the previously failed tests instead of all 7:"
  echo "  \$ pytest \$ONLY_TESTS"
  echo
  set +e
  ( cd "$SUITE" && "${PYTEST[@]}" -q -c pytest.ini --junit-xml="$WORK/split-junit.xml" $ONLY_TESTS )
  split_rc=$?
  set -e
  printf '\npytest exit code: %s\n' "$split_rc"
else
  ( cd "$SUITE" && "${PYTEST[@]}" -q )
fi

# ===========================================================================
step "Summary"
full_count=$(grep -c '^def test_' "$SUITE"/test_*.py | awk -F: '{s+=$2} END{print s}')
only_count=$(wc -w < "$WORK/failed-tests.txt" | tr -d ' ')
printf '  Parent batch  : ran %s%s tests%s (full suite) -> failed, split\n' "$B" "$full_count" "$N"
printf '  This split    : ran %s%s test%s  (only the previously failed) -> %s\n' "$B" "$only_count" "$N" "$([ "${split_rc:-1}" -eq 0 ] && echo "${G}green${N}" || echo "${R}still red${N}, isolates the culprit PR")"
printf '  Saved         : %s%s of %s tests skipped%s on the split\n' "$G" "$((full_count - only_count))" "$full_count" "$N"
echo
note "Scratch artifacts in: $WORK  (gitignored, safe to delete)"
