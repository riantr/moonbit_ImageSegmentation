# moonbit_segmentation

A MoonBit port of the Java/ImageJ segmentation algorithm collection found in
`D:/src/java/algo/Segmentation`.

The port reproduces the behaviour of the original Java code: the output images
are identical byte for byte, the width and height of the output images match
and the values of the internal scalars match — for the floating point
statistics down to the last bit of the IEEE-754 representation. This is
verified automatically by running the *unmodified* Java sources next to the
MoonBit port and diffing their outputs byte by byte.

```
$ powershell -ExecutionPolicy Bypass -File .\verify\verify_all.ps1
...
ALL-PASS: every gate of the verification is green
```

### What "byte for byte" means here, precisely

The reference is **not** a stock ImageJ: it is the original plugin sources
compiled against the minimal ImageJ stubs in `ref/harness/`. Two behaviours
of that reference differ from a stock ImageJ, and both are documented in
`ref/harness/README.md`:

* the `RATS_` mask has its dimensions swapped (the stub's `FloatProcessor`
  transposes the image like the original does, but upstream ImageJ does not),
* the 16 bit cases of the `Multi_Thresholder` helpers use the fixed range
  `0..65535` of the stub instead of the pixel range of upstream ImageJ.

Apart from those two, the port is byte exact against the Java reference. The
single place where a *decimal* comparison is used is the printed form of the
floating point scalars (Java prints a `float` with a different number of
digits than MoonBit); the raw bit patterns of the same values are compared
exactly.

## What is ported

| MoonBit file | Java original |
| --- | --- |
| `otsu.mbt` | `OtsuThresholding_` (with `GrayLevelClass`) |
| `multi_otsu.mbt` | `Multi_OtsuThreshold` (Liao, 2–5 levels) |
| `auto_threshold.mbt` | `AutoThresholder` (all 15 methods of `getMethods()`) |
| `mixture_modeling.mbt` | `MixtureModeling_` (two Gaussian mixture) |
| `blob_labeler.mbt` | `Blob_Labeler` (4- and 8-connected labeling) |
| `watershed.mbt` | `Watershed_Algorithm` (Vincent–Soille immersion) |
| `densitometry.mbt` | `Densitometry_1_Channel_`, `Densitometry_3_Channel_` |
| `retfm.mbt` | `RetFM_J` (`getThreshold`, `convertToGrayscale`) |
| `siox.mbt` | `siox.SioxSegmentator` (+ `ColorSignature`, `Utils`) |
| `rats.mbt` | `RATS_` (+ `RATSQuadtree`) |
| `multi_thresholder.mbt` | `Multi_Thresholder` (level mapping helpers) |
| `image.mbt`, `java_compat.mbt` | support code (image containers, Java float semantics) |
| `png_io.mbt` | a small PNG codec (8-bit gray / 8-bit RGB) used by the CLI |

The seven Java plugins that ship as jars were unpacked to `ref/java/` and are
read only; nothing in `D:/src/java/algo/Segmentation` was modified.

### What is *not* ported

Everything that belongs to the ImageJ user interface: the plugin frame, the
option dialogs, the background worker threads and `ij.gui.Wand` based
vectorization (`Blob_Labeler` keeps the labeling and drops the vector output
step). The algorithms themselves are complete.

### The configurations the port implements

The plugins read their parameters from an ImageJ dialog, which the port turns
into explicit options. All of them are covered by the byte exact comparison:

| plugin | parameter | values |
| --- | --- | --- |
| `Multi_OtsuThreshold` | `MLEVEL` | 2, 3, 4, 5 |
| `Blob_Labeler` | `bgcol` | 0, 1 |
| `Blob_Labeler` | `edge` | true, false |
| `Blob_Labeler` | `neighb8` | 4-connected, 8-connected |
| `Densitometry_*` | `blnFill`, `blnInvr` | false/true, false/true |
| `Densitometry_*` | the tolerance | 127, and 64 (64/32/16 per channel) |
| `Densitometry_*` | the region of interest | the whole image, or a rectangle |
| `RetFM_J` | `useChannels` | every selection of R, G, B (including none) |
| `AutoThresholder` | the method | all 15 names of `getMethods()` |
| `Multi_Thresholder` | the level mapping | 8 bit and 16 bit, four thresholds, nine cases |

## Layout

```
moon.pkg                    the library package (the algorithms)
cmd/seg/                    the `seg` command line tool
ref/java/                   the original Java sources (read only, unpacked from the jars)
ref/harness/                a minimal ImageJ stub + harness that runs the original Java
ref/harness/golden/         the golden outputs of the Java reference
verify/                     the test images, the comparison script and the driver
```

## Using the library

```moonbit
import {
  "riantr/moonbit_ImageSegmentation",
}

fn main {
  let image = @moonbit_ImageSegmentation.GrayImage::new(64, 64, 0)
  let threshold = @moonbit_ImageSegmentation.otsu_threshold(image)
  println("threshold: " + threshold.to_string())
}
```

## The command line tool

```
seg run --input <gray.raw|file.png> --width <w> --height <h> --outdir <dir>
seg <algorithm> --input <gray.raw|file.png> --width <w> --height <h> --outdir <dir>
seg to-png --input <gray.raw|file.png> --out <file.png>
seg results-png --dir <run-dir> --width <w> --height <h>
seg help
```

`seg run` writes the very same output set as the Java harness, so that
`verify/compare.py` can diff the two directories byte by byte:

| file | content |
| --- | --- |
| `scalars.txt` | the thresholds and statistics of every algorithm |
| `otsu_image.raw` | 8-bit binary image of `OtsuThresholding_` |
| `multiotsu_region0..3.raw` | the four region images of `Multi_OtsuThreshold` |
| `mixture_image.raw` | 8-bit binary image of `MixtureModeling_` |
| `blob4_map.raw`, `blob8_map.raw` | int16 label maps of `Blob_Labeler` |
| `blob4_noedge_map.raw`, `blob8_noedge_map.raw` | the same two label maps with the edge correction switched off |
| `blob4_bgcol_map.raw`, `blob8_bgcol_map.raw` | the same two label maps with a background colour of 1 |
| `watershed.raw` | 8-bit binary image of `Watershed_Algorithm` |
| `densitometry1.rgb.raw`, `densitometry3.rgb.raw` | RGB output of the densitometry plugins |
| `densitometry1_binary.rgb.raw`, `densitometry3_binary.rgb.raw` | the same two outputs, binarised |
| `densitometry1_inverse.rgb.raw`, `densitometry3_inverse.rgb.raw` | the same two outputs, inverted |
| `densitometry1_roi.rgb.raw` | the 1-channel output on a ROI (the middle half of the image) |
| `densitometry1_tol.rgb.raw`, `densitometry3_tol.rgb.raw` | the same two outputs with another tolerance (64, and 64/32/16 per channel) |
| `retfm_gray.raw`, `retfm_otsu_image.raw` | output of the `RetFM_J` helpers |
| `retfm_red_gray.raw`, `retfm_green_gray.raw`, `retfm_blue_gray.raw` | the grayscale conversion for a single channel |
| `retfm_rg_gray.raw`, `retfm_rb_gray.raw`, `retfm_gb_gray.raw` | the grayscale conversion for two channels |
| `retfm_none_gray.raw` | the grayscale conversion without any channel (the divisor is zero, the image is all zero) |
| `rats_mask.raw` | 8-bit mask of `RATS_` (**the dimensions are swapped**) |
| `siox_cm.raw`, `siox_mask.raw` | confidence matrix and mask of SIOX |
| `multithresholder.txt` | the level mapping helpers of `Multi_Thresholder` |

That is 36 files and 75 scalars per image. The variants are not decoration:
each of them is a branch of the original code that the port implements, and
each of them has a **real Java oracle** — the harness drives the original
plugin with the corresponding configuration (a different `MLEVEL`, a
different `bgcol` / `edge`, `blnFill` / `blnInvr`, a different selection of
the channels, a ROI) and the result is compared byte for byte.

### Every algorithm on its own

`seg run` executes all the algorithms at once. Each of them can also be run
**alone**, with its own sub command:

```
seg otsu            seg multiotsu       seg autothreshold
seg mixture         seg blob            seg watershed
seg densitometry    seg retfm           seg rats
seg siox            seg multithresholder
```

A sub command writes the files of its algorithm only, plus a `scalars.txt`
that holds the scalars of that algorithm, so a single algorithm can be
checked in isolation — on any of the four MoonBit backends:

```powershell
seg rats --input image.gray --width 32 --height 24 --outdir out
python verify\compare.py --algo rats ref\harness\golden\ramp_blobs out
```

`seg to-png` converts an image into a PNG, `seg results-png` renders the
result set of a `seg run` directory as PNG files (the int16 label maps have no
direct PNG representation and are skipped).

## Verification

The reference side is a small harness (`ref/harness/`) that stubs the parts of
ImageJ the plugins use and runs the **original, unmodified** Java sources. Its
output is compared with the MoonBit output by `verify/compare.py`: 36 files
and 75 scalars per test image, on seven happy path images and eighteen
adversarial ones, on four backends.

* binary files are compared byte by byte,
* the printed floating point scalars are compared with a tolerance of 1e-6
  (Java prints a `float` with a different number of digits than MoonBit),
* the `mixture.bits.*` scalars carry the raw IEEE-754 bit patterns and are
  compared **exactly** — an integer comparison, never a tolerance,
* `multithresholder.txt` carries the raw IEEE-754 bit patterns of the
  `Multi_Thresholder` helpers and is compared byte by byte.

Both sides also report explicitly when an algorithm failed: the `*.failed`
scalars (`blob4.failed`, `blob8.failed`, `blob4.noedge.failed`,
`blob8.noedge.failed`, `blob4.bgcol.failed`, `blob8.bgcol.failed`,
`rats.failed` and `siox.failed`) are `1` when the Java original raised an
exception (and the port reproduced the failure). A degraded reference and a
degraded port therefore cannot pass unnoticed.

The reference renders the grey levels as **non neutral colours**
(`R = v`, `G = 3v/4`, `B = 255 - v`). With a neutral `R = G = B` image a
plugin that mixes up the colour channels would pass the verification, because
every channel would carry the same value.

The `Multi_Thresholder` plugin is the odd one out: it is a GUI frame, so the
harness uses the **original compiled class** from the plugin jar and drives
its four helper methods with reflection on an instance that is allocated
without running the window building constructor. The oracle is therefore the
artifact that was actually shipped.

Run everything with:

```powershell
powershell -ExecutionPolicy Bypass -File .\verify\verify_all.ps1
```

The seven test images are generated by `verify/make_test_images.py`, the
eighteen adversarial ones by `verify/make_edge_images.py`.

| script | what it does |
| --- | --- |
| `verify/verify_all.ps1` | all the gates below, one after the other |
| `verify/run_verify.ps1` | the byte exact comparison of the seven happy path images |
| `verify/run_edge_verify.py` | the same for the eighteen adversarial images, on every backend, with every algorithm also run on its own |
| `verify/run_targets.ps1` | the matrix of backend x algorithm |
| `verify/run_png_verify.py` | the PNG commands against **Pillow**, an independent decoder |
| `verify/run_bench.py` | the runtime against the Java reference on the same machine |
| `ref/harness/tools/LiCrossCheck.java` | the `Li` method of the **original** `AutoThresholder` against the port, on a thousand hostile histograms |
| `ref/harness/tools/AutoThresholderCrossCheck.java` | **all fifteen** threshold methods of the **original** `AutoThresholder` against the port, on hostile histograms |
| `ref/harness/tools/BlobCrossCheck.java` | the six configurations of the **original** `Blob_Labeler` against the port, on random images |
| `ref/harness/tools/ThresholdCrossCheck.java` | the original `OtsuThresholding_` and `Multi_OtsuThreshold` against the port, on random images |
| `ref/harness/tools/MixtureCrossCheck.java` | the original `MixtureModeling_` against the port, on random images |
| `ref/harness/tools/SioxCrossCheck.java` | the original `SioxSegmentator` against the port, on random **colour** images |
| `ref/harness/tools/PowCrossCheck.java` | the `pow` of the port against the `Math.pow` of the reference, on the arguments the algorithms use |
| `verify/refresh_golden.ps1` | regenerates the committed golden from the Java harness |

`verify_all.ps1` runs the fourteen gates in this order and stops at the first
failure:

1. `moon check --deny-warn` — the source is free of warnings,
2. `moon test --target all` — the library tests on all four backends,
3. `verify/run_verify.ps1` — the byte exact comparison of the seven happy path
   images, including the freshness of the committed golden,
4. `ref/harness/tools/LiCrossCheck.java` — the `Li` method of the original
   `AutoThresholder` against the port, on a thousand hostile histograms,
5. `ref/harness/tools/PowCrossCheck.java` — the `pow` of the port against the
   `Math.pow` of the reference, on the arguments the algorithms use,
6. `ref/harness/tools/AutoThresholderCrossCheck.java` — **all fifteen** threshold
   methods of the original `AutoThresholder` against the port,
7. `ref/harness/tools/BlobCrossCheck.java` — the six configurations of the
   original `Blob_Labeler` against the port,
8. `ref/harness/tools/ThresholdCrossCheck.java` — the original
   `OtsuThresholding_` and `Multi_OtsuThreshold` against the port,
9. `ref/harness/tools/MixtureCrossCheck.java` — the original `MixtureModeling_`
   against the port,
10. `ref/harness/tools/SioxCrossCheck.java` — the original `SioxSegmentator`
    against the port, on random colour images,
11. `verify/run_edge_verify.py --backend all --per-algorithm` — the eighteen
    adversarial images on all four backends,
12. `verify/run_targets.ps1` — the matrix of backend × algorithm,
13. `verify/run_png_verify.py --backend all` — the PNG commands,
14. `verify/run_bench.py` — the performance budget.

The last two need Python with Pillow and a JDK; they are skipped with a
warning when something is missing, so that the byte exact gates still run on
a machine without them (`-SkipOptional` skips them on purpose).

### The `Li` cross check

The QA report of the first round listed as a residual risk that the `Li`
method of the `AutoThresholder` "can index outside the 256 bin histogram".
That turned out to be **wrong**: the iteration variable of `Li` is the
logarithmic mean of two means that both live in `0..255`, so the threshold
can never exceed 255.

Instead of arguing about it, both implementations are driven with the same
thousand hostile histograms (generated by the same linear congruential
generator, so no file has to be exchanged) and pinned to the same checksum:

* `ref/harness/tools/LiCrossCheck.java` drives the **original** class and
  fails when it computes something else,
* the MoonBit test `the Li threshold matches the original AutoThresholder on
  hostile histograms` drives the **port** and fails when it does.

A divergence on any of the thousand histograms therefore shows up on the side
that caused it.

### The cross check of the fifteen threshold methods

The same mechanism covers **all** fifteen methods of the `AutoThresholder`,
not only `Li`:

* `ref/harness/tools/AutoThresholderCrossCheck.java` drives the **original**
  class with 64 hostile histograms per method and checks the checksum of every
  method against a fixed constant,
* the MoonBit test `the fifteen threshold methods match the original
  AutoThresholder on hostile histograms` drives the **port** with the same
  histograms and checks the same constants.

The generator is restarted for every method, so every method sees the same
sequence of histograms and the checksum of a method depends on that method
alone — a divergence is localised to a single method. The tool compares the
names and the order of the method table of the original with the ones of the
port as well.

### The cross check of the blob labeling

The labeling of the blobs is the most intricate algorithm of the port, and the
image corpus of twenty five images never contains many separate blobs, blobs
that touch, blobs with a hole or a border that matters. So it is fuzzed like
the thresholds:

* `ref/harness/tools/BlobCrossCheck.java` drives the **original** with 96
  random images per configuration and checks the checksum of every
  configuration against a fixed constant,
* the MoonBit test `the blob labeler matches the original Blob_Labeler on
  random images` drives the **port** with the same images and checks the same
  constants.

The six configurations are the ones of the reference harness (4 and 8
connected, with and without the edge correction, background colour 0 and 1),
and the **failure path** is part of the comparison: the original raises an
exception when it has more labels than `size/2` or when it reads a neighbour
outside a one row or one column high image, and the number of failing images
per configuration is pinned as well.

### The cross check of the threshold plugins

The image corpus is a set of **pictures**, and a picture does not contain a
histogram on purpose — a histogram is exactly what the `OtsuThresholding_` and
the `Multi_OtsuThreshold` plugins consume. So they are fuzzed too:

* `ref/harness/tools/ThresholdCrossCheck.java` drives the **originals** with
  random images (among them the degenerate histograms: one bin, two levels,
  completely black) and checks the checksum of every configuration against a
  fixed constant,
* the MoonBit test `the otsu thresholds match the original plugins on random
  images` drives the **port** with the same images and checks the same
  constants.

The configurations are the single level Otsu (the threshold **and** the binary
image it produces) and the multi level search with the level counts 2, 3 and
4. The level count 5 is not fuzzed — its search is four nested loops over the
256 grey levels (about 160 million iterations per histogram) — but the corpus
compares it on every one of its 25 images.

### The cross check of the mixture model

The mixture model fits two Gaussian components to the histogram; its output is
floating point, and the corpus compares it bit for bit. The degenerate
histograms (one bin, two levels, completely black) are where one component
has no pixels at all, so its variance is zero and its density function
returns zero for every grey level — the fit degenerates, and the means, the
variances, the error and the thresholds come out completely different:

* `ref/harness/tools/MixtureCrossCheck.java` drives the **original** plugin and
  checks the checksum of the means, the variances, the error and the two
  thresholds against a fixed constant,
* the MoonBit test `the mixture model matches the original MixtureModeling_ on
  random images` drives the **port** and checks the same constant.

The floats are folded through their raw IEEE-754 bit patterns, so a difference
in the last bit cannot hide behind a tolerance.

### The cross check of the SIOX segmentation

SIOX is the only algorithm of the suite whose **colour conversion** runs on a
platform dependent power, and it is the one the corpus could not have caught:
all twenty five images of the corpus are grey scale, and a grey scale image has
`R = G = B`, so the clusters would be decided by the grey level alone. The
plugin, on the other hand, is meant for photographs.

* `ref/harness/tools/SioxCrossCheck.java` drives the **original**
  `siox.SioxSegmentator` with 64 random colour images and checks the checksum
  of the confidence matrices and the number of failing images against fixed
  constants,
* the MoonBit test `the siox segmentation matches the original SioxSegmentator
  on random images` drives the **port** with the same images and checks the same
  constants.

The failure paths are part of the comparison: the original raises an
`IllegalStateException` when the foreground signature does not exist (the
completely black shape) and returns `false` when the background signature is
empty. On the 64 images it raises on **8** of them and returns `false` on
**16** of them — the port has to fail in the same way and in the same number of
rounds.

The confidence matrices are compared through their raw IEEE-754 bit patterns,
so a one-ULP difference in the colour conversion cannot hide behind a
tolerance. The result: about 30 000 confidence values, **zero** differences —
the one-ULP difference of the sRGB gamma and of the CIELAB cube root never
flips a cluster boundary.

### The `pow` cross check

The same round measured the other open risk: `Math.pow` (Java) and
`@math.pow` (MoonBit) are not required to be bit identical. The measurement
is reassuring where it matters:

| use | exponent | Java | MoonBit | differing |
| --- | --- | --- | --- | --- |
| the mixture model, the Otsu plugin | 2.0 | 546001597 | 546001597 | **0 of 20 000** |
| the sRGB gamma of SIOX | 2.4 | 299101583 | 186648498 (native) / 744928871 (js) | 15 of 20 000, 1 ULP |
| the CIELAB cube root of SIOX | 1/3 | 656082642 | 233123601 (native) / 250071220 (js) | 20 of 20 000, 1 ULP |

For the exponent 2.0 the two sides are **bit identical on every platform**: a
single IEEE multiplication *is* the correctly rounded square, and both
`Math.pow(x, 2)` and `@math.pow(x, 2)` return it. The two cross checks pin
that: the Java tool asserts `Math.pow(x, 2)` is the exactly rounded `x * x`,
the MoonBit test asserts the same for `@math.pow` — and both sides end up
with the **same** checksum.

For the exponents 2.4 and 1/3 the platforms differ by one unit in the last
place of the double in about 0.1 % of the arguments. The result is narrowed
to a `float` right afterwards, which absorbs such a difference unless it
falls on a float rounding boundary. `QA_REPORT.md` §5.2 has the details — and
the SIOX cross check above is the direct answer for the exponents that only
SIOX uses: on 64 random colour images the two sides agree bit for bit, the
difference never flips a cluster boundary.

### The PNG commands

`seg to-png` and `seg results-png` have no Java counterpart, so they cannot be
part of the byte exact comparison. They are checked against **Pillow**, an
independent decoder — a PNG that the port writes and its own decoder reads
again would not prove that the file is a valid PNG:

* `seg to-png` writes a grayscale PNG whose samples are the samples of the
  input,
* `seg results-png` writes one PNG per 8-bit result image of a run directory,
  with the same samples as the raw file,
* a **PNG input** produces the same result as the equivalent raw input (the
  RGB input is converted to grayscale with the ITU-R BT.601 weights).

### The performance budget

The byte exact comparison says nothing about the runtime, so the port could
get ten times slower without any gate noticing. `verify/run_bench.py` measures
the complete `seg run` on a 1024×1024 noise image and compares it with the
Java reference **running on the same machine, in the same run**. The budget is
that **ratio**: the port may be at most 2× slower than the reference.

A ratio is used on purpose — an absolute time recorded on one machine means
nothing on another one, and a gate that fails on a fast machine is worse than
no gate at all. The absolute numbers are kept in `verify/perf_baseline.json`
as well, but they are reported, not enforced.

The recorded baseline of the development machine is **2.01 s** for the port
against **2.54 s** for the Java reference (the port is 1.26× as fast). A
repeated measurement moves between roughly 0.99× and 1.31× — the machine was
busy during some of the runs — which is exactly why the gate watches the
ratio and not the time.

The failure branch of the gate is tested as well: with `--budget-factor 0.5`
(which demands that the port be *faster* than the reference) the gate has to
fail — a gate whose failure path was never run is a gate that has never been
shown to work.

`QA_REPORT.md` holds the report of the last deep audit: the defects it found,
the coverage gaps it closed and the risks that are left.

### The four backends

The port has to work on every MoonBit backend, and every algorithm has to
work on its own. `verify/run_targets.ps1` checks both at once:

```powershell
powershell -ExecutionPolicy Bypass -File .\verify\run_targets.ps1
```

It runs the library test suite on all backends (`moon test --target all`),
builds the command line tool for each backend and then runs every algorithm
**alone** on every test image, comparing the result byte for byte with the
Java reference. The result is a matrix of backend x algorithm:

```
backend    otsu    multiotsu    autothreshold    mixture    blob    ...
native     ok      ok           ok               ok         ok      ...
js         ok      ok           ok               ok         ok      ...
wasm       ok      ok           ok               ok         ok      ...
wasm-gc    ok      ok           ok               ok         ok      ...
```

| backend | how it is run |
| --- | --- |
| `native` | `_build/native/debug/build/cmd/seg/seg.exe` |
| `js` | `node _build/js/debug/build/cmd/seg/seg.js` |
| `wasm` | `moonrun _build/wasm/debug/build/cmd/seg/seg.wasm` |
| `wasm-gc` | `moonrun _build/wasm-gc/debug/build/cmd/seg/seg.wasm` |

`moonrun` is the runner of the MoonBit toolchain
(`%USERPROFILE%\.moon\bin\moonrun.exe`). It only wires the file system
imports of the module when a sandbox policy is given, so the script passes
`verify/wasm_policy.json`; without it the wasm backends compute the right
results but write no files.

## Java quirks that are reproduced on purpose

The original code has a number of surprising behaviours. They are part of the
observable contract, so the port keeps them and documents them:

* **`RATS_` transposes the image.** The pixel arrays are kept in `[x][y]`
  order but handed to ImageJ's `FloatProcessor(float[][])`, which reads a 2D
  array as `[row][column]`. The output mask therefore has its width and height
  swapped with respect to the input, and the quadtree sums the *transposed*
  image. The quadtree level grid is assembled by `getLevel()`, which combines
  the four sub-trees in a transposed order, and the sum of an inner node is
  the sum of the four sums of its children — not the sum of the pixels of the
  node rectangle.
* **`SioxSegmentator` throws.** When the confidence matrix contains no known
  foreground pixel, `segmentate` raises
  `IllegalStateException("foreground signature does not exist")` at the first
  unknown pixel. The port reproduces the failure (`success = false`) and keeps
  the partially modified confidence matrix, exactly like the Java code leaves
  it behind.
* **`SIOX` compares with `<` and `<=` in different places**, the two stage
  clustering drops the cardinality slot of the cluster centroids (so the
  dimension becomes three), and the known background/foreground arrays are
  pre-allocated with the length of the whole image, so their unused tail
  takes part in the clustering.
* **`Multi_Thresholder` ships as a compiled plugin whose `NO_THRESHOLD`
  sentinel is `-808080.0`.** The value of `ImageProcessor.NO_THRESHOLD` is
  baked into the bytecode of the shipped class (seven `ldc2_w -808080.0d`
  constants), because the plugin was built against an ImageJ version that
  used that value; upstream ImageJ still defines the constant as
  `-808080.0` today, so this is not a deviation from ImageJ at all — it is
  simply the value of the shipped artifact. The port follows the **shipped
  class**, so that it reproduces the behaviour of the original plugin
  exactly; recompiling the plugin's source against a newer ImageJ would
  change the result of the `NO_THRESHOLD` branch (the threshold would be
  scaled instead of being left alone).
* **`Blob_Labeler` allocates `labels = new int[size/2]`**, which can overflow
  for large images; the port keeps the same allocation.
* **`Blob_Labeler` reads outside the image.** The plugin reads its neighbours
  through `ImageProcessor.get(x, y)`, which raises an
  `ArrayIndexOutOfBoundsException` when the read leaves the array: it reads
  the row 1 of an image that is one row high and the column -1 of an image
  that is one column wide. The port reports that failure
  (`blob*.failed = 1`) the way the reference harness observes it, instead of
  dying — a MoonBit panic cannot be caught and would take the whole tool
  with it.
* **`Math.round` is `floor(x + 0.5)`** and every `(int)` cast truncates
  towards zero, including for negative values. `java_compat.mbt` provides the
  Java semantics, including the wrapping of `int` arithmetic.

## The verification never trusts a leftover

`verify/run_verify.ps1` empties its output directories before it writes into
them, and `verify/compare.py` reports every file of the MoonBit output that
it does not expect — and, for the complete run, every file the Java output
does not expect either. Both are there because a file that is left over from
an earlier run hides the fact that the current run does not write it — a
missing output file would otherwise pass the comparison.

`verify/run_targets.ps1` does the same for the per backend output tree, and
`verify/run_edge_verify.py` empties the output tree of every backend before
it writes into it.

The committed golden (`ref/harness/golden/`) is the oracle of the 4 backend
matrix, so it must not be allowed to go stale: `verify/run_verify.ps1`
regenerates the Java output and compares it with the committed golden before
it compares anything else. A stale or hand edited golden is reported as such
instead of silently deciding the outcome. `verify/refresh_golden.ps1`
updates it deliberately.

## Building and checking

```powershell
moon check --deny-warn          # the gate: no warnings, no errors
moon build --target native      # builds _build/native/debug/build/cmd/seg/seg.exe
moon test --target all          # the unit tests on all four backends
```

The package metadata uses the modern `moon.pkg` format.

## Implementation notes (current state)

### Dependencies and replacements

The module has **no external MoonBit dependencies** (`moon.mod` declares none). Functionality previously provided by external packages is implemented in-repo:

* **zlib/DEFLATE/CRC32/Adler32 (PNG)**: `internal/zlib/` — CRC32/Adler32, bit I/O, Huffman tables, inflate/deflate (including stored/fixed/dynamic paths as needed), and zlib/gzip wrappers. Target-specific implementations are selected via `internal/zlib/moon.pkg` (`zlib_impl_js.mbt`, scalar/SIMD variants) for `js` / `native` / `wasm` / `wasm-gc`. The root package imports `riantr/moonbit_ImageSegmentation/internal/zlib` and `png_io.mbt` uses it for PNG chunk CRC (`@zlib.crc32`), IDAT compression (`@zlib.zlib_compress`), and decompression (`@zlib.zlib_decompress`); PNG structure/filtering/encoding logic remains in `png_io.mbt`.
* **Filesystem (CLI)**: `cmd/seg/fs/` — minimal `read_file_to_bytes`, `write_bytes_to_file`, `create_dir` with backend implementations in `fs_js.mbt`, `fs_native.mbt` (+ `fs_native.c`), and `fs_wasm.mbt`. The CLI imports this local package instead of `moonbitlang/x/fs`.

`https://mooncakes.io/user/riantr` was checked for drop-in replacements; no published package there provides the required filesystem or zlib/deflate/CRC functionality, so the implementations live in this repository.

### PNG and `riantr/moonbit_image@0.3.9`

`riantr/moonbit_image@0.3.9` can decode PNG (and detect dimensions/formats) but its `encode` supports only BMP/QOI — PNG encoding is not implemented (`EncodeNotImplemented`). This project’s CLI requires both PNG input decoding (grayscale or RGB→BT.601 luma) and PNG output encoding (`to-png`, `results-png`, grayscale/RGB). Because a PNG encoder is required and byte-level behavior must remain under project control for the reference-compatible pipeline, the current in-repo `png_io.mbt` + `internal/zlib` implementation is retained rather than replaced by `moonbit_image`.

### Static analysis notes

* `moonx riantr/moonbit_static_analysis@latest` (default, repo root): reports `actionable=1` in `internal/zlib/pkg.generated.mbti` — `unknown type 'Logger'` for `ZlibError::output(Self, &Logger)` (generated by `moon info` from the `Show` impl in `internal/zlib/zlib.mbt`). `moon check --deny-warn`, builds, and tests pass; this is treated as an analyzer/interface-resolution limitation rather than a source defect. The file is regenerated by `moon info`.
* The same run reports many `notices/unchecked` items and two `NOTPARSE` files (`internal/zlib/crc32_simd.mbt`, `internal/zlib/deflate_match_simd.mbt`) due to analyzer syntax/subset limits (e.g. inline `#|` block string forms), not confirmed code defects.
* `moonx riantr/LunaFlow@latest analyze --dir . --out reports/lunaflow` (level 1): `dead_code=0`, `unreachable=0`, `infinite_loop=0`, `taint_sinks=34`, `unsupported=262` — see `reports/lunaflow/riantr_moonbit_segmentation_0.1.0.*`.
