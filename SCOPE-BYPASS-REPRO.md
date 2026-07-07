# MRGFY-7922 scope-bypass repro

End-to-end check on `sileht/bacasable` that a **behind-but-scope-disjoint** PR
merges instead of sticking at "waiting for CI".

## Files

- `scope-bypass-repro.mergify.yml` — repro-tuned config: `mode: parallel`,
  `batch_size: 1`, files-based scopes, and **no `schedule` merge condition** (the
  everyday `.mergify.yml` only merges 18:00–20:00 Paris, which would mask the test).
- `scope-bypass-repro.sh` — orchestrates the scenario and prints a verdict.

## The scenario

| PR | touches | scope | role |
|----|---------|-------|------|
| B  | `docs/scope-repro-B.md` | `docs` | must merge while behind |
| A  | `main1.py` | `backend` | merged first → advances `main` |
| C  | `main2.py` | `backend` | merged next → advances `main` |

B's CI goes green on the old `main`. Then A and C merge, so `main` moves forward
with **backend-only** commits. B is now *behind* `main`, but its scope (`docs`) is
disjoint from what landed (`backend`), so its own green CI still covers the merge.

Queue B:

- **✅ FIXED** — B merges within a minute or two, no fresh CI run.
- **❌ BUG** — B stays open with its merge-queue check stuck at "waiting for CI".

## Prerequisites (the script can't set these)

1. The org (`sileht`) has `MERGE_QUEUE_SCOPE_UNAFFECTED_BYPASS_ENABLED_ORGS` on.
2. To observe **FIXED**, the engine serving this org must have **#36256 deployed**.
   Run it *before* the deploy and you should see the **BUG** — a useful baseline.

## Run

```bash
cd ~/workspace/mergify/bacasable
./scope-bypass-repro.sh          # full run; restores .mergify.yml at the end
./scope-bypass-repro.sh --keep   # leave the repro PRs/branches for inspection
```

It backs up `.mergify.yml`, commits the repro config to `main`, creates the PRs,
merges A and C, queues B, polls up to 10 min, prints the verdict (also written to
`scope-bypass-repro-<ts>.result`), then cleans up and restores the original config.
Refuses to run with a dirty worktree (it hard-resets to `origin/main`).
