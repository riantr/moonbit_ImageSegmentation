///|
/// Regression tests for the MoonBit port of the Java/ImageJ segmentation
/// algorithms.
///
/// The expected values are the ones produced by the **original Java code**
/// (see `ref/harness`), so these tests pin the port to the reference
/// implementation.
fn make_ramp_blobs(w : Int, h : Int) -> @moonbit_ImageSegmentation.GrayImage {
  let px = Array::make(w * h, 0)
  let mut y = 0
  while y < h {
    let mut x = 0
    while x < w {
      let mut v = 0
      if y < 2 {
        v = 4 + 4 * x
      }
      if x >= 4 && x < 12 && y >= 3 && y < 11 {
        v = 200
      }
      if x >= 18 && x < 27 && y >= 12 && y < 21 {
        v = 120
      }
      if x >= 2 && x < 5 && y >= 18 && y < 21 {
        v = 90
      }
      px[y * w + x] = v
      x = x + 1
    }
    y = y + 1
  }
  @moonbit_ImageSegmentation.GrayImage::from_pixels(w, h, px)
}

///|
/// The Otsu plugin threshold matches the Java reference.
test "otsu threshold matches the Java reference" {
  let img = make_ramp_blobs(32, 24)
  assert_eq(@moonbit_ImageSegmentation.otsu_threshold(img), 73)
}

///|
/// All fifteen auto threshold methods match the Java reference.
test "auto thresholds match the Java reference" {
  let img = make_ramp_blobs(32, 24)
  let hist = @moonbit_ImageSegmentation.GrayImage::histogram(img)
  assert_eq(@moonbit_ImageSegmentation.auto_threshold("Huang", hist), 0)
  assert_eq(@moonbit_ImageSegmentation.auto_threshold("Intermodes", hist), 153)
  assert_eq(@moonbit_ImageSegmentation.auto_threshold("IsoData", hist), 73)
  assert_eq(@moonbit_ImageSegmentation.auto_threshold("Li", hist), 21)
  assert_eq(@moonbit_ImageSegmentation.auto_threshold("MaxEntropy", hist), 0)
  assert_eq(@moonbit_ImageSegmentation.auto_threshold("Mean", hist), 35)
  assert_eq(@moonbit_ImageSegmentation.auto_threshold("MinError(I)", hist), 1)
  assert_eq(@moonbit_ImageSegmentation.auto_threshold("Minimum", hist), 170)
  assert_eq(@moonbit_ImageSegmentation.auto_threshold("Moments", hist), 120)
  assert_eq(@moonbit_ImageSegmentation.auto_threshold("Otsu", hist), 75)
  assert_eq(@moonbit_ImageSegmentation.auto_threshold("Percentile", hist), 0)
  assert_eq(@moonbit_ImageSegmentation.auto_threshold("RenyiEntropy", hist), 17)
  assert_eq(@moonbit_ImageSegmentation.auto_threshold("Shanbhag", hist), 116)
  assert_eq(@moonbit_ImageSegmentation.auto_threshold("Triangle", hist), 2)
  assert_eq(@moonbit_ImageSegmentation.auto_threshold("Yen", hist), 0)
}

///|
/// The multi level Otsu thresholds match the Java reference.
test "multi level otsu matches the Java reference" {
  let img = make_ramp_blobs(32, 24)
  let (result, regions) = @moonbit_ImageSegmentation.multi_otsu(img, 4)
  assert_eq(result.thresholds[0], 0)
  assert_eq(result.thresholds[1], 52)
  assert_eq(result.thresholds[2], 96)
  assert_eq(result.thresholds[3], 128)
  assert_eq(regions.length(), 4)
}

///|
/// The mixture model threshold matches the Java reference.
test "mixture modelling matches the Java reference" {
  let img = make_ramp_blobs(32, 24)
  let result = @moonbit_ImageSegmentation.mixture_modeling(img)
  assert_eq(result.real_threshold, 1)
  assert_eq(result.direct_threshold, 4)
}

///|
/// The blob labeler finds the same components as the Java reference.
test "blob labelling matches the Java reference" {
  let img = make_ramp_blobs(32, 24)
  let four = @moonbit_ImageSegmentation.blob_label(img, 0, false, true)
  let eight = @moonbit_ImageSegmentation.blob_label(img, 0, true, true)
  assert_eq(four.number_of_labels, 4)
  assert_eq(eight.number_of_labels, 4)
}

///|
/// The watershed runs and produces a binary image.
test "watershed produces a binary image" {
  let img = make_ramp_blobs(32, 24)
  let ws = @moonbit_ImageSegmentation.watershed(img)
  assert_eq(ws.width, 32)
  assert_eq(ws.height, 24)
  let mut i = 0
  while i < ws.pixels.length() {
    assert_true(ws.pixels[i] == 0 || ws.pixels[i] == 255)
    i = i + 1
  }
}

///|
/// The densitometry plugins transform the pixels of the ROI.
test "densitometry transforms the image" {
  let rgb = @moonbit_ImageSegmentation.RgbImage::new(4, 4, 10, 10, 10)
  let colors = @moonbit_ImageSegmentation.DensitometryColors::default()
  let options = @moonbit_ImageSegmentation.DensitometryOptions::default()
  let out = @moonbit_ImageSegmentation.densitometry_1_channel(rgb, colors, options)
  // the reference colour is white, the pixel is dark -> it becomes the
  // background colour (black)
  assert_eq(out.red(0, 0), 0)
  assert_eq(out.green(0, 0), 0)
  assert_eq(out.blue(0, 0), 0)
}

///|
/// The RetFM helpers average the channels and threshold the result.
test "retfm helpers match the Java reference" {
  let rgb = @moonbit_ImageSegmentation.RgbImage::new(2, 1, 10, 20, 30)
  let gray = @moonbit_ImageSegmentation.retfm_convert_to_grayscale(
    rgb,
    [true, true, true]
  )
  assert_eq(gray.pixels[0], 20)
  assert_eq(gray.pixels[1], 20)
}

///|
/// Java's narrowing conversion of `NaN` and of out of range values.
test "java narrowing conversions" {
  assert_eq(@moonbit_ImageSegmentation.java_double_to_int(0.0 / 0.0), 0)
  assert_eq(@moonbit_ImageSegmentation.java_double_to_int(3.9), 3)
  assert_eq(@moonbit_ImageSegmentation.java_double_to_int(-3.9), -3)
  assert_eq(@moonbit_ImageSegmentation.java_double_to_int(1.0e30), 2147483647)
  assert_eq(@moonbit_ImageSegmentation.java_double_to_int(-1.0e30), -2147483648)
  assert_eq(@moonbit_ImageSegmentation.java_round_double(2.5), 3)
  assert_eq(@moonbit_ImageSegmentation.java_round_double(-2.5), -2)
}

///|
/// The threshold level mapping of the Multi_Thresholder plugin.
test "threshold level mapping" {
  assert_eq(
    @moonbit_ImageSegmentation.scale_up(0.0, 65535.0, 255.0),
    65535.0
  )
  assert_eq(@moonbit_ImageSegmentation.scale_up(0.0, 0.0, 100.0), @moonbit_ImageSegmentation.NO_THRESHOLD)
  assert_eq(@moonbit_ImageSegmentation.scale_down(true, 0.0, 255.0, 77.0), 77.0)
  assert_eq(@moonbit_ImageSegmentation.scale_down(false, 0.0, 65535.0, 65535.0), 255.0)
  let pair = @moonbit_ImageSegmentation.threshold_pair(
    120.0,
    255.0,
    @moonbit_ImageSegmentation.LutMode::normal(),
    @moonbit_ImageSegmentation.BackgroundMode::light()
  )
  assert_eq(pair.lower, 0.0)
  assert_eq(pair.upper, 120.0)
}

///|
/// The faithful `setThreshold` of the Multi_Thresholder plugin: the
/// threshold is scaled first and then turned into the lower/upper pair.
test "threshold pair of the plugin" {
  let pair = @moonbit_ImageSegmentation.set_threshold(
    120.0,
    0.0,
    255.0,
    @moonbit_ImageSegmentation.LutMode::normal(),
    @moonbit_ImageSegmentation.BackgroundMode::light()
  )
  assert_eq(pair.lower, 0.0)
  assert_eq(pair.upper, 120.0)
  let dark = @moonbit_ImageSegmentation.set_threshold(
    120.0,
    0.0,
    255.0,
    @moonbit_ImageSegmentation.LutMode::normal(),
    @moonbit_ImageSegmentation.BackgroundMode::dark()
  )
  assert_eq(dark.lower, 120.0)
  assert_eq(dark.upper, 255.0)
  let inverted = @moonbit_ImageSegmentation.set_threshold(
    120.0,
    0.0,
    255.0,
    @moonbit_ImageSegmentation.LutMode::inverted(),
    @moonbit_ImageSegmentation.BackgroundMode::light()
  )
  assert_eq(inverted.lower, 120.0)
  assert_eq(inverted.upper, 255.0)
}

///|
/// The reference table of the Multi_Thresholder helpers has 72 lines (two
/// processor kinds, four thresholds and nine cases each) and starts with
/// the byte processor at threshold zero.
test "multi thresholder reference table" {
  let table = @moonbit_ImageSegmentation.multi_thresholder_table()
  assert_eq(table.length(), 72)
  assert_eq(
    table[0],
    "byte t=0 scaleUp(0,255) => 0000000000000000"
  )
  assert_eq(
    table[1],
    "byte t=0 scaleDown(0,255) => 0000000000000000"
  )
  assert_eq(
    table[4],
    "byte t=0 scaleUpAndSet(NO_THRESHOLD,255) => c128a92000000000 406fe00000000000"
  )
}

///|
/// SIOX segmentation runs and returns a confidence matrix.
test "siox segmentation runs" {
  let rgb = @moonbit_ImageSegmentation.RgbImage::new(8, 8, 0, 0, 0)
  let mut i = 0
  while i < 16 {
    rgb.set(i % 8, i / 8, 255, 255, 255)
    i = i + 1
  }
  let cm = Array::make(64, 0.5F)
  i = 0
  while i < 8 {
    cm[i] = 0.0F
    cm[56 + i] = 1.0F
    i = i + 1
  }
  let result = @moonbit_ImageSegmentation.siox_segmentate(
    rgb,
    cm,
    1,
    4.0,
    @moonbit_ImageSegmentation.siox_default_limits()
  )
  assert_true(result.success)
  assert_eq(result.confidence.length(), 64)
}

///|
/// RATS regionalised thresholding runs.
test "rats thresholding runs" {
  let px = Array::make(64, 0)
  let mut i = 0
  while i < 64 {
    px[i] = if i % 8 < 4 { 10 } else { 240 }
    i = i + 1
  }
  let img = @moonbit_ImageSegmentation.GrayImage::from_pixels(8, 8, px)
  let result = @moonbit_ImageSegmentation.rats(
    img,
    @moonbit_ImageSegmentation.RatsOptions::default()
  )
  assert_eq(result.mask.width, 8)
  assert_eq(result.mask.height, 8)
}

///|
/// The PNG codec round trips a grayscale and an RGB image.
///
/// The test runs on every backend (`moon test --target all`), so it also
/// proves that the zlib dependency works on all of them.
test "png round trip" {
  let px = Array::make(16, 0)
  let mut i = 0
  while i < 16 {
    px[i] = i * 16
    i = i + 1
  }
  let gray = @moonbit_ImageSegmentation.GrayImage::from_pixels(4, 4, px)
  let encoded = @moonbit_ImageSegmentation.png_encode_gray(gray)
  let decoded = @moonbit_ImageSegmentation.png_decode_gray(encoded)
  assert_eq(decoded.width, 4)
  assert_eq(decoded.height, 4)
  let mut i = 0
  while i < 16 {
    assert_eq(decoded.pixels[i], px[i])
    i = i + 1
  }
  let rgb = @moonbit_ImageSegmentation.RgbImage::new(4, 4, 10, 20, 30)
  let encoded = @moonbit_ImageSegmentation.png_encode_rgb(rgb)
  let decoded = @moonbit_ImageSegmentation.png_decode_rgb(encoded)
  assert_eq(decoded.width, 4)
  assert_eq(decoded.red(1, 1), 10)
  assert_eq(decoded.green(1, 1), 20)
  assert_eq(decoded.blue(1, 1), 30)
}

///|
/// Every algorithm runs on its own and produces its result.
///
/// The test runs on every backend, so it proves that each algorithm works
/// on all of them.
test "every algorithm runs on its own" {
  let px = Array::make(64, 0)
  let mut i = 0
  while i < 64 {
    px[i] = if i % 8 < 4 { 10 } else { 240 }
    i = i + 1
  }
  let img = @moonbit_ImageSegmentation.GrayImage::from_pixels(8, 8, px)
  let rgb = @moonbit_ImageSegmentation.RgbImage::new(8, 8, 120, 120, 120)
  // Otsu
  assert_true(@moonbit_ImageSegmentation.otsu_threshold(img) >= 0)
  // multi level Otsu
  let (_, regions) = @moonbit_ImageSegmentation.multi_otsu(img, 4)
  assert_eq(regions.length(), 4)
  // the automatic thresholds
  // (-1 is ImageJ's "no threshold found"; see AutoThresholder)
  let histogram = img.histogram()
  let methods = @moonbit_ImageSegmentation.auto_threshold_methods()
  assert_eq(methods.length(), 15)
  let mut i = 0
  while i < methods.length() {
    assert_true(@moonbit_ImageSegmentation.auto_threshold(methods[i], histogram) >= -1)
    i = i + 1
  }
  // the mixture model
  assert_true(
    @moonbit_ImageSegmentation.mixture_modeling(img).real_threshold >= 0
  )
  // the blob labeling
  assert_eq(
    @moonbit_ImageSegmentation.blob_label(img, 0, false, true).map.length(),
    64
  )
  // the watershed
  assert_eq(@moonbit_ImageSegmentation.watershed(img).pixels.length(), 64)
  // the densitometry
  let colors = @moonbit_ImageSegmentation.DensitometryColors::default()
  let options = @moonbit_ImageSegmentation.DensitometryOptions::default()
  assert_eq(
    @moonbit_ImageSegmentation.densitometry_1_channel(rgb, colors, options).pixels.length(),
    192
  )
  assert_eq(
    @moonbit_ImageSegmentation.densitometry_3_channel(rgb, colors, options).pixels.length(),
    192
  )
  // the RetFM helpers
  let retfm = @moonbit_ImageSegmentation.retfm_convert_to_grayscale(rgb, [
    true,
    true,
    true,
  ])
  assert_eq(retfm.pixels.length(), 64)
  // RATS
  assert_eq(
    @moonbit_ImageSegmentation.rats(
      img,
      @moonbit_ImageSegmentation.RatsOptions::default()
    ).mask.pixels.length(),
    64
  )
  // SIOX
  let cm = Array::make(64, 0.5F)
  assert_eq(
    @moonbit_ImageSegmentation.siox_segmentate(
      rgb,
      cm,
      1,
      4.0,
      @moonbit_ImageSegmentation.siox_default_limits()
    ).confidence.length(),
    64
  )
  // the level mapping helpers of Multi_Thresholder
  assert_eq(@moonbit_ImageSegmentation.multi_thresholder_table().length(), 72)
}

///|
/// MoonBit's `Int` arithmetic has to wrap exactly like a Java `int`.
///
/// Several of the ported algorithms accumulate into a Java `int` and rely on
/// the overflow: `AutoThresholder` computes `x += i * i * y[i]` and `RetFM_J`
/// computes `i * hist[i]`. The Java `int` overflows silently (it wraps), so the
/// port is only equivalent if MoonBit's `Int` does the same. This test pins
/// that assumption down - if MoonBit ever changes the semantics, the test
/// fails instead of the byte comparison silently diverging.
test "the Int arithmetic wraps like a Java int" {
  // Java: Integer.MAX_VALUE + 1 == Integer.MIN_VALUE
  assert_eq(2147483647 + 1, -2147483648)
  // Java: Integer.MIN_VALUE - 1 == Integer.MAX_VALUE
  assert_eq(-2147483648 - 1, 2147483647)
  // Java: 200 * 200 * 1048576 overflows the 32 bit int
  assert_eq(200 * 200 * 1048576, -1006632960)
  // Java: the product is computed as an int first and only then widened
  assert_eq((200 * 200 * 1048576).to_double(), -1006632960.0)
}

///|
/// `retfm_convert_to_grayscale` with no selected channel.
///
/// The Java original divides by the number of selected channels. With none
/// selected the divisor is zero, the multiplication produces `NaN` and the
/// narrowing conversion of a `NaN` yields `0` - so the Java original returns
/// an all zero image. MoonBit's `to_int` would trap on the `NaN`.
test "retfm grayscale with no channel is an all zero image" {
  let rgb = @moonbit_ImageSegmentation.RgbImage::from_pixels(2, 2, [
    255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255,
  ])
  let gray = @moonbit_ImageSegmentation.retfm_convert_to_grayscale(rgb, [])
  assert_eq(gray.pixels.length(), 4)
  assert_eq(gray.pixels[0], 0)
  assert_eq(gray.pixels[1], 0)
  assert_eq(gray.pixels[2], 0)
  assert_eq(gray.pixels[3], 0)
}

///|
/// The channel number of `RetFM_J.convertToGrayscale` is the index in
/// `useChannels` plus one, and `ColorProcessor.getChannel` returns a zero
/// image for every channel number beyond the third. A fourth channel
/// therefore contributes zeros (but still counts towards the divisor).
test "retfm grayscale ignores a channel beyond the third" {
  let rgb = @moonbit_ImageSegmentation.RgbImage::from_pixels(1, 1, [0x80, 0x40, 0x20])
  // only the red channel: the value is the red one
  let red = @moonbit_ImageSegmentation.retfm_convert_to_grayscale(rgb, [true])
  assert_eq(red.pixels[0], 0x80)
  // the red channel and a fourth (zero) channel: the average of 0x80 and 0
  let with_fourth = @moonbit_ImageSegmentation.retfm_convert_to_grayscale(rgb, [
    true,
    false,
    false,
    true,
  ])
  assert_eq(with_fourth.pixels[0], 0x40)
}
///|
/// The densitometry plugins only iterate the ROI of the image, not the whole
/// image: every pixel outside the ROI keeps its value.
test "the densitometry only works on the region" {
  // a 4x2 image, every pixel black
  let rgb = @moonbit_ImageSegmentation.RgbImage::from_pixels(4, 2, [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ])
  let colors = @moonbit_ImageSegmentation.DensitometryColors::default()
  // the foreground is white, so every black pixel is background
  let options = @moonbit_ImageSegmentation.DensitometryOptions::default()
  let full = @moonbit_ImageSegmentation.densitometry_1_channel(rgb, colors, options)
  // the whole image is background
  assert_eq(full.pixels[0], 0)
  assert_eq(full.pixels[21], 0)
  // now only the region (1, 0) with the size 2x1 is worked on
  let region = @moonbit_ImageSegmentation.DensitometryRegion::new(1, 0, 2, 1)
  let cropped = options.configured(false, false, region)
  let partial = @moonbit_ImageSegmentation.densitometry_1_channel(rgb, colors, cropped)
  // the pixels of the region are the background ...
  assert_eq(partial.pixels[3], 0)
  assert_eq(partial.pixels[6], 0)
  // ... and the pixels outside of it keep the value they had
  assert_eq(partial.pixels[0], rgb.pixels[0])
  assert_eq(partial.pixels[9], rgb.pixels[9])
}

///|
/// The `Blob_Labeler` plugin reads its neighbours through
/// `ImageProcessor.get(x, y)`, which raises an
/// `ArrayIndexOutOfBoundsException` when the read leaves the image: the
/// plugin reads the row 1 of an image that is one row high, and the column
/// -1 of an image that is one column wide. The port reports that failure
/// the way the reference harness observes it (an empty label map and
/// `failed = true`) instead of dying - a MoonBit panic cannot be caught and
/// would take the whole command line tool with it.
test "the blob labeler reports the out of bounds neighbour read" {
  // a 16x1 image: the west neighbour of every pixel is in the row 1 that
  // does not exist
  let row = @moonbit_ImageSegmentation.GrayImage::from_pixels(16, 1, [
    10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160,
  ])
  // with the edge correction the first row is the background, so nothing is
  // read out of bounds
  let edged = @moonbit_ImageSegmentation.blob_label(row, 0, false, true)
  assert_false(edged.failed)
  // without the edge correction the plugin reads outside the image
  let noedge = @moonbit_ImageSegmentation.blob_label(row, 0, false, false)
  assert_true(noedge.failed)
  assert_eq(noedge.number_of_labels, 0)
  // a 1x16 image: the north west neighbour of the first pixel is in the
  // column -1 that does not exist (the 8 connected variant only)
  let column = @moonbit_ImageSegmentation.GrayImage::from_pixels(1, 16, [
    10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160,
  ])
  let four = @moonbit_ImageSegmentation.blob_label(column, 0, false, false)
  assert_false(four.failed)
  let eight = @moonbit_ImageSegmentation.blob_label(column, 0, true, false)
  assert_true(eight.failed)
}

///|
/// `RetFM_J.convertToGrayscale` averages the **selected** channels: the
/// divisor is the number of the selected channels and every selected channel
/// contributes its own plane. The empty selection divides by zero, the
/// product becomes NaN and the Java original returns an all zero image.
test "the retfm grayscale averages the selected channels only" {
  // the colours of the grey level 200: R = v, G = 3v/4, B = 255 - v
  let rgb = @moonbit_ImageSegmentation.RgbImage::from_pixels(1, 1, [200, 150, 55])
  // the red and the green channel: (200 + 150) / 2 = 175
  let red_green = @moonbit_ImageSegmentation.retfm_convert_to_grayscale(rgb, [
    true,
    true,
    false,
  ])
  assert_eq(red_green.pixels[0], 175)
  // the green and the blue channel: (150 + 55) / 2 = 102.5 -> 103
  let green_blue = @moonbit_ImageSegmentation.retfm_convert_to_grayscale(rgb, [
    false,
    true,
    true,
  ])
  assert_eq(green_blue.pixels[0], 103)
  // the blue channel alone: 55
  let blue = @moonbit_ImageSegmentation.retfm_convert_to_grayscale(rgb, [
    false,
    false,
    true,
  ])
  assert_eq(blue.pixels[0], 55)
  // no channel at all: the divisor is zero, the product becomes NaN and the
  // narrowing conversion of a NaN yields zero
  let none = @moonbit_ImageSegmentation.retfm_convert_to_grayscale(rgb, [
    false,
    false,
    false,
  ])
  assert_eq(none.pixels[0], 0)
}

///|
/// The tolerance of the densitometry plugins is a **parameter** and not a
/// constant: a plugin that ignored it would produce the same image for every
/// tolerance.
///
/// The pixel of the test is 30 away from the white foreground in the red and
/// 40 in the green and the blue channel, so the squared distance is
/// `30^2 + 40^2 + 40^2 = 4100`: it is inside the default tolerance of 127
/// (`127^2 = 16129`) and outside the tolerance of 64 (`64^2 = 4096`). The
/// 3-channel variant uses 64 / 32 / 16, so only the **green** channel
/// (`40 > 32`) puts the pixel outside.
test "the densitometry honours the tolerance" {
  let rgb = @moonbit_ImageSegmentation.RgbImage::from_pixels(1, 1, [225, 215, 215])
  let colors = @moonbit_ImageSegmentation.DensitometryColors::default()
  let options = @moonbit_ImageSegmentation.DensitometryOptions::default()
  // the default tolerance of 127 accepts the pixel: it keeps its value
  let default = @moonbit_ImageSegmentation.densitometry_1_channel(rgb, colors, options)
  assert_eq(default.pixels[0], 225)
  let default3 = @moonbit_ImageSegmentation.densitometry_3_channel(rgb, colors, options)
  assert_eq(default3.pixels[0], 225)
  // the tolerance of 64 rejects it: it becomes the background colour
  let narrow = options.with_tolerances(64, 64, 32, 16)
  let tight = @moonbit_ImageSegmentation.densitometry_1_channel(rgb, colors, narrow)
  assert_eq(tight.pixels[0], 0)
  // the 3-channel variant: only the green channel (40 > 32) rejects it
  let tight3 = @moonbit_ImageSegmentation.densitometry_3_channel(rgb, colors, narrow)
  assert_eq(tight3.pixels[0], 0)
}

///|
/// The next value of the linear congruential generator that builds the
/// hostile histograms of the `Li` cross check and the arguments of the `pow`
/// cross check. The Java tool `ref/harness/tools/LiCrossCheck.java` and
/// `ref/harness/tools/PowCrossCheck.java` use exactly the same arithmetic, so
/// both sides see the same inputs without exchanging a file.
fn lcg_next(state : Int) -> Int {
  (1103515245 * state + 12345) & 0x7FFFFFFF
}

///|
/// The hostile histogram of a round: the histogram and the state of the
/// generator after it. The shapes are the ones of the Java tool — a single
/// bin, the two extreme bins, everything in the last or in the first bin, an
/// empty histogram, a sparse and a dense random histogram and a single spike.
fn hostile_histogram(round : Int, state : Int) -> (Array[Int], Int) {
  let histogram = Array::make(256, 0)
  let mut s = state
  let kind = round % 8
  if kind == 0 {
    // a single bin
    s = lcg_next(s)
    let bin = s % 256
    s = lcg_next(s)
    histogram[bin] = 1 + s % 1000
  } else if kind == 1 {
    // the two extreme bins
    s = lcg_next(s)
    histogram[0] = s % 100
    s = lcg_next(s)
    histogram[255] = s % 100
  } else if kind == 2 {
    // everything in the last bin
    s = lcg_next(s)
    histogram[255] = 1 + s % 1000
  } else if kind == 3 {
    // everything in the first bin
    s = lcg_next(s)
    histogram[0] = 1 + s % 1000
  } else if kind == 5 {
    // a sparse random histogram
    for i in 0..<256 {
      s = lcg_next(s)
      histogram[i] = s % 3
    }
  } else if kind == 6 {
    // a dense random histogram
    for i in 0..<256 {
      s = lcg_next(s)
      histogram[i] = s % 1000
    }
  } else if kind == 7 {
    // a single spike
    s = lcg_next(s)
    let bin = s % 256
    s = lcg_next(s)
    histogram[bin] = 1 + s % 100
  }
  // kind == 4 is the completely empty histogram (the mean is NaN): the
  // histogram stays as it is and the generator is not advanced.
  (histogram, s)
}

///|
/// The `Li` threshold of the port matches the original `AutoThresholder` on
/// a thousand hostile histograms.
///
/// The QA report listed as a residual risk that the `Li` method could index
/// outside the 256 bin histogram. It cannot: the iteration variable is the
/// logarithmic mean of two means that both live in `0..255`, so the threshold
/// never exceeds 255. Both implementations are driven with the same hostile
/// histograms and pinned to the same checksum — the Java tool
/// `ref/harness/tools/LiCrossCheck.java` fails when the **original** computes
/// something else, this test fails when the **port** does.
test "the Li threshold matches the original AutoThresholder on hostile histograms" {
  let mut state = 20261030
  let mut checksum = 0L
  let mut lowest = 2147483647
  let mut highest = -2147483648
  for round in 0..<1000 {
    let (histogram, next_state) = hostile_histogram(round, state)
    state = next_state
    let threshold = @moonbit_ImageSegmentation.auto_threshold_li(histogram)
    // the threshold never leaves the histogram
    assert_true(threshold >= 0 && threshold <= 255)
    if threshold < lowest {
      lowest = threshold
    }
    if threshold > highest {
      highest = threshold
    }
    checksum = (checksum * 31 + (threshold + 1).to_int64()) % 1000000007
  }
  assert_eq(lowest, 0)
  assert_eq(highest, 114)
  assert_eq(checksum, 333878761L)
}

///|
/// Fold the raw IEEE-754 bit pattern of a result into the checksum, exactly
/// as `ref/harness/tools/PowCrossCheck.java` does it.
fn pow_fold(value : Double) -> Int64 {
  let bits = value.reinterpret_as_int64()
  ((bits % 1000000007L) + 1000000007L) % 1000000007L
}

///|
/// The `pow` of the port matches the `Math.pow` of the Java reference on the
/// arguments the algorithms use.
///
/// The port uses a power in three places: the mixture model and the Otsu
/// plugin with the exponent 2.0, and the colour conversion of SIOX with the
/// exponents 2.4 and 1/3.
///
/// For the exponent 2.0 the two sides are **bit identical on every
/// platform**: a single IEEE multiplication is the correctly rounded square,
/// `Math.pow(x, 2)` returns it on the Java side (the tool
/// `ref/harness/tools/PowCrossCheck.java` checks that) and `@math.pow` returns
/// it on the MoonBit side (this test checks that). The two checksums are
/// therefore the same number.
///
/// For the exponents 2.4 and 1/3 the platforms differ by one unit in the
/// last place of the double in about 0.1 % of the arguments; the result is
/// narrowed to a float right afterwards, which absorbs the difference. The
/// measurement is in QA_REPORT.md.
test "the pow of the port matches the Java Math.pow on the arguments of the algorithms" {
  let mut state = 20261030
  let mut checksum = 0L
  let mut not_the_square = 0
  for _ in 0..<20000 {
    state = lcg_next(state)
    let x = Double::from_int(state % 2000001) / 1000000.0 - 256.0
    let squared = @math.pow(x, 2.0)
    // the correctly rounded square is the product of the two operands
    if squared.reinterpret_as_uint64() != (x * x).reinterpret_as_uint64() {
      not_the_square = not_the_square + 1
    }
    checksum = (checksum * 31 + pow_fold(squared)) % 1000000007L
  }
  assert_eq(not_the_square, 0)
  // the same checksum as the Java side (`Math.pow`): 546001597
  assert_eq(checksum, 546001597L)
}

///|
/// The fifteen threshold methods match the original `AutoThresholder` on
/// hostile histograms.
///
/// The QA report listed as a residual risk that the `Li` cross check covers
/// one method of the fifteen — the other fourteen were only covered by the
/// image corpus, not by a fuzz. This test closes that gap: **every** method of
/// the original is driven with the same hostile histograms that the Java tool
/// `ref/harness/tools/AutoThresholderCrossCheck.java` uses, and the checksum of
/// every method is pinned to the same constant on both sides.
///
/// The tool fails when the **Java** original computes something else, this test
/// fails when the **port** computes something else, so a divergence shows up
/// on the side that caused it.
///
/// The generator is restarted for every method, so every method sees the same
/// sequence of histograms and the checksum of a method depends on that method
/// alone.
test "the fifteen threshold methods match the original AutoThresholder on hostile histograms" {
  let methods = @moonbit_ImageSegmentation.auto_threshold_methods()
  assert_eq(methods.length(), 15)
  // the names and their order are the table of the Java original
  let expected_names = [
    "Huang",
    "Intermodes",
    "IsoData",
    "Li",
    "MaxEntropy",
    "Mean",
    "MinError(I)",
    "Minimum",
    "Moments",
    "Otsu",
    "Percentile",
    "RenyiEntropy",
    "Shanbhag",
    "Triangle",
    "Yen",
  ]
  for index in 0..<methods.length() {
    assert_eq(methods[index], expected_names[index])
  }
  // the same checksums as the Java side (`AutoThresholderCrossCheck.java`)
  let expected = [
    107048180L,
    880944531L,
    273794009L,
    431563462L,
    686060938L,
    956456453L,
    517811581L,
    924797356L,
    662340405L,
    901090455L,
    934842986L,
    670314028L,
    879143749L,
    799090228L,
    299050832L,
  ]
  let mut combined = 0L
  // the lowest and the highest threshold of every method - the same numbers
  // the Java tool reports next to its checksums
  let expected_low = [
    -1, -1, 116, 0, -1, 0, 0, -1, -1, 119, -1, 0, -1, 1, -1,
  ]
  let expected_high = [
    141, 143, 131, 109, 135, 255, 255, 252, 255, 254, 136, 135, 136, 254, 135,
  ]
  for index in 0..<methods.length() {
    // every method sees the same sequence of histograms
    let mut state = 20261030
    let mut checksum = 0L
    let mut lowest = 2147483647
    let mut highest = -2147483648
    for round in 0..<64 {
      let (histogram, next_state) = hostile_histogram(round, state)
      state = next_state
      let threshold = @moonbit_ImageSegmentation.auto_threshold(methods[index], histogram)
      if threshold < lowest {
        lowest = threshold
      }
      if threshold > highest {
        highest = threshold
      }
      checksum = (checksum * 31 + (threshold + 1).to_int64()) % 1000000007
    }
    assert_eq(checksum, expected[index])
    assert_eq(lowest, expected_low[index])
    assert_eq(highest, expected_high[index])
    combined = (combined * 31 + checksum) % 1000000007
  }
  // the fold of the fifteen checksums, the same constant as the Java side
  assert_eq(combined, 981417562L)
}

///|
/// The random image of a round: the pixels and the state of the generator
/// after it. The Java tool `ref/harness/tools/BlobCrossCheck.java` builds
/// **exactly the same** images.
///
/// The sizes are a table of sixteen shapes - among them the one row and the
/// one column high images, in which the plugin of the original reads outside
/// the image - and the densities are three families (half, two thirds and four
/// fifths of the pixels are foreground).
fn random_blob_image(
  round : Int,
  width : Int,
  height : Int,
  state : Int
) -> (Array[Int], Int) {
  let pixels = Array::make(width * height, 0)
  let mut s = state
  let range = 2 + (round % 3)
  for index in 0..<(width * height) {
    s = lcg_next(s)
    pixels[index] = s % range
  }
  (pixels, s)
}

///|
/// The six configurations of the original `Blob_Labeler` match the port on
/// random images.
///
/// The labeling is the most intricate algorithm of the port, and the image
/// corpus of the suite only contains twenty five images - it never contains
/// many separate blobs, blobs that touch, blobs with a hole or a border that
/// matters. This test closes that gap: the Java tool
/// `ref/harness/tools/BlobCrossCheck.java` and this test drive the **same**
/// random images and pin the **same** checksums, so a divergence shows up on
/// the side that caused it.
///
/// The failure path is part of the comparison: the plugin of the original
/// raises an `ArrayIndexOutOfBoundsException` when it has more labels than
/// `size/2` or when it reads a neighbour outside a one row or one column high
/// image, and the port reports that failure the way the reference harness
/// observes it.
test "the blob labeler matches the original Blob_Labeler on random images" {
  let widths = [
    8, 12, 16, 24, 7, 32, 1, 8, 1, 2, 5, 1, 10, 20, 3, 15,
  ]
  let heights = [
    8, 10, 16, 18, 5, 24, 8, 1, 1, 3, 1, 5, 7, 20, 3, 11,
  ]
  // the same checksums as the Java side (`BlobCrossCheck.java`)
  let expected = [
    717071813L,
    41598674L,
    99965418L,
    549135478L,
    470942760L,
    776978089L,
  ]
  // the number of images on which the original fails
  let expected_failures = [
    6, 6, 22, 29, 6, 6,
  ]
  // the six configurations: the 4 and the 8 connected neighbourhood, with and
  // without the edge correction, and the background colour 0 and 1
  let eights = [
    false, true, false, true, false, true,
  ]
  let bgcols = [
    0, 0, 0, 0, 1, 1,
  ]
  let edges = [
    true, true, false, false, true, true,
  ]
  let mut combined = 0L
  for configuration in 0..<6 {
    // every configuration sees the same images
    let mut state = 20261030
    let mut checksum = 0L
    let mut failures = 0
    for round in 0..<96 {
      let width = widths[round % 16]
      let height = heights[round % 16]
      let (pixels, next_state) = random_blob_image(round, width, height, state)
      state = next_state
      let image = @moonbit_ImageSegmentation.GrayImage::from_pixels(width, height, pixels)
      let result = @moonbit_ImageSegmentation.blob_label(
        image,
        bgcols[configuration],
        eights[configuration],
        edges[configuration],
      )
      let mut failed = 0
      if result.failed {
        failed = 1
        failures = failures + 1
      }
      checksum = (checksum * 31 + failed.to_int64()) % 1000000007
      checksum = (checksum * 31 + (result.number_of_labels + 1).to_int64()) % 1000000007
      for value in result.map {
        checksum = (checksum * 31 + (value + 1).to_int64()) % 1000000007
      }
    }
    assert_eq(checksum, expected[configuration])
    assert_eq(failures, expected_failures[configuration])
    combined = (combined * 31 + checksum) % 1000000007
  }
  // the fold of the six checksums, the same constant as the Java side
  assert_eq(combined, 482399897L)
}

///|
/// The random image of a round: the pixels and the state of the generator
/// after it. The Java tool `ref/harness/tools/ThresholdCrossCheck.java` builds
/// **exactly the same** images.
///
/// The generator is advanced once per pixel in **every** shape, so the two
/// sides consume the same numbers even in the shapes that do not use them.
fn random_threshold_image(
  round : Int,
  width : Int,
  height : Int,
  state : Int
) -> (Array[Int], Int) {
  let size = width * height
  let pixels = Array::make(size, 0)
  let mut s = state
  let shape = round % 8
  for index in 0..<size {
    s = lcg_next(s)
    let mut value = 0
    if shape == 0 {
      // sixteen grey levels
      value = s % 16
    } else if shape == 1 {
      // two levels
      value = if s % 2 == 0 { 0 } else { 255 }
    } else if shape == 2 {
      // a ramp
      value = index % 256
    } else if shape == 3 {
      // a single grey level
      value = s % 256
    } else if shape == 4 {
      // sparse noise on a background
      value = if s % 10 == 0 { s % 256 } else { 0 }
    } else if shape == 5 {
      // completely black
      value = 0
    } else if shape == 6 {
      // a gradient
      let divisor = if size > 1 { size - 1 } else { 1 }
      value = (index * 255) / divisor
    } else {
      // two halves with two levels
      value = if index < size / 2 { 40 } else { 200 }
    }
    pixels[index] = value
  }
  (pixels, s)
}

///|
/// The two threshold plugins of the original match the port on random images.
///
/// The image corpus is a set of pictures, and a picture does not contain a
/// histogram on purpose — a histogram is exactly what the `OtsuThresholding_`
/// and the `Multi_OtsuThreshold` plugins consume. The cases a corpus does not
/// produce are the ones worth checking: a histogram with a single bin, one
/// with everything in the last bin, one with two levels, an empty one, and the
/// level counts 2, 3 and 4 of the multi level search.
///
/// The level count 5 is **not** fuzzed here — its search is four nested loops
/// over the 256 grey levels, about 160 million iterations per histogram, which
/// would make the test minutes long on the slower backends. The corpus of the
/// suite compares it on every one of its 25 images instead (the plugin hard
/// codes 4, but its `findMaxSigma` implements all of them and so does the
/// port).
///
/// The Java tool `ref/harness/tools/ThresholdCrossCheck.java` and this test
/// drive the **same** random images and pin the **same** checksums, so a
/// divergence shows up on the side that caused it.
test "the otsu thresholds match the original plugins on random images" {
  let widths = [
    24, 16, 32, 8, 12, 7, 20, 16,
  ]
  let heights = [
    20, 16, 24, 8, 10, 5, 32, 4,
  ]
  // the same checksums as the Java side (`ThresholdCrossCheck.java`)
  let expected = [
    600913906L,
    828034254L,
    59404614L,
    289251653L,
  ]
  // the number of images of every configuration - the search of the multi level
  // Otsu is a nested loop over the 256 grey levels, so the counts are scaled
  // by their cost
  let counts = [
    64, 32, 16, 8,
  ]
  // the level count of every configuration (0 is the single level Otsu)
  let mlevels = [
    0, 2, 3, 4,
  ]
  let mut combined = 0L
  for configuration in 0..<4 {
    // every configuration sees the same images
    let mut state = 20261030
    let mut checksum = 0L
    for round in 0..<counts[configuration] {
      let width = widths[round % 8]
      let height = heights[round % 8]
      let (pixels, next_state) = random_threshold_image(round, width, height, state)
      state = next_state
      let image = @moonbit_ImageSegmentation.GrayImage::from_pixels(width, height, pixels)
      if mlevels[configuration] == 0 {
        // the Otsu plugin: the threshold and the binary image
        let threshold = @moonbit_ImageSegmentation.otsu_threshold(image)
        checksum = (checksum * 31 + (threshold + 1).to_int64()) % 1000000007
        let binary = @moonbit_ImageSegmentation.otsu_threshold_image(image)
        for value in binary.pixels {
          checksum = (checksum * 31 + (value + 1).to_int64()) % 1000000007
        }
      } else {
        // the multi level search
        let result = @moonbit_ImageSegmentation.multi_otsu_thresholds(
          image.histogram(),
          mlevels[configuration],
        )
        for value in result.thresholds {
          checksum = (checksum * 31 + (value + 1).to_int64()) % 1000000007
        }
      }
    }
    assert_eq(checksum, expected[configuration])
    combined = (combined * 31 + checksum) % 1000000007
  }
  // the fold of the four checksums, the same constant as the Java side
  assert_eq(combined, 697755534L)
}

///|
/// The raw IEEE-754 bit pattern of a float, as an **unsigned** 32 bit value.
///
/// The Java side folds the same value with
/// `Float.floatToRawIntBits(value) & 0xFFFFFFFFL`, so that the checksum stays
/// positive on both sides.
fn float_bits(value : Float) -> Int64 {
  let bits = value.reinterpret_as_int()
  (bits.to_int64() & 0xFFFFFFFFL)
}

///|
/// The mixture model matches the original `MixtureModeling_` on random images.
///
/// The mixture model is the last of the histogram algorithms: it fits two
/// Gaussian components to the histogram and reports the mean, the variance,
/// the fitting error and two thresholds of the fit. Its output is floating
/// point, and the corpus compares it **bit for bit** — but only on the images
/// of the corpus.
///
/// The interesting inputs are the degenerate histograms: a single bin (one
/// component has no pixels at all), two levels, an empty one, a histogram
/// with everything in the last bin. On those the fit degenerates — the
/// component without pixels gets the variance zero, and its density function
/// then returns zero for every grey level instead of dividing by zero. The
/// result stays finite (the plugin never produces a NaN or an infinity), but
/// the means, the variances, the error and the thresholds are completely
/// different from the ones of a balanced histogram — the cases a corpus does
/// not contain.
///
/// The Java tool `ref/harness/tools/MixtureCrossCheck.java` and this test
/// drive the **same** random images and pin the **same** checksum, so a
/// divergence shows up on the side that caused it.
test "the mixture model matches the original MixtureModeling_ on random images" {
  let widths = [
    24, 16, 32, 8, 12, 7, 20, 16,
  ]
  let heights = [
    20, 16, 24, 8, 10, 5, 32, 4,
  ]
  let mut state = 20261101
  let mut checksum = 0L
  for round in 0..<64 {
    let width = widths[round % 8]
    let height = heights[round % 8]
    let (pixels, next_state) = random_threshold_image(round, width, height, state)
    state = next_state
    let image = @moonbit_ImageSegmentation.GrayImage::from_pixels(width, height, pixels)
    let result = @moonbit_ImageSegmentation.mixture_modeling(image)
    checksum = (checksum * 31 + float_bits(result.mu1) + 1) % 1000000007
    checksum = (checksum * 31 + float_bits(result.variance1) + 1) % 1000000007
    checksum = (checksum * 31 + float_bits(result.mu2) + 1) % 1000000007
    checksum = (checksum * 31 + float_bits(result.variance2) + 1) % 1000000007
    checksum = (checksum * 31 + float_bits(result.error_min) + 1) % 1000000007
    checksum = (checksum * 31 + float_bits(result.diff_mu) + 1) % 1000000007
    checksum = (checksum * 31 + (result.direct_threshold + 1).to_int64()) % 1000000007
    checksum = (checksum * 31 + float_bits(Float::from_int(result.real_threshold)) + 1) % 1000000007
    for value in result.image.pixels {
      checksum = (checksum * 31 + (value + 1).to_int64()) % 1000000007
    }
  }
  // the same checksum as the Java side (`MixtureCrossCheck.java`)
  assert_eq(checksum, 166889024L)
}

///|
/// The value clamped into `0..255`.
fn clamp_byte(value : Int) -> Int {
  if value < 0 {
    0
  } else if value > 255 {
    255
  } else {
    value
  }
}

///|
/// The random SIOX image of a round: the pixels, the grey levels that decide
/// the confidences and the state of the generator after it.
///
/// The generator is advanced **four** times per pixel in every shape, so that
/// the two sides consume the same numbers even in the shapes that do not use
/// them.
fn random_siox_image(
  round : Int,
  width : Int,
  height : Int,
  state : Int
) -> (Array[Int], Array[Int], Int) {
  let size = width * height
  let rgb = Array::make(size * 3, 0)
  let grey = Array::make(size, 0)
  let mut s = state
  let shape = round % 8
  for index in 0..<size {
    s = lcg_next(s)
    let a = s
    s = lcg_next(s)
    let b = s
    s = lcg_next(s)
    let c = s
    s = lcg_next(s)
    let d = s
    let x = index % width
    let mut level = 0
    let mut r = 0
    let mut g = 0
    let mut bl = 0
    if shape == 0 {
      // a dark and a bright half, greyish colours
      level = if x < width / 2 { 20 } else { 220 }
      r = clamp_byte(level + (a % 21) - 10)
      g = clamp_byte(level + (b % 21) - 10)
      bl = clamp_byte(level + (c % 21) - 10)
    } else if shape == 1 {
      // a dark and an unknown half, greyish colours
      level = if x < width / 2 { 20 } else { 128 }
      r = clamp_byte(level + (a % 21) - 10)
      g = clamp_byte(level + (b % 21) - 10)
      bl = clamp_byte(level + (c % 21) - 10)
    } else if shape == 2 {
      // completely random colours
      level = a % 256
      r = b % 256
      g = c % 256
      bl = d % 256
    } else if shape == 3 {
      // a gradient with the colours of the reference harness
      let divisor = if size > 1 { size - 1 } else { 1 }
      level = (index * 255) / divisor
      r = level
      g = (level * 3) / 4
      bl = 255 - level
    } else if shape == 4 {
      // completely black: no foreground signature at all
      level = 0
      r = 0
      g = 0
      bl = 0
    } else if shape == 5 {
      // completely white: no background signature at all
      level = 255
      r = 255
      g = 255
      bl = 255
    } else if shape == 6 {
      // a dark and a bright half with completely random colours - the colour
      // conversion is what decides the clusters here
      level = if x < width / 2 { 20 } else { 220 }
      r = b % 256
      g = c % 256
      bl = d % 256
    } else {
      // a random grey level with one dominant channel
      level = a % 256
      r = b % 256
      // the sum of two generator values overflows the 32 bit, so the low byte
      // is taken with a mask - the same arithmetic as in Java
      g = (b + c) & 0xFF
      bl = d % 256
    }
    grey[index] = level
    rgb[index * 3] = r
    rgb[index * 3 + 1] = g
    rgb[index * 3 + 2] = bl
  }
  (rgb, grey, s)
}

///|
/// The SIOX segmentation matches the original `SioxSegmentator` on random
/// images.
///
/// SIOX is the only algorithm of the suite whose **colour conversion** runs on
/// a platform dependent power: the sRGB gamma (the exponent 2.4) and the
/// CIELAB cube root (the exponent 1/3). The first audit measured that these
/// two exponents differ by one unit in the last place of the double on about
/// 0.1 % of the arguments, and that the difference is narrowed to a float
/// right afterwards, which absorbs it — unless it lands exactly on a float
/// rounding boundary, or unless it **flips a cluster boundary**: the Lab
/// coordinates decide the clusters, and a coordinate that differs in the last
/// bit can put a pixel in another cluster.
///
/// The corpus of the suite (25 images) never showed such a case. This test
/// looks for it with random colours: the Java tool
/// `ref/harness/tools/SioxCrossCheck.java` and this test drive the **same**
/// random images and pin the **same** checksum, so a divergence shows up on
/// the side that caused it.
///
/// The failure paths are part of the comparison: the original raises an
/// `IllegalStateException` when the foreground signature does not exist and
/// returns `false` when the background signature is empty. The number of
/// failing images is pinned as well.
test "the siox segmentation matches the original SioxSegmentator on random images" {
  let widths = [
    16, 20, 12, 24, 8, 32, 16, 28,
  ]
  let heights = [
    12, 16, 12, 20, 8, 24, 16, 14,
  ]
  let mut state = 20261102
  let mut checksum = 0L
  let mut failures = 0
  for round in 0..<64 {
    let width = widths[round % 8]
    let height = heights[round % 8]
    let (rgb, grey, next_state) = random_siox_image(round, width, height, state)
    state = next_state
    // the confidence matrix of the known strokes, exactly as the reference
    // harness builds it from the grey level
    let cm = Array::make(width * height, 0.0F)
    for index in 0..<(width * height) {
      let level = grey[index]
      cm[index] = if level <= 63 {
        0.0F
      } else if level >= 192 {
        1.0F
      } else {
        0.5F
      }
    }
    let image = @moonbit_ImageSegmentation.RgbImage::from_pixels(width, height, rgb)
    let result = @moonbit_ImageSegmentation.siox_segmentate(
      image,
      cm,
      1,
      4.0,
      @moonbit_ImageSegmentation.siox_default_limits(),
    )
    let mut failed = 0
    if result.failed {
      failed = 1
      failures = failures + 1
    }
    let mut success = 0
    if result.success {
      success = 1
    }
    checksum = (checksum * 31 + failed.to_int64()) % 1000000007
    checksum = (checksum * 31 + success.to_int64()) % 1000000007
    for value in result.confidence {
      checksum = (checksum * 31 + float_bits(value) + 1) % 1000000007
    }
  }
  // the number of images on which the original raises
  assert_eq(failures, 8)
  // the same checksum as the Java side (`SioxCrossCheck.java`)
  assert_eq(checksum, 15384133L)
}