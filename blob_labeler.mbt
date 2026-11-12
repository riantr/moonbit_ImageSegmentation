///|
/// Port of the `Blob_Labeler` ImageJ plugin (Dimiter Prodanov, IMEC),
/// which labels connected components in a 2D image.
///
/// The labeling follows the classic HIPR2 algorithm
/// (http://homepages.inf.ed.ac.uk/rbf/HIPR2/labeldemo.htm): every pixel
/// inherits the label of an already labelled neighbour, or starts a new
/// label when all its neighbours are background. Labels are then merged
/// with a union-find style `associate` / `reduce` pair and condensed into a
/// dense `1..n` range.
///
/// The optional *vectorization* step of the Java plugin (contour tracing with
/// `ij.gui.Wand`) is ImageJ specific and is not part of this port.
pub struct BlobLabelResult {
  /// number of connected components
  number_of_labels : Int
  /// label map, row-major; background is 0
  map : Array[Int]
  width : Int
  height : Int
  /// `true` when the Java plugin would have raised an exception
  ///
  /// The Java plugin allocates `int[] labels = new int[size/2]` and then
  /// reads `labels[i]` for `i` in `0 .. labelColour`. When the image has
  /// more labels than `size/2` the read leaves the array and the plugin
  /// raises an `ArrayIndexOutOfBoundsException`. The port reports that
  /// failure instead of reading out of bounds.
  failed : Bool
}

///|
/// The clamped coordinates of the neighbours of the pixel (x, y), exactly as
/// the Java plugin computes them: `x <= 0` becomes 1, `x >= width` becomes
/// `width - 1` and `y <= 0` becomes 1. The `y` is **not** clamped against the
/// height - that is what makes the plugin read outside the image for an image
/// that is one row high.
fn clamped_neighbour(width : Int, x : Int, y : Int) -> (Int, Int) {
  let mut cx = x
  let mut cy = y
  if cx <= 0 {
    cx = 1
  }
  if cx >= width {
    cx = width - 1
  }
  if cy <= 0 {
    cy = 1
  }
  (cx, cy)
}

///|
/// Whether the reads of the neighbours of the pixel (x, y) stay inside the
/// image.
///
/// The Java plugin reads its neighbours through `ImageProcessor.get(x, y)`,
/// which is `pixels[y * width + x]` in the reference stub. A read that leaves
/// the array raises an `ArrayIndexOutOfBoundsException` there - the plugin
/// reads the row 1 of an image that is one row high, and the column -1 of an
/// image that is one column wide. MoonBit cannot catch an out of bounds
/// access, so the port checks the indices itself and reports the failure the
/// way the reference harness observes it.
fn neighbours_in_bounds(
  width : Int,
  size : Int,
  x : Int,
  y : Int,
  eight_connected : Bool
) -> Bool {
  let (cx, cy) = clamped_neighbour(width, x, y)
  // the west neighbour: get(cx - 1, cy)
  let west = cy * width + (cx - 1)
  if west < 0 || west >= size {
    return false
  }
  // the north neighbour: get(cx, cy - 1)
  let north = (cy - 1) * width + cx
  if north < 0 || north >= size {
    return false
  }
  if eight_connected {
    // the north west neighbour: get(cx - 1, cy - 1)
    let north_west = (cy - 1) * width + (cx - 1)
    if north_west < 0 || north_west >= size {
      return false
    }
    // the north east neighbour: get(cx + 1, cy - 1)
    let north_east = (cy - 1) * width + (cx + 1)
    if north_east < 0 || north_east >= size {
      return false
    }
  }
  true
}

///|
/// Java `neighborhood4(ImageProcessor bp, int[] nbs, int x, int y, int width)`.
///
/// The clamping of `x` / `y` is reproduced verbatim: `x <= 0` becomes 1 and
/// `y <= 0` becomes 1, so the "west" neighbour of column 0 is column 0
/// itself and the "north" neighbour of row 0 is row 0 itself.
fn neighborhood4(
  pixels : Array[Int],
  width : Int,
  x : Int,
  y : Int
) -> (Int, Int) {
  let (cx, cy) = clamped_neighbour(width, x, y)
  (pixels[cy * width + (cx - 1)], pixels[(cy - 1) * width + cx])
}

///|
/// Java `neighborhood8(ImageProcessor bp, int[] nbs, int x, int y, int width)`.
///
/// Note that the Java code clamps `x` to `width - 1` and **then** reads
/// `get(x + 1, y - 1)`, so for the last column the linear index becomes
/// `(y - 1) * width + width = y * width`: the read leaves the row and lands on
/// the **first pixel of row `y`**, the row below the intended north row. The
/// port keeps that behaviour because it is observable in the resulting labels.
fn neighborhood8(
  pixels : Array[Int],
  width : Int,
  x : Int,
  y : Int
) -> (Int, Int, Int, Int) {
  let (cx, cy) = clamped_neighbour(width, x, y)
  (pixels[cy * width + (cx - 1)], pixels[(cy - 1) * width + cx],
   pixels[(cy - 1) * width + (cx - 1)], pixels[(cy - 1) * width + (cx + 1)])
}

///|
/// The result the Java plugin produces when it raises an exception: the
/// reference harness observes an empty label map and no labels at all.
///
/// The Java plugin allocates `int[] labels = new int[size/2]` and reads
/// `labels[i]` for label indices up to `labelColour - 1`. As soon as a label
/// index reaches `size/2` the read leaves the array and the plugin raises an
/// `ArrayIndexOutOfBoundsException` - either while two labels are merged
/// (`associate`) or while the labels are condensed at the end. MoonBit cannot
/// catch an out of bounds access, so the port checks the index itself and
/// reports the failure the same way the harness observes it.
fn blob_label_failed(size : Int, width : Int, height : Int) -> BlobLabelResult {
  let empty = Array::make(size, 0)
  { number_of_labels: 0, map: empty, width, height, failed: true }
}

///|
/// Java `associate(int[] labels, int a, int b)`: merge the equivalence
/// classes of `a` and `b`, keeping the smaller label as representative.
fn associate(labels : Array[Int], a : Int, b : Int) -> Unit {
  if a > b {
    associate(labels, b, a)
    return
  }
  if a == b || labels[b] == a {
    return
  }
  if labels[b] == b {
    labels[b] = a
  } else {
    associate(labels, labels[b], a)
    if labels[b] > a {
      labels[b] = a
    }
  }
}

///|
/// Java `reduce(int[] labels, int a)`: follow the label chain to its root.
fn reduce(labels : Array[Int], a : Int) -> Int {
  if labels[a] == a {
    a
  } else {
    reduce(labels, labels[a])
  }
}

///|
/// Label the connected components of a grayscale image.
///
/// Parameters:
/// - `bgcol`: the background value (pixels equal to it stay unlabelled)
/// - `eight_connected`: use the 8-connected neighbourhood
/// - `edge_correction`: overwrite the first row and the first column with
///   the background value before labeling (as the Java plugin does)
///
/// The input image is not modified; the Java plugin overwrites the border
/// of the image it is given.
pub fn blob_label(
  img : GrayImage,
  bgcol : Int,
  eight_connected : Bool,
  edge_correction : Bool
) -> BlobLabelResult {
  let width = img.width
  let height = img.height
  let size = width * height
  let bp = img.copy()
  let pixels = bp.pixels
  let map = Array::make(size, 0)
  if edge_correction {
    let mut a = 0
    while a < width {
      pixels[a] = bgcol
      a = a + 1
    }
    a = 0
    while a < height {
      pixels[a * width] = bgcol
      a = a + 1
    }
  }
  // Java: int[] labels = new int[size/2];
  let labels = Array::make(size / 2, 0)
  let mut i = 0
  while i < labels.length() {
    labels[i] = i
    i = i + 1
  }
  let mut label_colour = 1
  let mut y = 0
  while y < height {
    let mut x = 0
    while x < width {
      let val = pixels[y * width + x]
      let mut result = 0
      if val != bgcol {
        // The Java plugin reads its neighbours through `ImageProcessor.get`,
        // which raises an `ArrayIndexOutOfBoundsException` when the read
        // leaves the image (an image that is one row or one column high).
        // The port reports that failure the way the harness observes it.
        if !neighbours_in_bounds(width, size, x, y, eight_connected) {
          return blob_label_failed(size, width, height)
        }
        if eight_connected {
          let (n0, n1, n2, n3) = neighborhood8(pixels, width, x, y)
          let (l0, l1, l2, l3) = neighborhood8(map, width, x, y)
          let nbs = [n0, n1, n2, n3]
          let nbslab = [l0, l1, l2, l3]
          if nbs[0] == nbs[1] && nbs[1] == nbs[2] && nbs[2] == nbs[3] &&
            nbs[0] == bgcol {
            result = label_colour
            label_colour = label_colour + 1
            if label_colour > labels.length() {
              return blob_label_failed(size, width, height)
            }
          } else {
            let mut count = 0
            let mut found = -1
            let mut j = 0
            while j < 4 {
              if nbs[j] != bgcol {
                count = count + 1
                found = j
              }
              j = j + 1
            }
            if count == 1 {
              result = nbslab[found]
            } else {
              result = nbslab[found]
              j = 0
              while j < 4 {
                if nbslab[j] != 0 && nbslab[j] != result {
                  associate(labels, nbslab[j], result)
                }
                j = j + 1
              }
            }
          }
        } else {
          let (n0, n1) = neighborhood4(pixels, width, x, y)
          let (l0, l1) = neighborhood4(map, width, x, y)
          let nbs = [n0, n1]
          let nbslab = [l0, l1]
          if nbs[0] == nbs[1] && nbs[0] == bgcol {
            result = label_colour
            label_colour = label_colour + 1
            if label_colour > labels.length() {
              return blob_label_failed(size, width, height)
            }
          } else {
            let mut count = 0
            let mut found = -1
            let mut j = 0
            while j < 2 {
              if nbs[j] != bgcol {
                count = count + 1
                found = j
              }
              j = j + 1
            }
            if count == 1 {
              result = nbslab[found]
            } else {
              result = nbslab[found]
              j = 0
              while j < 2 {
                if nbslab[j] != 0 && nbslab[j] != result {
                  associate(labels, nbslab[j], result)
                }
                j = j + 1
              }
            }
          }
        }
        map[y * width + x] = result
      }
      x = x + 1
    }
    y = y + 1
  }
  // reduce the labels (in reverse order to preserve sorting)
  i = labels.length() - 1
  while i > 0 {
    labels[i] = reduce(labels, i)
    i = i - 1
  }
  let mut number_of_labels = -1
  if label_colour > 0 {
    // Java reads `labels[i]` for `i` in `0 .. labelColour` while the array
    // only has `size/2` entries; a larger label count leaves the array and
    // the Java plugin raises an ArrayIndexOutOfBoundsException. The port
    // reports the failure the way the reference harness observes it: no
    // label map at all and no labels.
    if label_colour > labels.length() {
      return blob_label_failed(size, width, height)
    }
    let condensed = Array::make(label_colour, 0)
    let mut count = 0
    i = 0
    while i < label_colour {
      if i == labels[i] {
        condensed[i] = count
        count = count + 1
      }
      i = i + 1
    }
    number_of_labels = count - 1
    i = 0
    while i < size {
      let val = map[i]
      map[i] = condensed[labels[val]]
      i = i + 1
    }
  }
  { number_of_labels, map, width, height, failed: false }
}
