#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Generate a JUnit XML report of an arbitrary size.

Used by demo-junit-upload-500mb.sh to stress `mergify ci junit-process` with a
very large report. Two shapes of "big" exist and they exercise different parts
of the pipeline, hence --mode:

  tests    millions of small <testcase> elements -> high test cardinality,
           huge span count on the OTLP upload.
  payload  fewer tests, each carrying a fat <system-out>/<failure> body ->
           few spans, but very large attributes per span.

Output is streamed suite by suite so memory stays flat whatever the size.
"""

from __future__ import annotations

import argparse
import pathlib
import random
import sys
import time

UNITS = {
    "b": 1,
    "kb": 1000,
    "mb": 1000**2,
    "gb": 1000**3,
    "kib": 1024,
    "mib": 1024**2,
    "gib": 1024**3,
}

# One test in TESTS_PER_SUITE out of this many is made to fail, and one in half
# of it is skipped: enough red to be visible in CI Insights without drowning it.
FAILURE_EVERY = 97
SKIP_EVERY = 211
# A suite is written in one go, so it is also the size granularity: keep it
# small in payload mode where a single test weighs ~15 KiB.
TESTS_PER_SUITE = {"tests": 5000, "payload": 500}

STACK = """Traceback (most recent call last):
  File "/src/tests/module_{suite}/test_{mod}.py", line {line}, in {name}
    assert compute_widget_total(order) == expected
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
AssertionError: assert 41 == 42
 +  where 41 = compute_widget_total(&lt;Order id=32109&gt;)"""


def parse_size(value: str) -> int:
    text = value.strip().lower().replace(" ", "").replace("o", "b")
    for suffix in sorted(UNITS, key=len, reverse=True):
        if text.endswith(suffix):
            return int(float(text[: -len(suffix)]) * UNITS[suffix])
    return int(float(text))


def human(size: int) -> str:
    for unit in ("B", "KiB", "MiB", "GiB"):
        if size < 1024 or unit == "GiB":
            return f"{size:.1f} {unit}" if unit != "B" else f"{size} B"
        size /= 1024
    raise AssertionError("unreachable")


def make_testcase(
    suite: int, index: int, mode: str, failure_every: int, rng: random.Random
) -> str:
    mod = index % 17
    name = f"test_case_{index:06d}_{('widget', 'order', 'invoice', 'user')[index % 4]}"
    classname = f"tests.module_{suite:05d}.test_{mod:02d}"
    head = (
        f'    <testcase classname="{classname}" name="{name}" '
        f'file="tests/module_{suite:05d}/test_{mod:02d}.py" '
        f'line="{10 + index % 900}" time="{rng.uniform(0.001, 2.5):.3f}"'
    )

    if index % SKIP_EVERY == 0:
        return f'{head}>\n      <skipped type="pytest.skip" message="needs network"/>\n    </testcase>\n'

    body = ""
    if failure_every and index % failure_every == 0:
        stack = STACK.format(suite=suite, mod=mod, line=10 + index % 900, name=name)
        body += (
            '      <failure message="assert 41 == 42" type="AssertionError">'
            f"{stack}</failure>\n"
        )

    if mode == "payload":
        # ~20 KiB of captured stdout per test: this is what makes the report fat
        # in payload mode, and what the ingestion has to carry per span.
        log = "".join(
            f"      [{i:04d}] DEBUG worker-{i % 8} processed batch {i} in {i % 97}ms\n"
            for i in range(280)
        )
        body += f"      <system-out>{log}      </system-out>\n"

    if not body:
        return head + "/>\n"
    return f"{head}>\n{body}    </testcase>\n"


def generate(
    out: pathlib.Path, target: int, mode: str, failure_every: int, seed: int
) -> tuple[int, int]:
    rng = random.Random(seed)
    timestamp = time.strftime("%Y-%m-%dT%H:%M:%S")
    per_suite = TESTS_PER_SUITE[mode]
    written = 0
    total_tests = 0
    suite = 0
    next_report = 50 * 1024 * 1024

    with out.open("w", encoding="ascii", newline="\n") as fd:
        header = '<?xml version="1.0" encoding="utf-8"?>\n<testsuites>\n'
        fd.write(header)
        written += len(header)

        while written < target:
            # Test indexes are global, not per-suite: a failure rate sparser
            # than the suite size (1 in 50k) would otherwise never fire, since
            # `i` would never reach it inside a single suite.
            first = suite * per_suite
            indexes = range(first, first + per_suite)
            cases = [make_testcase(suite, i, mode, failure_every, rng) for i in indexes]
            failures = sum(
                1
                for i in indexes
                if failure_every and i % failure_every == 0 and i % SKIP_EVERY != 0
            )
            skipped = sum(1 for i in indexes if i % SKIP_EVERY == 0)
            chunk = (
                f'  <testsuite name="module_{suite:05d}" tests="{per_suite}" '
                f'failures="{failures}" errors="0" skipped="{skipped}" '
                f'time="{rng.uniform(30, 400):.3f}" timestamp="{timestamp}" '
                f'hostname="runner-{suite % 32:02d}">\n'
                + "".join(cases)
                + "  </testsuite>\n"
            )
            fd.write(chunk)
            written += len(chunk)
            total_tests += per_suite
            suite += 1

            if written >= next_report:
                print(
                    f"  ... {human(written)} / {human(target)}"
                    f"  ({total_tests:,} tests)",
                    file=sys.stderr,
                    flush=True,
                )
                next_report += 50 * 1024 * 1024

        footer = "</testsuites>\n"
        fd.write(footer)
        written += len(footer)

    return written, total_tests


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=pathlib.Path, required=True)
    parser.add_argument(
        "--size", default="500MB", help="target size, e.g. 500MB, 512MiB, 1GB"
    )
    parser.add_argument("--mode", choices=("tests", "payload"), default="tests")
    parser.add_argument(
        "--failure-every",
        type=int,
        default=FAILURE_EVERY,
        help="one test in N fails; 0 makes every test pass (default: %(default)s)",
    )
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    target = parse_size(args.size)
    args.out.parent.mkdir(parents=True, exist_ok=True)

    started = time.monotonic()
    written, tests = generate(
        args.out, target, args.mode, args.failure_every, args.seed
    )
    elapsed = time.monotonic() - started

    print(
        f"generated {args.out} — {human(written)}, {tests:,} tests, "
        f"mode={args.mode}, in {elapsed:.1f}s",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
