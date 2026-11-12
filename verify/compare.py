#!/usr/bin/env python3
"""Compare the Java reference outputs with the MoonBit port outputs.

Both sides write the same file layout:

    scalars.txt              one "key value" line per scalar
    otsu_image.raw           binary image of the Otsu plugin
    multiotsu_region0..3.raw the four multi level Otsu regions
    mixture_image.raw        binary image of the mixture model plugin
    blob4_map.raw            4-connected label map (little endian int16)
    blob8_map.raw            8-connected label map (little endian int16)
    blob4_noedge_map.raw     the same without the edge correction
    blob8_noedge_map.raw
    blob4_bgcol_map.raw      the same with a background colour of 1
    blob8_bgcol_map.raw
    watershed.raw            binary image of the watershed plugin
    densitometry1.rgb.raw    RGB output of the 1-channel densitometry
    densitometry3.rgb.raw    RGB output of the 3-channel densitometry
    densitometry1_binary.rgb.raw    the same, binarised
    densitometry3_binary.rgb.raw
    densitometry1_inverse.rgb.raw   the same, inverted
    densitometry3_inverse.rgb.raw
    densitometry1_roi.rgb.raw       the same, on a region of interest
    retfm_gray.raw           grayscale conversion of RetFM_J (all channels)
    retfm_otsu_image.raw     thresholded + inverted RetFM_J image
    retfm_red_gray.raw       the same conversion for every other selection of
    retfm_green_gray.raw     the channels (a single channel, two channels and
    retfm_blue_gray.raw      no channel at all)
    retfm_rg_gray.raw
    retfm_rb_gray.raw
    retfm_gb_gray.raw
    retfm_none_gray.raw
    rats_mask.raw            8 bit mask of RATS_ (swapped dimensions)
    siox_cm.raw              float32 confidence matrix of SIOX (little endian)
    siox_mask.raw            8 bit mask of SIOX
    multithresholder.txt     level mapping helpers of Multi_Thresholder

Binary files are compared byte for byte. Scalars are compared numerically:

  * integers (and the IEEE-754 bit patterns under a ``*.bits.*`` key) are
    compared **exactly**,
  * the remaining floating point scalars are compared with a relative
    tolerance of 1e-6, because Java prints a ``float`` with a different
    number of digits than MoonBit.

The bit pattern scalars are the only *exact* floating point evidence of the
suite, so they must never be compared with a tolerance: a tolerance of 1e-6
on a bit pattern around 1.1e9 would allow roughly a thousand units in the
last place of the float.

With ``--algo <name>`` only the files and the scalars of that single algorithm
are compared; the MoonBit side then holds the output of one algorithm only.
In that mode the set of scalar keys of the MoonBit side has to be exactly the
expected set of the algorithm — a dropped or renamed scalar is a failure.

Usage:
    python verify/compare.py [--algo <name>] <java_dir> <moonbit_dir>
"""

from __future__ import annotations

import argparse
import math
import os
import re
import sys

FLOAT_TOL = 1e-6

# A key of the form "<something>.bits.<name>" holds the raw IEEE-754 bit
# pattern of a 32 bit float. It is compared as an exact integer.
BIT_KEY = re.compile(r"\.bits\.")

BINARY_FILES = [
    "otsu_image.raw",
    "multiotsu_region0.raw",
    "multiotsu_region1.raw",
    "multiotsu_region2.raw",
    "multiotsu_region3.raw",
    "mixture_image.raw",
    "blob4_map.raw",
    "blob8_map.raw",
    "blob4_noedge_map.raw",
    "blob8_noedge_map.raw",
    "blob4_bgcol_map.raw",
    "blob8_bgcol_map.raw",
    "watershed.raw",
    "densitometry1.rgb.raw",
    "densitometry3.rgb.raw",
    "densitometry1_binary.rgb.raw",
    "densitometry3_binary.rgb.raw",
    "densitometry1_inverse.rgb.raw",
    "densitometry3_inverse.rgb.raw",
    "densitometry1_roi.rgb.raw",
    "densitometry1_tol.rgb.raw",
    "densitometry3_tol.rgb.raw",
    "retfm_gray.raw",
    "retfm_otsu_image.raw",
    "retfm_red_gray.raw",
    "retfm_green_gray.raw",
    "retfm_blue_gray.raw",
    "retfm_rg_gray.raw",
    "retfm_rb_gray.raw",
    "retfm_gb_gray.raw",
    "retfm_none_gray.raw",
    "rats_mask.raw",
    "siox_cm.raw",
    "siox_mask.raw",
    "multithresholder.txt",
]

# The algorithms, with the files they write and the exact list of the scalars
# they report. The scalar list is the contract of the algorithm: in the
# `--algo` mode the MoonBit side has to produce exactly these keys.
ALGORITHMS = {
    "otsu": (["otsu_image.raw"], ["otsu.threshold"]),
    "multiotsu": (
        [
            "multiotsu_region0.raw",
            "multiotsu_region1.raw",
            "multiotsu_region2.raw",
            "multiotsu_region3.raw",
        ],
        [
            "multiotsu.level",
            "multiotsu.t1",
            "multiotsu.t2",
            "multiotsu.t3",
            "multiotsu.t4",
            "multiotsu.level2.t1",
            "multiotsu.level2.t2",
            "multiotsu.level3.t1",
            "multiotsu.level3.t2",
            "multiotsu.level3.t3",
            "multiotsu.level5.t1",
            "multiotsu.level5.t2",
            "multiotsu.level5.t3",
            "multiotsu.level5.t4",
            "multiotsu.level5.t5",
        ],
    ),
    "autothreshold": (
        [],
        [
            "autothreshold.Huang",
            "autothreshold.Intermodes",
            "autothreshold.IsoData",
            "autothreshold.Li",
            "autothreshold.MaxEntropy",
            "autothreshold.Mean",
            "autothreshold.MinError(I)",
            "autothreshold.Minimum",
            "autothreshold.Moments",
            "autothreshold.Otsu",
            "autothreshold.Percentile",
            "autothreshold.RenyiEntropy",
            "autothreshold.Shanbhag",
            "autothreshold.Triangle",
            "autothreshold.Yen",
        ],
    ),
    "mixture": (
        ["mixture_image.raw"],
        [
            "mixture.threshold",
            "mixture.mu1",
            "mixture.variance1",
            "mixture.mu2",
            "mixture.variance2",
            "mixture.errorMin",
            "mixture.diffMu",
            "mixture.directThreshold",
            "mixture.realThreshold",
            "mixture.bits.mu1",
            "mixture.bits.variance1",
            "mixture.bits.mu2",
            "mixture.bits.variance2",
            "mixture.bits.errorMin",
            "mixture.bits.diffMu",
            "mixture.bits.realThreshold",
        ],
    ),
    "blob": (
        [
            "blob4_map.raw",
            "blob8_map.raw",
            "blob4_noedge_map.raw",
            "blob8_noedge_map.raw",
            "blob4_bgcol_map.raw",
            "blob8_bgcol_map.raw",
        ],
        [
            "blob4.numberOfLabels",
            "blob4.failed",
            "blob8.numberOfLabels",
            "blob8.failed",
            "blob4.noedge.numberOfLabels",
            "blob4.noedge.failed",
            "blob8.noedge.numberOfLabels",
            "blob8.noedge.failed",
            "blob4.bgcol.numberOfLabels",
            "blob4.bgcol.failed",
            "blob8.bgcol.numberOfLabels",
            "blob8.bgcol.failed",
        ],
    ),
    "watershed": (["watershed.raw"], []),
    "densitometry": (
        [
            "densitometry1.rgb.raw",
            "densitometry3.rgb.raw",
            "densitometry1_binary.rgb.raw",
            "densitometry3_binary.rgb.raw",
            "densitometry1_inverse.rgb.raw",
            "densitometry3_inverse.rgb.raw",
            "densitometry1_roi.rgb.raw",
            "densitometry1_tol.rgb.raw",
            "densitometry3_tol.rgb.raw",
        ],
        [],
    ),
    "retfm": (
        [
            "retfm_gray.raw",
            "retfm_otsu_image.raw",
            "retfm_red_gray.raw",
            "retfm_green_gray.raw",
            "retfm_blue_gray.raw",
            "retfm_rg_gray.raw",
            "retfm_rb_gray.raw",
            "retfm_gb_gray.raw",
            "retfm_none_gray.raw",
        ],
        [
            "retfm.otsuThreshold",
            "retfm.red.otsuThreshold",
            "retfm.green.otsuThreshold",
            "retfm.blue.otsuThreshold",
            "retfm.rg.otsuThreshold",
            "retfm.rb.otsuThreshold",
            "retfm.gb.otsuThreshold",
            "retfm.none.otsuThreshold",
        ],
    ),
    "rats": (
        ["rats_mask.raw"],
        ["rats.mask.width", "rats.mask.height", "rats.failed"],
    ),
    "siox": (
        ["siox_cm.raw", "siox_mask.raw"],
        ["siox.success", "siox.failed"],
    ),
    "multithresholder": (["multithresholder.txt"], []),
}


class ScalarFileError(Exception):
    """The scalars.txt of a side is malformed."""


def read_scalars(path: str) -> dict:
    """Read a scalars.txt into a dictionary.

    A line without a space and a duplicated key are errors: both would make
    the comparison ambiguous (two lines with the same key would silently
    overwrite each other).
    """
    out: dict[str, str] = {}
    if not os.path.exists(path):
        raise ScalarFileError(f"{path} does not exist")
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for number, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            if " " not in line:
                raise ScalarFileError(
                    f"{path}:{number}: no space between the key and the value: {line!r}"
                )
            key, value = line.split(" ", 1)
            if key in out:
                raise ScalarFileError(f"{path}:{number}: duplicated key: {key}")
            out[key] = value.strip()
    return out


def same_bits(a: str, b: str) -> bool:
    """Compare two IEEE-754 bit patterns exactly."""
    try:
        return int(a) == int(b)
    except ValueError:
        return False


def same_scalar(key: str, a: str, b: str) -> bool:
    """Compare two scalar values.

    The bit patterns are compared exactly, integers exactly, and the printed
    floats with a relative tolerance.
    """
    if BIT_KEY.search(key):
        return same_bits(a, b)
    if a == b:
        return True
    try:
        ia = int(a)
        ib = int(b)
    except ValueError:
        pass
    else:
        return ia == ib
    try:
        fa = float(a)
        fb = float(b)
    except ValueError:
        return False
    if math.isnan(fa) and math.isnan(fb):
        return True
    if fa == fb:
        return True
    scale = max(abs(fa), abs(fb), 1.0)
    return abs(fa - fb) <= FLOAT_TOL * scale


def compare_scalars(
    java_scalars: dict,
    mbt_scalars: dict,
    keys: list[str],
    failures: list,
) -> None:
    """Compare the given scalar keys of the two sides."""
    for key in keys:
        if key not in java_scalars:
            failures.append(f"scalar {key}: missing in Java output")
            continue
        if key not in mbt_scalars:
            failures.append(f"scalar {key}: missing in MoonBit output")
            continue
        if not same_scalar(key, java_scalars[key], mbt_scalars[key]):
            failures.append(
                f"scalar {key}: java={java_scalars[key]} moonbit={mbt_scalars[key]}"
            )


def compare_files(java_dir: str, mbt_dir: str, files: list[str], failures: list) -> None:
    for name in files:
        jpath = os.path.join(java_dir, name)
        mpath = os.path.join(mbt_dir, name)
        if not os.path.exists(jpath):
            failures.append(f"file {name}: missing in Java output")
            continue
        if not os.path.exists(mpath):
            failures.append(f"file {name}: missing in MoonBit output")
            continue
        with open(jpath, "rb") as fh:
            jdata = fh.read()
        with open(mpath, "rb") as fh:
            mdata = fh.read()
        if jdata != mdata:
            diff = [i for i in range(min(len(jdata), len(mdata))) if jdata[i] != mdata[i]]
            head = diff[0] if diff else min(len(jdata), len(mdata))
            failures.append(
                f"file {name}: {len(diff)} differing byte(s) "
                f"(len java={len(jdata)} moonbit={len(mdata)}), first at {head}"
            )


def check_file_set(directory: str, expected: set[str], side: str, failures: list) -> None:
    """Every file of the directory has to be an expected one."""
    for name in sorted(os.listdir(directory)):
        if name not in expected:
            failures.append(f"file {name}: unexpected file in the {side} output")


def compare_dir(java_dir: str, mbt_dir: str, algo: str | None = None) -> list:
    failures = []

    if algo is None:
        files = BINARY_FILES
        keys = None
    else:
        files, algo_keys = ALGORITHMS[algo]
        keys = algo_keys

    try:
        java_scalars = read_scalars(os.path.join(java_dir, "scalars.txt"))
    except ScalarFileError as error:
        failures.append(f"scalars.txt: {error}")
        java_scalars = {}
    try:
        mbt_scalars = read_scalars(os.path.join(mbt_dir, "scalars.txt"))
    except ScalarFileError as error:
        failures.append(f"scalars.txt: {error}")
        mbt_scalars = {}

    if keys is None:
        # The whole run: both sides have to report exactly the same keys.
        for key in sorted(set(java_scalars) | set(mbt_scalars)):
            compare_scalars(java_scalars, mbt_scalars, [key], failures)
    else:
        # A single algorithm: the MoonBit side has to report exactly the keys
        # of that algorithm — a dropped or renamed scalar is a failure.
        compare_scalars(java_scalars, mbt_scalars, keys, failures)
        for key in sorted(mbt_scalars):
            if key not in keys:
                failures.append(
                    f"scalar {key}: unexpected scalar in the MoonBit output"
                )

    compare_files(java_dir, mbt_dir, files, failures)

    # A file that a side does not write at all must not hide behind a leftover
    # of an earlier run, so the sets are compared too.
    expected_mbt = set(files) | {"scalars.txt"}
    check_file_set(mbt_dir, expected_mbt, "MoonBit", failures)
    if keys is None:
        # The whole run: the Java side has to hold the same complete set.
        expected_java = set(BINARY_FILES) | {"scalars.txt"}
        check_file_set(java_dir, expected_java, "Java", failures)

    return failures


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--algo", choices=sorted(ALGORITHMS.keys()))
    parser.add_argument("java_dir")
    parser.add_argument("moonbit_dir")
    args = parser.parse_args()

    failures = compare_dir(args.java_dir, args.moonbit_dir, args.algo)
    if failures:
        print("FAIL")
        for line in failures:
            print(f"  - {line}")
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
