#!/usr/bin/env python3
"""Verify the PNG commands of the `seg` command line tool.

The PNG commands are the only part of the tool that has no Java counterpart,
so they cannot be part of the byte exact comparison. They are checked here
against an **independent** decoder (Pillow), which is what makes the check
worth something: a PNG that the port writes and its own decoder reads again
would not prove that the file is a valid PNG.

Three things are checked:

  1. `seg to-png` writes a grayscale PNG whose samples are the samples of the
     input file,
  2. `seg results-png` writes one PNG per 8 bit result image of a run
     directory, with the same samples as the raw file,
  3. a PNG input produces the same result as the equivalent raw input (the
     RGB input is converted to grayscale with the ITU-R BT.601 weights, so the
     equivalent raw file is computed here with the same integer arithmetic).

Usage:
    python verify/run_png_verify.py [--backend native|js|wasm|wasm-gc]
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERIFY = os.path.join(ROOT, "verify")
HARNESS = os.path.join(ROOT, "ref", "harness")
IMAGE_DIR = os.path.join(VERIFY, "images")
OUT_DIR = os.path.join(VERIFY, "out", "png")

MOONRUN = os.path.join(os.path.expanduser("~"), ".moon", "bin", "moonrun.exe")
POLICY = os.path.join(VERIFY, "wasm_policy.json")

# the result images that `seg results-png` renders, with their channels
GRAY_RESULTS = [
    ("otsu_image", 0),
    ("mixture_image", 0),
    ("watershed", 0),
    ("retfm_gray", 0),
    ("retfm_otsu_image", 0),
    ("retfm_red_gray", 0),
    ("retfm_green_gray", 0),
    ("retfm_blue_gray", 0),
    ("retfm_rg_gray", 0),
    ("retfm_rb_gray", 0),
    ("retfm_gb_gray", 0),
    ("retfm_none_gray", 0),
    ("siox_mask", 0),
    ("rats_mask", 0),
    ("multiotsu_region0", 0),
    ("multiotsu_region1", 0),
    ("multiotsu_region2", 0),
    ("multiotsu_region3", 0),
]
RGB_RESULTS = [
    ("densitometry1.rgb", 1),
    ("densitometry3.rgb", 1),
    ("densitometry1_binary.rgb", 1),
    ("densitometry3_binary.rgb", 1),
    ("densitometry1_inverse.rgb", 1),
    ("densitometry3_inverse.rgb", 1),
    ("densitometry1_roi.rgb", 1),
    ("densitometry1_tol.rgb", 1),
    ("densitometry3_tol.rgb", 1),
]


def samples(image: Image.Image) -> list:
    """The samples of an image (Pillow renamed `getdata`)."""
    getter = getattr(image, "get_flattened_data", None)
    if getter is not None:
        return list(getter())
    return list(image.getdata())


def run(cmd: list[str]) -> tuple[int, str]:
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return result.returncode, result.stdout.decode("utf-8", "replace")


def runner_for(backend: str) -> list[str]:
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
    return [
        MOONRUN,
        "--policy",
        POLICY,
        os.path.join(
            ROOT, "_build", "wasm-gc", "debug", "build", "cmd", "seg", "seg.wasm"
        ),
    ]


def dimensions(name: str) -> tuple[int, int]:
    """The dimensions of a test image (from the generator table)."""
    sys.path.insert(0, VERIFY)
    import make_test_images  # noqa: E402

    width, height = make_test_images.IMAGES[name][0], make_test_images.IMAGES[name][1]
    return width, height


def check_to_png(runner: list[str], name: str, width: int, height: int) -> list[str]:
    """`seg to-png` has to write the samples of the input file."""
    problems = []
    source = os.path.join(IMAGE_DIR, f"{name}.gray")
    target = os.path.join(OUT_DIR, f"{name}.png")
    code, output = run(
        runner
        + [
            "to-png",
            "--input",
            source,
            "--width",
            str(width),
            "--height",
            str(height),
            "--out",
            target,
        ]
    )
    if code != 0:
        return [f"to-png failed: {output.strip()}"]
    with Image.open(target) as image:
        if image.mode != "L":
            problems.append(f"to-png wrote the mode {image.mode} instead of L")
        if image.size != (width, height):
            problems.append(
                f"to-png wrote the size {image.size} instead of {(width, height)}"
            )
        written = samples(image)
    with open(source, "rb") as fh:
        expected = list(fh.read())
    if written != expected:
        diff = sum(1 for a, b in zip(written, expected) if a != b)
        problems.append(f"to-png wrote {diff} different sample(s)")
    return problems


def check_results_png(
    runner: list[str], name: str, width: int, height: int
) -> list[str]:
    """`seg results-png` has to write one PNG per result image."""
    problems = []
    source = os.path.join(IMAGE_DIR, f"{name}.gray")
    run_dir = os.path.join(OUT_DIR, f"{name}-run")
    if os.path.isdir(run_dir):
        shutil.rmtree(run_dir)
    os.makedirs(run_dir, exist_ok=True)
    code, output = run(
        runner
        + [
            "run",
            "--input",
            source,
            "--width",
            str(width),
            "--height",
            str(height),
            "--outdir",
            run_dir,
        ]
    )
    if code != 0:
        return [f"run failed: {output.strip()}"]
    code, output = run(
        runner
        + [
            "results-png",
            "--dir",
            run_dir,
            "--width",
            str(width),
            "--height",
            str(height),
        ]
    )
    if code != 0:
        return [f"results-png failed: {output.strip()}"]

    for base, channels in GRAY_RESULTS + RGB_RESULTS:
        raw = os.path.join(run_dir, base + ".raw")
        png = os.path.join(run_dir, base + ".png")
        if not os.path.exists(raw):
            problems.append(f"results-png: the run wrote no {base}.raw")
            continue
        if not os.path.exists(png):
            problems.append(f"results-png wrote no {base}.png")
            continue
        with open(raw, "rb") as fh:
            expected = fh.read()
        with Image.open(png) as image:
            mode = "L" if channels == 0 else "RGB"
            if image.mode != mode:
                problems.append(
                    f"results-png wrote the mode {image.mode} instead of {mode} "
                    f"for {base}.png"
                )
            written = samples(image)
        if channels == 0:
            if bytes(written) != expected:
                problems.append(f"results-png: {base}.png holds different samples")
        else:
            flat = bytes(value for pixel in written for value in pixel)
            if flat != expected:
                problems.append(f"results-png: {base}.png holds different samples")
    return problems


def check_png_input(runner: list[str], name: str, width: int, height: int) -> list[str]:
    """A PNG input has to produce the same result as the raw input."""
    problems = []
    png = os.path.join(OUT_DIR, f"{name}-input.png")
    gray = os.path.join(OUT_DIR, f"{name}-input.gray")
    pixels = [
        ((x * 7 + y * 13) % 256, (x * 3 + y * 29) % 256, (x * 17 + y * 5) % 256)
        for y in range(height)
        for x in range(width)
    ]
    image = Image.new("RGB", (width, height))
    image.putdata(pixels)
    image.save(png)
    # the luma the CLI computes: (299r + 587g + 114b + 500) / 1000
    with open(gray, "wb") as fh:
        fh.write(bytes((299 * r + 587 * g + 114 * b + 500) // 1000 for r, g, b in pixels))

    png_dir = os.path.join(OUT_DIR, f"{name}-from-png")
    gray_dir = os.path.join(OUT_DIR, f"{name}-from-gray")
    for directory in (png_dir, gray_dir):
        if os.path.isdir(directory):
            shutil.rmtree(directory)
        os.makedirs(directory, exist_ok=True)
    code, output = run(
        runner
        + [
            "run",
            "--input",
            png,
            "--width",
            str(width),
            "--height",
            str(height),
            "--outdir",
            png_dir,
        ]
    )
    if code != 0:
        return [f"run with a PNG input failed: {output.strip()}"]
    code, output = run(
        runner
        + [
            "run",
            "--input",
            gray,
            "--width",
            str(width),
            "--height",
            str(height),
            "--outdir",
            gray_dir,
        ]
    )
    if code != 0:
        return [f"run with a raw input failed: {output.strip()}"]

    png_files = sorted(os.listdir(png_dir))
    gray_files = sorted(os.listdir(gray_dir))
    if png_files != gray_files:
        return [
            "the PNG input and the raw input produced different files: "
            f"{set(png_files) ^ set(gray_files)}"
        ]
    for base in png_files:
        with open(os.path.join(png_dir, base), "rb") as fh:
            a = fh.read()
        with open(os.path.join(gray_dir, base), "rb") as fh:
            b = fh.read()
        if a != b:
            problems.append(f"the PNG input and the raw input differ in {base}")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--backend",
        default="all",
        choices=["all", "native", "js", "wasm", "wasm-gc"],
    )
    args = parser.parse_args()
    backends = (
        ["native", "js", "wasm", "wasm-gc"]
        if args.backend == "all"
        else [args.backend]
    )

    images = sorted(
        name[:-5] for name in os.listdir(IMAGE_DIR) if name.endswith(".gray")
    )
    if not images:
        print("no test images; run make_test_images.py first")
        return 2

    if os.path.isdir(OUT_DIR):
        shutil.rmtree(OUT_DIR)
    os.makedirs(OUT_DIR, exist_ok=True)

    failed = []
    for backend in backends:
        print(f"== backend: {backend} ==")
        build = subprocess.run(
            ["moon", "build", "--target", backend],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        if build.returncode != 0:
            print(build.stdout.decode("utf-8", "replace"))
            return 1
        runner = runner_for(backend)
        for name in images:
            width, height = dimensions(name)
            problems = (
                check_to_png(runner, name, width, height)
                + check_results_png(runner, name, width, height)
                + check_png_input(runner, name, width, height)
            )
            if problems:
                failed.append(f"{backend}/{name}")
                print(f"  FAIL {name}")
                for line in problems:
                    print("      " + line)
            else:
                print(f"  PASS {name}")

    print()
    if failed:
        print("FAIL: the PNG commands differ on: " + ", ".join(failed))
        return 1
    print(
        f"ALL-PASS: the PNG commands are correct on all {len(images)} image(s) "
        f"({', '.join(backends)})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
