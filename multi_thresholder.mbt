///|
/// Port of the GUI independent core of the `Multi_Thresholder` ImageJ plugin
/// (a port of G. Landini's Auto_Threshold plugin).
///
/// Despite its name the plugin computes a **single** threshold with one of
/// the 15 `AutoThresholder` methods (ported in `auto_threshold.mbt`) and
/// uses it to derive the lower/upper threshold pair that drives the
/// display LUT. The actual binarisation is delegated to ImageJ's "Convert
/// to Mask" command and is therefore not part of this port.
///
/// What is reproduced here are the level mapping helpers and the rule that
/// turns one threshold into the lower/upper pair.
///|
/// The "no threshold" marker of the plugin.
///
/// The shipped `Multi_Thresholder` class was compiled against an ImageJ
/// whose `ImageProcessor.NO_THRESHOLD` was `-808080.0`, and that value is
/// baked into the bytecode of the class. The port follows the shipped
/// class, so that it reproduces the behaviour of the original plugin
/// exactly.
///
/// A modern ImageJ uses `Double.MAX_VALUE` (1.7976931348623157E308)
/// instead; recompiling the plugin's source against it would change the
/// result of the `NO_THRESHOLD` branch (the threshold would be scaled
/// instead of being left alone).
pub const NO_THRESHOLD : Double = -808080.0

///|
/// Whether the image is displayed with an inverted lookup table.
pub enum LutMode {
  Normal
  Inverted
}

///|
/// Build a `LutMode::Normal` value.
pub fn LutMode::normal() -> LutMode {
  LutMode::Normal
}

///|
/// Build a `LutMode::Inverted` value.
pub fn LutMode::inverted() -> LutMode {
  LutMode::Inverted
}

///|
/// Whether the background is dark (the "dark background" checkbox).
pub enum BackgroundMode {
  Dark
  Light
}

///|
/// Build a `BackgroundMode::Dark` value.
pub fn BackgroundMode::dark() -> BackgroundMode {
  BackgroundMode::Dark
}

///|
/// Build a `BackgroundMode::Light` value.
pub fn BackgroundMode::light() -> BackgroundMode {
  BackgroundMode::Light
}

///|
/// The lower/upper threshold pair of a single threshold.
///
/// Java `Multi_Thresholder.setThreshold(double threshold, ImagePlus imp)`:
///
/// ```text
/// if (darkBackground) { invertedLut ? (0, t) : (t, max) }
/// else                { invertedLut ? (t, max) : (0, t) }
/// ```
///
/// The threshold that is put into the pair is the *scaled* one (see
/// `scale_up`); `set_threshold` does the scaling and the pairing in one
/// step, exactly like the Java method does.
pub struct ThresholdPair {
  lower : Double
  upper : Double
}

///|
/// Map a threshold from the 0..255 scale to the actual pixel levels.
///
/// Java `Multi_Thresholder.scaleUp(ImageProcessor, double)`.
pub fn scale_up(image_min : Double, image_max : Double, threshold : Double) -> Double {
  if image_max > image_min {
    image_min + (threshold / 255.0) * (image_max - image_min)
  } else {
    NO_THRESHOLD
  }
}

///|
/// Map a threshold from the actual pixel levels back to the 0..255 scale.
///
/// Java `Multi_Thresholder.scaleDown(ImageProcessor, double)`; for 8-bit
/// images the threshold is already on the 0..255 scale and is returned
/// unchanged.
pub fn scale_down(
  is_byte_image : Bool,
  image_min : Double,
  image_max : Double,
  threshold : Double
) -> Double {
  if is_byte_image {
    threshold
  } else if image_max > image_min {
    ((threshold - image_min) / (image_max - image_min)) * 255.0
  } else {
    NO_THRESHOLD
  }
}

///|
/// Map both levels of a threshold pair to the actual pixel levels.
///
/// Java `Multi_Thresholder.scaleUpAndSet(ImageProcessor, double, double)`.
pub fn scale_up_pair(
  is_byte_image : Bool,
  image_min : Double,
  image_max : Double,
  lower : Double,
  upper : Double
) -> (Double, Double) {
  if !is_byte_image && lower != NO_THRESHOLD {
    if image_max > image_min {
      (
        image_min + (lower / 255.0) * (image_max - image_min),
        image_min + (upper / 255.0) * (image_max - image_min),
      )
    } else {
      (NO_THRESHOLD, upper)
    }
  } else {
    (lower, upper)
  }
}

///|
/// The lower/upper threshold pair for a single *scaled* threshold.
///
/// Java `Multi_Thresholder.setThreshold(double, ImagePlus)`, see
/// `ThresholdPair`.
pub fn threshold_pair(
  scaled_threshold : Double,
  image_max : Double,
  lut : LutMode,
  background : BackgroundMode
) -> ThresholdPair {
  match (background, lut) {
    (BackgroundMode::Dark, LutMode::Inverted) => {
      lower: 0.0, upper: scaled_threshold
    }
    (BackgroundMode::Dark, LutMode::Normal) => {
      lower: scaled_threshold, upper: image_max
    }
    (BackgroundMode::Light, LutMode::Inverted) => {
      lower: scaled_threshold, upper: image_max
    }
    (BackgroundMode::Light, LutMode::Normal) => {
      lower: 0.0, upper: scaled_threshold
    }
  }
}

///|
/// The lower/upper threshold pair of a threshold on the 0..255 scale.
///
/// Java `Multi_Thresholder.setThreshold(double threshold, ImagePlus imp)`:
/// the threshold is first scaled to the actual pixel levels and then
/// turned into the lower/upper pair.
pub fn set_threshold(
  threshold : Double,
  image_min : Double,
  image_max : Double,
  lut : LutMode,
  background : BackgroundMode
) -> ThresholdPair {
  threshold_pair(
    scale_up(image_min, image_max, threshold),
    image_max,
    lut,
    background
  )
}

///|
/// The raw IEEE-754 bits of a double, as 16 hex digits.
///
/// The Java reference writes the results of the level mapping helpers this
/// way, so that the two sides can be compared byte for byte.
fn double_bits_hex(value : Double) -> String {
  let digits = [
    "0", "1", "2", "3", "4", "5", "6", "7",
    "8", "9", "a", "b", "c", "d", "e", "f",
  ]
  let bits = value.reinterpret_as_int64()
  let mut out = ""
  let mut shift = 60
  while shift >= 0 {
    let nibble = ((bits >> shift) & 0xFL).to_int()
    out = out + digits[nibble]
    shift = shift - 4
  }
  out
}

///|
/// The table of the level mapping helpers of the Multi_Thresholder plugin.
///
/// The Java reference harness writes the very same table, computed by the
/// *original compiled* plugin class. Every line has the shape
///
/// ```text
/// <kind> t=<threshold> <operation> => <result>...
/// ```
///
/// and every result is the raw IEEE-754 bits of a double, so that the two
/// sides can be compared byte for byte.
///
/// The matrix covers the two processor kinds of the plugin (8 bit and 16
/// bit, with the value ranges 0..255 and 0..65535) and the four
/// thresholds 0, 73, 128 and 255. It is independent of the image that is
/// segmented.
pub fn multi_thresholder_table() -> Array[String] {
  let lines = []
  let kinds = [
    ("byte", true, 0.0, 255.0),
    ("short", false, 0.0, 65535.0),
  ]
  let thresholds = [0.0, 73.0, 128.0, 255.0]
  let mut k = 0
  while k < kinds.length() {
    let (name, is_byte, image_min, image_max) = kinds[k]
    let max_text = image_max.to_int().to_string()
    let mut t = 0
    while t < thresholds.length() {
      let threshold = thresholds[t]
      let threshold_text = threshold.to_int().to_string()
      let head = name + " t=" + threshold_text
      lines.push(
        head +
        " scaleUp(0," +
        max_text +
        ") => " +
        double_bits_hex(scale_up(image_min, image_max, threshold))
      )
      lines.push(
        head +
        " scaleDown(0," +
        max_text +
        ") => " +
        double_bits_hex(scale_down(is_byte, image_min, image_max, threshold))
      )
      let (lower1, upper1) = scale_up_pair(
        is_byte,
        image_min,
        image_max,
        0.0,
        threshold
      )
      lines.push(
        head +
        " scaleUpAndSet(0," +
        threshold_text +
        ") => " +
        double_bits_hex(lower1) +
        " " +
        double_bits_hex(upper1)
      )
      let (lower2, upper2) = scale_up_pair(
        is_byte,
        image_min,
        image_max,
        threshold,
        image_max
      )
      lines.push(
        head +
        " scaleUpAndSet(" +
        threshold_text +
        "," +
        max_text +
        ") => " +
        double_bits_hex(lower2) +
        " " +
        double_bits_hex(upper2)
      )
      let (lower3, upper3) = scale_up_pair(
        is_byte,
        image_min,
        image_max,
        NO_THRESHOLD,
        image_max
      )
      lines.push(
        head +
        " scaleUpAndSet(NO_THRESHOLD," +
        max_text +
        ") => " +
        double_bits_hex(lower3) +
        " " +
        double_bits_hex(upper3)
      )
      let mut dark = 0
      while dark < 2 {
        let mut inverted = 0
        while inverted < 2 {
          let background = if dark == 0 {
            BackgroundMode::Light
          } else {
            BackgroundMode::Dark
          }
          let lut = if inverted == 0 {
            LutMode::Normal
          } else {
            LutMode::Inverted
          }
          let pair = set_threshold(
            threshold,
            image_min,
            image_max,
            lut,
            background
          )
          lines.push(
            head +
            " setThreshold(dark=" +
            dark.to_string() +
            ",inverted=" +
            inverted.to_string() +
            ") => " +
            double_bits_hex(pair.lower) +
            " " +
            double_bits_hex(pair.upper)
          )
          inverted = inverted + 1
        }
        dark = dark + 1
      }
      t = t + 1
    }
    k = k + 1
  }
  lines
}
