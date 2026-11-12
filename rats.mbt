///|
/// Port of the `RATS_` ImageJ plugin (Robust Automatic Threshold Selection,
/// M.H.F. Wilkinson, 2000).
///
/// RATS establishes *regionalized* thresholds: the image is split into a
/// quadtree, every leaf gets its own threshold
///
/// ```text
/// threshold = SUM(edge * original) / SUM(edge)
/// ```
///
/// and the leaf thresholds are bilinearly interpolated back to the full
/// image resolution. Leaves whose edge energy is too small fall back to
/// their parent (the "upward region growing").
///
/// The Java original keeps its arrays in `[x][y]` (column major) order and
/// hands them to ImageJ's `FloatProcessor(float[][])` constructor, which
/// interprets a 2D array as `[row][column]`. The result is a set of
/// transpositions that are observable in the output; they are reproduced
/// here verbatim.
///
/// The quadtree is mirrored one to one: the children of a node are stored
/// as `qt[y group][x group]` and the level grid that the threshold search
/// walks is assembled by `getLevel()`, which interleaves the four
/// sub-trees in a transposed way. Both are reproduced here, because the
/// grid position decides which leaf ends up at which position of the
/// interpolated mask.
///
/// A further Java quirk is reproduced as well: the sum of an inner node is
/// the sum of the four sums of its children (NW, NE, SW, SE), which is
/// *not* the same as summing the pixels of the node rectangle.

///|
/// A 2D float image with the semantics of ImageJ's
/// `FloatProcessor(float[][])`: the array is read as `[row][column]`, so
/// the image width is the length of the inner arrays.
priv struct FloatImage {
  width : Int
  height : Int
  /// row major storage, `data[row * width + col]`
  data : Array[Float]
}

///|
/// Build a `FloatImage` from a `[a][b]` array the way ImageJ does.
fn FloatImage::from_2d(arr : Array[Array[Float]]) -> FloatImage {
  let height = arr.length()
  let width = if height == 0 { 0 } else { arr[0].length() }
  let data = Array::make(width * height, 0.0F)
  let mut row = 0
  while row < height {
    let line = arr[row]
    let mut col = 0
    while col < width {
      data[row * width + col] = line[col]
      col = col + 1
    }
    row = row + 1
  }
  { width, height, data }
}

///|
/// Pixel value at `(col, row)`.
fn FloatImage::get(self : FloatImage, col : Int, row : Int) -> Float {
  self.data[row * self.width + col]
}

///|
/// A node of the RATS quadtree.
///
/// The coordinates are the inclusive pixel bounds of the node; they can be
/// fractional because the tree halves odd sized regions.
priv struct RatsNode {
  x0 : Double
  y0 : Double
  x1 : Double
  y1 : Double
}

///|
/// The RATS quadtree, a one to one mirror of Java's `RATSQuadtree`.
priv struct RatsTree {
  /// the bounds of every node
  nodes : Array[RatsNode]
  /// the level of every node, the root being level 0
  levels : Array[Int]
  /// the parent of every node, -1 for the root
  parents : Array[Int]
  /// the four children of every node in the order NW, NE, SW, SE
  children : Array[Array[Int]]
}

///|
/// An empty tree.
fn RatsTree::new() -> RatsTree {
  { nodes: [], levels: [], parents: [], children: [] }
}

///|
/// Add a node to the tree and subdivide it if it is large enough.
///
/// Java `RATSQuadtree` constructor + `subdivide()`.
fn rats_tree_add(
  tree : RatsTree,
  node : RatsNode,
  level : Int,
  parent : Int,
  min_sz : Double
) -> Int {
  let id = tree.nodes.length()
  tree.nodes.push(node)
  tree.levels.push(level)
  tree.parents.push(parent)
  tree.children.push([])
  let w = node.x1 - node.x0 + 1.0
  let h = node.y1 - node.y0 + 1.0
  if w / 2.0 >= min_sz && h / 2.0 >= min_sz {
    // The children are stored as `qt[y group][x group]`, so NW is (0, 0),
    // NE is (0, 1), SW is (1, 0) and SE is (1, 1).
    let nw = rats_tree_add(
      tree,
      {
        x0: node.x0,
        y0: node.y0,
        x1: node.x0 + w / 2.0 - 1.0,
        y1: node.y0 + h / 2.0 - 1.0,
      },
      level + 1,
      id,
      min_sz
    )
    let ne = rats_tree_add(
      tree,
      {
        x0: node.x0 + w / 2.0,
        y0: node.y0,
        x1: node.x0 + w - 1.0,
        y1: node.y0 + h / 2.0 - 1.0,
      },
      level + 1,
      id,
      min_sz
    )
    let sw = rats_tree_add(
      tree,
      {
        x0: node.x0,
        y0: node.y0 + h / 2.0,
        x1: node.x0 + w / 2.0 - 1.0,
        y1: node.y0 + h - 1.0,
      },
      level + 1,
      id,
      min_sz
    )
    let se = rats_tree_add(
      tree,
      {
        x0: node.x0 + w / 2.0,
        y0: node.y0 + h / 2.0,
        x1: node.x0 + w - 1.0,
        y1: node.y0 + h - 1.0,
      },
      level + 1,
      id,
      min_sz
    )
    tree.children[id] = [nw, ne, sw, se]
  }
  id
}

///|
/// Build the quadtree of an image of the given size.
///
/// Java `new RATSQuadtree(dim, minSzPx)`.
fn rats_tree_build(
  width : Int,
  height : Int,
  min_sz : Double
) -> RatsTree {
  let tree = RatsTree::new()
  let _ = rats_tree_add(
    tree,
    {
      x0: 0.0,
      y0: 0.0,
      x1: Double::from_int(width - 1),
      y1: Double::from_int(height - 1),
    },
    0,
    -1,
    min_sz
  )
  tree
}

///|
/// The number of levels of the tree, the root counting as one.
///
/// Java `RATSQuadtree.countLevels()`.
fn rats_tree_count_levels(tree : RatsTree, id : Int) -> Int {
  let mut levels = 1
  let kids = tree.children[id]
  if kids.length() > 0 {
    levels = levels + rats_tree_count_levels(tree, kids[0])
  }
  levels
}

///|
/// The nodes of the given level, as a grid of node ids.
///
/// Java `RATSQuadtree.getLevel(theLevel)`: the grid is built by combining
/// the four sub-trees, and the combination order transposes the result.
fn rats_tree_level(
  tree : RatsTree,
  id : Int,
  the_level : Int
) -> Array[Array[Int]] {
  let level = tree.levels[id]
  if the_level == level {
    return [[id]]
  }
  let kids = tree.children[id]
  if the_level == level + 1 {
    return [[kids[0], kids[1]], [kids[2], kids[3]]]
  }
  let qnw = rats_tree_level(tree, kids[0], the_level)
  let qne = rats_tree_level(tree, kids[1], the_level)
  let qsw = rats_tree_level(tree, kids[2], the_level)
  let qse = rats_tree_level(tree, kids[3], the_level)
  let ny = qnw.length()
  let nx = qnw[0].length()
  let q : Array[Array[Int]] = {
    let rows = Array::make(ny * 2, [0])
    let mut r = 0
    while r < ny * 2 {
      rows[r] = Array::make(nx * 2, 0)
      r = r + 1
    }
    rows
  }
  let mut v = 0
  while v < ny {
    let mut u = 0
    while u < nx {
      q[v][u] = qnw[v][u]
      q[v][u + nx] = qne[v][u]
      q[v + ny][u] = qsw[v][u]
      q[v + ny][u + nx] = qse[v][u]
      u = u + 1
    }
    v = v + 1
  }
  q
}

///|
/// Java `RATSQuadtree.getCoordsInteger()`: `Math.round` of the bounds.
fn rats_coords_integer(node : RatsNode) -> (Int, Int, Int, Int) {
  (
    java_round_double(node.x0),
    java_round_double(node.y0),
    java_round_double(node.x1),
    java_round_double(node.y1),
  )
}

///|
/// Java `RATSQuadtree.getSumFloat(ImageProcessor)`: the sum of the pixels
/// covered by the node.
///
/// The Java code sums `ip.getPixelValue(i + x0, j + y0)` over the node
/// rectangle; because `ip` is the *transposed* float image (see
/// `FloatImage::from_2d`), the rectangle is effectively sampled transposed
/// as well.
///
/// Returns `None` when the sample leaves the image, which is what the Java
/// code does by throwing an `ArrayIndexOutOfBoundsException`.
fn rats_node_sum(
  img : FloatImage,
  node : RatsNode
) -> Float? {
  let (x0i, y0i, x1i, y1i) = rats_coords_integer(node)
  let wh0 = x1i - x0i + 1
  let wh1 = y1i - y0i + 1
  let mut sum = 0.0F
  let mut j = 0
  while j < wh1 {
    let mut i = 0
    while i < wh0 {
      let index = (j + y0i) * img.width + (i + x0i)
      if index < 0 || index >= img.data.length() {
        return None
      }
      sum = sum + img.data[index]
      i = i + 1
    }
    j = j + 1
  }
  Some(sum)
}

///|
/// Parameters of the RATS algorithm.
pub struct RatsOptions {
  /// noise estimate (standard deviation of the background)
  sigma : Double
  /// scaling factor applied to the noise estimate
  lambda : Double
}

///|
/// Default parameters of the Java plugin (sigma = 25, lambda = 3).
pub fn RatsOptions::default() -> RatsOptions {
  { sigma: 25.0, lambda: 3.0 }
}

///|
/// Result of the RATS thresholding.
pub struct RatsResult {
  /// the regionalised threshold grid, one entry per leaf
  thresholds : Array[Array[Float]]
  /// the interpolated mask; note that its dimensions are swapped with
  /// respect to the input, exactly like in the Java plugin
  mask : GrayImage
  /// `true` when the Java plugin would have raised an exception
  ///
  /// The Java plugin divides by `width - 1` and `height - 1` in
  /// `gradientMHFW`, so an image with a single row or a single column makes
  /// it raise an `ArithmeticException`. The port reports that failure the
  /// same way the reference harness observes it: an empty mask with the
  /// dimensions `0 x 0`.
  failed : Bool
}

///|
/// Regionalised automatic threshold selection (RATS).
///
/// Port of `RATS_.run(ImageProcessor)`.
pub fn rats(img : GrayImage, options : RatsOptions) -> RatsResult {
  let width = img.width
  let height = img.height
  // Java `gradientMHFW` evaluates `y % hm1` and `x % wm1`, where
  // `hm1 = height - 1` and `wm1 = width - 1`. A single row or a single
  // column makes the remainder a division by zero, and the Java plugin
  // raises an `ArithmeticException`. The port stops here and reports the
  // failure instead of running into an out of bounds access later on.
  if width == 1 || height == 1 {
    return { thresholds: [], mask: GrayImage::new(0, 0, 0), failed: true }
  }
  // Java: `minSzPx[0] = (double) ((int) dim[0] / 5.0)` and the same for the
  // height; the larger of the two is then reduced to the smaller one.
  let min_w = Double::from_int(width) / 5.0
  let min_h = Double::from_int(height) / 5.0
  let min_sz = if min_w < min_h { min_w } else { min_h }
  // --- fill the arrays (Java keeps them as float[x][y]) ---
  let p : Array[Array[Float]] = Array::make(width, [0.0F])
  let top : Array[Array[Float]] = Array::make(width, [0.0F])
  let bot : Array[Array[Float]] = Array::make(width, [0.0F])
  let mut x = 0
  while x < width {
    let pcol = Array::make(height, 0.0F)
    let mut y = 0
    while y < height {
      pcol[y] = Float::from_int(img.pixels[y * width + x])
      y = y + 1
    }
    p[x] = pcol
    top[x] = Array::make(height, 0.0F)
    bot[x] = Array::make(height, 0.0F)
    x = x + 1
  }
  // --- gradient (Java gradientMHFW) ---
  let scale = 1.0F / 16.0F
  let lambdasigma = Float::from_double(
    options.lambda * options.sigma * options.lambda * options.sigma
  )
  let two = 2.0F
  let mut y = 0
  let wm1 = width - 1
  let hm1 = height - 1
  y = 0
  while y < height {
    let y_u = if y % hm1 == 0 {
      y - (if y == 0 { 0 } else { 1 })
    } else {
      y - 1
    }
    let y_d = if y % hm1 == 0 {
      y + (if y == hm1 { 0 } else { 1 })
    } else {
      y + 1
    }
    x = 0
    while x < width {
      let x_l = if x % wm1 == 0 {
        x - (if x == 0 { 0 } else { 1 })
      } else {
        x - 1
      }
      let x_r = if x % wm1 == 0 {
        x + (if x == wm1 { 0 } else { 1 })
      } else {
        x + 1
      }
      let wx = p[x_l][y_u] - p[x_l][y_d] +
        two * (p[x][y_u] - p[x][y_d]) +
        p[x_r][y_u] - p[x_r][y_d]
      let wy = p[x_l][y_u] - p[x_r][y_u] +
        two * (p[x_l][y] - p[x_r][y]) +
        p[x_l][y_d] - p[x_r][y_d]
      let temp_g = (wx * wx + wy * wy) * scale
      if temp_g > lambdasigma {
        bot[x][y] = temp_g
        top[x][y] = p[x][y] * temp_g
      }
      x = x + 1
    }
    y = y + 1
  }
  // --- quadtree ---
  let tree = rats_tree_build(width, height, min_sz)
  let depth = rats_tree_count_levels(tree, 0)
  let top_image = FloatImage::from_2d(top)
  let bot_image = FloatImage::from_2d(bot)
  // --- sums of every node (Java fillWithSums) ---
  // The lowest level is summed pixel by pixel, every level above is the
  // sum of the four sums of the children (NW, NE, SW, SE).
  let top_sums = Array::make(tree.nodes.length(), 0.0F)
  let bot_sums = Array::make(tree.nodes.length(), 0.0F)
  let leaf_grid = rats_tree_level(tree, 0, depth - 1)
  let mut v = 0
  while v < leaf_grid.length() {
    let mut u = 0
    while u < leaf_grid[0].length() {
      let id = leaf_grid[v][u]
      match (rats_node_sum(top_image, tree.nodes[id]), rats_node_sum(bot_image, tree.nodes[id])) {
        (Some(t), Some(b)) => {
          top_sums[id] = t
          bot_sums[id] = b
        }
        _ => {
          // The Java code leaves the image here and fails; the harness
          // reports an empty mask.
          return {
            thresholds: [],
            mask: GrayImage::new(0, 0, 0),
            failed: true,
          }
        }
      }
      u = u + 1
    }
    v = v + 1
  }
  let mut level = depth - 2
  while level >= 0 {
    let grid = rats_tree_level(tree, 0, level)
    v = 0
    while v < grid.length() {
      let mut u = 0
      while u < grid[0].length() {
        let id = grid[v][u]
        let kids = tree.children[id]
        top_sums[id] = top_sums[kids[0]] + top_sums[kids[1]] +
          top_sums[kids[2]] + top_sums[kids[3]]
        bot_sums[id] = bot_sums[kids[0]] + bot_sums[kids[1]] +
          bot_sums[kids[2]] + bot_sums[kids[3]]
        u = u + 1
      }
      v = v + 1
    }
    level = level - 1
  }
  // --- per leaf thresholds (Java ratsThresh, walking up the tree) ---
  let test_value = Float::from_double(
    3.0 * options.lambda * options.sigma * options.lambda * options.sigma
  )
  let leaf_rows = leaf_grid.length()
  let leaf_cols = leaf_grid[0].length()
  let thresholds : Array[Array[Float]] = Array::make(leaf_rows, [0.0F])
  v = 0
  while v < leaf_rows {
    let line = Array::make(leaf_cols, 0.0F)
    let mut u = 0
    while u < leaf_cols {
      line[u] = rats_threshold(
        tree,
        top_sums,
        bot_sums,
        leaf_grid[v][u],
        test_value
      )
      u = u + 1
    }
    thresholds[v] = line
    v = v + 1
  }
  // --- bilinear interpolation back to the image resolution ---
  let mask = rats_resize(thresholds, p, width, height)
  { thresholds, mask, failed: false }
}

///|
/// Java `RATS_.ratsThresh(qTop, qBot, test)`.
///
/// The threshold of a leaf is `SUM(top) / SUM(bot)` when `SUM(bot)` is
/// above the test value; otherwise the parent node is used, up to the root
/// which yields `-1`.
fn rats_threshold(
  tree : RatsTree,
  top_sums : Array[Float],
  bot_sums : Array[Float],
  id : Int,
  test_value : Float
) -> Float {
  let mut current = id
  let mut result = -1.0F
  let mut running = true
  while running {
    let top_v = top_sums[current]
    let bot_v = bot_sums[current]
    if bot_v > test_value {
      result = top_v / bot_v
      running = false
    } else if tree.levels[current] == 0 {
      result = -1.0F
      running = false
    } else {
      current = tree.parents[current]
    }
  }
  result
}

///|
/// Java `RATS_.resize(float[][] in)`.
///
/// The Java implementation samples the leaf grid transposed (the first
/// index of `in` is driven by the image x axis) and clamps the last sample
/// with a `0.99` factor so that `in[ix + 1]` stays in range.
fn rats_resize(
  thresholds : Array[Array[Float]],
  p : Array[Array[Float]],
  width : Int,
  height : Int
) -> GrayImage {
  let ow = width
  let oh = height
  let iw = thresholds.length()
  let ih = if iw == 0 { 0 } else { thresholds[0].length() }
  let sx = Array::make(ow, 0.0F)
  let sy = Array::make(oh, 0.0F)
  let ix = Array::make(ow, 0)
  let iy = Array::make(oh, 0)
  let mut x = 0
  while x < ow {
    sx[x] = Float::from_int(x) / Float::from_int(ow - 1) * Float::from_int(iw - 1)
    ix[x] = java_float_to_int(sx[x])
    x = x + 1
  }
  sx[ow - 1] = sx[ow - 2] + 0.99F * (sx[ow - 1] - sx[ow - 2])
  ix[ow - 1] = java_float_to_int(sx[ow - 1])
  let mut y = 0
  while y < oh {
    sy[y] = Float::from_int(y) / Float::from_int(oh - 1) * Float::from_int(ih - 1)
    iy[y] = java_float_to_int(sy[y])
    y = y + 1
  }
  sy[oh - 1] = sy[oh - 2] + 0.99F * (sy[oh - 1] - sy[oh - 2])
  iy[oh - 1] = java_float_to_int(sy[oh - 1])
  // out[x][y] in the Java code, converted to the ImageJ layout below
  let out : Array[Array[Float]] = Array::make(ow, [0.0F])
  let mut xx = 0
  while xx < ow {
    let line = Array::make(oh, 0.0F)
    let mut yy = 0
    while yy < oh {
      let dx = (Float::from_int(ix[xx] + 1) - sx[xx]) * thresholds[ix[xx]][iy[yy]] +
        (sx[xx] - Float::from_int(ix[xx])) * thresholds[ix[xx] + 1][iy[yy]]
      let gx = (Float::from_int(ix[xx] + 1) - sx[xx]) * thresholds[ix[xx]][iy[yy] + 1] +
        (sx[xx] - Float::from_int(ix[xx])) * thresholds[ix[xx] + 1][iy[yy] + 1]
      let r = (Float::from_int(iy[yy] + 1) - sy[yy]) * dx +
        (sy[yy] - Float::from_int(iy[yy])) * gx
      if r < p[xx][yy] {
        line[yy] = 255.0F
      }
      yy = yy + 1
    }
    out[xx] = line
    xx = xx + 1
  }
  // The FloatProcessor(out) constructor reads the array as [row][column],
  // so the mask image has the dimensions swapped with respect to the input.
  let image = FloatImage::from_2d(out)
  let mask = GrayImage::new(image.width, image.height, 0)
  let mut row = 0
  while row < image.height {
    let mut col = 0
    while col < image.width {
      let v = image.get(col, row)
      mask.pixels[row * image.width + col] = if v > 127.0F { 255 } else { 0 }
      col = col + 1
    }
    row = row + 1
  }
  mask
}
