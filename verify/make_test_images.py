#!/usr/bin/env python3
"""Generate the deterministic test images used to verify the MoonBit port.

The images are plain 8-bit grayscale rasters (row major, one byte per pixel)
so that both the Java reference harness and the MoonBit CLI can read them
without any image codec in the way.

Usage:
    python verify/make_test_images.py [outdir]
"""

from __future__ import annotations

import os
import sys


def ramp_blobs(w: int, h: int) -> bytes:
    """Grey ramp in the first two rows plus three rectangular blobs."""
    px = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            v = 0
            if y < 2:
                v = 4 + 4 * x
            if 4 <= x < 12 and 3 <= y < 11:
                v = 200
            if 18 <= x < 27 and 12 <= y < 21:
                v = 120
            if 2 <= x < 5 and 18 <= y < 21:
                v = 90
            px[y * w + x] = v
    return bytes(px)


def two_blobs(w: int, h: int) -> bytes:
    """Two round-ish blobs on a dark background."""
    px = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            v = 10
            if (x - 8) ** 2 + (y - 8) ** 2 <= 25:
                v = 220
            if (x - 20) ** 2 + (y - 15) ** 2 <= 16:
                v = 180
            px[y * w + x] = v
    return bytes(px)


def diagonal_gradient(w: int, h: int) -> bytes:
    """Smooth diagonal gradient (no flat background)."""
    px = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            px[y * w + x] = (x * 3 + y * 5) % 256
    return bytes(px)


def checkerboard(w: int, h: int) -> bytes:
    """Hard 4x4 checkerboard (degenerate for the smoothing based methods)."""
    px = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            px[y * w + x] = 0 if ((x // 4) + (y // 4)) % 2 == 0 else 255
    return bytes(px)


def uniform(w: int, h: int) -> bytes:
    """Constant image (all histograms are single bin)."""
    return bytes([77]) * (w * h)


def sparse(w: int, h: int) -> bytes:
    """Mostly background with a handful of isolated bright pixels."""
    px = bytearray(w * h)
    for i, (x, y) in enumerate([(1, 1), (5, 3), (9, 9), (14, 2), (20, 7)]):
        px[y * w + x] = 250 - 10 * i
    return bytes(px)


def ring(w: int, h: int) -> bytes:
    """A hollow ring (tests watershed lines and 4/8 connectivity)."""
    px = bytearray(w * h)
    cx, cy = w // 2, h // 2
    for y in range(h):
        for x in range(w):
            d = (x - cx) ** 2 + (y - cy) ** 2
            if 36 <= d <= 64:
                px[y * w + x] = 200
            elif d <= 4:
                px[y * w + x] = 30
    return bytes(px)


IMAGES = {
    "ramp_blobs": (32, 24, ramp_blobs),
    "two_blobs": (24, 20, two_blobs),
    "gradient": (28, 22, diagonal_gradient),
    "checker": (16, 16, checkerboard),
    "uniform": (12, 10, uniform),
    "sparse": (24, 12, sparse),
    "ring": (22, 18, ring),
}


def main() -> int:
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "images"
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
