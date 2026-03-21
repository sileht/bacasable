#!/usr/bin/env python3
"""Render the merge queue DAG from a train_model row.

Reads the raw psql row_to_json output from stdin and prints
a human-readable DAG visualization.
"""
from __future__ import annotations

import json
import sys


def unwrap(val: str | dict | list) -> str | list:
    """Unwrap Python-typed JSON objects like {"value": ..., "__pytype__": ...}."""
    if isinstance(val, dict) and "__pytype__" in val:
        return val["value"]
    return val


def unwrap_uuid(val: str | dict) -> str:
    result = unwrap(val)
    return str(result)


def short(uuid: str | dict) -> str:
    return unwrap_uuid(uuid)[:8]


OUTCOME_SYMBOLS = {
    "preparing": "⏳",
    "checking": "🔄",
    "waiting_for_merge": "✅",
    "merged": "🟢",
    "error_checking": "❌",
    "batch_split": "✂️",
    "schedule_blocked": "⏸️",
    "freeze_blocked": "🧊",
    "frozen": "🧊",
}


def parse_psql_output(text: str) -> dict | None:
    """Extract JSON from psql row_to_json output."""
    for line in text.strip().split("\n"):
        stripped = line.strip()
        if stripped.startswith("{"):
            return json.loads(stripped)
    return None


def render(data: dict) -> None:
    cars = data["cars"]
    scope_queues = data["scope_queues"] or {}
    mode = data["mode"] or "serial (legacy)"
    waiting = data["waiting_pulls"]

    car_by_id: dict[str, dict] = {}
    for car in cars:
        car_by_id[unwrap_uuid(car["id"])] = car

    # Header
    print("╔══════════════════════════════════════════════════════════════════╗")
    print(f"║  Merge Queue DAG — mode: {mode:<40s}║")
    print("╚══════════════════════════════════════════════════════════════════╝")
    print()

    if not cars:
        print("  (empty queue)")
        if waiting:
            print()
            print(f"  Waiting pulls: {len(waiting)}")
            for wp in waiting:
                print(f"    PR #{wp['user_pull_request_number']}")
        return

    # Cars table
    print(f"  Cars ({len(cars)}):")
    print(f"  {'ID':>8s}  {'PRs':<14s} {'Outcome':<22s} {'Scopes':<20s} {'Parents':<20s} {'Parent PRs':<20s}")
    print(f"  {'─'*8}  {'─'*14} {'─'*22} {'─'*20} {'─'*20} {'─'*20}")
    for car in cars:
        pr_nums = ", ".join(
            f"#{ep['user_pull_request_number']}"
            for ep in car["still_queued_embarked_pulls"]
        )
        outcome = car["train_car_state"]["outcome"]
        symbol = OUTCOME_SYMBOLS.get(outcome, "?")
        scopes_list = car.get("scopes") or []
        scopes = ", ".join(scopes_list) if scopes_list else "(none)"
        parent_ids = car.get("parent_car_ids") or []
        parents = (
            "(root)"
            if not parent_ids
            else ", ".join(short(p) for p in parent_ids)
        )
        if not parent_ids:
            parent_prs = "(root)"
        else:
            parent_pr_parts = []
            for pid in parent_ids:
                parent_car = car_by_id.get(unwrap_uuid(pid))
                if parent_car:
                    parent_pr_parts.extend(
                        f"#{ep['user_pull_request_number']}"
                        for ep in parent_car["still_queued_embarked_pulls"]
                    )
                else:
                    parent_pr_parts.append(f"?{short(pid)}")
            parent_prs = ", ".join(parent_pr_parts)
        print(f"  {short(car['id']):>8s}  {pr_nums:<14s} {symbol} {outcome:<19s} {scopes:<20s} {parents:<20s} {parent_prs:<20s}")

    # Scope queues
    real_scopes = {
        k: v for k, v in sorted(scope_queues.items())
        if v and not k.startswith("__unique_") and k != "__default__"
    }
    unique_scopes = {
        k: v for k, v in scope_queues.items()
        if k.startswith("__unique_")
    }

    if real_scopes or unique_scopes:
        print()
        print("  Scope Queues:")
        for scope_name, car_ids in real_scopes.items():
            chain_parts = []
            for cid in car_ids:
                cid_str = unwrap_uuid(cid)
                car = car_by_id.get(cid_str, {})
                prs = ", ".join(
                    f"#{ep['user_pull_request_number']}"
                    for ep in car.get("still_queued_embarked_pulls", [])
                )
                outcome = car.get("train_car_state", {}).get("outcome", "?")
                symbol = OUTCOME_SYMBOLS.get(outcome, "?")
                chain_parts.append(f"[{short(cid)} {prs} {symbol}]")
            print(f"    {scope_name}: {' → '.join(chain_parts)}")

        if unique_scopes:
            for scope_name, car_ids in unique_scopes.items():
                for cid in car_ids:
                    cid_str = unwrap_uuid(cid)
                    car = car_by_id.get(cid_str, {})
                    prs = ", ".join(
                        f"#{ep['user_pull_request_number']}"
                        for ep in car.get("still_queued_embarked_pulls", [])
                    )
                    outcome = car.get("train_car_state", {}).get("outcome", "?")
                    symbol = OUTCOME_SYMBOLS.get(outcome, "?")
                    print(f"    (isolated): [{short(cid)} {prs} {symbol}]")

    # DAG (tree view from roots)
    print()
    print("  DAG:")
    roots = [
        c for c in cars
        if not c.get("parent_car_ids")
    ]
    visited: set[str] = set()

    def print_tree(car_id: str, prefix: str = "    ", is_last: bool = True) -> None:
        if car_id in visited:
            print(f"{prefix}{'└── ' if is_last else '├── '}({short(car_id)} — see above)")
            return
        visited.add(car_id)

        car = car_by_id.get(car_id)
        if car is None:
            print(f"{prefix}{'└── ' if is_last else '├── '}({short(car_id)} — removed)")
            return

        prs = ", ".join(
            f"#{ep['user_pull_request_number']}"
            for ep in car.get("still_queued_embarked_pulls", [])
        )
        outcome = car["train_car_state"]["outcome"]
        symbol = OUTCOME_SYMBOLS.get(outcome, "?")
        scopes_list = car.get("scopes") or []
        scopes_str = ",".join(scopes_list) if scopes_list else "none"

        connector = "└── " if is_last else "├── "
        print(f"{prefix}{connector}{short(car_id)} {prs} [{scopes_str}] {symbol} {outcome}")

        # Find children (cars whose parent_car_ids includes this car)
        children = [
            c for c in cars
            if car_id in [unwrap_uuid(p) for p in (c.get("parent_car_ids") or [])]
        ]
        child_prefix = prefix + ("    " if is_last else "│   ")
        for i, child in enumerate(children):
            print_tree(unwrap_uuid(child["id"]), child_prefix, i == len(children) - 1)

    for i, root in enumerate(roots):
        print_tree(unwrap_uuid(root["id"]), "    ", i == len(roots) - 1)

    # Waiting pulls
    if waiting:
        print()
        print(f"  Waiting ({len(waiting)}):")
        for wp in waiting:
            raw_scopes = wp.get("config", {}).get("scopes") or []
            scopes_list = unwrap(raw_scopes) if isinstance(raw_scopes, dict) else raw_scopes
            scopes = ", ".join(sorted(scopes_list)) if scopes_list else "(none)"
            print(f"    PR #{wp['user_pull_request_number']}  scopes: {scopes}")

    print()


def main() -> None:
    text = sys.stdin.read()
    data = parse_psql_output(text)
    if data is None:
        print("No train data found (empty queue or no matching row).", file=sys.stderr)
        sys.exit(1)
    render(data)


if __name__ == "__main__":
    main()
