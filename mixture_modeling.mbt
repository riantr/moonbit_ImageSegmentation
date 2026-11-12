///|
/// Port of the `Mixture_Modeling` ImageJ plugin (Christopher Mei /
/// Maxime Dauphin, 2003).
///
/// The image histogram is modelled as a two-component Gaussian mixture;
/// the plugin sweeps the split index, keeps the split with the smallest
/// fitting error and finally refines the threshold by looking for the
/// minimum of the squared difference between the two component densities.
///
/// The Java original is written with `float` (f32) accumulators and casts
/// the results of `Math.pow` / `Math.exp` back to `float`; those roundings
/// are reproduced exactly.
priv struct MixtureValues {
  index : Int
  mu1 : Float
  mu2 : Float
  sigma2_1 : Float
  sigma2_2 : Float
  mult1 : Float
  mult2 : Float
  two_variance1 : Float
  two_variance2 : Float
}

///|
/// Maximum gray level of the histogram (Java `GrayLevelClassMixtureModeling.MAX`).
pub const MIXTURE_MAX : Int = 255

///|
/// Minimum split index (Java `INDEX_MIN`).
pub const MIXTURE_INDEX_MIN : Int = 1

///|
/// Maximum split index (Java `INDEX_MAX`).
pub const MIXTURE_INDEX_MAX : Int = 253

///|
/// Java `calculateMax(int index)`: the average of the histogram bin `index`
/// and its two neighbours (whichever exist).
fn mixture_calculate_max(histogram : Array[Int], index : Int) -> Float {
  let mut sum = Float::from_int(histogram[index])
  let mut num = 1.0F
  if index - 1 >= 0 {
    sum = sum + Float::from_int(histogram[index - 1])
    num = num + 1.0F
  }
  if index + 1 < MIXTURE_MAX {
    sum = sum + Float::from_int(histogram[index + 1])
    num = num + 1.0F
  }
  sum / num
}

///|
/// Java `setValues()`: compute all statistics for the current split index.
fn mixture_values(index : Int, histogram : Array[Int]) -> MixtureValues {
  let mut mu1 = 0.0F
  let mut mu2 = 0.0F
  let mut sigma2_1 = 0.0F
  let mut sigma2_2 = 0.0F
  let mut cardinal1 = 0
  let mut cardinal2 = 0
  let mut i = 0
  while i <= index {
    cardinal1 = cardinal1 + histogram[i]
    mu1 = mu1 + Float::from_int(i * histogram[i])
    i = i + 1
  }
  i = index + 1
  while i <= MIXTURE_MAX {
    cardinal2 = cardinal2 + histogram[i]
    mu2 = mu2 + Float::from_int(i * histogram[i])
    i = i + 1
  }
  if cardinal1 == 0 {
    mu1 = 0.0F
    sigma2_1 = 0.0F
  } else {
    mu1 = mu1 / Float::from_int(cardinal1)
  }
  if cardinal2 == 0 {
    mu2 = 0.0F
    sigma2_2 = 0.0F
  } else {
    mu2 = mu2 / Float::from_int(cardinal2)
  }
  let mut max1 = 0.0F
  let mut max2 = 0.0F
  let mut mult1 = 0.0F
  let mut mult2 = 0.0F
  let mut two_variance1 = 0.0F
  let mut two_variance2 = 0.0F
  if mu1 != 0.0F {
    i = 0
    while i <= index {
      // Java: sigma2_1 += histogram[i] * Math.pow(i - mu1, 2);
      // the product is computed in double and narrowed back to float.
      let d = Float::from_int(i) - mu1
      let term = Double::from_int(histogram[i]) * @math.pow(d.to_double(), 2.0)
      sigma2_1 = Float::from_double(sigma2_1.to_double() + term)
      i = i + 1
    }
    sigma2_1 = sigma2_1 / Float::from_int(cardinal1)
    max1 = mixture_calculate_max(histogram, java_float_to_int(mu1))
    mult1 = max1
    two_variance1 = 2.0F * sigma2_1
  }
  if mu2 != 0.0F {
    i = index + 1
    while i <= MIXTURE_MAX {
      let d = Float::from_int(i) - mu2
      let term = Double::from_int(histogram[i]) * @math.pow(d.to_double(), 2.0)
      sigma2_2 = Float::from_double(sigma2_2.to_double() + term)
      i = i + 1
    }
    sigma2_2 = sigma2_2 / Float::from_int(cardinal2)
    max2 = mixture_calculate_max(histogram, java_float_to_int(mu2))
    mult2 = max2
    two_variance2 = 2.0F * sigma2_2
  }
  {
    index,
    mu1,
    mu2,
    sigma2_1,
    sigma2_2,
    mult1,
    mult2,
    two_variance1,
    two_variance2,
  }
}

///|
/// Java `gamma1(int i)`: density of the first component.
fn mixture_gamma1(v : MixtureValues, i : Int) -> Float {
  if v.sigma2_1 == 0.0F {
    return 0.0F
  }
  let d = Float::from_int(i) - v.mu1
  let num = @math.pow(d.to_double(), 2.0)
  let e = @math.exp(-(num / v.two_variance1.to_double()))
  Float::from_double(v.mult1.to_double() * e)
}

///|
/// Java `gamma2(int i)`: density of the second component.
fn mixture_gamma2(v : MixtureValues, i : Int) -> Float {
  if v.sigma2_2 == 0.0F {
    return 0.0F
  }
  let d = Float::from_int(i) - v.mu2
  let num = @math.pow(d.to_double(), 2.0)
  let e = @math.exp(-(num / v.two_variance2.to_double()))
  Float::from_double(v.mult2.to_double() * e)
}

///|
/// Java `gamma(int i)`: sum of both component densities.
fn mixture_gamma(v : MixtureValues, i : Int) -> Float {
  mixture_gamma1(v, i) + mixture_gamma2(v, i)
}

///|
/// Java `differenceGamma(int i)`.
fn mixture_difference_gamma(v : MixtureValues, i : Int) -> Float {
  mixture_gamma1(v, i) - mixture_gamma2(v, i)
}

///|
/// Java `calculateError(GrayLevelClassMixtureModeling)`.
fn mixture_calculate_error(v : MixtureValues, histogram : Array[Int]) -> Float {
  let mut error = 0.0F
  let mut i = 0
  while i <= MIXTURE_MAX {
    let d = mixture_gamma(v, i) - Float::from_int(histogram[i])
    let term = @math.pow(d.to_double(), 2.0)
    error = Float::from_double(error.to_double() + term)
    i = i + 1
  }
  error / Float::from_int(MIXTURE_MAX + 1)
}

///|
/// Java `findThreshold(int mu1, int mu2, GrayLevelClassMixtureModeling)`.
fn mixture_find_threshold(
  mu1 : Int,
  mu2 : Int,
  v : MixtureValues
) -> Int {
  let mut min = 9999999.0F
  let mut threshold = 0
  let mut i = mu1
  while i < mu2 {
    let val = Float::from_double(
      @math.pow(mixture_difference_gamma(v, i).to_double(), 2.0)
    )
    if min > val {
      min = val
      threshold = i
    }
    i = i + 1
  }
  threshold
}

///|
/// Result of the mixture modelling thresholding.
pub struct MixtureModelingResult {
  /// the split index with the smallest fitting error
  direct_threshold : Int
  /// the refined threshold derived from the component densities
  real_threshold : Int
  /// mean of the first component
  mu1 : Float
  /// mean of the second component
  mu2 : Float
  /// variance of the first component
  variance1 : Float
  /// variance of the second component
  variance2 : Float
  /// smallest fitting error
  error_min : Float
  /// `mu2 - mu1`
  diff_mu : Float
  /// the binarised image (255 where the pixel is above the threshold)
  image : GrayImage
}

///|
/// Threshold a grayscale image with the Gaussian mixture model.
///
/// Port of `MixtureModeling_.run(ImageProcessor)`.
pub fn mixture_modeling(img : GrayImage) -> MixtureModelingResult {
  let histogram = img.histogram()
  let mut error_min = 9999999.0F
  let mut threshold = 0
  let mut mu1 = 0.0F
  let mut variance1 = 0.0F
  let mut mu2 = 0.0F
  let mut variance2 = 0.0F
  let mut index = MIXTURE_INDEX_MIN - 1
  let mut running = true
  while running {
    index = index + 1
    if index > MIXTURE_INDEX_MAX {
      running = false
    } else {
      let v = mixture_values(index, histogram)
      let error = mixture_calculate_error(v, histogram)
      if error < error_min {
        error_min = error
        threshold = v.index
        mu1 = v.mu1
        variance1 = v.sigma2_1
        mu2 = v.mu2
        variance2 = v.sigma2_2
      }
    }
  }
  let final_values = mixture_values(threshold, histogram)
  let real_threshold = mixture_find_threshold(
    java_float_to_int(mu1),
    java_float_to_int(mu2),
    final_values
  )
  let out = GrayImage::new(img.width, img.height, 0)
  let pixels = img.pixels
  let mut i = 0
  while i < pixels.length() {
    if pixels[i] > real_threshold {
      out.pixels[i] = 255
    }
    i = i + 1
  }
  {
    direct_threshold: threshold,
    real_threshold,
    mu1,
    mu2,
    variance1,
    variance2,
    error_min,
    diff_mu: mu2 - mu1,
    image: out,
  }
}
