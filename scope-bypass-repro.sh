#!/usr/bin/env bash
# scope-bypass-repro.sh — reproduce MRGFY-7922 end-to-end on sileht/bacasable.
#
# The bug: a queued pull request that is BEHIND main, but whose scopes are
# DISJOINT from the commits it is missing, must merge immediately (its own green
# CI still covers it). Before the fix it got stuck at "waiting for CI" forever.
#
# Scenario (the customer's, minimized):
#   - PR B : touches docs/**            (scope = docs), CI goes green on old main.
#   - PR A : touches main1.py           (scope = backend), merged -> advances main.
#   - PR C : touches main2.py           (scope = backend), merged -> advances main.
#   Now B is BEHIND main by A+C (both backend) but B is docs -> scopes disjoint.
#   Queue B:
#       FIXED  -> B merges within a minute or two WITHOUT re-running CI.
#       BUG    -> B stays open, its merge-queue check sits at "waiting for CI".
#
# PREREQUISITES (this script cannot set them):
#   1. The org (sileht) has MERGE_QUEUE_SCOPE_UNAFFECTED_BYPASS_ENABLED_ORGS on.
#   2. To observe FIXED, the engine serving this org must have #36256 deployed.
#      Run it before the deploy and you should observe the BUG (a good baseline).
#
# Usage:
#   ./scope-bypass-repro.sh            # full run, restores .mergify.yml at the end
#   ./scope-bypass-repro.sh --keep     # leave the repro PRs/branches for inspection
#   ./scope-bypass-repro.sh --no-config# don't touch .mergify.yml (use the live one;
#                                       # only works inside the 18:00-20:00 window)
set -euo pipefail

REPO="sileht/bacasable"
TS="$(date +%s)"
A_BRANCH="scope-repro-A-$TS"   # backend
B_BRANCH="scope-repro-B-$TS"   # docs (the one that must merge while behind)
C_BRANCH="scope-repro-C-$TS"   # backend
QUEUE_LABEL="queue"
POLL_TIMEOUT=600               # seconds to wait for B to merge before calling it stuck
KEEP=0; TOUCH_CONFIG=1
for arg in "$@"; do
  case "$arg" in
    --keep) KEEP=1 ;;
    --no-config) TOUCH_CONFIG=0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
[ -f .mergify.yml ] || { echo "not in the bacasable checkout ($here)"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "run: gh auth login"; exit 1; }
# The script does `git reset --hard origin/main`; refuse to nuke uncommitted work.
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "worktree has uncommitted changes — commit/stash them first (this script hard-resets to origin/main)"; exit 1
fi

log(){ printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
note(){ printf '   %s\n' "$*"; }

restore_config(){
  if [ "$TOUCH_CONFIG" = 1 ] && [ -f .mergify.yml.repro-bak ]; then
    log "Restoring the original .mergify.yml"
    mv .mergify.yml.repro-bak .mergify.yml
    git add .mergify.yml
    git commit -m "chore: restore .mergify.yml after scope-bypass repro" >/dev/null
    git push origin main >/dev/null
  fi
}
cleanup(){
  local rc=$?
  if [ "$KEEP" = 0 ]; then
    log "Cleanup (close repro PRs, delete branches)"
    for b in "$A_BRANCH" "$B_BRANCH" "$C_BRANCH"; do
      gh pr close "$b" --delete-branch >/dev/null 2>&1 || true
      git push origin --delete "$b" >/dev/null 2>&1 || true
    done
  else
    note "--keep: left repro PRs/branches in place"
  fi
  restore_config
  exit $rc
}
trap cleanup EXIT

# ---- helpers ---------------------------------------------------------------
wait_ci_gate_green(){  # $1 = branch
  local br="$1" deadline=$((SECONDS+600)) st
  log "Waiting for ci-gate to go green on $br (its own CI)"
  while :; do
    st=$(gh pr checks "$br" --json name,state 2>/dev/null \
          | python3 -c "import sys,json;d=json.load(sys.stdin);print(next((c['state'] for c in d if c['name']=='ci-gate'),'MISSING'))" 2>/dev/null || echo ERR)
    note "ci-gate: $st"
    [ "$st" = "SUCCESS" ] && return 0
    [ $SECONDS -ge $deadline ] && { echo "timed out waiting for ci-gate on $br"; return 1; }
    sleep 15
  done
}
queue_and_wait_merge(){  # $1 = branch, $2 = human label
  local br="$1" what="$2" deadline=$((SECONDS+POLL_TIMEOUT)) state
  log "Queueing $what ($br) and waiting for it to merge"
  gh pr edit "$br" --add-label "$QUEUE_LABEL" >/dev/null
  while :; do
    state=$(gh pr view "$br" --json state --jq .state 2>/dev/null || echo ERR)
    note "$what state: $state"
    [ "$state" = "MERGED" ] && { note "$what merged"; return 0; }
    [ $SECONDS -ge $deadline ] && { echo "$what did not merge in time"; return 1; }
    sleep 20
  done
}
mk_pr(){  # $1 branch, $2 file, $3 content-tag, $4 title, $5 base-branch(optional, default main)
  local br="$1" file="$2" tag="$3" title="$4" base="${5:-main}"
  git fetch origin "$base" >/dev/null 2>&1
  git checkout -q -B "$br" "origin/$base"
  mkdir -p "$(dirname "$file")"
  printf '# scope-bypass repro %s (%s)\n' "$tag" "$TS" >> "$file"
  git add "$file"
  git commit -q -m "$title"
  git push -q -u origin "$br" -f
  gh pr create --repo "$REPO" --base main --head "$br" --title "$title" \
    --body "Automated scope-bypass repro ($TS). Safe to close." >/dev/null
  note "created PR $br  ($file)"
}

# ---- 0. apply repro config -------------------------------------------------
git fetch origin main >/dev/null 2>&1
git checkout -q main
git reset -q --hard origin/main
if [ "$TOUCH_CONFIG" = 1 ]; then
  log "Applying repro .mergify.yml (parallel, batch_size 1, no schedule)"
  cp .mergify.yml .mergify.yml.repro-bak
  cp scope-bypass-repro.mergify.yml .mergify.yml
  git add .mergify.yml
  git commit -q -m "chore: scope-bypass repro config (temporary)"
  git push -q origin main
  note "gave Mergify a few seconds to ingest the config"
  sleep 8
fi

# ---- 1. create A (backend) and B (docs), both off main ---------------------
log "Creating PRs A (backend) and B (docs)"
mk_pr "$A_BRANCH" "main1.py"                "A-backend" "scope-repro: A backend (main1.py)"
mk_pr "$B_BRANCH" "docs/scope-repro-B.md"   "B-docs"    "scope-repro: B docs (must merge while behind)"

# ---- 2. let B's own CI go green on old main --------------------------------
wait_ci_gate_green "$B_BRANCH"

# ---- 3. merge A, then C — advance main with backend-only commits -----------
queue_and_wait_merge "$A_BRANCH" "A (backend)"
# C is branched off the NOW-advanced main so it is itself up-to-date and merges.
mk_pr "$C_BRANCH" "main2.py" "C-backend" "scope-repro: C backend (main2.py)"
queue_and_wait_merge "$C_BRANCH" "C (backend)"

# ---- 4. B is now behind main by A+C (backend), disjoint from B (docs) ------
log "B is now behind main by backend-only commits, disjoint from its docs scope"
gh pr view "$B_BRANCH" --json mergeable,mergeStateStatus --jq \
  '"   B mergeable=\(.mergeable) mergeStateStatus=\(.mergeStateStatus)"' || true

log "Queueing B — THE TEST"
gh pr edit "$B_BRANCH" --add-label "$QUEUE_LABEL" >/dev/null
B_URL=$(gh pr view "$B_BRANCH" --json url --jq .url)
note "watching $B_URL"
deadline=$((SECONDS+POLL_TIMEOUT))
verdict="UNKNOWN"
while :; do
  state=$(gh pr view "$B_BRANCH" --json state --jq .state 2>/dev/null || echo ERR)
  mqline=$(gh pr checks "$B_BRANCH" 2>/dev/null | grep -iE "merge.?queue" | head -1 | tr '\t' ' ' || true)
  note "B state=$state | mq: ${mqline:-n/a}"
  if [ "$state" = "MERGED" ]; then verdict="FIXED"; break; fi
  if [ "$state" = "CLOSED" ]; then verdict="CLOSED-EXTERNALLY"; break; fi
  if [ $SECONDS -ge $deadline ]; then verdict="BUG-STUCK"; break; fi
  sleep 20
done

log "RESULT"
case "$verdict" in
  FIXED)
    printf '   ✅ FIXED — B merged while behind by scope-disjoint backend commits (bypass fired, no fresh CI).\n' ;;
  BUG-STUCK)
    printf '   ❌ BUG — B did not merge within %ss; it is stuck (waiting for CI) despite disjoint scopes.\n' "$POLL_TIMEOUT"
    printf '      If the fix (#36256) is not deployed to this org yet, this is the expected baseline.\n' ;;
  *)
    printf '   ⚠️  Inconclusive (verdict=%s). Inspect %s\n' "$verdict" "$B_URL" ;;
esac
echo "$verdict" > "scope-bypass-repro-$TS.result"
note "verdict written to scope-bypass-repro-$TS.result"
