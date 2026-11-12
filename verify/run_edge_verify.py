#!/usr/bin/env python3
"""Compare the Java reference with the MoonBit port on the EDGE images.

This is the adversarial half of the verification: the seven happy path
images of `make_test_images.py` never reach the degenerate branches of the
algorithms, the edge case images of `make_edge_images.py` do.

Both sides are run on every image and the outputs are compared with
`compare.py` (the whole output set). With `--per-algorithm` every algorithm is
additionally run **on its own** and compared with `compare.py --algo <name>`,
so a degenerate branch cannot hide behind a crash of a neighbouring algorithm.

The output directories are emptied before every backend: a file that is left
over from an earlier run would hide the fact that the current run does not
write it.

Usage:
    python verify/run_edge_verify.py [--backend native|js|wasm|wasm-gc|all]
                                     [--per-algorithm]
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERIFY = os.path.join(ROOT, "verify")
HARNESS = os.path.join(ROOT, "ref", "harness")
IMAGE_DIR = os.path.join(VERIFY, "edge_images")
OUT_DIR = os.path.join(VERIFY, "out", "edge")

MOONRUN = os.path.join(os.path.expanduser("~"), ".moon", "bin", "moonrun.exe")
POLICY = os.path.join(VERIFY, "wasm_policy.json")

ALGORITHMS = [
    "otsu",
    "multiotsu",
    "autothreshold",
    "mixture",
    "blob",
    "watershed",
    "densitometry",
    "retfm",
    "rats",
    "siox",
    "multithresholder",
]


def run(cmd: list[str], cwd: str | None = None) -> int:
    return subprocess.run(
        cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    ).returncode


def build_harness() -> bool:
    """Compile the Java reference harness (it may be out of date)."""
    print("== building the Java reference harness ==")
    result = subprocess.run(
        [
            "powershell",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            os.path.join(HARNESS, "build.ps1"),
        ],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if result.returncode != 0:
        print(result.stdout.decode("utf-8", "replace"))
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--backend",
        default="all",
        choices=["all", "native", "js", "wasm", "wasm-gc"],
    )
    parser.add_argument(
        "--per-algorithm",
        action="store_true",
        help="also run every algorithm on its own and compare it in isolation",
    )
    args = parser.parse_args()
    backends = (
        ["native", "js", "wasm", "wasm-gc"]
        if args.backend == "all"
        else [args.backend]
    )

    images = sorted(
        f for f in os.listdir(IMAGE_DIR) if f.endswith(".gray")
    )
    if not images:
        print("no edge images; run make_edge_images.py first")
        return 2

    # The dimensions are taken from the generator table.
    sys.path.insert(0, VERIFY)
    import make_edge_images  # noqa: E402

    table = make_edge_images.IMAGES

    if not build_harness():
        print("FAIL: the Java reference harness could not be built")
        return 1

    failed_backends = []
    for backend in backends:
        if not run_backend(backend, images, table, args.per_algorithm):
            failed_backends.append(backend)

    print()
    if failed_backends:
        print(
            "FAIL: the port differs on the edge images of: "
            + ", ".join(failed_backends)
        )
        return 1
    print(
        f"ALL-PASS: the port matches the Java reference on all {len(images)} edge image(s)"
        f" ({', '.join(backends)})"
    )
    return 0


def runner_for(backend: str) -> list[str] | None:
    if backend == "native":
        return [
            os.path.join(
                ROOT, "_build", "native", "debug", "build", "cmd", "seg", "seg.exe"
            )
        ]
    if backend == "js":
        return [
            "node",
            os.path.join(
                ROOT, "_build", "js", "debug", "build", "cmd", "seg", "seg.js"
            ),
        ]
    if backend == "wasm":
        return [
            MOONRUN,
            "--policy",
            POLICY,
            os.path.join(
                ROOT, "_build", "wasm", "debug", "build", "cmd", "seg", "seg.wasm"
            ),
        ]
    if backend == "wasm-gc":
        return [
            MOONRUN,
            "--policy",
            POLICY,
            os.path.join(
                ROOT, "_build", "wasm-gc", "debug", "build", "cmd", "seg", "seg.wasm"
            ),
        ]
    return None


def compare(java_out: str, mbt_out: str, algo: str | None = None) -> tuple[bool, str]:
    cmd = ["python", os.path.join(VERIFY, "compare.py")]
    if algo is not None:
        cmd += ["--algo", algo]
    cmd += [java_out, mbt_out]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return result.returncode == 0, result.stdout.decode("utf-8", "replace")


def run_backend(
    backend: str, images: list[str], table: dict, per_algorithm: bool
) -> bool:
    print()
    print(f"== backend: {backend} ==")
    build = subprocess.run(
        ["moon", "build", "--target", backend],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if build.returncode != 0:
        print(build.stdout.decode("utf-8", "replace"))
        return False

    runner = runner_for(backend)
    if runner is None:
        print(f"unknown backend: {backend}")
        return False

    # The output tree of this backend is emptied first: a leftover of an
    # earlier run would hide the fact that the current run does not write it.
    backend_out = os.path.join(OUT_DIR, backend)
    if os.path.isdir(backend_out):
        shutil.rmtree(backend_out)

    ok = True
    for image in images:
        name = image[: -len(".gray")]
        w, h = table[name][0], table[name][1]
        gray = os.path.join(IMAGE_DIR, image)
        java_out = os.path.join(backend_out, "java", name)
        mbt_out = os.path.join(backend_out, "moonbit", name)
        os.makedirs(java_out, exist_ok=True)
        os.makedirs(mbt_out, exist_ok=True)

        rc = run(
            ["java", "-cp", "out", "Harness", gray, str(w), str(h), java_out],
            cwd=HARNESS,
        )
        if rc != 0:
            ok = False
            print(f"  FAIL {name}: the Java harness failed (exit {rc})")
            continue

        rc = run(
            runner
            + [
                "run",
                "--input",
                gray,
                "--width",
                str(w),
                "--height",
                str(h),
                "--outdir",
                mbt_out,
            ]
        )
        if rc != 0:
            ok = False
            print(f"  FAIL {name}: the MoonBit CLI failed (exit {rc})")
            continue

        passed, detail = compare(java_out, mbt_out)
        if not passed:
            ok = False
            print(f"  FAIL {name}: the output differs")
            for line in detail.splitlines():
                print("      " + line)
            continue

        if per_algorithm:
            algorithm_failed = []
            for algorithm in ALGORITHMS:
                algo_out = os.path.join(backend_out, "algo", algorithm, name)
                if os.path.isdir(algo_out):
                    shutil.rmtree(algo_out)
                os.makedirs(algo_out, exist_ok=True)
                rc = run(
                    runner
                    + [
                        algorithm,
                        "--input",
                        gray,
                        "--width",
                        str(w),
                        "--height",
                        str(h),
                        "--outdir",
                        algo_out,
                    ]
                )
                if rc != 0:
                    algorithm_failed.append(f"{algorithm} (the command failed)")
                    continue
                passed, detail = compare(java_out, algo_out, algorithm)
                if not passed:
                    algorithm_failed.append(algorithm)
                    for line in detail.splitlines():
                        print(f"      {algorithm}: {line}")
            if algorithm_failed:
                ok = False
                print(
                    f"  FAIL {name}: the isolated algorithms differ: "
                    + ", ".join(algorithm_failed)
                )
                continue

        print(f"  PASS {name}")
    return ok


if __name__ == "__main__":
    raise SystemExit(main())
