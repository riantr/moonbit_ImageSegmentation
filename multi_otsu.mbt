///|
/// Port of `Multi_OtsuThreshold` (ImageJ plugin by Yasunari Tosa, based on
/// P.S. Liao, T.S. Chen and P.C. Chung, "A Threshold Selection Method for
/// Multi-Level Gray-Level Image Segmentation", JISE 17, 713-727 (2001)).
///
/// The Java plugin computes `MLEVEL - 1` thresholds that maximize the
/// multi-class between-class variance, then splits the image into `MLEVEL`
/// regions. All lookup tables are `float` (f32) in the original and are
/// reproduced as `Float` here.
priv struct OtsuTables {
  h : Array[Float]
}

///|
/// Index into the 256x256 lookup tables.
fn otsu_idx(i : Int, j : Int) -> Int {
  i * 256 + j
}

///|
/// Build the `P`, `S` and `H` lookup tables from the normalised histogram.
///
/// Java `buildLookupTables(float[][] P, float[][] S, float[][] H, float[] h)`.
fn build_otsu_tables(h : Array[Float]) -> OtsuTables {
  let p = Array::make(256 * 256, 0.0F)
  let s = Array::make(256 * 256, 0.0F)
  let hh = Array::make(256 * 256, 0.0F)
  // diagonal
  let mut i = 1
  while i < 256 {
    p[otsu_idx(i, i)] = h[i]
    s[otsu_idx(i, i)] = Float::from_int(i) * h[i]
    i = i + 1
  }
  // first row (row 0 stays zero)
  i = 1
  while i < 255 {
    p[otsu_idx(1, i + 1)] = p[otsu_idx(1, i)] + h[i + 1]
    s[otsu_idx(1, i + 1)] = s[otsu_idx(1, i)] +
      Float::from_int(i + 1) * h[i + 1]
    i = i + 1
  }
  // remaining rows are derived from row 1
  i = 2
  while i < 256 {
    let mut j = i + 1
    while j < 256 {
      p[otsu_idx(i, j)] = p[otsu_idx(1, j)] - p[otsu_idx(1, i - 1)]
      s[otsu_idx(i, j)] = s[otsu_idx(1, j)] - s[otsu_idx(1, i - 1)]
      j = j + 1
    }
    i = i + 1
  }
  // H[i][j] = (S[i][j]^2) / P[i][j]
  i = 1
  while i < 256 {
    let mut j = i + 1
    while j < 256 {
      let pv = p[otsu_idx(i, j)]
      if pv != 0.0F {
        hh[otsu_idx(i, j)] = (s[otsu_idx(i, j)] * s[otsu_idx(i, j)]) / pv
      } else {
        hh[otsu_idx(i, j)] = 0.0F
      }
      j = j + 1
    }
    i = i + 1
  }
  { h: hh }
}

///|
/// Result of the multi-level Otsu search.
pub struct MultiOtsuResult {
  /// the `MLEVEL - 1` thresholds, `t[1] .. t[MLEVEL-1]`
  thresholds : Array[Int]
  /// the maximum between-class variance found
  max_sigma : Float
}

///|
/// Multi-level Otsu thresholds.
///
/// Java `findMaxSigma(int mlevel, float[][] H, int[] t)`. `mlevel` must be
/// between 2 and 5; the returned array holds `mlevel - 1` thresholds, where
/// `t[0]` is always 0 (as in the Java code).
pub fn multi_otsu_thresholds(
  histogram : Array[Int],
  mlevel : Int
) -> MultiOtsuResult {
  let width_total = histogram_total(histogram)
  let h = Array::make(256, 0.0F)
  let mut i = 0
  while i < 256 {
    // Java `buildHistogram` accumulates the histogram in a `float[]`:
    // `h[(int)(pixels[i]&0xff)]++`. A float cannot represent every integer
    // above 2^24, so the counter of the Java original stops growing at
    // 16777216 - it saturates instead of overflowing to a wrong count.
    let count = histogram[i]
    let saturated = if count > 16777216 {
      16777216
    } else {
      count
    }
    h[i] = Float::from_int(saturated) / Float::from_int(width_total)
    i = i + 1
  }
  let tables = build_otsu_tables(h)
  let hh = tables.h
  let thresholds = Array::make(mlevel, 0)
  let mut max_sig = 0.0F
  if mlevel == 2 {
    let mut i = 1
    while i < 256 - mlevel {
      let sq = hh[otsu_idx(1, i)] + hh[otsu_idx(i + 1, 255)]
      if max_sig < sq {
        thresholds[1] = i
        max_sig = sq
      }
      i = i + 1
    }
  } else if mlevel == 3 {
    let mut i = 1
    while i < 256 - mlevel {
      let mut j = i + 1
      while j < 256 - mlevel + 1 {
        let sq = hh[otsu_idx(1, i)] + hh[otsu_idx(i + 1, j)] +
          hh[otsu_idx(j + 1, 255)]
        if max_sig < sq {
          thresholds[1] = i
          thresholds[2] = j
          max_sig = sq
        }
        j = j + 1
      }
      i = i + 1
    }
  } else if mlevel == 4 {
    let mut i = 1
    while i < 256 - mlevel {
      let mut j = i + 1
      while j < 256 - mlevel + 1 {
        let mut k = j + 1
        while k < 256 - mlevel + 2 {
          let sq = hh[otsu_idx(1, i)] + hh[otsu_idx(i + 1, j)] +
            hh[otsu_idx(j + 1, k)] + hh[otsu_idx(k + 1, 255)]
          if max_sig < sq {
            thresholds[1] = i
            thresholds[2] = j
            thresholds[3] = k
            max_sig = sq
          }
          k = k + 1
        }
        j = j + 1
      }
      i = i + 1
    }
  } else if mlevel == 5 {
    let mut i = 1
    while i < 256 - mlevel {
      let mut j = i + 1
      while j < 256 - mlevel + 1 {
        let mut k = j + 1
        while k < 256 - mlevel + 2 {
          let mut m = k + 1
          while m < 256 - mlevel + 3 {
            let sq = hh[otsu_idx(1, i)] + hh[otsu_idx(i + 1, j)] +
              hh[otsu_idx(j + 1, k)] + hh[otsu_idx(k + 1, m)] +
              hh[otsu_idx(m + 1, 255)]
            if max_sig < sq {
              thresholds[1] = i
              thresholds[2] = j
              thresholds[3] = k
              thresholds[4] = m
              max_sig = sq
            }
            m = m + 1
          }
          k = k + 1
        }
        j = j + 1
      }
      i = i + 1
    }
  }
  { thresholds, max_sigma: max_sig }
}

///|
/// Total number of pixels described by a histogram.
fn histogram_total(histogram : Array[Int]) -> Int {
  let mut total = 0
  let mut i = 0
  while i < histogram.length() {
    total = total + histogram[i]
    i = i + 1
  }
  total
}

///|
/// Split a grayscale image into the `mlevel` regions selected by the
/// multi-level Otsu thresholds.
///
/// Port of `Multi_OtsuThreshold.showRegions(int, int[], byte[], int, int)`:
/// region `k` keeps the original pixel value where the pixel belongs to
/// region `k` and 0 everywhere else. For `k < mlevel - 1` a pixel belongs
/// to region `k` when `t[k] < value < t[k+1]`; the last region keeps every
/// pixel above `t[mlevel-1]`.
pub fn multi_otsu_regions(
  img : GrayImage,
  thresholds : Array[Int]
) -> Array[GrayImage] {
  let mlevel = thresholds.length()
  let regions = Array::make(mlevel, GrayImage::new(0, 0, 0))
  let mut k = 0
  while k < mlevel {
    regions[k] = GrayImage::new(img.width, img.height, 0)
    k = k + 1
  }
  let pixels = img.pixels
  let n = pixels.length()
  let mut i = 0
  while i < n {
    let val = pixels[i]
    let mut k = 0
    while k < mlevel {
      if k < mlevel - 1 {
        if val < thresholds[k + 1] && val > thresholds[k] {
          regions[k].pixels[i] = val
        }
      } else if val > thresholds[k] {
        regions[k].pixels[i] = val
      }
      k = k + 1
    }
    i = i + 1
  }
  regions
}

///|
/// Convenience wrapper: thresholds plus regions for a grayscale image.
pub fn multi_otsu(
  img : GrayImage,
  mlevel : Int
) -> (MultiOtsuResult, Array[GrayImage]) {
  let result = multi_otsu_thresholds(img.histogram(), mlevel)
  let regions = multi_otsu_regions(img, result.thresholds)
  (result, regions)
}
