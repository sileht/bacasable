# monorepo example project with badly configured CI

## CI Setup Issues with GitHub Workflow Paths Filtering

This repository demonstrates common CI configuration problems in monorepos when using GitHub Actions with paths filtering. The current setup uses workflow triggers like:

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

This repository uses the first approach (no paths filtering would be needed), demonstrating why paths filtering in monorepos often leads to either broken protections or wasted CI time.


