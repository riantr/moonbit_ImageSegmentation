///|
/// Port of the reusable numeric helpers of the `RetFM_J` ImageJ plugin
/// (Hedberg-Buenz et al. 2015, "RetFM-J, an ImageJ-based module for
/// automated counting and quantifying features of nuclei in retinal
/// whole-mounts").
///
/// The plugin itself is a GUI application; the two pieces that carry actual
/// image processing are ported here: the channel-averaging grayscale
/// conversion and the Otsu threshold search.

///|
/// Otsu threshold of a grayscale image.
///
/// Port of `RetFM_J.getThreshold(ImageProcessor)`: the threshold maximizes
/// `(pUnder/pixels) * (pOver/pixels) * (mUnder - mOver)^2`, with `double`
/// accumulators (unlike the `Otsu_Thresholding` plugin, which uses
/// `float`).
pub fn retfm_otsu_threshold(img : GrayImage) -> Int {
  let hist = img.histogram()
  let pixels = img.width * img.height
  let mut p_under = 0.0
  let mut p_over = 0.0
  let mut s_under = 0.0
  let mut s_over = 0.0
  let mut max = 0.0
  let mut t = 0
  let mut i = 0
  while i < hist.length() {
    s_over = s_over + Double::from_int(i * hist[i])
    i = i + 1
  }
  i = 0
  while i < hist.length() {
    p_under = p_under + Double::from_int(hist[i])
    p_over = Double::from_int(pixels) - p_under
    if p_under == 0.0 || p_over == 0.0 {
      i = i + 1
      continue
    }
    s_under = s_under + Double::from_int(i * hist[i])
    s_over = s_over - Double::from_int(i * hist[i])
    let m_under = s_under / p_under
    let m_over = s_over / p_over
    let check = (p_under / Double::from_int(pixels)) *
      (p_over / Double::from_int(pixels)) *
      (m_under - m_over) * (m_under - m_over)
    if check > max {
      max = check
      t = i
    }
    i = i + 1
  }
  t
}

///|
/// Convert an RGB image to grayscale by averaging the selected channels.
///
/// Port of `RetFM_J.convertToGrayscale(ColorProcessor)` combined with
/// `RetFM_J.addImages(FloatProcessor, FloatProcessor)`:
/// the channels are summed in `float` precision, divided by the number of
/// selected channels and finally converted to bytes with
/// `FloatProcessor.convertToByte(false)`, i.e. `(byte)(value + 0.5)`.
pub fn retfm_convert_to_grayscale(
  img : RgbImage,
  use_channels : Array[Bool]
) -> GrayImage {
  let n = img.width * img.height
  let gray = Array::make(n, 0.0F)
  let mut count = 0
  let mut c = 0
  while c < use_channels.length() {
    if use_channels[c] {
      let mut i = 0
      while i < n {
        // Java `color.getChannel(i + 1, null)`: channel 1 is the red, 2 the
        // green, 3 the blue channel and every other channel number yields a
        // zero image. A channel index beyond the third therefore contributes
        // zeros (but still counts towards the divisor).
        let value = if c == 0 {
          img.red(i % img.width, i / img.width)
        } else if c == 1 {
          img.green(i % img.width, i / img.width)
        } else if c == 2 {
          img.blue(i % img.width, i / img.width)
        } else {
          0
        }
        gray[i] = gray[i] + Float::from_int(value)
        i = i + 1
      }
      count = count + 1
    }
    c = c + 1
  }
  let factor = 1.0 / Double::from_int(count)
  let mut i = 0
  while i < n {
    gray[i] = Float::from_double(gray[i].to_double() * factor)
    i = i + 1
  }
  let out = GrayImage::new(img.width, img.height, 0)
  i = 0
  while i < n {
    // Java `(byte)(pixels[i] + 0.5)`: the sum is evaluated in double
    // precision and the narrowing conversion of a NaN yields 0. When no
    // channel is selected the divisor is zero, the multiplication produces
    // NaN and the Java original returns an all zero image - MoonBit's
    // `to_int` would trap on the NaN instead.
    let v = gray[i].to_double() + 0.5
    let byte = java_double_to_int(v)
    out.pixels[i] = byte & 0xff
    i = i + 1
  }
  out
}

///|
/// Threshold a grayscale image the way `ImageProcessor.threshold(int)` does
/// and invert it like `ImageProcessor.invert()`.
///
/// `threshold(t)` sets a pixel to 255 when its value is **greater** than
/// `t` and to 0 otherwise; `invert()` maps 0 to 255 and 255 to 0.
pub fn retfm_threshold_and_invert(img : GrayImage, threshold : Int) -> GrayImage {
  let out = GrayImage::new(img.width, img.height, 0)
  let n = img.width * img.height
  let mut i = 0
  while i < n {
    if img.pixels[i] > threshold {
      out.pixels[i] = 255
    }
    i = i + 1
  }
  i = 0
  while i < n {
    out.pixels[i] = if out.pixels[i] == 0 { 255 } else { 0 }
    i = i + 1
  }
  out
}
