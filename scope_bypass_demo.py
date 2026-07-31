#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Demo: scope-driven merge-queue bypass (MRGFY-7904, shipped in #36075).

Shows *when* a queued pull request skips the merge-queue CI run and merges
immediately, using the customer's own example (Valentin Reis, Plain T-4441):

    main merge commits, newest first, with the scopes each impacted:
        A: s1, s2
        B: s1, s2
        C: s3
        D: s4
    open PRs, with scope + the commit their CI was based on:
        E: s3, based on B      -> should merge immediately (A/B/C/D didn't touch s3)
        F: s4, based on B      -> should merge immediately

The decision function `_base_delta_scopes_disjoint` below is a VERBATIM copy of
the shipped one in:
    engine/mergify_engine/queue/merge_queue/batch.py
The shipped code is authoritatively verified by the unit tests in
    engine/mergify_engine/tests/unit/queue/merge_queue/test_scope_bypass.py
This script just makes the behavior visible and lets you play with scenarios.

Run:  ./scope_bypass_demo.py           (or: uv run scope_bypass_demo.py)
"""

from __future__ import annotations

import fnmatch


# ---------------------------------------------------------------------------
# 1. The shipped decision function (verbatim from batch.py), instrumented with
#    an optional trace so you can watch the chain walk.
# ---------------------------------------------------------------------------
def base_delta_scopes_disjoint(
    current_base_sha: str,
    contained_shas: set[str],
    chain_rows: dict[str, tuple[str | None, set[str]]],
    pr_scopes: frozenset[str],
    *,
    trace: list[str] | None = None,
) -> bool:
    """Whether every base commit the PR lacks is scope-disjoint from it.

    Walks the recorded merge chain from `current_base_sha` back via each row's
    `previous_sha`, stopping at a commit the PR already contains, unioning the
    scopes of each intervening merge. Declines (returns False) on anything it
    cannot prove safe: empty pr_scopes, an unrecorded commit (external merge /
    direct push), a merge with empty scopes, a broken chain, an over-long walk,
    or an empty walk (a base read that disagrees with is_behind).
    """
    def log(msg: str) -> None:
        if trace is not None:
            trace.append(msg)

    if not pr_scopes:
        log("pr has no scopes (catch-all lane) -> DECLINE")
        return False

    impacted: set[str] = set()
    cursor = current_base_sha
    max_steps = len(chain_rows) + 1
    steps = 0
    while cursor not in contained_shas:
        row = chain_rows.get(cursor)
        if row is None:
            log(f"  {cursor}: no recorded row (external / too old) -> DECLINE")
            return False
        previous_sha, scopes = row
        if not scopes:
            log(f"  {cursor}: recorded merge with unknown scopes -> DECLINE")
            return False
        impacted |= scopes
        log(f"  {cursor}: merge touched {sorted(scopes)}  (impacted so far: {sorted(impacted)})")
        if previous_sha is None:
            log("  chain ran out before reaching a contained commit -> DECLINE")
            return False
        cursor = previous_sha
        steps += 1
        if steps > max_steps:
            log("  walk too long (corruption / cycle) -> DECLINE")
            return False
    log(f"  {cursor}: already contained by the PR -> stop")
    if not impacted:
        log("  empty delta (stale base read vs is_behind) -> DECLINE")
        return False
    ok = impacted.isdisjoint(pr_scopes)
    log(f"impacted {sorted(impacted)}  vs  pr {sorted(pr_scopes)}  -> "
        f"{'DISJOINT: BYPASS ✅' if ok else 'OVERLAP: RUN CI ❌'}")
    return ok


# ---------------------------------------------------------------------------
# 2. files -> scopes derivation (mirrors scopes.SourceFiles.match_scopes)
# ---------------------------------------------------------------------------
def match_scopes(changed_files: list[str], scope_globs: dict[str, list[str]]) -> set[str]:
    return {
        name
        for name, globs in scope_globs.items()
        if any(fnmatch.fnmatch(f, g) for f in changed_files for g in globs)
    }


# ---------------------------------------------------------------------------
# 3. The customer's scenario as a recorded scope-impact chain.
#    main history (oldest -> newest):  P -> D -> C -> B -> A
#    chain_rows = { resulting_sha: (previous_sha, scopes_touched) }
# ---------------------------------------------------------------------------
MAIN_TIP = "A"
CHAIN: dict[str, tuple[str | None, set[str]]] = {
    "D": ("P", {"s4"}),
    "C": ("D", {"s3"}),
    "B": ("C", {"s1", "s2"}),
    "A": ("B", {"s1", "s2"}),
}


def run(title: str, pr_scopes: set[str], based_on: str, chain=CHAIN, tip=MAIN_TIP) -> None:
    trace: list[str] = []
    decision = base_delta_scopes_disjoint(
        tip, {based_on}, chain, frozenset(pr_scopes), trace=trace,
    )
    verdict = "MERGE NOW, skip queue CI ✅" if decision else "run queue CI ❌"
    print(f"\n▶ {title}")
    print(f"    scopes={sorted(pr_scopes) or '(none)'}  based on {based_on}  "
          f"(main tip = {tip})")
    for line in trace:
        print(f"    {line}")
    print(f"    => {verdict}")


def main() -> None:
    print("=" * 72)
    print("Scope-driven merge-queue bypass — customer scenario (Plain T-4441)")
    print("main, newest first:  A:s1,s2   B:s1,s2   C:s3   D:s4")
    print("=" * 72)

    # The two PRs from the ticket — both should merge immediately.
    run("E — the ticket's first PR", {"s3"}, based_on="B")
    run("F — the ticket's second PR", {"s4"}, based_on="B")

    print("\n" + "-" * 72)
    print("Edge cases that must NOT bypass (safety):")
    print("-" * 72)

    # Scope actually touched by a base commit -> must run CI.
    run("G — touches s1 (which A/B changed)", {"s1"}, based_on="B")

    # No scopes (catch-all lane) -> must run CI.
    run("H — no scopes at all", set(), based_on="B")

    # An external commit X landed on main that Mergify did not merge -> unknown
    # impact -> must run CI (we only trust what we recorded).
    ext_chain = dict(CHAIN) | {"X": None}  # X present as tip but no recorded row
    run("I — external commit X on top of main", {"s3"}, based_on="B",
        chain={**CHAIN}, tip="X")

    print("\n" + "-" * 72)
    print("Deeper-behind but still disjoint -> still bypasses:")
    print("-" * 72)
    run("J — s3, based further back on C", {"s3"}, based_on="C")

    print("\n" + "-" * 72)
    print("files -> scopes derivation (files source):")
    print("-" * 72)
    scope_globs = {
        "s1": ["services/a/**"],
        "s2": ["services/b/**"],
        "s3": ["services/c/**"],
        "s4": ["services/d/**"],
    }
    for files in (["services/c/handler.py"], ["services/a/x.py", "services/d/y.py"]):
        print(f"    changed {files}  ->  scopes {sorted(match_scopes(files, scope_globs))}")


if __name__ == "__main__":
    main()
