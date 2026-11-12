# Java reference harness

A headless harness that runs the **original, unmodified** Java segmentation
algorithms and writes deterministic golden outputs, so that a MoonBit port can
be verified byte-for-byte against them.

The algorithm sources are **read only** and are compiled verbatim:

| source | location |
|---|---|
| `Blob_Labeler.java`, `Multi_OtsuThreshold.java`, `Densitometry_1_Channel_.java`, `Densitometry_3_Channel_.java`, `RetFM_J.java` | `D:\src\java\algo\Segmentation` |
| `OtsuThresholding_.java`, `GrayLevelClass.java` | `..\java\Otsu_Thresholding\` |
| `MixtureModeling_.java`, `GrayLevelClassMixtureModeling.java` | `..\java\Mixture_Modeling\` |
| `AutoThresholder.java` | `..\java\Multi_Thresholder\` |
| `Watershed_Algorithm.java`, `WatershedStructure.java`, `WatershedPixel.java`, `WatershedFIFO.java` | `..\java\Watershed_Algorithm\` |
| `RATS_.java`, `RATSQuadtree.java` | `..\java\RATS_\` |
| `SioxSegmentator.java`, `Utils.java`, `ColorSignature.java`, `IntArrayList.java`, `IntHashMap.java`, `ControlJPanel.java` | `..\java\siox_\siox\` |
| `Multi_Thresholder.class`, `MultiThresholderPlot.class` (the **original compiled classes**, taken from the plugin jar) | `D:\src\java\algo\Segmentation\Multi_Thresholder.jar` |

## Build

```powershell
cd D:\src\moonbit\moonbit_segmentation\ref\harness
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

`build.ps1` compiles the stubs + the original sources + `Harness.java` with
`javac` into `out\` (`-d out`, so no `.class` file is ever written next to the
originals). Use `-SegmentationDir <dir>` if the originals live somewhere else.

Three SIOX files are **not** compiled, because they are ImageJ/Fiji user
interface entry points that do not compile against the headless stubs:

| file | why |
|---|---|
| `..\java\siox_\siox\SegmentationGUI.java` | needs `ij.process.Blitter`, `ImagePlus.changes` / `killRoi()`, a 4 argument `ImagePlus.setOverlay(...)`, `Overlay(Roi)`, `Roi.clone()` — none of them are reachable from the algorithms the harness drives. |
| `..\java\siox_\siox\Siox_Segmentation.java` | declares `package SIXX;` but instantiates `SegmentationGUI`, which lives in package `siox` → `cannot find symbol`. |
| `..\java\siox_\SIOX_Segmentation.java` | the Fiji plugin wrapper; it needs `SegmentationGUI` (see above) and `IJ.getImage()`. |

The algorithm itself (`SioxSegmentator` + `Utils` + `ColorSignature` +
`IntArrayList` + `IntHashMap`) is compiled verbatim and is what the harness
drives. `ControlJPanel.java` compiles cleanly (it only uses `ImagePlus` as a
parameter type) and is included for completeness.

`Multi_Thresholder.java` is **not** compiled either, and for a different
reason: the plugin is a GUI frame whose constructor builds a window, a
histogram plot and a whole panel of widgets. Compiling it would need a
complete AWT/ImageJ GUI. The harness only needs its four level mapping
helper methods (`scaleUp`, `scaleDown`, `scaleUpAndSet`, `setThreshold`), so
it uses the **original compiled class** of the plugin, taken from the plugin
jar by `build.ps1`, and drives it with reflection on an instance that is
allocated **without running the constructor** (`sun.misc.Unsafe.allocateInstance`).
That way no window is needed and the oracle is the artifact that was
actually shipped, not a recompilation of it.

## Run

```powershell
java -cp out Harness <input.gray> <width> <height> <outdir>
```

* `<input.gray>` — raw file with **exactly** `width*height` bytes, one 8 bit
  grey level per pixel, row major.
* `<outdir>` — created if missing; the golden outputs are written there.

The seven test images of `verify\images` are run with (from this directory):

```powershell
$cp = 'D:\src\moonbit\moonbit_segmentation\ref\harness\out'
$root = 'D:\src\moonbit\moonbit_segmentation'
$images = @{ 'ramp_blobs'=@(32,24); 'two_blobs'=@(24,20); 'gradient'=@(28,22);
             'checker'=@(16,16); 'uniform'=@(12,10); 'sparse'=@(24,12); 'ring'=@(22,18) }
foreach ($name in $images.Keys) {
  $w = $images[$name][0]; $h = $images[$name][1]
  $out = Join-Path $root "ref\harness\golden\$name"
  New-Item -ItemType Directory -Force -Path $out | Out-Null
  java -cp $cp Harness (Join-Path $root "verify\images\$name.gray") $w $h $out
}
```

The reference outputs of that run are kept in `ref\harness\golden\<name>\`
(28 files per image).

## The per backend check

`verify\run_targets.ps1` runs every algorithm **on its own** on every test
image, on every MoonBit backend, and compares the result with the golden
output of this directory:

```powershell
powershell -ExecutionPolicy Bypass -File .\verify\run_targets.ps1
```

The wasm backends are driven by `moonrun.exe` (the runner of the MoonBit
toolchain). It only wires the file system imports of the module when a
sandbox policy is given, so the script passes `verify\wasm_policy.json`; the
golden comparison of the wasm backends needs the files it writes.

A synthetic test image (32x24, a grey ramp plus three blobs) can be produced
with:

```powershell
$w=32; $h=24; $px=New-Object byte[] ($w*$h)
for($y=0;$y -lt $h;$y++){ for($x=0;$x -lt $w;$x++){
  $v=0; if($y -lt 2){$v=4+4*$x}
  if($x -ge 4  -and $x -lt 12 -and $y -ge 3  -and $y -lt 11){$v=200}
  if($x -ge 18 -and $x -lt 27 -and $y -ge 12 -and $y -lt 21){$v=120}
  if($x -ge 2  -and $x -lt 5  -and $y -ge 18 -and $y -lt 21){$v=90}
  $px[$y*$w+$x]=[byte]$v } }
[IO.File]::WriteAllBytes("test32x24.gray",$px)
java -cp out Harness test32x24.gray 32 24 golden
```

## Output files

| file | content |
|---|---|
| `scalars.txt` | one `key value` line per scalar, see the key list below |
| `otsu_image.raw` | `width*height` bytes: binary image of `OtsuThresholding_` (255 background, 0 for pixels `<= threshold`) |
| `multiotsu_region0.raw` … `multiotsu_region3.raw` | `width*height` bytes each: region `k` of `Multi_OtsuThreshold` (MLEVEL=4); keeps the original pixel value inside the region, 0 elsewhere |
| `mixture_image.raw` | `width*height` bytes: binary image of `MixtureModeling_` (255 where pixel `> threshold`, else 0) |
| `blob4_map.raw` | `width*height` little endian **int16** label map of `Blob_Labeler.doLabels4` (background = 0) |
| `blob8_map.raw` | same for `doLabels8` (8 connected) |
| `blob4_noedge_map.raw`, `blob8_noedge_map.raw` | the same two label maps with the static field `edge` set to **false** (the edge correction of the plugin is switched off) |
| `blob4_bgcol_map.raw`, `blob8_bgcol_map.raw` | the same two label maps with the static field `bgcol` set to **1** (a background colour other than 0) |
| `watershed.raw` | `width*height` bytes: binary image of `Watershed_Algorithm` (255 on the watershed lines) |
| `densitometry1.rgb.raw` | `width*height*3` bytes: RGB output of `Densitometry_1_Channel_` (tolerance 127, blnFill=false, blnInvr=false) |
| `densitometry3.rgb.raw` | same for `Densitometry_3_Channel_` (per channel tolerances 127) |
| `densitometry1_binary.rgb.raw`, `densitometry3_binary.rgb.raw` | the same two outputs with `blnFill = true` (the output is binarised) |
| `densitometry1_inverse.rgb.raw`, `densitometry3_inverse.rgb.raw` | the same two outputs with `blnInvr = true` (the output is inverted) |
| `densitometry1_roi.rgb.raw` | the 1-channel output with a **ROI** that covers only the middle half of the image (see `densitometryRoi` in `Harness.java`); the pixels outside the ROI keep their original value |
| `densitometry1_tol.rgb.raw` | the 1-channel output with the tolerance **64** instead of 127 |
| `densitometry3_tol.rgb.raw` | the 3-channel output with the tolerances **64 / 32 / 16** (one per channel, so that a mix-up of the channels would show up) |
| `retfm_gray.raw` | `width*height` bytes: `RetFM_J.convertToGrayscale` with `useChannels = {true,true,true}` |
| `retfm_otsu_image.raw` | `width*height` bytes: `RetFM_J.getThreshold(ip)` + `ip.threshold(t)` + `ip.invert()` |
| `retfm_red_gray.raw`, `retfm_green_gray.raw`, `retfm_blue_gray.raw` | the same conversion for a single channel (`{R}`, `{G}`, `{B}`) |
| `retfm_rg_gray.raw`, `retfm_rb_gray.raw`, `retfm_gb_gray.raw` | the same conversion for two channels (`{R,G}`, `{R,B}`, `{G,B}`) |
| `retfm_none_gray.raw` | the same conversion **without** any channel: the divisor is zero, the product becomes NaN and the original returns an all zero image |
| `retfm_red_gray.raw` | `width*height` bytes: `RetFM_J.convertToGrayscale` with `useChannels = {true,false,false}` (the **red** channel only) |
| `rats_mask.raw` | `rats.mask.width * rats.mask.height` bytes: binary mask of `RATS_` (0x00 / 0xFF). **The dimensions are swapped with respect to the input** (its width is the input *height*) — see below. |
| `siox_cm.raw` | `width*height*4` bytes: the confidence matrix of `SioxSegmentator.segmentate` after the segmentation, one little endian **float32** per pixel (`Float.floatToRawIntBits`), raster order. |
| `siox_mask.raw` | `width*height` bytes: the SIOX mask — 255 where the final `cm[i] >= 0.5f`, else 0. |
| `multithresholder.txt` | the results of the four level mapping helpers of the `Multi_Thresholder` plugin (72 lines, see below). |

RGB files are dumped in **R, G, B** order (the packed pixel is `0x00RRGGBB`,
red in the most significant byte).

### `multithresholder.txt`

The file holds the results of the level mapping helpers of the original
`Multi_Thresholder` class. Every line has the shape

```
<kind> t=<threshold> <operation> => <result>...
```

and every result is the **raw IEEE-754 bits** of a double, written as 16 hex
digits, so that the MoonBit port can be compared byte for byte.

The matrix covers the two processor kinds of the plugin (8 bit with the value
range 0..255 and 16 bit with the range 0..65535) and the four thresholds 0,
73, 128 and 255. For every combination it runs the nine cases

```
scaleUp(0,max)                     scaleDown(0,max)
scaleUpAndSet(0,t)                 scaleUpAndSet(t,max)
scaleUpAndSet(NO_THRESHOLD,max)    setThreshold(dark=0|1,inverted=0|1)
```

which is 2 × 4 × 9 = 72 lines. The table does not depend on the image that is
segmented.

The `NO_THRESHOLD` sentinel is the value of the ImageJ version the plugin was
built against: **-808080.0**. It is baked into the bytecode of the shipped
class (seven `ldc2_w -808080.0d` constants), so the stub
`ij.process.ImageProcessor.NO_THRESHOLD` uses the very same value — a modern
ImageJ would use `Double.MAX_VALUE` there, and recompiling the plugin's
source against it would change the result of the `NO_THRESHOLD` branch (the
threshold would be scaled instead of being left alone).

## `scalars.txt` key list (exact order)

```
otsu.threshold
multiotsu.level
multiotsu.t1
multiotsu.t2
multiotsu.t3
multiotsu.t4
multiotsu.level2.t1
multiotsu.level2.t2
multiotsu.level3.t1
multiotsu.level3.t2
multiotsu.level3.t3
multiotsu.level5.t1
multiotsu.level5.t2
multiotsu.level5.t3
multiotsu.level5.t4
multiotsu.level5.t5
autothreshold.Huang
autothreshold.Intermodes
autothreshold.IsoData
autothreshold.Li
autothreshold.MaxEntropy
autothreshold.Mean
autothreshold.MinError(I)
autothreshold.Minimum
autothreshold.Moments
autothreshold.Otsu
autothreshold.Percentile
autothreshold.RenyiEntropy
autothreshold.Shanbhag
autothreshold.Triangle
autothreshold.Yen
mixture.threshold
mixture.mu1
mixture.variance1
mixture.mu2
mixture.variance2
mixture.errorMin
mixture.diffMu
mixture.directThreshold
mixture.realThreshold
mixture.bits.mu1
mixture.bits.variance1
mixture.bits.mu2
mixture.bits.variance2
mixture.bits.errorMin
mixture.bits.diffMu
mixture.bits.realThreshold
blob4.numberOfLabels
blob4.failed
blob8.numberOfLabels
blob8.failed
blob4.noedge.numberOfLabels
blob4.noedge.failed
blob8.noedge.numberOfLabels
blob8.noedge.failed
blob4.bgcol.numberOfLabels
blob4.bgcol.failed
blob8.bgcol.numberOfLabels
blob8.bgcol.failed
retfm.otsuThreshold
retfm.red.otsuThreshold
retfm.green.otsuThreshold
retfm.blue.otsuThreshold
retfm.rg.otsuThreshold
retfm.rb.otsuThreshold
retfm.gb.otsuThreshold
retfm.none.otsuThreshold
rats.mask.width
rats.mask.height
rats.failed
siox.success
siox.failed
```

* `otsu.threshold` — parsed from the `IJ.showMessage("Found threshold : N")`
  message emitted by `OtsuThresholding_`.
* `multiotsu.tN` — `threshold[N-1]` of the algorithm's `int[4]` threshold array.
  `findMaxSigma` hard codes `t[0] = 0`, so `multiotsu.t1` is always `0` and
  `multiotsu.t2..t4` are the three computed thresholds. The values are obtained
  through the algorithm's own public methods (`buildHistogram` →
  `buildLookupTables` → `findMaxSigma`), i.e. the same code path as `run()`.
* `autothreshold.*` — `new AutoThresholder().getThreshold(method, histogram)`
  for the 15 names of `AutoThresholder.getMethods()` (note the parentheses in
  `MinError(I)`), using the 256 bin histogram of the input image.
* `mixture.*` — parsed from the `IJ.write` messages of `MixtureModeling_`
  (`"Mu1 : …"`, `"ErrorMin : …"`, `"Diff Mu : …"`, `"Direct threshold : …"`,
  `"Real threshold : …"`). The numbers are written exactly as printed.
  `mixture.threshold` is the integer threshold actually used to binarize
  (`(int)` of the "Real threshold" value).
* `mixture.bits.*` — the raw IEEE-754 bit pattern of the corresponding float
  (`Float.floatToRawIntBits`), written as a signed 32 bit integer. The values
  are the plugin's own floats: `Float.toString` → `Float.parseFloat` is an
  exact round trip, so parsing the printed numbers reproduces the plugin's
  float bit for bit. `mixture.bits.diffMu` and `mixture.bits.realThreshold`
  are the bit patterns of the two floats that had no bit pattern of their own
  before; they are compared **exactly** (as integers, never with a
  tolerance).
* `blob4.numberOfLabels` / `blob8.numberOfLabels` — the label count of
  `doLabels4` / `doLabels8`, read from the result image title
  (`"blobs 4c <n>"`).
* `blob4.failed` / `blob8.failed` — `1` when the plugin raised an exception
  (the label map is then empty and the label count is `0`), `0` otherwise.
* `retfm.otsuThreshold` — `RetFM_J.getThreshold(ip)` on the converted
  grayscale image (the plugin thresholds *that* image, see the deviations
  below).
* `rats.mask.width` / `rats.mask.height` — the dimensions of `rats_mask.raw`,
  i.e. the dimensions of the mask image that `RATS_` produced. They are
  **swapped** with respect to the input (the mask width is the input height),
  because the plugin hands a `[x][y]` array to `FloatProcessor(float[][])`.
  Both are `0` if `RATS_` failed.
* `rats.failed` — `1` when `RATS_` raised an exception (the mask is then
  empty), `0` otherwise.
* `siox.success` — `1` when `SioxSegmentator.segmentate` returned `true`, `0`
  when it returned `false` (empty background signature) or threw.
* `siox.failed` — `1` when `segmentate` threw the
  `IllegalStateException`, `0` otherwise. Together with `siox.success` it
  distinguishes the two failure modes, which the confidence matrix alone
  only shows indirectly.
* `multiotsu.level2.*`, `multiotsu.level3.*`, `multiotsu.level5.*` — the
  thresholds of `Multi_OtsuThreshold` for the other three level counts the
  plugin offers. `findMaxSigma(int, float[][], int[])` is public, so the
  harness calls it directly with `MLEVEL` = 2, 3 and 5 and reports the
  thresholds it computes (`levelN.tK`). The plugin itself hard codes
  `MLEVEL = 4` (that is the default of its dialog), so the port has to
  support the other three as well to match these keys.
* `blob4.noedge.*`, `blob8.noedge.*` — the label count and the failure flag of
  the run with the static field `edge` set to **false** (the edge correction
  of the plugin is switched off).
* `blob4.bgcol.*`, `blob8.bgcol.*` — the label count and the failure flag of
  the run with the static field `bgcol` set to **1** (a background colour
  other than 0).
* `retfm.red.otsuThreshold` — the Otsu threshold of the **red channel only**
  grayscale conversion of `RetFM_J` (`useChannels = {true,false,false}`).
* `retfm.green.otsuThreshold`, `retfm.blue.otsuThreshold`,
  `retfm.rg.otsuThreshold`, `retfm.rb.otsuThreshold`,
  `retfm.gb.otsuThreshold`, `retfm.none.otsuThreshold` — the same for every
  other selection of the channels. The plugin averages the **selected**
  channels, so the divisor is the number of the selected channels and every
  selected channel contributes its own plane; the empty selection divides by
  zero, the product becomes NaN and the original returns an all zero image.

The `*.failed` keys exist so that a **degraded reference cannot hide behind a
degraded port**: the harness catches the exceptions of the original plugins
and continues, so without them a crash on both sides would look like a
perfect match.

## Stub semantics (`stub\ij\**`)

The stubs implement **only** the ImageJ API that the original sources touch,
and they implement it with ImageJ's own semantics:

* `ij.IJ` — no-ops, except `IJ.write` and `IJ.showMessage` **record** their
  text into `public static List<String> IJ.MESSAGES` (call order) and
  `IJ.log` records into `IJ.LOGS`. `IJ.debugMode = false`,
  `IJ.versionLessThan(...)` returns false, `IJ.setupDialog(imp, flags)`
  returns `flags`.
* `ij.ImagePlus` — every constructed instance is appended to
  `public static List<ImagePlus> ImagePlus.CREATED` (construction order); that
  is how the harness finds the images the algorithms create in `run()`.
  `show()` / `close()` / `setOverlay()` are no-ops, `setCalibration(Object)`
  accepts anything. `getShortTitle()` is ImageJ's: the title without a
  trailing `.tif` (`RATS_` names its result image with it). `isLocked()` is
  always false, `lock()` / `unlock()` are no-ops.
* `ij.Macro` — `getOptions()` returns `null`: the harness never runs inside a
  macro, so a plugin that would read its parameters from a macro falls back to
  its own dialog (and therefore to the dialog defaults).
* `ij.util.Tools` — only `parseDouble(String)`; the `ij.util` package has to
  exist because `RATS_.java` imports `ij.util.*`.
* `ij.NewImage` — `FILL_WHITE = 0`, `FILL_BLACK = 1`. `createByteImage` fills
  the byte image with **255** (white) or **0** (black); `createRGBImage` fills
  with `0xFFFFFF` or `0x000000`.
* `ij.process.ImageProcessor` — owns the geometry and the ROI. The ROI
  defaults to the whole image `(0,0,width,height)`; `threshold(int)` sets
  `255` where `get(x,y) > level` else `0`; `invert()` is ImageJ's `255 - v`.
  `getPixelValue(x,y)` returns the pixel value in the native range of the
  processor (ImageJ returns a `float` there). `setRoi(java.awt.Rectangle)`
  and `setRoi(ij.gui.Roi)` both set the ROI; the densitometry variant uses a
  real (rectangular) ROI, so the ROI is no longer always the whole image.
* `ij.process.ByteProcessor` — **signed** `byte[]`; `get(x,y)` returns
  `pixels[..] & 0xff`, `set(x,y,v)` stores `(byte) v`, `getHistogram()` counts
  the unsigned values. `getPixelValue(x,y)` returns the unsigned byte value
  as a `float`.
* `ij.process.ShortProcessor` — signed `short[]`, plus the linear (index)
  accessors `get(int)` / `set(int,int)` that `Blob_Labeler` uses.
* `ij.process.FloatProcessor` — `getf`/`setf`, `multiply(double)` (evaluated
  in double precision, like ImageJ).
  * `getPixelValue(x,y)` returns the **float** value of the pixel (it is not
    truncated to an int) — `RATSQuadtree.getSumFloat` sums the gradient
    energies with it. It reads the flat index `y * width + x` **without** a
    bounds check (upstream ImageJ would return `NaN` outside the image);
    see the deviations section below.
  * `FloatProcessor(float[][] pixels)` reads the 2D array as **`[row][column]`**:
    the image **width** is `pixels[0].length` (the length of the inner
    arrays), the image **height** is `pixels.length` (the number of rows) and
    the pixel (column, row) holds `pixels[row][column]`:

    ```java
    public FloatProcessor(float[][] pixels) {
        this(pixels[0].length, pixels.length);
        for (int y = 0; y < pixels.length; y++) {
            int rowoffset = y * width;
            for (int x = 0; x < pixels[0].length; x++)
                setf(rowoffset + x, pixels[y][x]);
        }
    }
    ```

    This is the semantics the MoonBit port implements (`FloatImage::from_2d`).
    It differs from ImageJ 1.x master, whose `FloatProcessor(float[][])` sets
    `width = array.length`, `height = array[0].length` and *transposes* the
    data (`pixels[y*width+x] = array[x][y]`); with upstream ImageJ the RATS
    mask would keep the dimensions of the input instead of swapping them.
  * `convertToByte(boolean clip)`:

    ```java
    if (clip) { if (pix[i] > 255) bp[i] = (byte)255; else if (pix[i] < 0) bp[i] = 0; else bp[i] = (byte)pix[i]; }
    else bp[i] = (byte)(pix[i] + 0.5);
    ```

    With `clip == true` the values are clipped into `0..255` (RATS_ calls
    `convertToByte(true)`); with `clip == false` they are rounded and **not**
    clipped (this is the path of `RetFM_J.convertToGrayscale`, whose grey
    values are always inside `0..255`).

* `ij.process.ColorProcessor` — `int[]` packed `0x00RRGGBB`;
  `getChannel(1|2|3)` returns the R/G/B plane as a `ByteProcessor`,
  `convertToByte(boolean)` uses the standard luminance weights
  (`0.299 R + 0.587 G + 0.114 B`), `convertToFloatProcessor()` returns the
  luminance as floats.
* `ij.process.BinaryProcessor` — a 0/255 view over a `ByteProcessor`.
* `ij.gui.GenericDialog` — `showDialog()` does nothing, `wasCanceled()` returns
  false, `wasOKed()` returns true, so every algorithm runs with its **default**
  parameter values. `getNextNumber()` / `getNextBoolean()` return the default
  that was registered for the widget. `getNextChoiceIndex()` returns the index
  of the default item: `Multi_OtsuThreshold` registers `{"2","3","4","5"}` with
  default `"4"` → index **2** → `MLEVEL = 2 + 2 = 4`.
* `ij.gui.Toolbar` — foreground `Color(255,255,255)`, background
  `Color(0,0,0)` (the colours the densitometry plugins compare against).
* `ij.gui.Roi` — `(x,y,w,h)` with `POLYGON = 2`.
* `ij.plugin.filter.PlugInFilter` — the ImageJ 1.x flag constants
  (`DOES_8G`, `DOES_8C`, `DOES_16`, `DOES_32`, `DOES_RGB`, `DOES_STACKS`,
  `NO_CHANGES`, `NO_UNDO`, `PARALLELIZE_STACKS`, `SUPPORTS_MASKING`, `DONE`,
  …), `setup` + `run`. The harness never inspects the flags.
* `ij.plot.PlotWindow` — headless no-op (`setLimits`, `draw`).
* `ij.plugin.frame.PlugInFrame` — extends `java.awt.Frame` (like the real
  one), because the JVM verifier needs the frame hierarchy to resolve the
  AWT calls of the original `Multi_Thresholder` class. The harness never
  instantiates a frame, so the headless environment is not a problem.
* `ij.plugin.frame.Recorder`, `ij.gui.GUI`, `ij.gui.TrimmedButton`,
  `ij.measure.Measurements`, `ij.measure.StackStatistics`,
  `ij.process.ImageStatistics` — the types the original `Multi_Thresholder`
  class and its `MultiThresholderPlot` refer to. They only have to exist so
  that the shipped class links; the harness never calls into them.
* `ij.process.ImageProcessor` — additionally owns the value range
  (`getMin()` / `getMax()`: 0..255 for the byte processor, 0..65535 for the
  short one) and the threshold range (`setThreshold(double,double,int)` /
  `getMinThreshold()` / `getMaxThreshold()`), which the `Multi_Thresholder`
  helpers read and write. `NO_THRESHOLD` is `-808080.0`, the value of the
  ImageJ version the plugin was built against (see `multithresholder.txt`).

## Driving the original classes

* `OtsuThresholding_`, `MixtureModeling_`, `Watershed_Algorithm`,
  `Multi_OtsuThreshold` — `run(ip)` is called on a fresh `ByteProcessor`; the
  result image is taken from `ImagePlus.CREATED` **with a size check** (the
  helper `created(count, width, height, what)` fails loudly when the plugin
  did not produce the expected number of images of the expected size, instead
  of silently taking the last one). The thresholds of `Multi_OtsuThreshold`
  are additionally computed for `MLEVEL` = 2, 3 and 5 through the public
  `findMaxSigma(int, float[][], int[])`.
* `Blob_Labeler` — the private static `segment` flag is set to **false** by
  reflection (the optional vectorization step is skipped, the labeling itself
  is untouched); `neighb8` is toggled by reflection for the 4 and the 8
  connected run. The plugin is run in **six** configurations — the defaults
  (`bgcol = 0`, `edge = true`), the same without the edge correction and the
  same with `bgcol = 1` — because the two static fields are read by the
  plugin and two of the three paths were never exercised before. With the
  defaults the original code overwrites the first row and the first column of
  its input with 0 — every run therefore gets its **own fresh copy** of the
  image.
* `Densitometry_1_Channel_` / `Densitometry_3_Channel_` — `run(ip)` on a
  `ColorProcessor` built from the grey input (the **non neutral** colours of
  deviation 21, not `R = G = B`); the plugin writes the transformed values
  back into the processor's `int[]`. The static fields `blnFill` and `blnInvr`
  are set by reflection, so the binarised and the inverted variants are
  produced as well, one run works on a **ROI** (the middle half of the image)
  instead of the whole image, and one run uses another **tolerance**
  (`intTol` = 64, `intRtol` / `intGtol` / `intBtol` = 64 / 32 / 16).
  Every run sets **all** of the static fields explicitly (`configure1` and
  `configure3`), because the plugins read them statically: a field that was
  left over from an earlier run would silently change the next one.
* `RetFM_J` — `useChannels` is set to `{true,true,true}` by reflection;
  `getThreshold(ByteProcessor)` and `convertToGrayscale(ColorProcessor)` are
  called directly. Every other selection of the channels is driven as well
  (a single channel, two channels and no channel at all).
* `RATS_` — the plugin is driven with its **own defaults**: `sigma = 25.0`,
  `lambda = 3.0` and the minimum leaf size `min(floor(w/5), floor(h/5))`
  that `RATS_.run()` derives from the image dimensions (`Macro.getOptions()`
  is `null`, so the plugin asks its `GenericDialog`, and the stub answers with
  the dialog defaults). `setup("", imp)` is called with an `ImagePlus` that
  wraps the input, because `RATS_` names its result image after
  `imp.getShortTitle()`. The result is the last entry of `ImagePlus.CREATED`.
  The threshold itself is private (`RATS_.rats()`), so it is not reported.
* `SioxSegmentator` — `new SioxSegmentator(w, h, new float[]{0.64f, 1.28f,
  2.56f})` and `segmentate(argb, cm, 1, 4.0)`. The ARGB image is built from
  the grey input with `argb[i] = 0xFF000000 | (v << 16) | (v << 8) | v`.
  The confidence matrix is built **deterministically** from the grey levels:

  | grey level `v` | `cm[i]` | meaning |
  |---|---|---|
  | `v <= 63` | `0.0f` | known background |
  | `v >= 192` | `1.0f` | known foreground |
  | otherwise | `0.5f` | unknown |

  (`SioxSegmentator` itself treats `cm <= 0.1` as known background and
  `cm >= 0.8` as known foreground.)
* `Multi_Thresholder` — the **original compiled class** of the plugin (taken
  from the plugin jar) is loaded with `Class.forName`, allocated without
  running its constructor and driven with reflection. The two fields the
  helper methods read are set for every case: the `darkBackground` check box
  (a real `java.awt.Checkbox`) and the `invertedLut` flag. The methods are
  called on a fresh processor per case and the results are read back from
  `getMinThreshold()` / `getMaxThreshold()`.

## Deviations from stock ImageJ (all forced by the original sources)

1. **`ij.gui.PlotWindow` exists in addition to `ij.plot.PlotWindow`.**
   `Multi_OtsuThreshold` imports `ij.gui.*` (not `ij.plot.*`), and ImageJ 1.x
   kept the plot window in `ij.gui`, so the class has to be reachable from
   `ij.gui` for the original to compile. `ij.gui.PlotWindow` extends
   `ij.plot.PlotWindow`.
2. **`ij.process.ByteProcessor(int, int, ByteProcessor)` copy constructor.**
   `RetFM_J` builds a `ByteProcessor` from `ColorProcessor.getChannel(int)`;
   the pixels of the source processor are copied verbatim.
3. **`ImageProcessor.setRoi(ij.gui.Roi)` overload.** `RetFM_J` calls
   `ip.setRoi(r)` with an `ij.gui.Roi`; only its bounding box is honoured (no
   non rectangular ROI is ever used).
4. **`IJ.run(String)` overload.** `RetFM_J` calls `IJ.run("Flatten")`.
5. **`ij.gui.DialogListener.dialogItemChanged(GenericDialog, java.awt.AWTEvent)`**
   — the `AWTEvent` of the original sources is `java.awt.AWTEvent` (resolved
   through their `import java.awt.*`), not `java.awt.event.AWTEvent`.
6. **`GenericDialog extends java.awt.Component`.** `RetFM_J` hands the dialog to
   `javax.swing.JFileChooser.showOpenDialog(Component)`. No window is created,
   so the harness stays headless.
7. **`ColorProcessor.putPixel` stores the value verbatim** (ImageJ would OR
   `0xff000000` into it). Not observable in any golden output, because the RGB
   bytes are always read from the low 24 bits.
8. **`ImageStatistics.area`** counts the non zero pixels of the ROI (an
   approximation). It is only used by `RetFM_J.run()`, which the harness does
   not call; `pixelCount` (the ROI pixel count) is exact and is what
   `RetFM_J.getThreshold` uses.
9. **`MixtureModeling_` is driven with `run(ip)` only** (no `setup()`), so the
   optional histogram overlay (`runHistogram`) is not drawn. That only removes
   a debug image; no emitted value changes.
10. **`ij.Macro` and `ij.util.Tools` exist.** `RATS_.java` imports `ij.util.*`
    and calls `Macro.getOptions()` / `Tools.parseDouble(String)`, so both
    classes have to exist for the original to compile. `Macro.getOptions()`
    returns `null` (no macro is running), which makes `RATS_` use its dialog
    defaults.
11. **`ImagePlus.isLocked()` / `lock()` / `unlock()` and `IJ.setTool(int)` /
    `IJ.makePoint(int,int)` / `Toolbar.POINT` exist.** They are only used by
    `RATSQuadtree.drawBounds()` / `drawCenter()`, which the harness never
    calls, but the methods have to exist for the original to compile.
12. **`FloatProcessor(float[][])` and `convertToByte(boolean)` follow the
    semantics of the MoonBit port, not of ImageJ 1.x master** (see the stub
    section above for the exact code and the difference). The RATS mask of
    this harness is therefore the transposed mask with swapped dimensions.
13. **`FloatProcessor.getPixelValue(x,y)` reads the flat index
    `y * width + x` without a bounds check** (upstream ImageJ returns `NaN`
    for coordinates outside the image). This matters for RATS: the plugin
    sums the **transposed** float image (its width is the image *height*)
    with a quadtree rectangle that spans the *original* image, so for every
    input that is not square it addresses the float image outside its
    width. With the upstream `NaN` behaviour every such sum becomes `NaN`,
    the leaf fails the Wilkinson test, the threshold becomes `-1` and the
    whole image turns into foreground. The MoonBit port (`FloatImage::get`)
    reads the same flat index without a bounds check — and the flat index
    always stays inside the array (the largest one is
    `(h-1)*h + (w-1) < w*h` for `w >= h`), so the port and this harness
    agree. With the flat read the RATS masks are the expected ones (the
    bright blobs of `ramp_blobs`, the five bright pixels of `sparse`, the
    checker board of `checker`). For `w < h` the index leaves the array, both
    sides fail and both report an empty mask (see the notes on the outputs).
14. **`ShortProcessor.getMax()` returns the fixed `65535.0`** (and `getMin()`
    the fixed `0.0`), while upstream ImageJ returns the range of the *pixels*.
    The harness only uses a blank 1x1 `ShortProcessor` to drive the
    `Multi_Thresholder` helpers, and upstream would therefore take the
    `max > min == false` branch and return `NO_THRESHOLD` where the stub
    scales the value. **36 of the 72 lines of `multithresholder.txt` are
    therefore not what the plugin produces under a stock ImageJ.** This is
    the second (and last) place where the reference deviates from a stock
    ImageJ; the port follows the reference.
15. **`ImageProcessor.setThreshold(int, int)` stores the pair verbatim.**
    Upstream `ShortProcessor.setThreshold` resets *both* bounds when the
    lower bound is `NO_THRESHOLD`; the stub keeps the pair as it is. This is
    visible in the `scaleUpAndSet(NO_THRESHOLD,65535)` line of
    `multithresholder.txt`.
16. **`ColorProcessor.convertToFloatProcessor()` computes in float**
    (`0.299f*r + 0.587f*g + 0.114f*b`), upstream computes in double and
    casts the result. The difference is at most one unit in the last place
    and it is not observable in the golden outputs, because `RetFM_J` uses
    `ByteProcessor.convertToFloatProcessor` and not this one.
17. **`ShortProcessor.getHistogram()` returns 256 bins**, upstream returns
    65536. Only the 16 bit `Multi_Thresholder` cases use a
    `ShortProcessor`, and they do not read a histogram.
18. **`ImageProcessor.threshold(int)` honours the ROI**, upstream
    `ByteProcessor.threshold` loops over the whole array. The ROI of the
    harness is always the whole image, so the two agree.
19. **`ByteProcessor.getHistogram()` counts the whole array**, upstream counts
    the ROI only. Same argument as above.
20. **`ImageProcessor.getStatistics()` fills only `pixelCount`, `area` and
    `mean`**, upstream returns the full statistics. Only `pixelCount` is
    consumed (`RetFM_J.getThreshold`).
21. **The colour image of the harness is not neutral.** The grey level `v` is
    rendered as `R = v`, `G = 3v/4`, `B = 255 - v` (see `color` and
    `packColor` in `Harness.java`). With a neutral `R = G = B` image a plugin
    that mixes up the colour channels would pass the verification unnoticed,
    because every channel would carry the same value. The MoonBit CLI builds
    its RGB image the same way (`gray_to_rgb` in `cmd/seg/main.mbt`).
22. **The `RetFM_J` threshold belongs to the converted grayscale image.**
    The plugin converts the colour image to grayscale, computes the Otsu
    threshold of *that* image and thresholds it (`RetFM_J.java:190-196`); the
    harness does the same. With a neutral colour image the converted
    grayscale and the grey source are the same, with the non neutral colours
    of point 21 they are not.

## Diagnostic: `tools\LiCrossCheck.java`

`tools\LiCrossCheck.java` is a **gate** (it is run by
`verify\verify_all.ps1`, step 4) and a diagnostic at the same time. It drives
the **original** `AutoThresholder.Li` with a thousand hostile histograms and
checks the checksum of the thresholds against a fixed constant:

```
checked       : 1000 hostile histograms
threshold range: 0 .. 114
checksum      : 333878761
```

The histograms are generated by a linear congruential generator, so the
MoonBit test `the Li threshold matches the original AutoThresholder on
hostile histograms` (`segmentation_test.mbt`) builds **exactly the same**
histograms and is pinned to the **same** checksum. The Java tool fails when
the original computes something else, the MoonBit test fails when the port
does — a divergence shows up on the side that caused it.

The tool answers a question of the QA report, which claimed that the `Li`
method "can index outside the 256 bin histogram". It cannot: the iteration
variable of `Li` is the logarithmic mean of two means that both live in
`0..255`, so the threshold never exceeds 255. The hostile histograms (an
empty one, a single bin, the two extreme bins, a sparse and a dense random
one) confirm it.

```powershell
javac -encoding UTF-8 -cp out -d tools\out tools\LiCrossCheck.java
java -cp "out;tools\out" LiCrossCheck
```

## Gate: `tools\AutoThresholderCrossCheck.java`

`tools\AutoThresholderCrossCheck.java` is a **gate** (it is run by
`verify\verify_all.ps1`, step 6). It extends the cross check of the `Li` method
to **all fifteen** threshold methods of the original `AutoThresholder` — the QA
report had listed "the `Li` cross check covers one method of the fifteen" as a
residual risk.

```
Huang          checksum= 107048180 range=-1..141
Intermodes     checksum= 880944531 range=-1..143
IsoData        checksum= 273794009 range=116..131
Li             checksum= 431563462 range=0..109
MaxEntropy     checksum= 686060938 range=-1..135
Mean           checksum= 956456453 range=0..255
MinError(I)    checksum= 517811581 range=0..255
Minimum        checksum= 924797356 range=-1..252
Moments        checksum= 662340405 range=-1..255
Otsu           checksum= 901090455 range=119..254
Percentile     checksum= 934842986 range=-1..136
RenyiEntropy   checksum= 670314028 range=0..135
Shanbhag       checksum= 879143749 range=-1..136
Triangle       checksum= 799090228 range=1..254
Yen            checksum= 299050832 range=-1..135
combined   : 981417562
checked    : 64 hostile histograms per method, 15 methods
ALL-PASS: all fifteen methods of the original AutoThresholder match the pinned checksums
```

The generator is **restarted for every method**, so every method sees the same
sequence of the 64 hostile histograms and the checksum of a method depends on
that method alone. The MoonBit test `the fifteen threshold methods match the
original AutoThresholder on hostile histograms` (`segmentation_test.mbt`) builds
**exactly the same** histograms and is pinned to the **same** constants, so a
divergence shows up on the side that caused it. The tool also compares the
names and the order of the method table of the original with the ones of the
port.

Every method of the original was measured on all eight hostile shapes before
the check was written: not one of them raises an exception (24000 calls), so a
method that throws here would be a defect of the original and not of the port.

```powershell
javac -encoding UTF-8 -cp out -d tools\out tools\AutoThresholderCrossCheck.java
java -cp "out;tools\out" AutoThresholderCrossCheck
```

## Gate: `tools\BlobCrossCheck.java`

`tools\BlobCrossCheck.java` is a **gate** (it is run by
`verify\verify_all.ps1`, step 7). It fuzzes the labeling of the blobs — the
most intricate algorithm of the port — against the **original**
`Blob_Labeler`:

```
blob4          checksum= 717071813 failed rounds=6
blob8          checksum=  41598674 failed rounds=6
blob4_noedge   checksum=  99965418 failed rounds=22
blob8_noedge   checksum= 549135478 failed rounds=29
blob4_bgcol    checksum= 470942760 failed rounds=6
blob8_bgcol    checksum= 776978089 failed rounds=6
combined   : 482399897
checked    : 96 random image(s) per configuration, 6 configurations
ALL-PASS: all six configurations of the original Blob_Labeler match the pinned checksums
```

The six configurations are the ones of the harness: the 4 and the 8 connected
neighbourhood, with and without the edge correction, and the background colour
0 and 1. The images are generated by the same linear congruential generator as
in the other cross checks, so the MoonBit test `the blob labeler matches the
original Blob_Labeler on random images` (`segmentation_test.mbt`) builds
**exactly the same** images and is pinned to the **same** constants.

The **failure path** is part of the comparison: the plugin allocates
`int[] labels = new int[size/2]`, so it raises an `ArrayIndexOutOfBoundsException`
when it has more labels than `size/2`, and it reads outside the image when the
image is one row or one column high and the edge correction is off. The number
of failing images per configuration is pinned as well — the configuration
without the edge correction fails far more often, because then the border of
the image is labeled as well.

```powershell
javac -encoding UTF-8 -cp out -d tools\out tools\BlobCrossCheck.java
java -cp "out;tools\out" BlobCrossCheck
```

## Gate: `tools\ThresholdCrossCheck.java`

`tools\ThresholdCrossCheck.java` is a **gate** (it is run by
`verify\verify_all.ps1`, step 8). It fuzzes the two threshold plugins of the
original — `OtsuThresholding_` and `Multi_OtsuThreshold`:

```
otsu         checksum= 600913906 images=64
multiotsu2   checksum= 828034254 images=32
multiotsu3   checksum=  59404614 images=16
multiotsu4   checksum= 289251653 images=8
combined   : 697755534
checked    : 4 configurations
ALL-PASS: the original OtsuThresholding_ and Multi_OtsuThreshold match the pinned checksums
```

The image corpus is a set of pictures, and a picture does not contain a
histogram on purpose — a histogram is exactly what these two plugins consume.
The eight shapes of the fuzz are the ones a corpus does not produce: sixteen
grey levels, two levels, a ramp, a single grey level, sparse noise on a
background, completely black, a gradient and two halves with two levels. The
generator is advanced once per pixel in **every** shape, so the two sides
consume the same numbers even in the shapes that do not use them.

The number of images is scaled by the cost of the search (one loop over the
grey levels for the level count 2, two for 3, three for 4). The level count 5
is **not** fuzzed — four nested loops are about 160 million iterations per
histogram — but the corpus compares it on every one of its 25 images.

```powershell
javac -encoding UTF-8 -cp out -d tools\out tools\ThresholdCrossCheck.java
java -cp "out;tools\out" ThresholdCrossCheck
```

## Gate: `tools\MixtureCrossCheck.java`

`tools\MixtureCrossCheck.java` is a **gate** (it is run by
`verify\verify_all.ps1`, step 9). It fuzzes the mixture model of the original
— the last of the histogram algorithms:

```
checksum   : 166889024
checked    : 64 random image(s), 0 failed
ALL-PASS: the original MixtureModeling_ matches the pinned checksum
```

The plugin fits two Gaussian components to the histogram and reports the mean,
the variance, the fitting error and two thresholds. Its output is **floating
point**, and the corpus compares it bit for bit — but only on the images of
the corpus. The degenerate histograms (a single bin, two levels, completely
black) are where one component has no pixels at all: its variance is zero and
its density function returns zero for every grey level, so the fit degenerates
(the result stays finite — the plugin never produces a NaN).

The tool drives the original plugin and scrapes the numbers it prints through
`ij.IJ.MESSAGES`; the floating point values are folded into the checksum
through their raw IEEE-754 bit patterns, as unsigned 32 bit values, so that
the checksum stays positive on both sides.

```powershell
javac -encoding UTF-8 -cp out -d tools\out tools\MixtureCrossCheck.java
java -cp "out;tools\out" MixtureCrossCheck
```

## Gate: `tools\SioxCrossCheck.java`

`tools\SioxCrossCheck.java` is a **gate** (it is run by
`verify\verify_all.ps1`, step 10). It fuzzes the SIOX segmentation of the
original against the MoonBit port on random **colour** images:

```
checksum   : 15384133
checked    : 64 random image(s), 8 failed
succeeded  : 48, returned false: 16
ALL-PASS: the original SioxSegmentator matches the pinned checksum
```

SIOX is the only algorithm of the suite whose **colour conversion** runs on a
platform dependent power (the sRGB gamma with the exponent 2.4 and the CIELAB
cube root with the exponent 1/3), and the corpus could not have caught it: all
twenty five images of the corpus are grey scale, and a grey scale image has
`R = G = B`, so the clusters would be decided by the grey level alone. The
plugin, on the other hand, is meant for photographs.

The tool drives the **original** `siox.SioxSegmentator` with 64 random colour
images (eight shapes: dark/bright halves, a dark and an unknown half,
completely random colours, a gradient, completely black, completely white,
dark/bright with random colours, and a random grey level with one dominant
channel) and pins two constants:

* the checksum of the confidence matrices — the floats are folded through their
  raw IEEE-754 bit patterns, as unsigned 32 bit values, so that a one-ULP
  difference cannot hide behind a tolerance,
* the number of images on which the original **raises**. It is not zero: the
  completely black shape has no foreground signature at all, and the original
  raises an `IllegalStateException` on it. The port has to fail in the same way
  and in the same number of rounds — a port that fails differently is a defect,
  and a port that does *not* fail where the original fails is a defect as well.

The counterpart on the port side is the MoonBit test `the siox segmentation
matches the original SioxSegmentator on random images`, which drives the same
generator and checks the same two constants.

```powershell
javac -encoding UTF-8 -cp out -d tools\out tools\SioxCrossCheck.java
java -cp "out;tools\out" SioxCrossCheck
```

## Gate: `tools\PowCrossCheck.java`

`tools\PowCrossCheck.java` is a **gate** (it is run by
`verify\verify_all.ps1`, step 5). It pins the behaviour of the JDK's
`Math.pow` on the arguments the port uses:

```
family 2.0   : 546001597
family 2.4   : 299101583
family 1/3   : 656082642
ALL-PASS: Math.pow behaves as the reference of the port does
```

The three families are the exponent 2.0 with a base in `[-256, 256]` (the
mixture model `Math.pow(i - mu, 2)` and the Otsu plugin), the exponent 2.4
with a base in `[0, 1]` (the sRGB gamma of SIOX) and the exponent 1/3 with a
base in `[0, 1]` (the CIELAB cube root of SIOX).

The arguments come from the same linear congruential generator as the MoonBit
test `the pow of the port matches the Java Math.pow on the arguments of the
algorithms`, so both sides see exactly the same arguments. The tool also
checks that `Math.pow(x, 2)` is the **exactly rounded** `x * x` — a single
IEEE multiplication is the correctly rounded square, and that is what makes
the mixture model and the Otsu plugin safe on every platform.

The exponents 2.4 and 1/3 are the interesting part: the JDK, the MoonBit
native backend and the MoonBit js backend differ from each other by exactly
one unit in the last place of the double in about 0.1 % of the arguments.
The measurement is in `QA_REPORT.md` §5.2.

```powershell
javac -encoding UTF-8 -cp out -d tools\out tools\PowCrossCheck.java
java -cp "out;tools\out" PowCrossCheck
```

## Diagnostic: `tools\RatsLayoutProbe.java`

`tools\RatsLayoutProbe.java` is **not** part of the harness (it is not
compiled by `build.ps1`). It is a diagnostic that reproduces the RATS
computation with the original `RATSQuadtree` class and compares the two
possible leaf layouts of the quadtree:

* **original** — `RATSQuadtree.getLevel(depth-1)`, i.e. the leaflets of a level
  ordered quadrant wise (NW | NE / SW | SE),
* **push order** — the levels built with `nw, ne, sw, se` per parent and
  indexed row major (this is what the MoonBit port does).

```powershell
javac -encoding UTF-8 -cp out -d tools\out tools\RatsLayoutProbe.java
java -cp "out;tools\out" RatsLayoutProbe <input.gray> <w> <h> <mask.raw>
```

It prints which layout reproduces the given mask. The **original** layout (the
quadrant wise one of `RATSQuadtree.getLevel`) is the one the MoonBit port
implements, so it reproduces the mask of this harness byte for byte on every
test image; the push order is only a permutation of it and differs on the
images whose level grid has more than one row and more than one column.

## Notes on the outputs

* `otsu_image.raw`, `mixture_image.raw` and `watershed.raw` are images in
  which "background" is 255 for Otsu (the algorithm fills with white and
  paints the pixels `<= threshold` black) and 0 for the other two.
* The watershed output is empty (all zero) for images whose basins never meet;
  a textured image produces watershed lines, i.e. the algorithm really runs.
* `mixture.*` can be degenerate for images with a very sparse histogram
  (the Gaussian model collapses and the first split wins); this is the
  behaviour of the original code, not of the harness.
* The harness is deterministic: two runs on the same input produce byte
  identical outputs (no timestamps, no randomness, no hash ordering).
* **RATS mask geometry.** `RATS_` keeps its arrays as `[x][y]` (column major)
  and hands the threshold array to `FloatProcessor(float[][])`, which reads a
  2D array as `[row][column]`. The mask image therefore has the dimensions of
  the input **swapped** (width = input height, height = input width) and its
  content is transposed with respect to the input. This is the behaviour of
  the original plugin and is preserved (see the `FloatProcessor(float[][])`
  note above).
* **RATS quadtree leaf order.** The original orders the leaflets of a level
  quadrant wise (`RATSQuadtree.getLevel`: `q[v][u] = qnw[v][u]`,
  `q[v][u+nx] = qne[v][u]`, `q[v+ny][u] = qsw[v][u]`,
  `q[v+ny][u+nx] = qse[v][u]`), so the leaflet at the grid position
  `(v, u)` is the child `(v/2, u/2)` of its parent. **The MoonBit port uses the
  same quadrant wise order**, so the leaf thresholds are not permuted with
  respect to the original and the masks are identical byte for byte. (An
  earlier version of the port built the levels in the "push order" (`nw, ne,
  sw, se` for every parent) and indexed them row major, which is a
  *permutation* of the original order — the two agree only in the first row
  and in the first column. That version differed from the original in 12
  bytes for `checker` and `ramp_blobs`; the port has been corrected since.)
  See `tools\RatsLayoutProbe.java`.
* **RATS on an image that is taller than it is wide.** The quadtree sums the
  *transposed* float image with the flat index `y * height + x`, so for
  `w < h` the index leaves the array (the largest one is
  `(h-1)*h + (w-1)`, which exceeds `w*h` as soon as `h > w`). The original
  then raises an `ArrayIndexOutOfBoundsException`, the harness catches it and
  reports an empty mask (`rats.mask.width`/`height` are `0`, `rats.failed` is
  `1`); the port detects the same condition and reports the same failure.
  The `edge_tall` image of the adversarial corpus covers this case.
* **The blob labeler reads outside the image.** The plugin reads its
  neighbours through `ImageProcessor.get(x, y)`, which is
  `pixels[y * width + x]` in the stub — a read that leaves the array raises
  an `ArrayIndexOutOfBoundsException`. The plugin clamps `x` to `1` when it
  is `0` and to `width - 1` when it is `>= width`, and clamps `y` to `1` when
  it is `0` **without** clamping it against the height. The result:
  * an image that is one **row** high makes the plugin read the row 1 that
    does not exist (the "west" neighbour),
  * an image that is one **column** wide makes the 8 connected variant read
    the column -1 that does not exist (the "north west" neighbour).

  The harness catches the exception and reports an empty label map and
  `failed = 1`; the port checks the indices itself and reports the same
  failure (a MoonBit panic cannot be caught). With the **edge correction**
  (the default) the border is overwritten with the background colour, so the
  plugin never reaches the read — only the `edge = false` variant does. The
  `edge_one_row`, `edge_one_column` and `edge_one_pixel` images of the
  adversarial corpus cover this case.
* **SIOX failure modes.** `segmentate` returns `false` when the background
  colour signature is empty (no pixel has `cm <= 0.1`); the confidence matrix
  is then left untouched and `siox.success` is `0`. It throws
  `java.lang.IllegalStateException("foreground signature does not exist")`
  when the foreground signature is empty but at least one pixel is unknown
  (`0.1 < cm < 0.8`) — the exception propagates out of the classification
  loop, so the confidence matrix holds the partially classified result. The
  harness catches the exception, prints its type, message and stack trace to
  **stderr** (it is never swallowed silently), writes the partial confidence
  matrix to `siox_cm.raw` and sets `siox.success` to `0`.
* Both new algorithms are wrapped in `try { … } catch (Throwable)` blocks:
  if one of them fails, the harness still writes every output file and all
  scalars, and the failure is reported on stderr. A failed `RATS_` writes an
  empty `rats_mask.raw` (and `rats.mask.width` / `rats.mask.height` become
  `0`); a failed `SIOX` still writes `siox_cm.raw` / `siox_mask.raw` with the
  state the original left behind.

