#!/usr/bin/env python3
"""Generate the ADVERSARIAL test images used to probe the port.

The seven images of `make_test_images.py` are the happy paths. These images
are the edge cases: they are built to reach the branches that the happy
paths never touch — degenerate sizes, single valued images, extreme
contrasts, saturated histograms, and the shapes that make the quadtree of
RATS_ and the connectivity of Blob_Labeler behave differently.

Every image is a plain 8-bit grayscale raster (row major, one byte per
pixel) so that the Java reference harness and the MoonBit CLI can read it
without any image codec in the way.

Usage:
    python verify/make_edge_images.py [outdir]
"""

from __future__ import annotations

import os
import sys


def one_pixel(w: int, h: int) -> bytes:
    """A single pixel image (the smallest possible one)."""
    return bytes([128]) * (w * h)


def one_row(w: int, h: int) -> bytes:
    """A single row: the height is 1, so every column is an edge column."""
    px = bytearray(w * h)
    for x in range(w):
        px[x] = (x * 255) // max(w - 1, 1)
    return bytes(px)


def one_column(w: int, h: int) -> bytes:
    """A single column: the width is 1."""
    px = bytearray(w * h)
    for y in range(h):
        px[y] = (y * 255) // max(h - 1, 1)
    return bytes(px)


def all_black(w: int, h: int) -> bytes:
    """Every pixel is 0: the histogram has a single bin at 0."""
    return bytes([0]) * (w * h)


def all_white(w: int, h: int) -> bytes:
    """Every pixel is 255: the histogram has a single bin at 255."""
    return bytes([255]) * (w * h)


def two_levels(w: int, h: int) -> bytes:
    """Exactly two grey levels (0 and 255): every threshold method has to
    decide between two candidates."""
    px = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            px[y * w + x] = 255 if x >= w // 2 else 0
    return bytes(px)


def one_hot_pixel(w: int, h: int) -> bytes:
    """One bright pixel in a dark image (the smallest possible foreground)."""
    px = bytearray([0]) * (w * h)
    px[(h // 2) * w + (w // 2)] = 255
    return bytes(px)


def inverted(w: int, h: int) -> bytes:
    """A bright background with dark blobs (the polarity of the two blobs
    image, reversed)."""
    px = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            v = 220
            if (x - 8) ** 2 + (y - 8) ** 2 <= 25:
                v = 10
            px[y * w + x] = v
    return bytes(px)


def saturating_gradient(w: int, h: int) -> bytes:
    """A gradient that saturates at both ends of the 8 bit range, so that
    the histogram has holes in the middle and the outliers dominate."""
    px = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            v = (x * 300) // max(w - 1, 1) - 30
            if v < 0:
                v = 0
            if v > 255:
                v = 255
            px[y * w + x] = v
    return bytes(px)


def checker_1px(w: int, h: int) -> bytes:
    """A checkerboard with a one pixel period: the most fragmented image
    possible, every pixel is isolated."""
    px = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            px[y * w + x] = 255 if (x + y) % 2 == 0 else 0
    return bytes(px)


def near_square(w: int, h: int) -> bytes:
    """A square image (the RATS quadtree does not transpose its sum) next
    to a very non square one."""
    px = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            v = 40 + ((x * 7 + y * 13) % 180)
            if (x - w // 3) ** 2 + (y - h // 3) ** 2 <= 16:
                v = 250
            px[y * w + x] = v
    return bytes(px)


def thin_line(w: int, h: int) -> bytes:
    """A one pixel wide vertical line (tests the 4 connectivity against the
    8 connectivity)."""
    px = bytearray([30]) * (w * h)
    for y in range(h):
        px[y * w + (w // 2)] = 230
    return bytes(px)


def diagonal_line(w: int, h: int) -> bytes:
    """A one pixel wide diagonal line: the 4 connected labeling splits it
    into many labels, the 8 connected labeling does not."""
    px = bytearray([30]) * (w * h)
    for y in range(h):
        px[y * w + (y * (w - 1)) // max(h - 1, 1)] = 230
    return bytes(px)


def noise(w: int, h: int) -> bytes:
    """Deterministic pseudo random noise (a fixed LCG, no randomness)."""
    px = bytearray(w * h)
    state = 12345
    for i in range(w * h):
        state = (1103515245 * state + 12345) & 0x7FFFFFFF
        px[i] = (state >> 16) & 0xFF
    return bytes(px)


def big_blob(w: int, h: int) -> bytes:
    """A blob that touches all four edges (the flood fill / watershed
    boundary handling)."""
    px = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            edge = x < 3 or y < 3 or x >= w - 3 or y >= h - 3
            px[y * w + x] = 220 if edge else 20
    return bytes(px)


def tall(w: int, h: int) -> bytes:
    """A tall image (the height is larger than the width).

    The RATS quadtree reads its (transposed) gradient image with the flat
    index `y * height + x`, so it leaves the image as soon as the image is
    taller than it is wide. The Java original then raises an
    `ArrayIndexOutOfBoundsException` and the reference harness reports an
    empty mask - the port has to do the same.
    """
    px = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            px[y * w + x] = 30 + ((x * 5 + y * 3) % 190)
    return bytes(px)


def siox_exception(w: int, h: int) -> bytes:
    """Only a known background and unknown pixels, but no known foreground.

    The confidence matrix of the harness is derived from the grey level: a
    level of at most 63 is a known background, a level of at least 192 a known
    foreground and everything in between is unknown. With a background and
    unknown pixels but without a foreground the SIOX segmentator raises an
    `IllegalStateException` ("foreground signature does not exist") - the only
    way to reach that branch.
    """
    px = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            px[y * w + x] = 0 if (x + y) % 3 == 0 else 100
    return bytes(px)


def large_mixed(w: int, h: int) -> bytes:
    """A large image whose bin counts overflow the 32 bit accumulators.

    `AutoThresholder` computes `x += i * i * y[i]` with a Java `int` product:
    a bin that holds more than a few ten thousand pixels at a high grey level
    makes that product overflow. The overflow wraps silently in Java and it
    has to wrap silently in MoonBit as well, so the two sides only agree if
    the arithmetic of `Int` behaves like the arithmetic of a Java `int`.
    """
    px = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            v = 40 + (x * 215) // max(w - 1, 1)
            if y < h // 3:
                v = 200
            px[y * w + x] = v
    return bytes(px)


IMAGES = {
    "edge_one_pixel": (1, 1, one_pixel),
    "edge_one_row": (16, 1, one_row),
    "edge_one_column": (1, 16, one_column),
    "edge_all_black": (12, 10, all_black),
    "edge_all_white": (12, 10, all_white),
    "edge_two_levels": (16, 12, two_levels),
    "edge_one_hot": (14, 14, one_hot_pixel),
    "edge_inverted": (24, 20, inverted),
    "edge_saturating": (32, 8, saturating_gradient),
    "edge_checker_1px": (16, 16, checker_1px),
    "edge_near_square": (21, 21, near_square),
    "edge_thin_line": (20, 20, thin_line),
    "edge_diagonal": (16, 16, diagonal_line),
    "edge_noise": (20, 15, noise),
    "edge_big_blob": (18, 18, big_blob),
    "edge_tall": (12, 30, tall),
    "edge_siox_exception": (16, 12, siox_exception),
    "edge_large_mixed": (600, 600, large_mixed),
}


def main() -> int:
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "edge_images"
    )
    os.makedirs(outdir, exist_ok=True)
    for name, (w, h, fn) in IMAGES.items():
        path = os.path.join(outdir, f"{name}.gray")
        with open(path, "wb") as fh:
            fh.write(fn(w, h))
        print(f"{name}: {w}x{h} -> {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
