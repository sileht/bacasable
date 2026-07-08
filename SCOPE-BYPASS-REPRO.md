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
| N advancers | `main-repro-*.py`, `frontend/*`, `infra/*`, `api/*` (rotating) | backend / frontend / infra / api | merged one after another → march `main` forward |

B's CI goes green on the old `main`. Then `N` advancers merge in sequence
(default 6, rotating through the non-docs scopes), so `main` marches forward by
`N` **scope-disjoint** commits. B is now *behind* `main` by all of them, but its
scope (`docs`) is disjoint from every one, so its own green CI still covers the
merge — and the bypass has to walk the whole `N`-long recorded scope-impact chain
(`get_recent_chain`) to prove it.

Queue B:

- **✅ FIXED** — B merges within a minute or two, no fresh CI run.
- **❌ BUG** — B stays open with its merge-queue check stuck at "waiting for CI".

`--advancers N` sets the chain length — a longer chain is a busier-monorepo
scenario and stresses the chain walk harder.

## Prerequisites (the script can't set these)

1. The org (`sileht`) has `MERGE_QUEUE_SCOPE_UNAFFECTED_BYPASS_ENABLED_ORGS` on.
2. To observe **FIXED**, the engine serving this org must have **#36256 deployed**.
   Run it *before* the deploy and you should see the **BUG** — a useful baseline.

## Run

```bash
cd ~/workspace/mergify/bacasable
./scope-bypass-repro.sh                 # 6 advancers; restores .mergify.yml at the end
./scope-bypass-repro.sh --advancers 10  # march main forward 10 commits before B
./scope-bypass-repro.sh --keep          # leave the repro PRs/branches for inspection
```

It backs up `.mergify.yml`, commits the repro config to `main`, creates B, lands
the `N` scope-disjoint advancers, queues B, polls up to 10 min, prints the verdict
(also written to `scope-bypass-repro-<ts>.result`), then cleans up and restores the
original config. Refuses to run with a dirty worktree (it hard-resets to `origin/main`).
