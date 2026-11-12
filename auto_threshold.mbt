///|
/// Port of `AutoThresholder` (bundled with the `Multi_Thresholder.jar`
/// ImageJ plugin, itself a port of G. Landini's Auto_Threshold plugin).
///
/// Every method takes the 256-bin intensity histogram of an 8-bit image and
/// returns a single threshold. All arithmetic in the Java original is
/// `double` (f64) with a few `int` accumulators; those are reproduced here
/// as `Int` (i32) so that 32-bit overflow behaves identically.
///
/// The Java dispatch is `Arrays.binarySearch` over a sorted method table;
/// `auto_threshold` below does the same lookup by name.
///
/// An unknown method name is an error in the Java original
/// (`IllegalArgumentException("Method not found")`). MoonBit cannot raise a
/// catchable error, so the port aborts with the same message instead of
/// returning a threshold that no caller could interpret.
pub fn auto_threshold(method_name : String, histogram : Array[Int]) -> Int {
  match method_name {
    "Huang" => auto_threshold_huang(histogram)
    "Intermodes" => auto_threshold_intermodes(histogram)
    "IsoData" => auto_threshold_isodata(histogram)
    "Li" => auto_threshold_li(histogram)
    "MaxEntropy" => auto_threshold_max_entropy(histogram)
    "Mean" => auto_threshold_mean(histogram)
    "MinError(I)" => auto_threshold_min_error_i(histogram)
    "Minimum" => auto_threshold_minimum(histogram)
    "Moments" => auto_threshold_moments(histogram)
    "Otsu" => auto_threshold_otsu(histogram)
    "Percentile" => auto_threshold_percentile(histogram)
    "RenyiEntropy" => auto_threshold_renyi_entropy(histogram)
    "Shanbhag" => auto_threshold_shanbhag(histogram)
    "Triangle" => auto_threshold_triangle(histogram)
    "Yen" => auto_threshold_yen(histogram)
    _ => abort("Method not found: " + method_name)
  }
}

///|
/// Names of the 15 supported methods, in the order of the Java table.
pub fn auto_threshold_methods() -> Array[String] {
  [
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
}

///|
/// `java.lang.Math.round(double)` = `floor(x + 0.5)`.
fn java_round(x : Double) -> Int {
  java_round_double(x)
}

///|
/// `java.lang.Math.log10` as implemented in the Java source, i.e. the
/// quotient `log(x) / log(10)` and *not* `Math.log10`.
fn java_log10(x : Double) -> Double {
  @math.ln(x) / @math.ln(10.0)
}

///|
/// Huang's fuzzy thresholding (fuzziness measure minimisation).
///
/// Port of `AutoThresholder.Huang(int[])`.
pub fn auto_threshold_huang(data : Array[Int]) -> Int {
  let mut threshold = -1
  let mut first_bin = 0
  let mut ih = 0
  while ih < 256 {
    if data[ih] != 0 {
      first_bin = ih
      break
    }
    ih = ih + 1
  }
  let mut last_bin = 255
  ih = 255
  while ih >= first_bin {
    if data[ih] != 0 {
      last_bin = ih
      break
    }
    ih = ih - 1
  }
  let term = 1.0 / Double::from_int(last_bin - first_bin)
  let mu_0 = Array::make(256, 0.0)
  let mu_1 = Array::make(256, 0.0)
  let mut sum_pix = 0
  let mut num_pix = 0
  ih = first_bin
  while ih < 256 {
    sum_pix = sum_pix + ih * data[ih]
    num_pix = num_pix + data[ih]
    mu_0[ih] = Double::from_int(sum_pix) / Double::from_int(num_pix)
    ih = ih + 1
  }
  sum_pix = 0
  num_pix = 0
  ih = last_bin
  while ih > 0 {
    sum_pix = sum_pix + ih * data[ih]
    num_pix = num_pix + data[ih]
    mu_1[ih - 1] = Double::from_int(sum_pix) / Double::from_int(num_pix)
    ih = ih - 1
  }
  let mut min_ent = 1.7976931348623157e308
  let mut it = 0
  while it < 256 {
    let mut ent = 0.0
    ih = 0
    while ih <= it {
      let mu_x = 1.0 / (1.0 + term * (ih.to_double() - mu_0[it]).abs())
      if !((mu_x < 0.000001) || (mu_x > 0.999999)) {
        ent = ent +
          Double::from_int(data[ih]) *
          (-mu_x * @math.ln(mu_x) - (1.0 - mu_x) * @math.ln(1.0 - mu_x))
      }
      ih = ih + 1
    }
    ih = it + 1
    while ih < 256 {
      let mu_x = 1.0 / (1.0 + term * (ih.to_double() - mu_1[it]).abs())
      if !((mu_x < 0.000001) || (mu_x > 0.999999)) {
        ent = ent +
          Double::from_int(data[ih]) *
          (-mu_x * @math.ln(mu_x) - (1.0 - mu_x) * @math.ln(1.0 - mu_x))
      }
      ih = ih + 1
    }
    if ent < min_ent {
      min_ent = ent
      threshold = it
    }
    it = it + 1
  }
  threshold
}

///|
/// Java `bimodalTest`: true iff the histogram has exactly two strict local
/// maxima.
fn bimodal_test(y : Array[Double]) -> Bool {
  let len = y.length()
  let mut modes = 0
  let mut k = 1
  while k < len - 1 {
    if y[k - 1] < y[k] && y[k + 1] < y[k] {
      modes = modes + 1
      if modes > 2 {
        return false
      }
    }
    k = k + 1
  }
  modes == 2
}

///|
/// In-place 3-point running-mean smoothing used by `Intermodes` and
/// `Minimum`.
///
/// The Java code aliases `tHisto` and `iHisto` to the *same* array, so the
/// smoothing is sequential and in place: the left neighbour read at index
/// `i` has already been smoothed in this pass. That aliasing is reproduced
/// here on purpose.
fn smooth_in_place(i_histo : Array[Double]) -> Unit {
  let mut i = 1
  while i < 255 {
    i_histo[i] = (i_histo[i - 1] + i_histo[i] + i_histo[i + 1]) / 3.0
    i = i + 1
  }
  i_histo[0] = (i_histo[0] + i_histo[1]) / 3.0
  i_histo[255] = (i_histo[254] + i_histo[255]) / 3.0
}

///|
/// Prewitt & Mendelsohn "intermodes" threshold (mean of the two modes).
pub fn auto_threshold_intermodes(data : Array[Int]) -> Int {
  let i_histo = Array::make(256, 0.0)
  let mut i = 0
  while i < 256 {
    i_histo[i] = Double::from_int(data[i])
    i = i + 1
  }
  let mut iter = 0
  while !bimodal_test(i_histo) {
    smooth_in_place(i_histo)
    iter = iter + 1
    if iter > 10000 {
      return -1
    }
  }
  let mut tt = 0
  i = 1
  while i < 255 {
    if i_histo[i - 1] < i_histo[i] && i_histo[i + 1] < i_histo[i] {
      tt = tt + i
    }
    i = i + 1
  }
  java_double_to_int(@math.floor(Double::from_int(tt) / 2.0))
}

///|
/// Isodata / intermeans threshold (Ridler & Calvard).
pub fn auto_threshold_isodata(data : Array[Int]) -> Int {
  let max_value = data.length() - 1
  let mut min = 0
  while data[min] == 0 && min < max_value {
    min = min + 1
  }
  let mut max = max_value
  while data[max] == 0 && max > 0 {
    max = max - 1
  }
  if min >= max {
    return data.length() / 2
  }
  let mut moving_index = min
  let mut result = 0.0
  let mut again = true
  while again {
    let mut sum1 = 0.0
    let mut sum2 = 0.0
    let mut sum3 = 0.0
    let mut sum4 = 0.0
    let mut i = min
    while i <= moving_index {
      sum1 = sum1 + (i * data[i]).to_double()
      sum2 = sum2 + Double::from_int(data[i])
      i = i + 1
    }
    i = moving_index + 1
    while i <= max {
      sum3 = sum3 + (i * data[i]).to_double()
      sum4 = sum4 + Double::from_int(data[i])
      i = i + 1
    }
    result = (sum1 / sum2 + sum3 / sum4) / 2.0
    moving_index = moving_index + 1
    again = (moving_index + 1).to_double() <= result && moving_index < (max - 1)
  }
  java_round(result)
}

///|
/// Li's minimum cross entropy threshold (iterative version).
pub fn auto_threshold_li(data : Array[Int]) -> Int {
  let tolerance = 0.5
  let mut num_pixels = 0
  let mut ih = 0
  while ih < 256 {
    num_pixels = num_pixels + data[ih]
    ih = ih + 1
  }
  let mut mean = 0.0
  ih = 1
  while ih < 256 {
    mean = mean + (ih * data[ih]).to_double()
    ih = ih + 1
  }
  mean = mean / Double::from_int(num_pixels)
  let mut new_thresh = mean
  let mut old_thresh = 0.0
  let mut threshold = 0
  let mut again = true
  while again {
    old_thresh = new_thresh
    threshold = java_double_to_int(old_thresh + 0.5)
    let mut sum_back = 0
    let mut num_back = 0
    ih = 0
    while ih <= threshold {
      sum_back = sum_back + ih * data[ih]
      num_back = num_back + data[ih]
      ih = ih + 1
    }
    let mean_back = if num_back == 0 {
      0.0
    } else {
      Double::from_int(sum_back) / Double::from_int(num_back)
    }
    let mut sum_obj = 0
    let mut num_obj = 0
    ih = threshold + 1
    while ih < 256 {
      sum_obj = sum_obj + ih * data[ih]
      num_obj = num_obj + data[ih]
      ih = ih + 1
    }
    let mean_obj = if num_obj == 0 {
      0.0
    } else {
      Double::from_int(sum_obj) / Double::from_int(num_obj)
    }
    let temp = (mean_back - mean_obj) / (@math.ln(mean_back) - @math.ln(mean_obj))
    new_thresh = if temp < -2.220446049250313e-16 {
      Double::from_int(java_double_to_int(temp - 0.5))
    } else {
      Double::from_int(java_double_to_int(temp + 0.5))
    }
    again = (new_thresh - old_thresh).abs() > tolerance
  }
  threshold
}

///|
/// Normalised histogram plus the cumulative sums `P1`/`P2` shared by the
/// entropy based methods.
priv struct NormHistogram {
  norm_histo : Array[Double]
  p1 : Array[Double]
  p2 : Array[Double]
  first_bin : Int
  last_bin : Int
}

///|
/// Java `MaxEntropy`'s prologue: normalised histogram, cumulative `P1`/`P2`
/// and the first/last non-empty bins.
fn build_norm_histogram(data : Array[Int]) -> NormHistogram {
  let mut total = 0
  let mut ih = 0
  while ih < 256 {
    total = total + data[ih]
    ih = ih + 1
  }
  let norm_histo = Array::make(256, 0.0)
  ih = 0
  while ih < 256 {
    norm_histo[ih] = Double::from_int(data[ih]) / Double::from_int(total)
    ih = ih + 1
  }
  let p1 = Array::make(256, 0.0)
  let p2 = Array::make(256, 0.0)
  p1[0] = norm_histo[0]
  p2[0] = 1.0 - p1[0]
  ih = 1
  while ih < 256 {
    p1[ih] = p1[ih - 1] + norm_histo[ih]
    p2[ih] = 1.0 - p1[ih]
    ih = ih + 1
  }
  let mut first_bin = 0
  ih = 0
  while ih < 256 {
    if !(p1[ih].abs() < 2.220446049250313e-16) {
      first_bin = ih
      break
    }
    ih = ih + 1
  }
  let mut last_bin = 255
  ih = 255
  while ih >= first_bin {
    if !(p2[ih].abs() < 2.220446049250313e-16) {
      last_bin = ih
      break
    }
    ih = ih - 1
  }
  { norm_histo, p1, p2, first_bin, last_bin }
}

///|
/// Kapur-Sahoo-Wong maximum entropy threshold.
pub fn auto_threshold_max_entropy(data : Array[Int]) -> Int {
  let h = build_norm_histogram(data)
  let norm_histo = h.norm_histo
  let p1 = h.p1
  let p2 = h.p2
  let mut threshold = -1
  let mut max_ent = 4.9e-324
  let mut it = h.first_bin
  while it <= h.last_bin {
    let mut ent_back = 0.0
    let mut ih = 0
    while ih <= it {
      if data[ih] != 0 {
        let q = norm_histo[ih] / p1[it]
        ent_back = ent_back - q * @math.ln(q)
      }
      ih = ih + 1
    }
    let mut ent_obj = 0.0
    ih = it + 1
    while ih < 256 {
      if data[ih] != 0 {
        let q = norm_histo[ih] / p2[it]
        ent_obj = ent_obj - q * @math.ln(q)
      }
      ih = ih + 1
    }
    let tot_ent = ent_back + ent_obj
    if max_ent < tot_ent {
      max_ent = tot_ent
      threshold = it
    }
    it = it + 1
  }
  threshold
}

///|
/// Mean of the gray level data (Glasbey 1993).
pub fn auto_threshold_mean(data : Array[Int]) -> Int {
  let mut tot = 0.0
  let mut sum = 0.0
  let mut i = 0
  while i < 256 {
    tot = tot + Double::from_int(data[i])
    sum = sum + (i * data[i]).to_double()
    i = i + 1
  }
  java_double_to_int(@math.floor(sum / tot))
}

///|
/// Kittler & Illingworth minimum error threshold.
pub fn auto_threshold_min_error_i(data : Array[Int]) -> Int {
  let mut threshold = auto_threshold_mean(data)
  let mut t_prev = -2
  while threshold != t_prev {
    let mu = helper_b(data, threshold) / helper_a(data, threshold)
    let nu = (helper_b(data, 255) - helper_b(data, threshold)) /
      (helper_a(data, 255) - helper_a(data, threshold))
    let p = helper_a(data, threshold) / helper_a(data, 255)
    let q = (helper_a(data, 255) - helper_a(data, threshold)) / helper_a(data, 255)
    let sigma2 = helper_c(data, threshold) / helper_a(data, threshold) - mu * mu
    let tau2 = (helper_c(data, 255) - helper_c(data, threshold)) /
      (helper_a(data, 255) - helper_a(data, threshold)) - nu * nu
    let w0 = 1.0 / sigma2 - 1.0 / tau2
    let w1 = mu / sigma2 - nu / tau2
    let w2 = (mu * mu) / sigma2 - (nu * nu) / tau2 +
      java_log10((sigma2 * (q * q)) / (tau2 * (p * p)))
    let sqterm = (w1 * w1) - w0 * w2
    if sqterm < 0.0 {
      return threshold
    }
    t_prev = threshold
    let temp = (w1 + Double::sqrt(sqterm)) / w0
    if temp.is_nan() {
      threshold = t_prev
    } else {
      threshold = java_double_to_int(@math.floor(temp))
    }
  }
  threshold
}

///|
/// Java helper `A(y, j)`: sum of the bins up to `j`.
fn helper_a(y : Array[Int], j : Int) -> Double {
  let mut x = 0.0
  let mut i = 0
  while i <= j {
    x = x + Double::from_int(y[i])
    i = i + 1
  }
  x
}

///|
/// Java helper `B(y, j)`: weighted sum of the bins up to `j`.
fn helper_b(y : Array[Int], j : Int) -> Double {
  let mut x = 0.0
  let mut i = 0
  while i <= j {
    x = x + (i * y[i]).to_double()
    i = i + 1
  }
  x
}

///|
/// Java helper `C(y, j)`: squared weighted sum of the bins up to `j`.
fn helper_c(y : Array[Int], j : Int) -> Double {
  let mut x = 0.0
  let mut i = 0
  while i <= j {
    x = x + (i * i * y[i]).to_double()
    i = i + 1
  }
  x
}

///|
/// Prewitt & Mendelsohn "minimum" threshold (valley between the two modes).
pub fn auto_threshold_minimum(data : Array[Int]) -> Int {
  let i_histo = Array::make(256, 0.0)
  let mut i = 0
  while i < 256 {
    i_histo[i] = Double::from_int(data[i])
    i = i + 1
  }
  let mut iter = 0
  while !bimodal_test(i_histo) {
    smooth_in_place(i_histo)
    iter = iter + 1
    if iter > 10000 {
      return -1
    }
  }
  let mut threshold = -1
  i = 1
  while i < 255 {
    if i_histo[i - 1] > i_histo[i] && i_histo[i + 1] >= i_histo[i] {
      threshold = i
    }
    i = i + 1
  }
  threshold
}

///|
/// Tsai's moment preserving threshold.
pub fn auto_threshold_moments(data : Array[Int]) -> Int {
  let mut total = 0.0
  let mut i = 0
  while i < 256 {
    total = total + Double::from_int(data[i])
    i = i + 1
  }
  let histo = Array::make(256, 0.0)
  i = 0
  while i < 256 {
    histo[i] = Double::from_int(data[i]) / total
    i = i + 1
  }
  let m0 = 1.0
  let mut m1 = 0.0
  let mut m2 = 0.0
  let mut m3 = 0.0
  i = 0
  while i < 256 {
    m1 = m1 + Double::from_int(i) * histo[i]
    m2 = m2 + Double::from_int(i * i) * histo[i]
    m3 = m3 + Double::from_int(i * i * i) * histo[i]
    i = i + 1
  }
  let cd = m0 * m2 - m1 * m1
  let c0 = (-m2 * m2 + m1 * m3) / cd
  let c1 = (m0 * -m3 + m2 * m1) / cd
  let z0 = 0.5 * (-c1 - Double::sqrt(c1 * c1 - 4.0 * c0))
  let z1 = 0.5 * (-c1 + Double::sqrt(c1 * c1 - 4.0 * c0))
  let p0 = (z1 - m1) / (z1 - z0)
  let mut sum = 0.0
  let mut threshold = -1
  i = 0
  while i < 256 {
    sum = sum + histo[i]
    if sum > p0 {
      threshold = i
      break
    }
    i = i + 1
  }
  threshold
}

///|
/// Otsu's threshold (Jordan Bevik's between-class-variance formulation).
///
/// Ties are resolved towards the *larger* `k`, exactly like the Java
/// original (`BCV >= BCVmax`).
pub fn auto_threshold_otsu(data : Array[Int]) -> Int {
  let mut s = 0
  let mut n = 0
  let mut k = 0
  while k < 256 {
    s = s + k * data[k]
    n = n + data[k]
    k = k + 1
  }
  let mut sk = 0
  let mut n1 = data[0]
  let mut bcv = 0.0
  let mut bcv_max = 0.0
  let mut k_star = 0
  k = 1
  while k < 255 {
    sk = sk + k * data[k]
    n1 = n1 + data[k]
    let denom = Double::from_int(n1) * Double::from_int(n - n1)
    if denom != 0.0 {
      let num = (Double::from_int(n1) / Double::from_int(n)) *
        Double::from_int(s) - Double::from_int(sk)
      bcv = (num * num) / denom
    } else {
      bcv = 0.0
    }
    if bcv >= bcv_max {
      bcv_max = bcv
      k_star = k
    }
    k = k + 1
  }
  k_star
}

///|
/// Doyle's percentile threshold (50% foreground).
pub fn auto_threshold_percentile(data : Array[Int]) -> Int {
  let ptile = 0.5
  let total = partial_sum(data, 255)
  let mut temp = 1.0
  let mut threshold = -1
  let mut i = 0
  while i < 256 {
    let avec = (partial_sum(data, i) / total - ptile).abs()
    if avec < temp {
      temp = avec
      threshold = i
    }
    i = i + 1
  }
  threshold
}

///|
/// Java helper `partialSum(y, j)`.
fn partial_sum(y : Array[Int], j : Int) -> Double {
  let mut x = 0.0
  let mut i = 0
  while i <= j {
    x = x + Double::from_int(y[i])
    i = i + 1
  }
  x
}

///|
/// Renyi entropy threshold (three alpha values combined).
pub fn auto_threshold_renyi_entropy(data : Array[Int]) -> Int {
  let h = build_norm_histogram(data)
  let norm_histo = h.norm_histo
  let p1 = h.p1
  let p2 = h.p2
  // --- Shannon (alpha = 1) ---
  let mut threshold = 0
  let mut max_ent = 0.0
  let mut it = h.first_bin
  while it <= h.last_bin {
    let mut ent_back = 0.0
    let mut ih = 0
    while ih <= it {
      if data[ih] != 0 {
        let q = norm_histo[ih] / p1[it]
        ent_back = ent_back - q * @math.ln(q)
      }
      ih = ih + 1
    }
    let mut ent_obj = 0.0
    ih = it + 1
    while ih < 256 {
      if data[ih] != 0 {
        let q = norm_histo[ih] / p2[it]
        ent_obj = ent_obj - q * @math.ln(q)
      }
      ih = ih + 1
    }
    let tot_ent = ent_back + ent_obj
    if max_ent < tot_ent {
      max_ent = tot_ent
      threshold = it
    }
    it = it + 1
  }
  let t_star2 = threshold
  // --- alpha = 0.5 ---
  threshold = 0
  max_ent = 0.0
  let alpha = 0.5
  let term = 1.0 / (1.0 - alpha)
  it = h.first_bin
  while it <= h.last_bin {
    let mut ent_back = 0.0
    let mut ih = 0
    while ih <= it {
      ent_back = ent_back + Double::sqrt(norm_histo[ih] / p1[it])
      ih = ih + 1
    }
    let mut ent_obj = 0.0
    ih = it + 1
    while ih < 256 {
      ent_obj = ent_obj + Double::sqrt(norm_histo[ih] / p2[it])
      ih = ih + 1
    }
    let tot_ent = term *
      (if ent_back * ent_obj > 0.0 {
        @math.ln(ent_back * ent_obj)
      } else {
        0.0
      })
    if tot_ent > max_ent {
      max_ent = tot_ent
      threshold = it
    }
    it = it + 1
  }
  let t_star1 = threshold
  // --- alpha = 2.0 ---
  threshold = 0
  max_ent = 0.0
  let alpha2 = 2.0
  let term2 = 1.0 / (1.0 - alpha2)
  it = h.first_bin
  while it <= h.last_bin {
    let mut ent_back = 0.0
    let mut ih = 0
    while ih <= it {
      ent_back = ent_back + (norm_histo[ih] * norm_histo[ih]) / (p1[it] * p1[it])
      ih = ih + 1
    }
    let mut ent_obj = 0.0
    ih = it + 1
    while ih < 256 {
      ent_obj = ent_obj + (norm_histo[ih] * norm_histo[ih]) / (p2[it] * p2[it])
      ih = ih + 1
    }
    let tot_ent = term2 *
      (if ent_back * ent_obj > 0.0 {
        @math.ln(ent_back * ent_obj)
      } else {
        0.0
      })
    if tot_ent > max_ent {
      max_ent = tot_ent
      threshold = it
    }
    it = it + 1
  }
  let t_star3 = threshold
  // --- sort the three candidates ---
  let mut t1 = t_star1
  let mut t2 = t_star2
  let mut t3 = t_star3
  let tmp = t1
  if t2 < t1 {
    t1 = t2
    t2 = tmp
  }
  let tmp = t2
  if t3 < t2 {
    t2 = t3
    t3 = tmp
  }
  let tmp = t1
  if t2 < t1 {
    t1 = t2
    t2 = tmp
  }
  // --- beta adjustment ---
  let mut beta1 = 0
  let mut beta2 = 0
  let mut beta3 = 0
  if (t1 - t2).abs() <= 5 {
    if (t2 - t3).abs() <= 5 {
      beta1 = 1
      beta2 = 2
      beta3 = 1
    } else {
      beta1 = 0
      beta2 = 1
      beta3 = 3
    }
  } else if (t2 - t3).abs() <= 5 {
    beta1 = 3
    beta2 = 1
    beta3 = 0
  } else {
    beta1 = 1
    beta2 = 2
    beta3 = 1
  }
  let omega = p1[t3] - p1[t1]
  java_double_to_int(Double::from_int(t1) * (p1[t1] + 0.25 * omega * Double::from_int(beta1)) +
    0.25 * Double::from_int(t2) * omega * Double::from_int(beta2) +
    Double::from_int(t3) * (p2[t3] + 0.25 * omega * Double::from_int(beta3)))
}

///|
/// Shanbhag's information measure threshold.
pub fn auto_threshold_shanbhag(data : Array[Int]) -> Int {
  let h = build_norm_histogram(data)
  let norm_histo = h.norm_histo
  let p1 = h.p1
  let p2 = h.p2
  let mut threshold = -1
  let mut min_ent = 1.7976931348623157e308
  let mut it = h.first_bin
  while it <= h.last_bin {
    let term = 0.5 / p1[it]
    let mut ent_back = 0.0
    let mut ih = 1
    while ih <= it {
      ent_back = ent_back - norm_histo[ih] * @math.ln(1.0 - term * p1[ih - 1])
      ih = ih + 1
    }
    ent_back = ent_back * term
    let term = 0.5 / p2[it]
    let mut ent_obj = 0.0
    ih = it + 1
    while ih < 256 {
      ent_obj = ent_obj - norm_histo[ih] * @math.ln(1.0 - term * p2[ih])
      ih = ih + 1
    }
    ent_obj = ent_obj * term
    let tot_ent = (ent_back - ent_obj).abs()
    if tot_ent < min_ent {
      min_ent = tot_ent
      threshold = it
    }
    it = it + 1
  }
  threshold
}

///|
/// Zack's triangle threshold.
///
/// The Java original reverses the histogram in place when the data is
/// skewed; a local copy is used here so the caller's histogram is not
/// modified (the Java code restores it anyway).
pub fn auto_threshold_triangle(data : Array[Int]) -> Int {
  let hist = Array::make(256, 0)
  let mut i = 0
  while i < 256 {
    hist[i] = data[i]
    i = i + 1
  }
  let mut min = 0
  i = 0
  while i < hist.length() {
    if hist[i] > 0 {
      min = i
      break
    }
    i = i + 1
  }
  if min > 0 {
    min = min - 1
  }
  let mut min2 = 0
  i = 255
  while i > 0 {
    if hist[i] > 0 {
      min2 = i
      break
    }
    i = i - 1
  }
  if min2 < 255 {
    min2 = min2 + 1
  }
  let mut max = 0
  let mut dmax = 0
  i = 0
  while i < 256 {
    if hist[i] > dmax {
      max = i
      dmax = hist[i]
    }
    i = i + 1
  }
  let inverted = (max - min) < (min2 - max)
  if inverted {
    let mut left = 0
    let mut right = 255
    while left < right {
      let temp = hist[left]
      hist[left] = hist[right]
      hist[right] = temp
      left = left + 1
      right = right - 1
    }
    min = 255 - min2
    max = 255 - max
  }
  if min == max {
    return min
  }
  let mut nx = Double::from_int(hist[max])
  let mut ny = Double::from_int(min - max)
  let mut d = Double::sqrt(nx * nx + ny * ny)
  nx = nx / d
  ny = ny / d
  d = nx * Double::from_int(min) + ny * Double::from_int(hist[min])
  let mut split = min
  let mut split_distance = 0.0
  i = min + 1
  while i <= max {
    let new_distance = nx * Double::from_int(i) +
      ny * Double::from_int(hist[i]) - d
    if new_distance > split_distance {
      split = i
      split_distance = new_distance
    }
    i = i + 1
  }
  split = split - 1
  if inverted {
    let mut left = 0
    let mut right = 255
    while left < right {
      let temp = hist[left]
      hist[left] = hist[right]
      hist[right] = temp
      left = left + 1
      right = right - 1
    }
    return 255 - split
  }
  split
}

///|
/// Yen's maximum correlation criterion threshold.
pub fn auto_threshold_yen(data : Array[Int]) -> Int {
  let mut total = 0
  let mut ih = 0
  while ih < 256 {
    total = total + data[ih]
    ih = ih + 1
  }
  let norm_histo = Array::make(256, 0.0)
  ih = 0
  while ih < 256 {
    norm_histo[ih] = Double::from_int(data[ih]) / Double::from_int(total)
    ih = ih + 1
  }
  let p1 = Array::make(256, 0.0)
  let p1_sq = Array::make(256, 0.0)
  let p2_sq = Array::make(256, 0.0)
  p1[0] = norm_histo[0]
  ih = 1
  while ih < 256 {
    p1[ih] = p1[ih - 1] + norm_histo[ih]
    ih = ih + 1
  }
  p1_sq[0] = norm_histo[0] * norm_histo[0]
  ih = 1
  while ih < 256 {
    p1_sq[ih] = p1_sq[ih - 1] + norm_histo[ih] * norm_histo[ih]
    ih = ih + 1
  }
  p2_sq[255] = 0.0
  ih = 254
  while ih >= 0 {
    p2_sq[ih] = p2_sq[ih + 1] + norm_histo[ih + 1] * norm_histo[ih + 1]
    ih = ih - 1
  }
  let mut threshold = -1
  let mut max_crit = 4.9e-324
  let mut it = 0
  while it < 256 {
    let crit = -1.0 *
      (if p1_sq[it] * p2_sq[it] > 0.0 {
        @math.ln(p1_sq[it] * p2_sq[it])
      } else {
        0.0
      }) +
      2.0 *
      (if p1[it] * (1.0 - p1[it]) > 0.0 {
        @math.ln(p1[it] * (1.0 - p1[it]))
      } else {
        0.0
      })
    if crit > max_crit {
      max_crit = crit
      threshold = it
    }
    it = it + 1
  }
  threshold
}
