#!/usr/bin/env python3
"""Measure the runtime of the port and compare it with the Java reference.

The byte exact comparison says nothing about the runtime, so the port could
get ten times slower without any gate noticing. This script measures the
complete `seg run` (every algorithm) on a deterministic noise image and
compares it with the Java reference **running on the same machine, in the
same run**.

That ratio is the budget: the port must not be more than
``BUDGET_FACTOR`` times slower than the reference. A ratio is used instead of
an absolute time on purpose - an absolute baseline recorded on one machine
means nothing on another one, and a gate that fails on a fast machine is
worse than no gate at all.

The absolute numbers are recorded in `verify/perf_baseline.json` as well, so
that a change of the order of magnitude is visible in the history. They are
reported, not enforced.

Usage:
    python verify/run_bench.py [--size 1024] [--repeat 3] [--update-baseline]
                              [--budget-factor 2.0]
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERIFY = os.path.join(ROOT, "verify")
HARNESS = os.path.join(ROOT, "ref", "harness")
OUT_DIR = os.path.join(VERIFY, "out", "bench")
BASELINE = os.path.join(VERIFY, "perf_baseline.json")

# the port may be at most this factor slower than the Java reference
BUDGET_FACTOR = 2.0


def make_noise(path: str, size: int) -> None:
    """A deterministic noise image (a fixed LCG, no randomness)."""
    state = 12345
    data = bytearray(size * size)
    for i in range(size * size):
        state = (1103515245 * state + 12345) & 0x7FFFFFFF
        data[i] = (state >> 16) & 0xFF
    with open(path, "wb") as fh:
        fh.write(bytes(data))


def time_runs(command: list[str], cwd: str | None, repeat: int) -> list[float]:
    """The runtime of the command in seconds (the best of `repeat` runs)."""
    times = []
    for _ in range(repeat):
        start = time.perf_counter()
        result = subprocess.run(
            command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        )
        elapsed = time.perf_counter() - start
        if result.returncode != 0:
            raise SystemExit(
                "the command failed: "
                + result.stdout.decode("utf-8", "replace")[-2000:]
            )
        times.append(elapsed)
    return times


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--repeat", type=int, default=3)
    parser.add_argument("--update-baseline", action="store_true")
    # The budget is a parameter so that the *failure* branch of the gate can be
    # tested as well: `--budget-factor 0.5` demands the port to be faster than
    # the reference and has to fail. A gate whose failure path was never run is
    # a gate that has never been shown to work.
    parser.add_argument("--budget-factor", type=float, default=BUDGET_FACTOR)
    args = parser.parse_args()
    if args.budget_factor <= 0:
        print("--budget-factor has to be positive")
        return 2
    budget = args.budget_factor

    os.makedirs(OUT_DIR, exist_ok=True)
    image = os.path.join(OUT_DIR, f"noise_{args.size}.gray")
    make_noise(image, args.size)

    print(f"== building the release build of the CLI ==")
    build = subprocess.run(
        ["moon", "build", "--target", "native", "--release"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if build.returncode != 0:
        print(build.stdout.decode("utf-8", "replace"))
        return 1
    exe = os.path.join(ROOT, "_build", "native", "release", "build", "cmd", "seg", "seg.exe")

    out_dir = os.path.join(OUT_DIR, "run")
    os.makedirs(out_dir, exist_ok=True)
    print(f"== the MoonBit port ({args.size}x{args.size}, {args.repeat} runs) ==")
    moonbit = time_runs(
        [
            exe,
            "run",
            "--input",
            image,
            "--width",
            str(args.size),
            "--height",
            str(args.size),
            "--outdir",
            out_dir,
        ],
        None,
        args.repeat,
    )

    java_out = os.path.join(OUT_DIR, "java")
    os.makedirs(java_out, exist_ok=True)
    print(f"== the Java reference ({args.size}x{args.size}, {args.repeat} runs) ==")
    java = time_runs(
        ["java", "-cp", "out", "Harness", image, str(args.size), str(args.size), java_out],
        HARNESS,
        args.repeat,
    )

    moonbit_best = min(moonbit)
    java_best = min(java)
    print()
    print(f"  the MoonBit port : {moonbit_best:.3f} s  (runs: {', '.join(f'{t:.3f}' for t in moonbit)})")
    print(f"  the Java reference: {java_best:.3f} s  (runs: {', '.join(f'{t:.3f}' for t in java)})")
    print(f"  the port is {java_best / moonbit_best:.2f} times the speed of the reference")

    measured = {
        "size": args.size,
        "moonbit_seconds": round(moonbit_best, 4),
        "java_seconds": round(java_best, 4),
        "ratio": round(java_best / moonbit_best, 3),
    }

    if args.update_baseline:
        with open(BASELINE, "w", encoding="utf-8") as fh:
            json.dump(measured, fh, indent=2)
            fh.write("\n")
        print()
        print(f"the baseline in {BASELINE} has been updated")
        return 0

    if os.path.exists(BASELINE):
        with open(BASELINE, "r", encoding="utf-8") as fh:
            baseline = json.load(fh)
        if baseline.get("size") == args.size:
            print(
                f"  the recorded baseline: {baseline['moonbit_seconds']:.3f} s "
                f"(the reference {baseline['java_seconds']:.3f} s, "
                f"the ratio {baseline.get('ratio', '?')})"
            )
        else:
            print(
                f"  the recorded baseline was measured with {baseline.get('size')} "
                f"x{baseline.get('size')} pixels"
            )

    print()
    ratio = java_best / moonbit_best
    limit = 1.0 / budget
    print(
        f"  the budget: the port may be at most {budget} times slower "
        f"than the reference (the ratio has to be at least {limit:.2f})"
    )
    if ratio < limit:
        print(
            f"FAIL: the port is {1.0 / ratio:.2f} times slower than the reference, "
            f"that is more than the {budget} times of the budget"
        )
        return 1
    print(f"ALL-PASS: the port is within the performance budget ({ratio:.2f})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
