#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Extract failed/errored test node ids from a JUnit XML report.

This mirrors what a CI job does right before it uploads the `failed-tests`
artifact that Mergify's merge-queue batch-split optimization re-runs on each
split (see docs: merge-queue/batches "Re-running Only the Previously Failed
Tests"). Prints one pytest node id per line, e.g. `test_math.py::test_division`.

Caveat: with pytest's default junit_family (xunit2) a <testcase> only carries
`classname`/`name`, so we rebuild the file path from `classname`. That is exact
for top-level test functions (classname == module path). Class-based tests would
need `--override-ini junit_family=...` that emits a `file` attribute, which we
prefer here when present.
"""

import sys
import xml.etree.ElementTree as ET


def node_id(testcase: ET.Element) -> str:
    name = testcase.get("name", "")
    file = testcase.get("file")
    if not file:
        classname = testcase.get("classname") or ""
        file = classname.replace(".", "/") + ".py" if classname else ""
    return f"{file}::{name}" if file else name


def main(path: str) -> int:
    root = ET.parse(path).getroot()
    for testcase in root.iter("testcase"):
        if testcase.find("failure") is not None or testcase.find("error") is not None:
            print(node_id(testcase))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <junit.xml>", file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1]))
