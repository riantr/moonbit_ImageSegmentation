///|
/// Port of the SIOX segmentation plugin (`siox_.jar`, Simple Interactive
/// Object Extraction, Friedland / Jantz / Knipping).
///
/// SIOX builds colour signatures from the user's known background and
/// foreground strokes, classifies every pixel with the two signatures and
/// then post-processes the confidence matrix: smooth, normalise, erode,
/// keep the large components, smooth, binarise, keep the large components
/// again, fill the colour regions and dilate.
///
/// The Java original works on `float` confidence values and `int` ARGB
/// pixels; those types and the exact order of the floating point
/// operations are reproduced here.
priv struct SioxTupel {
  min_bg_dist : Float
  min_fg_dist : Float
}

///|
/// Confidence of a pixel that is known to be foreground.
pub const SIOX_CERTAIN_FOREGROUND : Float = 1.0F

///|
/// Confidence of a pixel that is known to be background.
pub const SIOX_CERTAIN_BACKGROUND : Float = 0.0F

///|
/// Confidence at or above which a pixel counts as known foreground.
pub const SIOX_FOREGROUND_CONFIDENCE : Float = 0.8F

///|
/// Confidence at or below which a pixel counts as known background.
pub const SIOX_BACKGROUND_CONFIDENCE : Float = 0.1F

///|
/// Confidence used as the "unknown" threshold in the post processing.
pub const SIOX_UNKNOWN_REGION_CONFIDENCE : Float = 0.5F

///|
/// Convert a 24 bit RGB value to the CIE-Lab triple used by SIOX.
///
/// Port of `Utils.rgbToClab(int)`: the sRGB gamma is lifted with
/// `Math.pow(base, 2.4)` (a *double* exponent) and the cube root uses the
/// *float* constant `1f/3f`, not `1.0/3.0`.
fn siox_rgb_to_clab(rgb : Int) -> Array[Float] {
  let r = (rgb >> 16) & 0xff
  let g = (rgb >> 8) & 0xff
  let b = rgb & 0xff
  let mut var_r = Float::from_int(r) / 255.0F
  let mut var_g = Float::from_int(g) / 255.0F
  let mut var_b = Float::from_int(b) / 255.0F
  if var_r.to_double() > 0.04045 {
    var_r = Float::from_double(
      @math.pow(((var_r + 0.055F) / 1.055F).to_double(), 2.4)
    )
  } else {
    var_r = var_r / 12.92F
  }
  if var_g.to_double() > 0.04045 {
    var_g = Float::from_double(
      @math.pow(((var_g + 0.055F) / 1.055F).to_double(), 2.4)
    )
  } else {
    var_g = var_g / 12.92F
  }
  if var_b.to_double() > 0.04045 {
    var_b = Float::from_double(
      @math.pow(((var_b + 0.055F) / 1.055F).to_double(), 2.4)
    )
  } else {
    var_b = var_b / 12.92F
  }
  var_r = var_r * 100.0F
  var_g = var_g * 100.0F
  var_b = var_b * 100.0F
  let x = var_r * 0.4124F + var_g * 0.3576F + var_b * 0.1805F
  let y = var_r * 0.2126F + var_g * 0.7152F + var_b * 0.0722F
  let z = var_r * 0.0193F + var_g * 0.1192F + var_b * 0.9505F
  let mut var_x = x / 95.047F
  let mut var_y = y / 100.0F
  let mut var_z = z / 108.883F
  let third = 1.0F / 3.0F
  if var_x > 0.008856F {
    var_x = Float::from_double(@math.pow(var_x.to_double(), third.to_double()))
  } else {
    var_x = (7.787F * var_x) + (16.0F / 116.0F)
  }
  if var_y > 0.008856F {
    var_y = Float::from_double(@math.pow(var_y.to_double(), third.to_double()))
  } else {
    var_y = (7.787F * var_y) + (16.0F / 116.0F)
  }
  if var_z > 0.008856F {
    var_z = Float::from_double(@math.pow(var_z.to_double(), third.to_double()))
  } else {
    var_z = (7.787F * var_z) + (16.0F / 116.0F)
  }
  let lab = Array::make(3, 0.0F)
  lab[0] = (116.0F * var_y) - 16.0F
  lab[1] = 500.0F * (var_x - var_y)
  lab[2] = 200.0F * (var_y - var_z)
  lab
}

///|
/// Squared euclidian distance of two Lab points.
///
/// Port of `Utils.sqrEuclidianDist(float[], float[])`.
fn siox_sqr_euclid(p : Array[Float], q : Array[Float]) -> Float {
  let mut sum = 0.0F
  let mut i = 0
  while i < p.length() {
    let d = p[i] - q[i]
    sum = sum + d * d
    i = i + 1
  }
  sum
}

///|
/// Euclidian distance of two colours in Lab space.
///
/// Port of `Utils.labcolordiff(int, int)`.
fn siox_lab_colour_diff(rgb0 : Int, rgb1 : Int) -> Float {
  let c1 = siox_rgb_to_clab(rgb0)
  let c2 = siox_rgb_to_clab(rgb1)
  let mut euclid = 0.0F
  let mut k = 0
  while k < c1.length() {
    let d = c1[k] - c2[k]
    euclid = euclid + d * d
    k = k + 1
  }
  Float::from_double(Double::sqrt(euclid.to_double()))
}

///|
/// 3x3 smoothing of the confidence matrix (in place).
///
/// Port of `Utils.smoothcm(float[], int, int, float, float, float)`. The
/// four passes are sequential and in place, so later passes read values
/// that earlier passes already modified.
fn siox_smooth_cm(
  cm : Array[Float],
  xres : Int,
  yres : Int,
  f1 : Float,
  f2 : Float,
  f3 : Float
) -> Unit {
  let mut y = 0
  while y < yres {
    let mut x = 0
    while x < xres - 2 {
      let idx = y * xres + x
      cm[idx] = f1 * cm[idx] + f2 * cm[idx + 1] + f3 * cm[idx + 2]
      x = x + 1
    }
    y = y + 1
  }
  y = 0
  while y < yres {
    let mut x = xres - 1
    while x >= 2 {
      let idx = y * xres + x
      cm[idx] = f3 * cm[idx - 2] + f2 * cm[idx - 1] + f1 * cm[idx]
      x = x - 1
    }
    y = y + 1
  }
  y = 0
  while y < yres - 2 {
    let mut x = 0
    while x < xres {
      let idx = y * xres + x
      cm[idx] = f1 * cm[idx] + f2 * cm[(y + 1) * xres + x] +
        f3 * cm[(y + 2) * xres + x]
      x = x + 1
    }
    y = y + 1
  }
  y = yres - 1
  while y >= 2 {
    let mut x = 0
    while x < xres {
      let idx = y * xres + x
      cm[idx] = f3 * cm[(y - 2) * xres + x] + f2 * cm[(y - 1) * xres + x] +
        f1 * cm[idx]
      x = x + 1
    }
    y = y - 1
  }
}

///|
/// `true` when the float is the negative zero.
fn java_is_negative_zero(x : Float) -> Bool {
  x == 0.0F && x.reinterpret_as_int() == -2147483648
}

///|
/// Java `Math.max(float, float)`.
///
/// A `NaN` wins over every other value (Java returns the `NaN` operand), and
/// `+0.0` wins over `-0.0`. A plain `if a > b { a } else { b }` would drop a
/// `NaN` and could return the negative zero.
fn java_max_float(a : Float, b : Float) -> Float {
  if a.is_nan() {
    a
  } else if b.is_nan() {
    b
  } else if a == 0.0F && b == 0.0F {
    // only the sign of the zero can differ here
    if java_is_negative_zero(a) {
      b
    } else {
      a
    }
  } else if a > b {
    a
  } else {
    b
  }
}

///|
/// Java `Math.min(float, float)`.
///
/// A `NaN` wins over every other value and `-0.0` wins over `+0.0`.
fn java_min_float(a : Float, b : Float) -> Float {
  if a.is_nan() {
    a
  } else if b.is_nan() {
    b
  } else if a == 0.0F && b == 0.0F {
    if java_is_negative_zero(b) {
      b
    } else {
      a
    }
  } else if a < b {
    a
  } else {
    b
  }
}

///|
/// Morphological erosion of the confidence matrix (in place).
///
/// Port of `Utils.erode(float[], int, int)`.
fn siox_erode(cm : Array[Float], xres : Int, yres : Int) -> Unit {
  let mut y = 0
  while y < yres {
    let mut x = 0
    while x < xres - 1 {
      let idx = y * xres + x
      cm[idx] = java_min_float(cm[idx], cm[idx + 1])
      x = x + 1
    }
    y = y + 1
  }
  y = 0
  while y < yres {
    let mut x = xres - 1
    while x >= 1 {
      let idx = y * xres + x
      cm[idx] = java_min_float(cm[idx - 1], cm[idx])
      x = x - 1
    }
    y = y + 1
  }
  y = 0
  while y < yres - 1 {
    let mut x = 0
    while x < xres {
      let idx = y * xres + x
      let other = cm[(y + 1) * xres + x]
      cm[idx] = java_min_float(cm[idx], other)
      x = x + 1
    }
    y = y + 1
  }
  y = yres - 1
  while y >= 1 {
    let mut x = 0
    while x < xres {
      let idx = y * xres + x
      let other = cm[(y - 1) * xres + x]
      cm[idx] = java_min_float(other, cm[idx])
      x = x + 1
    }
    y = y - 1
  }
}

///|
/// Morphological dilation of the confidence matrix (in place).
///
/// Port of `Utils.dilate(float[], int, int)`.
fn siox_dilate(cm : Array[Float], xres : Int, yres : Int) -> Unit {
  let mut y = 0
  while y < yres {
    let mut x = 0
    while x < xres - 1 {
      let idx = y * xres + x
      cm[idx] = java_max_float(cm[idx], cm[idx + 1])
      x = x + 1
    }
    y = y + 1
  }
  y = 0
  while y < yres {
    let mut x = xres - 1
    while x >= 1 {
      let idx = y * xres + x
      cm[idx] = java_max_float(cm[idx - 1], cm[idx])
      x = x - 1
    }
    y = y + 1
  }
  y = 0
  while y < yres - 1 {
    let mut x = 0
    while x < xres {
      let idx = y * xres + x
      let other = cm[(y + 1) * xres + x]
      cm[idx] = java_max_float(cm[idx], other)
      x = x + 1
    }
    y = y + 1
  }
  y = yres - 1
  while y >= 1 {
    let mut x = 0
    while x < xres {
      let idx = y * xres + x
      let other = cm[(y - 1) * xres + x]
      cm[idx] = java_max_float(other, cm[idx])
      x = x + 1
    }
    y = y - 1
  }
}

///|
/// Normalise the confidence matrix to `[0..1]` (in place).
///
/// Port of `Utils.normalizeMatrix(float[])`.
fn siox_normalize_matrix(cm : Array[Float]) -> Unit {
  let mut max = 0.0F
  let mut i = 0
  while i < cm.length() {
    if max < cm[i] {
      max = cm[i]
    }
    i = i + 1
  }
  if max <= 0.0F {
    return
  }
  if max.to_double() == 1.0 {
    return
  }
  let alpha = 1.0F / max
  i = 0
  while i < cm.length() {
    cm[i] = alpha * cm[i]
    i = i + 1
  }
}

///|
/// First stage of the colour signature clustering.
///
/// Port of `ColorSignature.stageone(float[][], int, ArrayList, float[], int)`.
///
/// The leaf stores the *whole* `points` array, which for the initial call
/// is the full sized input array (including the unused tail) — the Java
/// original has the same behaviour.
fn siox_stage_one(
  points : Array[Array[Float]],
  length : Int,
  depth : Int,
  clusters : Array[Array[Array[Float]]],
  limits : Array[Float]
) -> Unit {
  if length < 1 {
    return
  }
  let dims = points[0].length()
  let curdim = depth % dims
  let mut min = points[0][curdim]
  let mut max = points[0][curdim]
  let mut i = 1
  while i < length {
    if min > points[i][curdim] {
      min = points[i][curdim]
    }
    if max < points[i][curdim] {
      max = points[i][curdim]
    }
    i = i + 1
  }
  if max - min > limits[curdim] {
    let pivotvalue = ((max - min) / 2.0F) + min
    let mut countsm = 0
    let mut countgr = 0
    i = 0
    while i < length {
      if points[i][curdim] <= pivotvalue {
        countsm = countsm + 1
      } else {
        countgr = countgr + 1
      }
      i = i + 1
    }
    let smaller : Array[Array[Float]] = Array::make(countsm, [0.0F, 0.0F, 0.0F])
    let bigger : Array[Array[Float]] = Array::make(countgr, [0.0F, 0.0F, 0.0F])
    let mut smallc = 0
    let mut bigc = 0
    i = 0
    while i < length {
      if points[i][curdim] <= pivotvalue {
        smaller[smallc] = points[i]
        smallc = smallc + 1
      } else {
        bigger[bigc] = points[i]
        bigc = bigc + 1
      }
      i = i + 1
    }
    siox_stage_one(smaller, countsm, depth + 1, clusters, limits)
    siox_stage_one(bigger, countgr, depth + 1, clusters, limits)
  } else {
    clusters.push(points)
  }
}

///|
/// Second stage of the colour signature clustering.
///
/// Port of `ColorSignature.stagetwo(float[][], int, ArrayList, float[], int, float)`.
///
/// Note that the Java code allocates the split sub arrays with `dims`
/// (= 3) entries, i.e. the cardinality slot is dropped when the centroids
/// are split; that is reproduced here.
fn siox_stage_two(
  points : Array[Array[Float]],
  depth : Int,
  clusters : Array[Array[Float]],
  limits : Array[Float],
  total : Int,
  threshold : Float
) -> Unit {
  if points.length() < 1 {
    return
  }
  let dims = points[0].length() - 1
  let curdim = depth % dims
  let mut min = points[0][curdim]
  let mut max = points[0][curdim]
  let mut i = 1
  while i < points.length() {
    if min > points[i][curdim] {
      min = points[i][curdim]
    }
    if max < points[i][curdim] {
      max = points[i][curdim]
    }
    i = i + 1
  }
  if max - min > limits[curdim] {
    let pivotvalue = ((max - min) / 2.0F) + min
    let mut countsm = 0
    let mut countgr = 0
    i = 0
    while i < points.length() {
      if points[i][curdim] <= pivotvalue {
        countsm = countsm + 1
      } else {
        countgr = countgr + 1
      }
      i = i + 1
    }
    let smaller : Array[Array[Float]] = Array::make(countsm, [0.0F, 0.0F, 0.0F])
    let bigger : Array[Array[Float]] = Array::make(countgr, [0.0F, 0.0F, 0.0F])
    let mut smallc = 0
    let mut bigc = 0
    i = 0
    while i < points.length() {
      if points[i][curdim] <= pivotvalue {
        smaller[smallc] = points[i]
        smallc = smallc + 1
      } else {
        bigger[bigc] = points[i]
        bigc = bigc + 1
      }
      i = i + 1
    }
    siox_stage_two(smaller, depth + 1, clusters, limits, total, threshold)
    siox_stage_two(bigger, depth + 1, clusters, limits, total, threshold)
  } else {
    let mut sum = 0
    i = 0
    while i < points.length() {
      sum = java_float_to_int(
        Float::from_int(sum) + points[i][points[i].length() - 1]
      )
      i = i + 1
    }
    if ((Double::from_int(sum) * 100.0) / Double::from_int(total)) >=
      threshold.to_double() {
      let point = Array::make(points[0].length(), 0.0F)
      i = 0
      while i < points.length() {
        let mut j = 0
        while j < points[0].length() {
          point[j] = point[j] + points[i][j]
          j = j + 1
        }
        i = i + 1
      }
      let mut j = 0
      while j < points[0].length() - 1 {
        point[j] = point[j] / Float::from_int(points.length())
        j = j + 1
      }
      clusters.push(point)
    }
  }
}

///|
/// Build a colour signature from a set of Lab points.
///
/// Port of `ColorSignature.createSignature(float[][], int, float[], float)`.
fn siox_create_signature(
  input : Array[Array[Float]],
  length : Int,
  limits : Array[Float],
  threshold : Float
) -> Array[Array[Float]] {
  let clusters1 : Array[Array[Array[Float]]] = []
  siox_stage_one(input, length, 0, clusters1, limits)
  let centroids : Array[Array[Float]] = []
  let mut i = 0
  while i < clusters1.length() {
    let cluster = clusters1[i]
    let centroid = Array::make(cluster[0].length() + 1, 0.0F)
    let mut k = 0
    while k < cluster.length() {
      let mut j = 0
      while j < cluster[k].length() {
        centroid[j] = centroid[j] + cluster[k][j]
        j = j + 1
      }
      k = k + 1
    }
    let mut j = 0
    while j < cluster[0].length() {
      centroid[j] = centroid[j] / Float::from_int(cluster.length())
      j = j + 1
    }
    centroid[cluster[0].length()] = Float::from_int(cluster.length())
    centroids.push(centroid)
    i = i + 1
  }
  let clusters2 : Array[Array[Float]] = []
  siox_stage_two(centroids, 0, clusters2, limits, length, threshold)
  clusters2
}

///|
/// Depth first search over the foreground components.
///
/// Port of `SioxSegmentator.depthFirstSearch(float[], int, float, int)`.
fn siox_depth_first_search(
  cm : Array[Float],
  label_field : Array[Int],
  width : Int,
  height : Int,
  i : Int,
  threshold : Float,
  cur_label : Int
) -> Int {
  let mut component_size = 0
  let stack : Array[Int] = []
  if label_field[i] == -1 && cm[i] >= threshold {
    label_field[i] = cur_label
    component_size = component_size + 1
    stack.push(i)
  }
  while stack.length() > 0 {
    let pos = stack[stack.length() - 1]
    let _ = stack.pop()
    let x = pos % width
    let y = pos / width
    let left = pos - 1
    if x - 1 >= 0 && label_field[left] == -1 && cm[left] >= threshold {
      label_field[left] = cur_label
      component_size = component_size + 1
      stack.push(left)
    }
    let right = pos + 1
    if x + 1 < width && label_field[right] == -1 && cm[right] >= threshold {
      label_field[right] = cur_label
      component_size = component_size + 1
      stack.push(right)
    }
    let top = pos - width
    if y - 1 >= 0 && label_field[top] == -1 && cm[top] >= threshold {
      label_field[top] = cur_label
      component_size = component_size + 1
      stack.push(top)
    }
    let bottom = pos + width
    if y + 1 < height && label_field[bottom] == -1 && cm[bottom] >= threshold {
      label_field[bottom] = cur_label
      component_size = component_size + 1
      stack.push(bottom)
    }
  }
  component_size
}

///|
/// Keep the largest connected components only.
///
/// Port of `SioxSegmentator.keepOnlyLargeComponents(float[], float, double)`.
fn siox_keep_only_large_components(
  cm : Array[Float],
  label_field : Array[Int],
  width : Int,
  height : Int,
  threshold : Float,
  size_factor_to_keep : Double
) -> Unit {
  let mut i = 0
  while i < label_field.length() {
    label_field[i] = -1
    i = i + 1
  }
  let mut curlabel = 0
  let mut maxregion = 0
  let mut maxblob = 0
  let label_sizes : Array[Int] = []
  i = 0
  while i < cm.length() {
    let mut region_count = 0
    if label_field[i] == -1 && cm[i] >= threshold {
      region_count = siox_depth_first_search(
        cm,
        label_field,
        width,
        height,
        i,
        threshold,
        curlabel
      )
      curlabel = curlabel + 1
      label_sizes.push(region_count)
    }
    if region_count > maxregion {
      maxregion = region_count
      maxblob = curlabel - 1
    }
    i = i + 1
  }
  i = 0
  while i < cm.length() {
    if label_field[i] != -1 {
      if Double::from_int(label_sizes[label_field[i]]) * size_factor_to_keep <
        Double::from_int(maxregion) {
        cm[i] = SIOX_CERTAIN_BACKGROUND
      }
      if label_field[i] == maxblob {
        cm[i] = SIOX_CERTAIN_FOREGROUND
      }
    }
    i = i + 1
  }
}

///|
/// Fill the foreground regions with the colours of their neighbours.
///
/// Port of `SioxSegmentator.fillColorRegions(float[], int[])`.
fn siox_fill_color_regions(
  cm : Array[Float],
  image : Array[Int],
  label_field : Array[Int],
  width : Int,
  height : Int
) -> Unit {
  let mut i = 0
  while i < label_field.length() {
    label_field[i] = -1
    i = i + 1
  }
  let stack : Array[Int] = []
  i = 0
  while i < cm.length() {
    if label_field[i] != -1 || cm[i] < SIOX_UNKNOWN_REGION_CONFIDENCE {
      i = i + 1
      continue
    }
    let orig_color = image[i]
    let cur_label = i + 1
    label_field[i] = cur_label
    cm[i] = SIOX_CERTAIN_FOREGROUND
    stack.push(i)
    while stack.length() > 0 {
      let pos = stack[stack.length() - 1]
      let _ = stack.pop()
      let x = pos % width
      let y = pos / width
      let left = pos - 1
      if x - 1 >= 0 && label_field[left] == -1 &&
        siox_lab_colour_diff(image[left], orig_color) < 1.0 {
        label_field[left] = cur_label
        cm[left] = SIOX_CERTAIN_FOREGROUND
        stack.push(left)
      }
      let right = pos + 1
      if x + 1 < width && label_field[right] == -1 &&
        siox_lab_colour_diff(image[right], orig_color) < 1.0 {
        label_field[right] = cur_label
        cm[right] = SIOX_CERTAIN_FOREGROUND
        stack.push(right)
      }
      let top = pos - width
      if y - 1 >= 0 && label_field[top] == -1 &&
        siox_lab_colour_diff(image[top], orig_color) < 1.0 {
        label_field[top] = cur_label
        cm[top] = SIOX_CERTAIN_FOREGROUND
        stack.push(top)
      }
      let bottom = pos + width
      if y + 1 < height && label_field[bottom] == -1 &&
        siox_lab_colour_diff(image[bottom], orig_color) < 1.0 {
        label_field[bottom] = cur_label
        cm[bottom] = SIOX_CERTAIN_FOREGROUND
        stack.push(bottom)
      }
    }
    i = i + 1
  }
}

///|
/// Result of a SIOX segmentation.
pub struct SioxResult {
  /// `true` when the segmentation succeeded
  ///
  /// It is `false` in the two situations the Java original reports as a
  /// failure: an empty background signature (`segmentate` returns `false`)
  /// and a missing foreground signature (`segmentate` raises an
  /// `IllegalStateException`).
  success : Bool
  /// `true` when the Java original raised an `IllegalStateException`
  ///
  /// The Java original reports two different problems as a plain `false`:
  /// `segmentate` returns `false` when the background signature is empty and
  /// it raises an `IllegalStateException` when the foreground signature does
  /// not exist. The exception aborts the segmentation in the middle, so the
  /// confidence matrix keeps a partial state - which this flag distinguishes
  /// from the clean `false` return.
  failed : Bool
  /// the confidence matrix
  ///
  /// On a successful segmentation it holds the resulting confidences (0 =
  /// background, 1 = foreground). On a failed segmentation it holds the
  /// partial state the Java original left behind.
  confidence : Array[Float]
}

///|
/// Segment an image with SIOX.
///
/// Parameters:
/// - `cm`: the confidence matrix of the known strokes; it is modified in
///   place and holds the result afterwards
/// - `smoothness`: number of extra smoothing passes in the post processing
/// - `size_factor_to_keep`: components smaller than
///   `largest / size_factor_to_keep` are dropped
/// - `limits`: the cluster diameters of the Lab space
///
/// Port of `SioxSegmentator.segmentate(int[], float[], int, double)`.
pub fn siox_segmentate(
  img : RgbImage,
  cm : Array[Float],
  smoothness : Int,
  size_factor_to_keep : Double,
  limits : Array[Float]
) -> SioxResult {
  let width = img.width
  let height = img.height
  let n = width * height
  let label_field = Array::make(n, -1)
  let image = Array::make(n, 0)
  let mut i = 0
  while i < n {
    image[i] = img.packed(i % width, i / width)
    i = i + 1
  }
  // --- build the colour signatures ---
  // The Java code fills pre-allocated arrays of the full image size, so
  // the unused tail is part of the arrays handed to the clustering.
  let known_bg : Array[Array[Float]] = Array::make(n, [0.0F, 0.0F, 0.0F])
  let known_fg : Array[Array[Float]] = Array::make(n, [0.0F, 0.0F, 0.0F])
  let mut known_bg_count = 0
  let mut known_fg_count = 0
  i = 0
  while i < n {
    if cm[i] <= SIOX_BACKGROUND_CONFIDENCE {
      known_bg[known_bg_count] = siox_rgb_to_clab(image[i])
      known_bg_count = known_bg_count + 1
    } else if cm[i] >= SIOX_FOREGROUND_CONFIDENCE {
      known_fg[known_fg_count] = siox_rgb_to_clab(image[i])
      known_fg_count = known_fg_count + 1
    }
    i = i + 1
  }
  let bg_signature = siox_create_signature(
    known_bg,
    known_bg_count,
    limits,
    SIOX_BACKGROUND_CONFIDENCE
  )
  let fg_signature = siox_create_signature(
    known_fg,
    known_fg_count,
    limits,
    SIOX_BACKGROUND_CONFIDENCE
  )
  if bg_signature.length() < 1 {
    return { success: false, failed: false, confidence: cm }
  }
  // --- classify the pixels ---
  let cache : Map[Int, SioxTupel] = Map([])
  i = 0
  while i < n {
    if cm[i] >= SIOX_FOREGROUND_CONFIDENCE {
      cm[i] = SIOX_CERTAIN_FOREGROUND
      i = i + 1
      continue
    }
    if cm[i] > SIOX_BACKGROUND_CONFIDENCE {
      let is_background = match cache.get(image[i]) {
        Some(tupel) => tupel.min_bg_dist <= tupel.min_fg_dist
        None => {
          let lab = siox_rgb_to_clab(image[i])
          let mut min_bg = siox_sqr_euclid(lab, bg_signature[0])
          let mut j = 1
          while j < bg_signature.length() {
            let d = siox_sqr_euclid(lab, bg_signature[j])
            if d < min_bg {
              min_bg = d
            }
            j = j + 1
          }
          let mut min_fg = 3.4028235E38F
          j = 0
          while j < fg_signature.length() {
            let d = siox_sqr_euclid(lab, fg_signature[j])
            if d < min_fg {
              min_fg = d
            }
            j = j + 1
          }
          if fg_signature.length() == 0 {
            // The Java original raises an IllegalStateException here
            // ("foreground signature does not exist"). The exception aborts
            // the whole segmentation, so the caller observes a failed run
            // and the confidence matrix keeps the state it had when the
            // exception was raised: the pixels before the failing one are
            // already classified, the failing one and all the ones after it
            // still carry their original confidence.
            return { success: false, failed: true, confidence: cm }
          }
          cache.set(image[i], { min_bg_dist: min_bg, min_fg_dist: min_fg })
          min_bg < min_fg
        }
      }
      cm[i] = if is_background {
        SIOX_CERTAIN_BACKGROUND
      } else {
        SIOX_CERTAIN_FOREGROUND
      }
    } else {
      cm[i] = SIOX_CERTAIN_BACKGROUND
    }
    i = i + 1
  }
  // --- post processing ---
  siox_smooth_cm(cm, width, height, 0.33F, 0.33F, 0.33F)
  siox_normalize_matrix(cm)
  siox_erode(cm, width, height)
  siox_keep_only_large_components(
    cm,
    label_field,
    width,
    height,
    SIOX_UNKNOWN_REGION_CONFIDENCE,
    size_factor_to_keep
  )
  let mut s = 0
  while s < smoothness {
    siox_smooth_cm(cm, width, height, 0.33F, 0.33F, 0.33F)
    s = s + 1
  }
  siox_normalize_matrix(cm)
  i = 0
  while i < n {
    cm[i] = if cm[i] >= SIOX_UNKNOWN_REGION_CONFIDENCE {
      SIOX_CERTAIN_FOREGROUND
    } else {
      SIOX_CERTAIN_BACKGROUND
    }
    i = i + 1
  }
  siox_keep_only_large_components(
    cm,
    label_field,
    width,
    height,
    SIOX_UNKNOWN_REGION_CONFIDENCE,
    size_factor_to_keep
  )
  siox_fill_color_regions(cm, image, label_field, width, height)
  siox_dilate(cm, width, height)
  { success: true, failed: false, confidence: cm }
}

///|
/// Default cluster diameters of the Lab space (`{0.64, 1.28, 2.56}`).
pub fn siox_default_limits() -> Array[Float] {
  [0.64F, 1.28F, 2.56F]
}
