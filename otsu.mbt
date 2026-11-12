///|
/// Port of ImageJ plugin `ij.process.GrayLevelClass` (shipped in the
/// `Otsu_Thresholding.jar` plugin by Christopher Mei / Maxime Dauphin).
///
/// The class tracks one gray-level class of the Otsu split: its `index`
/// (the current threshold candidate), the class weight `omega` and the
/// class mean `mu`. Two instances are advanced in lock-step (`add_to_end` /
/// `remove_from_beginning`) while the threshold is swept from 0 to 254.
///
/// The Java original keeps the probability histogram in **static** state
/// shared by both classes; here the histogram is passed in and shared by
/// reference instead, which is the same thing without global variables.
pub struct GrayLevelClass {
  index : Int
  omega : Float
  mu : Float
  probability_histogram : Array[Float]
}

///|
/// Build the class for the lower gray levels (`first = true`).
///
/// Java:
/// ```java
/// index = 1;
/// omega = probabilityHistogram[0];
/// mu = (omega == 0) ? 0 : 1 * probabilityHistogram[0] / omega;
/// ```
pub fn GrayLevelClass::first(
  probability_histogram : Array[Float]
) -> GrayLevelClass {
  let index = 1
  let omega = probability_histogram[0]
  let mu = if omega == 0.0F {
    0.0F
  } else {
    probability_histogram[0] * 1.0F / omega
  }
  { index, omega, mu, probability_histogram }
}

///|
/// Build the class for the upper gray levels (`first = false`).
///
/// Java:
/// ```java
/// index = 2; omega = 0; mu = 0;
/// for (int i = index; i < 256; i++) {
///     omega += probabilityHistogram[i - 1];
///     mu    += probabilityHistogram[i - 1] * i;
/// }
/// if (omega == 0) mu = 0; else mu /= omega;
/// ```
///
/// Note that the Java loop stops at `i < 256`, so bin 255 never contributes
/// to this class. The port keeps that behaviour verbatim.
pub fn GrayLevelClass::second(
  probability_histogram : Array[Float]
) -> GrayLevelClass {
  let index = 2
  let mut omega = 0.0F
  let mut mu = 0.0F
  let mut i = index
  while i < 256 {
    omega = omega + probability_histogram[i - 1]
    mu = mu + probability_histogram[i - 1] * Float::from_int(i)
    i = i + 1
  }
  let mu = if omega == 0.0F { 0.0F } else { mu / omega }
  { index, omega, mu, probability_histogram }
}

///|
/// Current threshold candidate (the Java `getThreshold()`).
pub fn GrayLevelClass::threshold(self : GrayLevelClass) -> Int {
  self.index
}

///|
/// Class weight (`omega`).
pub fn GrayLevelClass::get_omega(self : GrayLevelClass) -> Float {
  self.omega
}

///|
/// Class mean (`mu`).
pub fn GrayLevelClass::get_mu(self : GrayLevelClass) -> Float {
  self.mu
}

///|
/// Java `addToEnd()`: grow the lower class by one gray level.
///
/// Returns the updated class; the Java original mutates the instance in
/// place, the port is purely functional.
pub fn GrayLevelClass::add_to_end(self : GrayLevelClass) -> GrayLevelClass {
  let index = self.index + 1
  let mut omega = 0.0F
  let mut mu = 0.0F
  let mut i = 1
  while i < index {
    omega = omega + self.probability_histogram[i - 1]
    mu = mu + self.probability_histogram[i - 1] * Float::from_int(i)
    i = i + 1
  }
  let mu = if omega == 0.0F { 0.0F } else { mu / omega }
  {
    index,
    omega,
    mu,
    probability_histogram: self.probability_histogram,
  }
}

///|
/// Java `removeFromBeginning()`: shrink the upper class by one gray level.
pub fn GrayLevelClass::remove_from_beginning(
  self : GrayLevelClass
) -> GrayLevelClass {
  let index = self.index + 1
  let mut omega = 0.0F
  let mut mu = 0.0F
  let mut i = index
  while i < 256 {
    omega = omega + self.probability_histogram[i - 1]
    mu = mu + self.probability_histogram[i - 1] * Float::from_int(i)
    i = i + 1
  }
  let mu = if omega == 0.0F { 0.0F } else { mu / omega }
  {
    index,
    omega,
    mu,
    probability_histogram: self.probability_histogram,
  }
}

///|
/// Otsu threshold of a grayscale image.
///
/// Port of `OtsuThresholding_.run(ImageProcessor)` from the
/// `Otsu_Thresholding.jar` plugin. The plugin computes the threshold by
/// maximizing
///
/// ```text
/// sigma = omega1 * (mu1 - fullMu)^2 + omega2 * (mu2 - fullMu)^2
/// ```
///
/// over `i = 0..254`, where `fullMu = omega1 * mu1 + omega2 * mu2`.
///
/// The returned value is the threshold in `0..255`.
pub fn otsu_threshold(img : GrayImage) -> Int {
  let width = img.width
  let height = img.height
  let n = width * height
  let hist = img.histogram()
  let probability_histogram = Array::make(256, 0.0F)
  let nf = Float::from_int(n)
  let mut i = 0
  while i < 256 {
    probability_histogram[i] = Float::from_int(hist[i]) / nf
    i = i + 1
  }
  let mut c1 = GrayLevelClass::first(probability_histogram)
  let mut c2 = GrayLevelClass::second(probability_histogram)
  let full_mu = c1.get_omega() * c1.get_mu() + c2.get_omega() * c2.get_mu()
  let mut sigma_max = 0.0
  let mut threshold = 0
  let mut i = 0
  while i < 255 {
    // Java: C1.getOmega() * (Math.pow(C1.getMu() - fullMu, 2))
    // The subtraction happens in float precision, the power in double.
    let d1 = c1.get_mu() - full_mu
    let d2 = c2.get_mu() - full_mu
    let sigma = c1.get_omega().to_double() * pow2(d1.to_double()) +
      c2.get_omega().to_double() * pow2(d2.to_double())
    if sigma > sigma_max {
      sigma_max = sigma
      threshold = c1.threshold()
    }
    c1 = c1.add_to_end()
    c2 = c2.remove_from_beginning()
    i = i + 1
  }
  threshold
}

///|
/// `x^2` computed the way `java.lang.Math.pow(x, 2)` computes it: a general
/// power, not a multiplication.
fn pow2(x : Double) -> Double {
  @math.pow(x, 2.0)
}

///|
/// Binary image produced by the Otsu plugin: background is white (255) and
/// every pixel with `value <= threshold` becomes black (0).
///
/// Port of the pixel loop at the end of `OtsuThresholding_.run`.
pub fn otsu_threshold_image(img : GrayImage) -> GrayImage {
  let threshold = otsu_threshold(img)
  apply_threshold(img, threshold)
}

///|
/// Binary image for an already computed threshold: pixels `<= threshold`
/// become 0, everything else stays 255.
pub fn apply_threshold(img : GrayImage, threshold : Int) -> GrayImage {
  let out = GrayImage::new(img.width, img.height, 255)
  let src = img.pixels
  let dst = out.pixels
  let n = src.length()
  let mut i = 0
  while i < n {
    if src[i] <= threshold {
      dst[i] = 0
    }
    i = i + 1
  }
  out
}
