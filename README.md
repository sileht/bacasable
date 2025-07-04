# monorepo example project with badly configured CI

## CI Setup Issues with GitHub Workflow Paths Filtering

This repository demonstrates common CI configuration problems in monorepos when using GitHub Actions with paths filtering. The problematic approach uses workflow triggers like:

```yaml
on:
  pull_request:
    paths:
      - 'python/**'
```

### The Problem

This approach creates two fundamental issues for monorepos:

#### 1. No "All CI Passed" Status in GitHub Actions

GitHub Actions has no built-in concept of "all CI passed" status. When a workflow doesn't run due to paths filtering, GitHub cannot distinguish between:
- **Intentionally skipped** (no relevant files changed)
- **Not started yet** (workflow pending)
- **CI system broken** (workflow failed to trigger)

This ambiguity makes it impossible to programmatically determine if all required checks have completed successfully.

#### 2. Incompatibility with Protection Systems

Since there's no "all CI passed" concept, protection systems require explicitly listing every CI job:

- **GitHub Branch Protection Rules**: Must specify each workflow/job name
- **Mergify Merge Protections**: Must list all required status checks
- **Merge Queue Systems**: Need to know which checks to wait for

When using paths filtering, workflows simply don't run for unrelated changes, causing these protection systems to fail because they're waiting for checks that will never report.

### The Trade-off

To make protection systems work, you have two options:

1. **Remove paths filtering** - All workflows run on every PR, wasting CI resources
2. **Complex conditional logic** - Use job-level conditions to skip work while still reporting status

Most repositories use the first approach (no paths filtering), which wastes CI time. This repository demonstrates a better solution that maintains CI efficiency while providing reliable protection system compatibility.

## Solution: Smart CI Workflow with Change Detection

This repository includes a solution that fixes the monorepo CI issues using `ci.yaml` workflow:

### Architecture

```yaml
# ci.yaml - Main workflow that always runs
name: CI

on:
  pull_request:
  push:
    branches: [main]

jobs:
  changes:
    runs-on: ubuntu-latest
    outputs:
      js: ${{ steps.changes.outputs.js }}
      python: ${{ steps.changes.outputs.python }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v3
        id: changes
        with:
          filters: |
            js:
              - 'js/**'
            python:
              - 'python/**'
    
  javascript:
    needs: changes
    if: ${{ needs.changes.outputs.js == 'true' }}
    uses: ./.github/workflows/javascript.yaml
    
  python:
    needs: changes
    if: ${{ needs.changes.outputs.python == 'true' }}
    uses: ./.github/workflows/python.yaml
    
  all-green:
    if: always()
    needs: [changes, javascript, python]
    runs-on: ubuntu-latest
    steps:
      - name: Decide whether the needed jobs succeeded or failed
        uses: re-actors/alls-green@release/v1
        with:
          jobs: ${{ toJSON(needs) }}
          allowed-skips: ${{ toJSON(needs) }}
```

### Key Components

1. **Change Detection**: Uses `dorny/paths-filter` to detect which directories have changes
2. **Conditional Jobs**: JavaScript and Python jobs only run when their respective directories change
3. **Always Report Status**: Main workflow always runs, providing consistent CI status
4. **Smart Completion**: `alls-green` with `allowed-skips` handles skipped jobs properly

### Benefits

- ✅ **Consistent Status**: Always provides "all CI passed" status
- ✅ **Efficient**: Only runs relevant tests when files change
- ✅ **Protection Compatible**: Works with branch protection and merge queues
- ✅ **Resource Saving**: Avoids unnecessary CI runs while maintaining reliability

### Migration Steps

1. Convert existing workflows to reusable workflows (change `pull_request` to `workflow_call`)
2. Create main `ci.yaml` with change detection and conditional job execution
3. Update branch protection rules to only require the main `ci.yaml` workflow
4. Remove paths filtering from individual workflows


