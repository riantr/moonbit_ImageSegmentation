# QA report — `moonbit_segmentation`

Date: 2026-10-30 (first audit) and 2026-10-31 (second round, the optimisation)
Scope: the MoonBit port of the Java/ImageJ segmentation plugins in
`D:/src/java/algo/Segmentation`, the Java reference harness in `ref/harness`,
and the verification chain in `verify/`.

Result: **all gates green**. The first audit found and fixed **9 real
defects** in the port, the harness or the verification chain and closed **6
coverage gaps** that had made parts of the suite vacuous. The second round
closed **8 of the 9** findings that the first audit had deliberately left open,
**proved the ninth one to be wrong**, and found (and fixed) **one more real
defect** (number 10 below) that the new coverage had uncovered. The third
round went through the **library surface** once more, completed the channel
selection of the `RetFM_J` conversion, **measured** the `pow` risk instead
of leaving it as a vague remark, extended the cross check of the
`AutoThresholder` from **one** of its fifteen methods to **all** of them, and
fuzzed the labeling of the blobs, the two threshold plugins, the mixture
model and the SIOX segmentation (§5).

---

## 1. What was verified

| gate | what it proves | result |
| --- | --- | --- |
| `moon check --deny-warn` | the source is free of warnings and errors | 0 warnings, 0 errors |
| `moon test --target all` | the library tests on all four backends | 30/30 on native, js, wasm, wasm-gc |
| `verify/run_verify.ps1` | the seven happy path images, byte for byte, plus the freshness of the golden | 7/7 ALL-PASS |
| `ref/harness/tools/LiCrossCheck.java` | the `Li` method of the **original** `AutoThresholder` against the port, on a thousand hostile histograms | 1000/1000, the same checksum |
| `ref/harness/tools/PowCrossCheck.java` | the `pow` of the port against the `Math.pow` of the reference, on the arguments the algorithms use | the same checksum for the exponent 2.0 |
| `ref/harness/tools/AutoThresholderCrossCheck.java` | **all fifteen** threshold methods of the **original** `AutoThresholder` against the port, on hostile histograms | 15 × 64, the same checksum per method |
| `ref/harness/tools/BlobCrossCheck.java` | the six configurations of the **original** `Blob_Labeler` against the port, on random images | 6 × 96, the same checksum per configuration |
| `ref/harness/tools/ThresholdCrossCheck.java` | the original `OtsuThresholding_` and `Multi_OtsuThreshold` against the port, on random images | 4 configurations, the same checksum per configuration |
| `ref/harness/tools/MixtureCrossCheck.java` | the original `MixtureModeling_` against the port, on random images | 64 images, the same checksum |
| `ref/harness/tools/SioxCrossCheck.java` | the original `SioxSegmentator` against the port, on random **colour** images | 64 images (8 of them raise), the same checksum and the same number of failures |
| `verify/run_edge_verify.py --backend all --per-algorithm` | the eighteen adversarial images on all four backends, as a whole set **and** with every algorithm on its own | 18 × 4 ALL-PASS |
| `verify/run_targets.ps1` | the matrix of backend × algorithm | 4 × 12 all `ok` |
| `verify/run_png_verify.py --backend all` | the PNG commands against **Pillow**, an independent decoder | 4/4 ALL-PASS |
| `verify/run_bench.py` | the runtime against the Java reference on the same machine | the ratio 1.04 in the last run (0.99…1.31 over the runs), the budget is 0.5 |

The comparison covers **252 files** of the happy path corpus and **648 files**
of the adversarial corpus (36 per image and backend), plus 75 scalars per
image. Every binary artefact is compared byte for byte; the floating point
statistics are compared through their raw IEEE-754 bit patterns (exactly, as
integers).

One entry point runs all of it:

```powershell
powershell -ExecutionPolicy Bypass -File .\verify\verify_all.ps1
```

---

## 2. Defects found and fixed (first audit)

### 2.1 The port

| # | defect | symptom | fix |
| --- | --- | --- | --- |
| 1 | `RATS_` divides by zero on a one pixel wide or high image | Java raises an `ArithmeticException`; MoonBit does not, so the port walked into an out of bounds access and **the whole CLI died** — every algorithm of that run lost its output | guard in `rats.mbt`; the port reports the failure (`rats.failed = 1`) and an empty mask, like the harness does |
| 2 | `Blob_Labeler` reads `labels[i]` outside `int[size/2]` | Java raises an `ArrayIndexOutOfBoundsException`; the port **panicked** (and a MoonBit panic cannot be caught) | the port checks the label index itself and reports `blob4.failed` / `blob8.failed` with an empty label map |
| 3 | `RetFM_J.convertToGrayscale` with no selected channel | Java divides by zero, the product becomes `NaN` and the narrowing conversion yields an all zero image; the port **trapped** on the `NaN` | the conversion goes through `java_double_to_int`, which has the Java semantics (`NaN → 0`) |
| 4 | `RetFM_J.convertToGrayscale` with a channel index beyond the third | Java's `ColorProcessor.getChannel` yields a zero image for every channel number above three; the port used the blue channel | the fourth channel contributes zeros (and still counts towards the divisor) |
| 5 | `Multi_OtsuThreshold.buildHistogram` accumulates the histogram in a `float[]` | a bin that holds more than 16 777 216 pixels saturates in Java; the port used the exact count | the count is capped at 2²⁴ before it is converted to a float |
| 6 | `Blob_Labeler` reads `labels[]` out of bounds *while* two labels are merged | the guard only covered the condensing loop at the end, so the port could still panic before it reached the guard | the guard is now in place at the creation of the offending label — the point at which the Java original leaves the array |
| 7 | the CLI accepted a missing or a wrongly sized input file | it exited with `0` and produced `otsu.threshold 0` | the loader refuses a file whose length is not `width * height` and aborts with a message, like the Java harness does |
| 8 | `siox.success` could not distinguish the two failure modes of `segmentate` | "returned `false`" and "raised `IllegalStateException`" both became `success = 0` | the port reports `siox.failed` separately; the harness does the same |
| 9 | *(found by the colour fix, below)* the harness computed the `RetFM_J` threshold on the **grey source** instead of the **converted grayscale** | with a neutral colour image the two are the same, so the bug was invisible | the harness now follows the original plugin (`RetFM_J.java:190-196`): it converts to grayscale, computes the threshold of *that* image and thresholds it. The port already did this. |
| 10 | *(found by the second round)* the `Blob_Labeler` neighbour read leaves the image | the plugin reads its neighbours through `ImageProcessor.get(x, y)`, which raises an `ArrayIndexOutOfBoundsException` when the read leaves the array — the plugin reads the **row 1** of an image that is one row high and the **column -1** of an image that is one column wide. The port did the same read and **panicked**, and a MoonBit panic cannot be caught: the whole command line tool died and every algorithm of that run lost its output. The new `edge = false` variant of the plugin (which does not overwrite the border and therefore reaches the read) exposed it on the `edge_one_row`, `edge_one_column` and `edge_one_pixel` images. | `blob_labeler.mbt` checks the neighbour indices itself (`neighbours_in_bounds`) and reports the failure the way the harness observes it — an empty label map and `failed = true`. The port and the reference now agree on all six blob configurations for those three images. |

### 2.2 The verification chain

| # | defect | why it mattered | fix |
| --- | --- | --- | --- |
| A | `compare.py` compared the IEEE-754 **bit patterns** with the 1e-6 tolerance | the only exact floating point evidence of the suite actually allowed about **1000 units in the last place** — a 1 ULP regression in the mixture model would still have reported PASS | a `*.bits.*` key is compared as an exact integer |
| B | `compare.py --algo <name>` compared **no** scalar at all for `watershed`, `densitometry` and `multithresholder` | the prefix list of these three was empty, and an empty list matched nothing | every algorithm now declares the exact set of its scalars; in the isolated mode the MoonBit side has to produce exactly that set, so a dropped or renamed scalar is a failure |
| C | `run_edge_verify.py` never emptied its output directories | a file of an earlier run could satisfy the comparison — the adversarial gate could pass on yesterday's output | the output tree of every backend is removed before it is written |
| D | the committed golden (`ref/harness/golden/`) was never regenerated nor cross checked | the whole 4 backend matrix is compared against it, so a stale or hand edited golden decided the outcome | `verify/run_verify.ps1` regenerates the Java output and compares it with the golden **before** anything else; `verify/refresh_golden.ps1` updates it deliberately |
| E | the Java harness caught the exceptions of the original plugins, printed them to stderr and **exited with 0** | a degraded reference and a degraded port would both "PASS" | both sides report `blob4.failed`, `blob8.failed`, `rats.failed` and `siox.failed`; the flags are compared exactly |
| F | the "unexpected file" check only looked at the MoonBit side | a file that the Java side writes and the comparison does not know about was invisible | the complete run checks both sides |
| G | `compare.py` silently accepted a duplicated key and a line without a space | two lines with the same key would overwrite each other | both are an error now |
| H | `run_targets.ps1` aborted the whole matrix when `moonrun.exe` was missing, even for the native and the js backend | a missing wasm runner hid the results of the two backends that do not need it | the runner is only required when a wasm backend is requested |
| I | the CLI padded a short raw input with zeros | the Java harness rejects such a file | the reader refuses a file whose length does not match |

---

## 3. Coverage gaps that were closed (first audit)

| gap | why it was a gap | what was done |
| --- | --- | --- |
| the colour paths were untested | **every** fixture was `R = G = B`, so a plugin that mixed up the colour channels could not fail | the reference now renders the grey level `v` as `R = v`, `G = 3v/4`, `B = 255 - v`; the MoonBit CLI builds the same colours. This immediately exposed defect 9 above. |
| the `*.bits.*` comparison could not fail | see A | now an exact integer comparison, and `mixture.bits.diffMu` / `mixture.bits.realThreshold` (two floats that had no bit pattern of their own) were added |
| the RATS branch that leaves the image was uncovered | every corpus image was wider than it is high | the adversarial corpus got `edge_tall` (12×30): the Java original leaves the array, the port detects the same condition, both report an empty mask and `rats.failed = 1` |
| the `IllegalStateException` of SIOX was assumed to be unreachable | — | the corpus got `edge_siox_exception` (a background and unknown pixels but no foreground). The exception path was in fact already reached by the `gradient` image, and `siox.failed` now pins it down |
| the 32 bit overflow of the Java accumulators was never executed | the largest bin count in the corpus was 1024, the overflow needs more than 32 900 | the corpus got `edge_large_mixed` (600×600), and the wrapping of the MoonBit `Int` is now pinned by a regression test |
| the adversarial corpus was not wired into any driver | a green `run_verify.ps1` said nothing about degenerate sizes | `verify/verify_all.ps1` runs everything, and the edge driver compares every algorithm **on its own** as well |

The adversarial corpus grew from 15 to 18 images.

---

## 4. The second round: the nine findings that were left open

The first audit listed nine findings it had **deliberately not** changed. The
optimisation round went through all of them. Eight are closed, and the ninth
turned out to be **wrong**.

| # | finding (first audit) | what happened |
| --- | --- | --- |
| 1 | `auto_threshold` returns `-1` for an unknown method name, Java throws an `IllegalArgumentException` | **closed.** The port now aborts with `Method not found: <name>`, the loud failure of a Java exception. MoonBit has no catchable exception, so a silent `-1` (which is the "no threshold" convention of `AutoThresholder`) would have been a wrong answer instead of a wrong *shape*. |
| 2 | the `Li` method can index outside the 256 bin histogram | **the finding was wrong.** The iteration variable of `Li` is the logarithmic mean of two means that both live in `0..255`, so the threshold can never exceed 255 and the read `data[0..threshold]` always stays inside the array. The claim is now pinned by a **cross language differential test**: `ref/harness/tools/LiCrossCheck.java` drives the original class and the MoonBit test `the Li threshold matches the original AutoThresholder on hostile histograms` drives the port with the **same** thousand hostile histograms (generated by the same linear congruential generator), and both sides are pinned to the same checksum (333878761). The Java side is a gate of `verify_all.ps1`. The tool also accepts a different number of rounds, so the claim can be re-checked on a wider set of histograms at any time — `LiCrossCheck 200000` drives the original class with 200 000 hostile histograms and reports a threshold range of `0 .. 123` and no read that leaves the histogram. |
| 3 | SIOX's `erode`/`dilate` use `Math.max`/`Math.min`, the port uses `if`/`else` | **closed.** `siox.mbt` uses `java_max_float` / `java_min_float` now, which have the Java semantics (`NaN` propagates, `+0.0` wins over `-0.0`). The divergence is gone, not just unlikely. |
| 4 | `Math.pow` (Java) and `@math.pow` (MoonBit) are not required to be bit identical | **measured and bounded** (see §5.2). The claim was right in general and wrong where it mattered: for the exponent 2.0 — the mixture model and the Otsu plugin — the two sides are **bit identical on every platform**, because both compute the correctly rounded square. Only the exponents 2.4 and 1/3 (the colour conversion of SIOX) differ, and only by one unit in the last place. The behaviour of both platforms is now pinned by a gate (`ref/harness/tools/PowCrossCheck.java` and the MoonBit test `the pow of the port matches the Java Math.pow on the arguments of the algorithms`). |
| 5 | the densitometry plugins only look at the ROI, the port has no ROI support | **closed.** `densitometry.mbt` has a `DensitometryRegion` and walks the image in the row major order of the ROI, exactly like the plugin. The oracle covers it: the harness runs the plugin on a ROI (the middle half of the image) and the CLI produces the same bytes. |
| 6 | the harness takes the *last* `ImagePlus` a plugin created | **closed.** The harness now takes the images through `created(width, height, what)` and `created(count, width, height, what)`, which fail loudly when the plugin did not produce the expected number of images of the expected size. The RATS mask is checked against (height, width). |
| 7 | `Blob_Labeler` with `edge_correction = false` or a background colour other than 0 | **closed.** The harness runs the plugin in six configurations (the defaults, `edge = false`, `bgcol = 1`, each of them 4- and 8-connected) by setting the private static fields with reflection; the port produces the same six label maps byte for byte. |
| 8 | `Multi_OtsuThreshold` with `MLEVEL` 2, 3 or 5 | **closed.** The plugin hard codes `MLEVEL = 4`, but the port supports 2…5, so the harness calls the public `findMaxSigma(int, float[][], int[])` with the other three level counts and reports the thresholds (`multiotsu.levelN.tK`). Both sides agree byte for byte. |
| 9 | the `to-png` and `results-png` commands are outside the byte exact comparison | **closed.** `verify/run_png_verify.py` checks them against **Pillow**, an independent decoder, on all four backends: the samples of `to-png` are the samples of the input, the samples of `results-png` are the samples of the raw files, and a PNG input produces the same result as the equivalent raw input (the ITU-R BT.601 luminance). |

### What else the round added

* **36 files and 75 scalars per image** (18 and 47 at the start of the very
  first audit) — every variant is a real branch of the original code with a
  real Java oracle.
* **The harness no longer trusts the plugins.** The size of every image a
  plugin produces is checked, so a plugin that returns an image of the wrong
  size fails the harness instead of silently changing the corpus.
* **Two new gates.** The PNG gate (against an independent decoder) and the
  performance gate (a ratio against the Java reference on the same machine, so
  the gate does not depend on the machine it runs on).
* **The performance gate has a tested failure branch.**
  `run_bench.py --budget-factor 0.5` demands that the port be *faster* than
  the reference and has to fail — a gate whose failure path was never run is
  a gate that has never been shown to work.
* **The unit tests grew from 19 to 24**: the ROI of the densitometry, the `Li`
  cross check, the out of bounds neighbour read of the blob labeler, the
  channel selection of the `RetFM_J` conversion and the `pow` cross check.
* **A new coverage hole was opened and closed at the same time.** The `Li`
  cross check (finding 2 above) and the `Blob_Labeler` fix (defect 10) only
  exist because the round added the coverage that made them visible.

---

## 5. The third round: what was still missing

The second round closed the nine findings of the first audit. A third pass
over the **library surface** (not just the command line tool) found two things
that were still open, and both are closed now.

### 5.1 The parameters of the densitometry plugins and the channel selection of `RetFM_J`

The port exposes the settings of the original plugins as options, and the
oracle covered only some of them:

* the **channel selection** of `RetFM_J.convertToGrayscale`: the plugin
  averages the **selected** channels, so the divisor is the number of the
  selected channels and every selected channel contributes its own plane. The
  oracle covered `{R,G,B}` and `{R}` — so the path with **two** channels (the
  divisor 2) and the path with **no** channel (the divisor 0, the product
  becomes NaN and the image is all zero) were never compared against
  anything, and a mix-up of the green and the blue channel would have gone
  unnoticed.
* the **tolerance** of the densitometry plugins (`intTol` and `intRtol` /
  `intGtol` / `intBtol`): it is a parameter of the plugins and not a
  constant, and a plugin that ignored it would have passed the whole
  verification.

Both are covered now: the harness drives **every** selection of the three
channels and another tolerance (64, and 64/32/16 per channel), and the port
produces the same images byte for byte: **36 files** and 75 scalars per
image.

The new variant also exposed a **latent fragility of the harness**: the
plugins read their settings from **static** fields, and the 3-channel plugin
still carried the `blnFill` / `blnInvr` of the previous (inverted) run, so
the two sides compared *different configurations*. Every run now sets all of
the fields explicitly (`configure1` / `configure3` in `Harness.java`), so the
order of the runs can no longer change a result.

### 5.2 The `pow` of the port against the `Math.pow` of the reference

The first audit listed "`Math.pow` and `@math.pow` are not required to be bit
identical" as a residual risk. A risk that cannot be closed can at least be
**measured**, and the measurement changed the statement considerably.

The three places the port uses a power:

| use | exponent | base |
| --- | --- | --- |
| the mixture model (`Math.pow(i - mu, 2)`) and the Otsu plugin | 2.0 | [-256, 256] |
| the sRGB gamma of SIOX | 2.4 | [0, 1] |
| the CIELAB cube root of SIOX | 1/3 | [0, 1] |

Both implementations were driven with the same 60 000 arguments (the same
linear congruential generator, the same arguments, the raw IEEE-754 bit
patterns of the results compared value by value):

| family | Java `Math.pow` | MoonBit native | MoonBit js | differing |
| --- | --- | --- | --- | --- |
| exponent 2.0 | 546001597 | 546001597 | 546001597 | **0 of 20 000** |
| exponent 2.4 | 299101583 | 186648498 | 744928871 | 15 of 20 000 (0.075 %) |
| exponent 1/3 | 656082642 | 233123601 | 250071220 | 20 of 20 000 (0.1 %) |

* **The exponent 2.0 is identical everywhere.** MoonBit's `@math.pow` is the
  fdlibm port of OpenJDK's `Math.pow` (the file even carries the Sun
  copyright), and it returns `x * x` for the exponent 2 — and a single IEEE
  multiplication *is* the correctly rounded square, so every conforming
  implementation returns the same bits. The mixture model and the Otsu plugin
  are therefore **safe**, not merely "probably fine".
* **The exponents 2.4 and 1/3 differ** — always by exactly **one** unit in the
  last place of the double, in about 0.1 % of the arguments. The result is
  narrowed to a `float` immediately afterwards (`Float::from_double`), which
  absorbs such a difference unless it falls on a float rounding boundary
  (about 2⁻²⁹ per differing value). The byte exact comparison of the 25
  corpus images on all four backends is the gate for that path.

Both platforms are now pinned: `ref/harness/tools/PowCrossCheck.java` checks
the three checksums of the Java side and the MoonBit test `the pow of the
port matches the Java Math.pow on the arguments of the algorithms` checks
that `@math.pow(x, 2.0)` is bit for bit the correctly rounded `x * x` on
**every** backend. A change of either platform is reported instead of
silently changing the result of the port.

### 5.3 All fifteen threshold methods against the original

The residual risk list ended with "the `Li` cross check covers one method of the
fifteen" — the other fourteen methods of the `AutoThresholder` were only
covered by the image corpus, not by a fuzz. A method that is wrong on a
degenerate histogram (an empty one, a single spike, everything in the last
bin) would have been invisible.

The cross check is now extended to **every** method, with the mechanism of the
`Li` check: the Java tool `ref/harness/tools/AutoThresholderCrossCheck.java`
and the MoonBit test `the fifteen threshold methods match the original
AutoThresholder on hostile histograms` drive the same histograms and pin the
same constants on both sides.

| | value |
| --- | --- |
| methods | 15 (`Huang`, `Intermodes`, `IsoData`, `Li`, `MaxEntropy`, `Mean`, `MinError(I)`, `Minimum`, `Moments`, `Otsu`, `Percentile`, `RenyiEntropy`, `Shanbhag`, `Triangle`, `Yen`) |
| histograms per method | 64 (eight hostile shapes, eight times each) |
| thresholds compared | 15 × 64 = **960** per side |
| checksums | one per method, plus the fold of all fifteen |

The generator is **restarted for every method**, so every method sees the same
sequence of histograms and the checksum of a method depends on that method
alone — a divergence is therefore localised to one method instead of hiding in
the sum of all of them. The tool also compares the **names and the order** of
the method table of the original with the ones of the port, so a renamed or
reordered method is caught as well.

Before the check was written, every method of the original was measured on all
eight shapes (24000 calls): **not one of them raises an exception**, so a
method that throws here is a defect of the original and not of the port — and
the port, which cannot catch an error, has to agree with it on every one of
them.

### 5.4 The labeling of the blobs

The labeling is the most intricate algorithm of the port: the HIPR2 algorithm
with a union-find style merge of the labels and a condensation of them at the
end. It was covered by the image corpus — twenty five images — and by nothing
else. A corpus does not contain the cases that make the algorithm interesting:
**many** separate blobs, blobs that **touch** (the merge of two labels), blobs
with a **hole**, and the **border** of the image (the edge correction overwrites
the first row and the first column).

So the labeling is now fuzzed like the thresholds: the Java tool
`ref/harness/tools/BlobCrossCheck.java` and the MoonBit test `the blob labeler
matches the original Blob_Labeler on random images` drive the **same** random
images and pin the **same** checksums.

| | value |
| --- | --- |
| configurations | 6 (the 4 and the 8 connected neighbourhood, with and without the edge correction, background colour 0 and 1) |
| images per configuration | 96 |
| shapes | 16 (among them the one row and the one column high images, on which the original reads outside the image) |
| densities | three families: half, two thirds and four fifths of the pixels are foreground |
| labels compared | 6 × 96 = **576** label maps per side |

The **failure path** is part of the comparison, and it fires a lot: the plugin
of the original raises an `ArrayIndexOutOfBoundsException` when it has more
labels than `size/2` (its label array is half the size of the image) or when
it reads a neighbour outside a one row or one column high image. The number of
failing images per configuration is pinned as well:

| configuration | checksum | failing images |
| --- | --- | --- |
| `blob4` | 717071813 | 6 |
| `blob8` | 41598674 | 6 |
| `blob4_noedge` | 99965418 | 22 |
| `blob8_noedge` | 549135478 | 29 |
| `blob4_bgcol` | 470942760 | 6 |
| `blob8_bgcol` | 776978089 | 6 |

The configuration **without** the edge correction fails far more often: without
the correction the border of the image is labeled as well, and the border of a
one row or one column high image is exactly the read that leaves the array.
The port reports these failures the way the reference harness observes them (an
empty label map, no labels, the failure flag set) — and the fuzz shows that it
does so in exactly the same rounds as the original.

### 5.5 The two threshold plugins

The image corpus is a set of **pictures**, and a picture does not contain a
histogram on purpose — a histogram is exactly what the `OtsuThresholding_` and
the `Multi_OtsuThreshold` plugins consume. The cases worth checking are the
ones a corpus does not produce: a histogram with a single bin, one with
everything in the last bin, one with two levels, an empty one, and the level
counts 2, 3 and 5 of the multi level search (the plugin hard codes 4, but its
`findMaxSigma` implements all of them and so does the port).

So both plugins are fuzzed with the same mechanism as the other two: the Java
tool `ref/harness/tools/ThresholdCrossCheck.java` and the MoonBit test `the
otsu thresholds match the original plugins on random images` drive the **same**
random images and pin the **same** checksums.

| configuration | what is compared | images | checksum |
| --- | --- | --- | --- |
| `otsu` | the threshold the plugin reports **and** the binary image it produces | 64 | 600913906 |
| `multiotsu2` | the thresholds of the level count 2 | 32 | 828034254 |
| `multiotsu3` | the thresholds of the level count 3 | 16 | 59404614 |
| `multiotsu4` | the thresholds of the level count 4 | 8 | 289251653 |

The images are eight shapes — sixteen grey levels, two levels, a ramp, a single
grey level, sparse noise on a background, completely black, a gradient and two
halves with two levels — and the generator is advanced once per pixel in
**every** shape, so the two sides consume the same numbers even in the shapes
that do not use them.

The **level count 5 is not fuzzed**: its search is a loop over four nested
loops over the 256 grey levels, about 160 million iterations per histogram,
which would make the unit test minutes long on the slower backends. The
corpus covers it instead — the harness calls `findMaxSigma(5, …)` on **every**
one of its 25 images, and the comparison is byte exact.

The number of images is scaled by the cost of the search (one loop for the
level count 2, two for 3, three for 4), so the whole test stays quick: the
four backends together need about ten seconds.

### 5.6 The mixture model

The mixture model is the last of the histogram algorithms: it fits two Gaussian
components to the histogram and reports the mean, the variance, the fitting
error and two thresholds of the fit. Its output is **floating point**, and the
corpus compares it bit for bit — but only on the images of the corpus.

The degenerate histograms are the interesting inputs: a single bin (one
component has no pixels at all), two levels, an empty one, a histogram with
everything in the last bin. On those the fit degenerates — the component
without pixels gets the variance zero, and its density function then returns
zero for every grey level instead of dividing by zero. The result stays
finite (the plugin never produces a NaN or an infinity), but the means, the
variances, the error and the thresholds are completely different from the ones
of a balanced histogram.

So the mixture model is fuzzed with the same mechanism as the others: the
Java tool `ref/harness/tools/MixtureCrossCheck.java` drives the **original**
plugin (and scrapes the numbers it prints through `ij.IJ.MESSAGES`), the MoonBit
test `the mixture model matches the original MixtureModeling_ on random images`
drives the **port**, and both pin the **same** checksum.

The floating point values are folded into the checksum through their **raw
IEEE-754 bit patterns**, as unsigned 32 bit values, so that the checksum stays
positive on both sides. Compared per image are the two means, the two
variances, the fitting error, `mu2 - mu1`, the direct threshold, the real
threshold and the binary image the plugin produces.

### 5.7 The SIOX segmentation

SIOX was the one algorithm of the suite that the fuzzes of the third round had
**not** reached, and it is the one with the sharpest risk: it is the only
algorithm whose **colour conversion** runs on a platform dependent power (the
sRGB gamma with the exponent 2.4 and the CIELAB cube root with the exponent 1/3,
§5.2).

The corpus could not have caught it either. All seven images of the happy path
corpus and all eighteen images of the adversarial corpus are **grey scale** — a
grey scale image has r = g = b, so the colour conversion is a degenerate path
and the clusters are decided by the grey level alone. The plugin, on the other
hand, is meant for photographs. The colour conversion of SIOX had therefore
never been compared against the original **on a colour image at all**.

The gate is the same mechanism as the other four: the Java tool
`ref/harness/tools/SioxCrossCheck.java` drives the **original**
`siox.SioxSegmentator`, the MoonBit test `the siox segmentation matches the
original SioxSegmentator on random images` drives the **port**, and both pin the
**same** checksum and the **same** number of failing images.

| | value |
| --- | --- |
| images | 64 (eight shapes, eight times each) |
| shapes | dark/bright halves, a dark and an unknown half, completely random colours, a gradient, completely black, completely white, dark/bright with random colours, a random grey level with one dominant channel |
| compared | the confidence matrix of every pixel, through its **raw IEEE-754 bit pattern** (as an unsigned 32 bit value) |
| pinned | the checksum `15384133` and the number of failing images `8` |

Two things make this gate more than a checksum comparison:

* **The failure paths are part of it.** The original raises an
  `IllegalStateException` when the foreground signature does not exist (the
  completely black shape has no foreground at all) and returns `false` when the
  background signature is empty. On the 64 images the original raises on
  **8** of them and returns `false` on **16** of them. The port has to fail in
  the same way and in the same number of rounds — a port that fails *differently*
  is a defect, and a port that *does not* fail where the original fails is a
  defect as well. The number of failing rounds is pinned on both sides.
* **The confidence matrix is compared bit for bit, not with a tolerance.** The
  confidence is a float; a decimal comparison with a tolerance would hide
  exactly the one-ULP difference this gate is looking for.

The result is the quantitative answer to the residual risk of §5.2: over about
30 000 confidence values of 64 random colour images the two sides agree **bit
for bit**. The one-ULP difference of the sRGB gamma and of the CIELAB cube root
therefore **does not flip a cluster boundary** — the difference is absorbed
before it can decide anything. The risk is closed, not merely restated.

### 5.8 The residual risks that are left

1. **The reference is the harness, not a stock ImageJ.** Two behaviours of the
   reference differ from a stock ImageJ and both are documented in
   `ref/harness/README.md` (deviations 12/13 and 14/15):
   * the `RATS_` mask has its dimensions swapped (the stub's
     `FloatProcessor` transposes the image like the original does, upstream
     ImageJ does not),
   * the 16 bit cases of the `Multi_Thresholder` helpers use the fixed range
     `0..65535` of the stub instead of the pixel range of upstream ImageJ —
     36 of the 72 lines of `multithresholder.txt`.

   A byte exact match against the harness therefore proves *internal
   consistency* with the original plugin sources, not equivalence with a
   stock ImageJ, for those two cases.
2. **The SIOX colour conversion depends on the platform's `pow`** — see
   §5.2. The difference is one unit in the last place of a double that is
   narrowed to a float right afterwards. This was a risk in the second round;
   the third round **measured** it on 64 random colour images (§5.7): about
   30 000 confidence values, **zero** differences in the raw bit patterns. The
   difference does not flip a cluster boundary. The byte exact comparison would
   still report it if it ever did (that is the point of the exact bit
   comparison), not hide it.
3. **The wrapping of the MoonBit `Int`** is a property of the language. It is
   used by `AutoThresholder` and `RetFM_J`, and it is now pinned by a
   regression test (`the Int arithmetic wraps like a Java int`) that fails if
   the semantics ever change.
4. **The branch coverage is not complete.** The list in section 4 names the
   branches that no image reaches. After the second round only the ones that
   are unreachable through the CLI are left; everything that the CLI *can*
   reach now has a Java oracle, and everything that the **library** exposes
   is covered as well (see §5.1). The five fuzzes of the third round (§5.3,
   §5.4, §5.5, §5.6 and §5.7) add random inputs on top of that. The
   `Blob_Labeler` defect 10 shows what is still possible: a branch that was
   added *and* covered in the same round uncovered a crash that had been
   hiding in the code the whole time.
5. **The performance budget is a ratio, not a number.** The gate demands that
   the port is at most twice as slow as the Java reference **on the same
   machine, in the same run**. A change that makes both sides slower (a
   slower JDK, a busier machine) does not trip it, and a change that makes
   the port slower by a constant factor of less than two does not either. The
   absolute numbers are recorded in `verify/perf_baseline.json` for the
   history, but they are reported, not enforced.
6. **The cross checks of the `AutoThresholder`, of the `Blob_Labeler`, of the
   two threshold plugins, of the mixture model and of the SIOX segmentation
   cover a fixed number of inputs.** They were extended from one method to all
   fifteen, from no fuzz to a fuzz and from the corpus to a fuzz in the third
   round (§5.3, §5.4, §5.5, §5.6, §5.7), but the number of inputs is still
   small: 64 histograms per
   method, 96 images per blob configuration, 8 to 64 images per threshold
   configuration, 64 images for the mixture model and 64 colour images for the
   SIOX segmentation. The checks find a
   divergence of the *shape* of an algorithm, not a divergence of the last
   digit in an exotic corner of the input space. The image corpus (25 images)
   covers the everyday cases much more densely.
7. **A NaN would have to have the same payload on both platforms.** The
   mixture model never produces one (§5.6), so the gate does not cover it. The
   two sides fold the raw bit pattern without canonicalising it — Java's
   `Float.floatToRawIntBits` and MoonBit's `reinterpret_as_int` both keep the
   payload — but two platforms are free to produce **different** NaN payloads
   for the same operation. If a NaN ever appears in the output of the port,
   the mixture gate would report a difference that is not a defect of the
   port.

---

## 6. How the suite would have failed before

A short list of regressions that the old suite would have reported as PASS
and that it now reports as a failure:

* a one ULP difference in `mixture.mu1` (the old tolerance allowed ~1000 ULP),
* a scalar that **both** sides dropped (the complete mode compared the union
  of the two key sets, so a key that disappeared on both sides was
  invisible; the isolated mode compared nothing at all for three algorithms),
* a stale `ref/harness/golden` (the matrix was compared against it and
  nothing ever checked it against a fresh Java run),
* a file that the port no longer writes (the edge driver did not empty its
  output tree, so the file of the previous run satisfied the comparison),
* a plugin that mixes up the colour channels (every fixture was neutral),
* a port that fails where the reference fails, but with a *different* failure
  (the `failed` flags did not exist, so a crash on both sides looked like a
  perfect match),
* a port that is twice as slow as the reference (there was no performance
  gate at all),
* a PNG that is not a valid PNG (the PNG commands had no independent
  decoder),
* a plugin that returns an image of the wrong size (the harness took the
  last image it found).

### The failure branches of the new gates

A gate whose failure path was never run is a gate that has never been shown to
work. The cross check gates of the third round were therefore run with a
deliberately wrong constant on purpose:

| gate | what was changed | what happened |
| --- | --- | --- |
| `AutoThresholderCrossCheck.java` | one expected checksum | `FAIL: the checksum of Huang is 107048180, the original is expected to compute 107048181`, exit code 1 |
| `BlobCrossCheck.java` | one expected checksum | `FAIL: the checksum of blob4 is 717071813, the original is expected to compute 717071814`, exit code 1 |
| `LiCrossCheck.java` | one expected checksum | `FAIL: the checksum is 333878761, the original AutoThresholder is expected to compute 333878762`, exit code 1 |
| `PowCrossCheck.java` | one expected checksum | `FAIL: the exponent 2.0 computes 546001597, 546001598 is expected`, exit code 1 |
| `ThresholdCrossCheck.java` | one expected checksum | `FAIL: the checksum of otsu is 600913906, the original is expected to compute 600913907`, exit code 1 |
| `MixtureCrossCheck.java` | one expected checksum | `FAIL: the checksum is 166889024, the original MixtureModeling_ is expected to compute 166889025`, exit code 1 |
| `SioxCrossCheck.java` | one expected checksum | `FAIL: the checksum is 15384133, the original SioxSegmentator is expected to compute 15384134`, exit code 1 |
| `SioxCrossCheck.java` | the expected number of failing images | `FAIL: the original raised on 8 image(s), it is expected to raise on 7`, exit code 1 |
| the MoonBit side of the blob fuzz | one expected checksum | `FAILED: 717071813 != 717071814`, exit code 2 |
| the MoonBit side of the threshold fuzz | one expected checksum | `FAILED: 107048180 != 107048181`, exit code 2 |
| the MoonBit side of the otsu fuzz | one expected checksum | `FAILED: 600913906 != 600913907`, exit code 2 |
| the MoonBit side of the mixture fuzz | one expected checksum | `FAILED: 166889024 != 166889025`, exit code 2 |
| the MoonBit side of the siox fuzz | one expected checksum | `FAILED: 15384133 != 15384134`, exit code 2 |

The Java tools were checked with a **copy** of the tool in a temporary
directory, so the committed tool was never in a wrong state. The MoonBit side
was checked by changing the constant in the test, running the single test
(`moon test --target native -f "*blob labeler matches*"`), and changing the
constant back — the suite was green again afterwards (30/30 on all four
backends, `moon check --deny-warn` clean).

## 7. An independent audit of the four new gates

The four cross check gates of the third round were audited by an **independent
verifier** that did not write a line of the suite. It was asked to assume the
author had been careless, and to answer six questions per gate: do the two
sides really see the same inputs, is the checksum sensitive to the output of
the port, do the two sides fold the results identically, are the failure paths
real, does the Java side drive the original code path, and can the suite be
vacuous.

**Verdict: all four gates are sound.** The findings that came out of it:

| # | severity | finding | fix |
| --- | --- | --- | --- |
| D1 | doc | the header of `ThresholdCrossCheck.java` announced five configurations and the level count 5, but the code fuzzes four (2, 3 and 4) | the header was corrected |
| D2 | doc | the MoonBit test of the same gate said "the level counts 2, 3 and 5" | corrected to 2, 3 and 4, with the reason |
| D3 | doc, **factually wrong** | five documents claimed that the mixture model "divides by zero" on the degenerate histograms and that "the error becomes NaN". The verifier dumped the output of all 64 rounds: **no NaN and no infinity ever occurs** — the density function returns zero when the variance is zero, so the division never happens | the five places now say what actually happens: the fit **degenerates** (one component has no pixels, its variance is zero, its density function returns zero), the result stays finite, and the statistics come out completely different |
| D4 | doc | the comment on `neighborhood8` in `blob_labeler.mbt` claimed that the Java reads `get(x + 1, y - 1)` "without clamping `x`". The Java **does** clamp `x` to `width - 1` and then adds one, so the linear index becomes `y * width` — the first pixel of row `y` | the comment was corrected (the **code** was always right) |
| D5 | robustness | the mixture gate printed the number of failing rounds but never compared it, so a round on which the plugin raised would have silently dropped out of the checksum | the count is now pinned (`EXPECTED_FAILURES = 0`) and the gate fails on it, exactly like the blob gate |
| D6 | coverage | the threshold gate reported the range of every method on the Java side, but the MoonBit side never compared it | the MoonBit test now asserts the lowest and the highest threshold of every method |

How the verifier established that the gates are not vacuous — worth recording,
because "the checksum is the same on both sides" is only convincing when the
inputs are proved to be the same:

* it transcribed the three generators of the MoonBit side **verbatim** into a
  throwaway module and compared a digest of **every generated value** with the
  Java generators: the digests are equal (740827042 for the hostile
  histograms, 753933664 for the blob images, and one per configuration for the
  threshold images);
* it confirmed that the MoonBit `Int` really wraps like a Java `int` **on all
  four backends** (`2147483647 + 1 = -2147483648`), so the 32 bit overflow of
  the generator is the same on both sides;
* it copied the **port sources** into a temporary module, ran the four gate
  bodies against them and reproduced every pinned checksum — so the assertions
  depend on the values the port computes;
* it transliterated the MoonBit `blob_label` into Java and compared it round
  by round with the real `Blob_Labeler`: 75 failures on each side, the same
  rounds, the same label counts, the same maps, **0 mismatches**;
* it confirmed that the level 5 of the multi level Otsu is out of reach for a
  unit test (four nested loops over the 256 grey levels, about 160 million
  iterations per histogram) and that the corpus covers it instead.

The audit also produced one **observation** about the way the work is done:
the constant of the mixture gate was still the placeholder `0L` and the gate
was not yet wired into the script while the documents already described it as
green. The constant and the wiring were finished right afterwards, and the
gate was re-verified end to end afterwards. A document must never describe a
gate that has not run yet.

**Scope of the audit.** The audit covers the four cross check gates that existed
when it was run — the `AutoThresholder`, the `Blob_Labeler`, the threshold
plugins and the mixture model. The SIOX gate (§5.7) was added **after** the
audit and has therefore **not** been audited by an independent party; it has
been checked by the same two self-tests as the others (the same input generator
on both sides, the same pinned checksum, the same number of failing rounds) and
its failure branches were run on purpose.
