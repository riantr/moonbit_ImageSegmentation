///|
/// `seg` CLI — runs the ported segmentation algorithms and writes the
/// result in the very same layout as the Java reference harness
/// (`ref/harness`), so that `verify/compare.py` can diff the two
/// directories byte by byte.
///
/// Usage:
///   seg run --input <gray.raw|file.png> --width <w> --height <h> --outdir <dir>
///   seg <algorithm> --input <gray.raw|file.png> --width <w> --height <h> --outdir <dir>
///   seg to-png --input <gray.raw|file.png> --out <file.png>
///   seg results-png --dir <run-dir> --width <w> --height <h>
///   seg help
///
/// `run` executes every algorithm and writes the complete result set. Every
/// algorithm can also be run **on its own** with its own sub command; the
/// sub commands write the files of that algorithm only (plus a `scalars.txt`
/// that holds the scalars of that algorithm), so that a single algorithm can
/// be checked in isolation — on any of the four MoonBit backends:
///
/// ```
/// seg otsu            seg multiotsu       seg autothreshold
/// seg mixture         seg blob            seg watershed
/// seg densitometry    seg retfm           seg rats
/// seg siox            seg multithresholder
/// ```
///
/// The input is a raw 8-bit grayscale file of exactly `width * height`
/// bytes in raster order. A PNG file is accepted as well; its dimensions
/// are then taken from the file and `--width`/`--height` are ignored.
fn main {
  let argv = user_args()
  if argv.length() < 1 {
    print_usage()
    abort("usage error")
  }
  let command = argv[0]
  if command == "help" || command == "--help" || command == "-h" {
    print_usage()
    return
  }
  let opts = parse_options(argv)
  match command {
    "run" => cmd_run(opts)
    "otsu" => cmd_otsu(opts)
    "multiotsu" => cmd_algorithm(opts, "multiotsu")
    "autothreshold" => cmd_algorithm(opts, "autothreshold")
    "mixture" => cmd_algorithm(opts, "mixture")
    "blob" => cmd_algorithm(opts, "blob")
    "watershed" => cmd_algorithm(opts, "watershed")
    "densitometry" => cmd_algorithm(opts, "densitometry")
    "retfm" => cmd_algorithm(opts, "retfm")
    "rats" => cmd_algorithm(opts, "rats")
    "siox" => cmd_algorithm(opts, "siox")
    "multithresholder" => cmd_multithresholder(opts)
    "to-png" => cmd_to_png(opts)
    "results-png" => cmd_results_png(opts)
    _ => {
      print_usage()
      abort("unknown command")
    }
  }
}

///|
/// Real command line arguments, without the program path.
///
/// `@env.args()` returns `process.argv` on the JavaScript backend (the node
/// binary and the script path come first) and the executable path only on
/// the native backend.
#cfg(target = "js")
fn user_args() -> Array[String] {
  let argv = @env.args()
  let args = []
  let mut k = 2
  while k < argv.length() {
    args.push(argv[k])
    k = k + 1
  }
  args
}

///|
/// Real command line arguments on the native backend.
#cfg(not(target = "js"))
fn user_args() -> Array[String] {
  let argv = @env.args()
  let args = []
  let mut k = 1
  while k < argv.length() {
    args.push(argv[k])
    k = k + 1
  }
  args
}

///|
/// Parse an integer, defaulting to 0.
fn parse_int_safe(s : String) -> Int {
  try {
    @string.parse_int(s)
  } catch {
    _ => 0
  }
}

///|
/// Parsed command line options.
priv struct Options {
  input : String
  width : Int
  height : Int
  outdir : String
  /// the output file of the `to-png` command
  out : String
  /// the directory the `results-png` command reads
  dir : String
}

///|
/// Parse `--key value` pairs.
fn parse_options(argv : Array[String]) -> Options {
  let mut input = ""
  let mut outdir = ""
  let mut out = ""
  let mut dir = "."
  let mut width = 0
  let mut height = 0
  let mut i = 1
  while i < argv.length() {
    let key = argv[i]
    let value = if i + 1 < argv.length() { argv[i + 1] } else { "" }
    if key == "--input" {
      input = value
      i = i + 2
    } else if key == "--outdir" {
      outdir = value
      i = i + 2
    } else if key == "--out" {
      out = value
      i = i + 2
    } else if key == "--dir" {
      dir = value
      i = i + 2
    } else if key == "--width" {
      width = parse_int_safe(value)
      i = i + 2
    } else if key == "--height" {
      height = parse_int_safe(value)
      i = i + 2
    } else {
      i = i + 1
    }
  }
  { input, width, height, outdir, out, dir }
}

///|
/// Print the usage text.
fn print_usage() -> Unit {
  println("seg — MoonBit port of the Java/ImageJ segmentation algorithms")
  println("")
  println("Usage:")
  println(
    "  seg run --input <gray.raw|file.png> --width <w> --height <h> --outdir <dir>"
  )
  println("")
  println("  Every algorithm can also be run on its own:")
  println("  seg otsu | multiotsu | autothreshold | mixture | blob | watershed")
  println("  seg densitometry | retfm | rats | siox | multithresholder")
  println("    --input <gray.raw|file.png> --width <w> --height <h> --outdir <dir>")
  println("")
  println("  seg to-png --input <gray.raw|file.png> --out <file.png>")
  println("  seg results-png --dir <run-dir> --width <w> --height <h>")
  println("  seg help")
  println("")
  println(
    "The input file holds width*height raw bytes (8-bit grayscale, raster"
  )
  println(
    "order). `run` writes the full result set used by verify/compare.py."
  )
  println(
    "`to-png` converts an image into a PNG, `results-png` renders the result"
  )
  println("set of a `run` directory as PNG files.")
}

///|
/// Read a whole file, returning an empty buffer on failure.
fn read_file_bytes(path : String) -> Bytes {
  try {
    @fs.read_file_to_bytes(normalize_path(path))
  } catch {
    _ => b""
  }
}

///|
/// Write a whole file, ignoring IO failures.
fn write_file_bytes(path : String, bytes : Bytes) -> Unit {
  try {
    @fs.write_bytes_to_file(normalize_path(path), bytes)
  } catch {
    _ => ()
  }
}

///|
/// Use forward slashes as the path separator.
///
/// Windows accepts them, node accepts them and the wasm file system shim
/// only understands them, so the same paths work on every backend.
///
/// `String::replace` only replaces the *first* occurrence, so the
/// replacement is repeated until the path does not change any more.
fn normalize_path(path : String) -> String {
  let mut out = path
  let mut i = 0
  while i < 64 {
    let next = out.replace(old="\\", new="/")
    if next == out {
      break
    }
    out = next
    i = i + 1
  }
  out
}

///|
/// Create a directory and every missing parent of it.
///
/// The file system API only has a non recursive `create_dir`, so the
/// parents are created one by one. IO failures are ignored: a directory
/// that already exists is not an error here.
fn create_dir_safe(path : String) -> Unit {
  let normalized = normalize_path(path)
  if normalized == "" {
    return
  }
  let absolute = normalized[0].to_int() == 47
  let mut prefix = if absolute { "/" } else { "" }
  for part in normalized.split("/") {
    let piece = part.to_owned()
    if piece != "" {
      if prefix == "" {
        prefix = piece
      } else if prefix == "/" {
        prefix = prefix + piece
      } else {
        prefix = prefix + "/" + piece
      }
      create_one_dir(prefix)
    }
  }
}

///|
/// Create a single directory, ignoring IO failures.
fn create_one_dir(path : String) -> Unit {
  if path == "" || path == "/" {
    return
  }
  try {
    @fs.create_dir(path)
  } catch {
    _ => ()
  }
}

///|
/// Read a raw grayscale file into a `GrayImage`.
///
/// The file has to hold exactly `width * height` bytes: the Java reference
/// harness rejects a file of a different length, so a short file must not be
/// silently padded with zeros here either.
fn read_gray(path : String, width : Int, height : Int) -> @moonbit_ImageSegmentation.GrayImage {
  let bytes = read_file_bytes(path)
  let n = width * height
  if bytes.length() != n {
    println(
      "error: expected " + n.to_string() + " bytes in " + path +
      " but got " + bytes.length().to_string()
    )
    abort("input error")
  }
  let pixels = Array::make(n, 0)
  let mut i = 0
  while i < n {
    pixels[i] = bytes[i].to_int() & 0xff
    i = i + 1
  }
  @moonbit_ImageSegmentation.GrayImage::from_pixels(width, height, pixels)
}

///|
/// Convert a grayscale image into an RGB image.
///
/// The colour channels are deliberately NOT neutral: the grey level `v` is
/// rendered as `R = v`, `G = 3v/4` and `B = 255 - v`. A neutral copy
/// (R = G = B) would let a plugin that mixes up the channels pass the
/// verification, because every channel would carry the same value. The Java
/// reference harness builds its colour image the same way (see `color` in
/// ref/harness/Harness.java), so both sides see exactly the same colours.
fn gray_to_rgb(img : @moonbit_ImageSegmentation.GrayImage) -> @moonbit_ImageSegmentation.RgbImage {
  let n = img.width * img.height
  let pixels = Array::make(n * 3, 0)
  let mut i = 0
  while i < n {
    let v = img.pixels[i]
    pixels[i * 3] = v
    pixels[i * 3 + 1] = (v * 3) / 4
    pixels[i * 3 + 2] = 255 - v
    i = i + 1
  }
  @moonbit_ImageSegmentation.RgbImage::from_pixels(img.width, img.height, pixels)
}

///|
/// Write the gray levels of an image as raw bytes.
fn write_gray(path : String, img : @moonbit_ImageSegmentation.GrayImage) -> Unit {
  let n = img.width * img.height
  let bytes = Bytes::makei(n, i => img.pixels[i].to_byte())
  write_file_bytes(path, bytes)
}

///|
/// Write the label map as little endian int16 values.
fn write_label_map(path : String, result : @moonbit_ImageSegmentation.BlobLabelResult) -> Unit {
  let n = result.width * result.height
  let bytes = Bytes::makei(n * 2, i => {
    let v = result.map[i / 2]
    if i % 2 == 0 {
      (v & 0xff).to_byte()
    } else {
      ((v >> 8) & 0xff).to_byte()
    }
  })
  write_file_bytes(path, bytes)
}

///|
/// Write the RGB channels of an image as raw bytes (R, G, B interleaved).
fn write_rgb(path : String, img : @moonbit_ImageSegmentation.RgbImage) -> Unit {
  let n = img.width * img.height
  let bytes = Bytes::makei(n * 3, i => img.pixels[i].to_byte())
  write_file_bytes(path, bytes)
}

///|
/// Write a SIOX confidence matrix as little endian float32 values.
fn write_siox_confidence(path : String, cm : Array[Float]) -> Unit {
  let bytes = Bytes::makei(cm.length() * 4, i => {
    let bits = cm[i / 4].reinterpret_as_int()
    let shift = (i % 4) * 8
    ((bits >> shift) & 0xff).to_byte()
  })
  write_file_bytes(path, bytes)
}

///|
/// Write the SIOX mask as one byte per pixel (255 = foreground).
fn write_siox_mask(path : String, cm : Array[Float]) -> Unit {
  let bytes = Bytes::makei(cm.length(), i => {
    if cm[i] >= 0.5F {
      (255).to_byte()
    } else {
      (0).to_byte()
    }
  })
  write_file_bytes(path, bytes)
}

///|
/// Write the scalar lines into the `scalars.txt` of the output directory.
fn write_scalars(outdir : String, scalars : Array[String]) -> Unit {
  let mut content = ""
  let mut i = 0
  while i < scalars.length() {
    content = content + scalars[i] + "\n"
    i = i + 1
  }
  write_file_bytes(outdir + "/scalars.txt", @utf8.encode(content))
}

// ---------------------------------------------------------------------------
// the algorithms, one by one
//
// Every function writes the output files of its algorithm and returns the
// scalar lines of that algorithm. They are the building blocks of both
// `seg run` (which calls all of them) and of the single algorithm sub
// commands.
// ---------------------------------------------------------------------------

///|
/// Otsu thresholding (`OtsuThresholding_`).
fn algo_otsu(
  img : @moonbit_ImageSegmentation.GrayImage,
  outdir : String
) -> Array[String] {
  let threshold = @moonbit_ImageSegmentation.otsu_threshold(img)
  write_gray(
    outdir + "/otsu_image.raw",
    @moonbit_ImageSegmentation.otsu_threshold_image(img)
  )
  ["otsu.threshold " + threshold.to_string()]
}

///|
/// Multi level Otsu (`Multi_OtsuThreshold`, MLEVEL = 4).
fn algo_multi_otsu(
  img : @moonbit_ImageSegmentation.GrayImage,
  outdir : String
) -> Array[String] {
  let (multi, regions) = @moonbit_ImageSegmentation.multi_otsu(img, 4)
  let scalars = ["multiotsu.level 4"]
  let mut k = 0
  while k < 4 {
    scalars.push("multiotsu.t" + (k + 1).to_string() + " " + multi.thresholds[k].to_string())
    write_gray(outdir + "/multiotsu_region" + k.to_string() + ".raw", regions[k])
    k = k + 1
  }
  // The plugin hard codes MLEVEL = 4, but `findMaxSigma` implements the
  // levels 2, 3 and 5 as well and the port supports them, so they are part of
  // the contract.
  let histogram = img.histogram()
  let levels = [2, 3, 5]
  k = 0
  while k < levels.length() {
    let level = levels[k]
    let result = @moonbit_ImageSegmentation.multi_otsu_thresholds(histogram, level)
    let thresholds = result.thresholds
    let mut j = 0
    while j < level {
      scalars.push(
        "multiotsu.level" + level.to_string() + ".t" + (j + 1).to_string() +
        " " + thresholds[j].to_string()
      )
      j = j + 1
    }
    k = k + 1
  }
  scalars
}

///|
/// The 15 automatic threshold methods of `AutoThresholder`.
///
/// The method only produces scalars, so it writes no file.
fn algo_autothreshold(
  img : @moonbit_ImageSegmentation.GrayImage,
  _outdir : String
) -> Array[String] {
  let histogram = img.histogram()
  let methods = @moonbit_ImageSegmentation.auto_threshold_methods()
  let scalars = []
  let mut k = 0
  while k < methods.length() {
    let value = @moonbit_ImageSegmentation.auto_threshold(methods[k], histogram)
    scalars.push("autothreshold." + methods[k] + " " + value.to_string())
    k = k + 1
  }
  scalars
}

///|
/// The two Gaussian mixture model (`MixtureModeling_`).
fn algo_mixture(
  img : @moonbit_ImageSegmentation.GrayImage,
  outdir : String
) -> Array[String] {
  let mixture = @moonbit_ImageSegmentation.mixture_modeling(img)
  write_gray(outdir + "/mixture_image.raw", mixture.image)
  let scalars = [
    "mixture.threshold " + mixture.real_threshold.to_string(),
    "mixture.mu1 " + mixture.mu1.to_string(),
    "mixture.variance1 " + mixture.variance1.to_string(),
    "mixture.mu2 " + mixture.mu2.to_string(),
    "mixture.variance2 " + mixture.variance2.to_string(),
    "mixture.errorMin " + mixture.error_min.to_string(),
    "mixture.diffMu " + mixture.diff_mu.to_string(),
    "mixture.directThreshold " + mixture.direct_threshold.to_string(),
    "mixture.realThreshold " + mixture.real_threshold.to_string(),
    "mixture.bits.mu1 " + mixture.mu1.reinterpret_as_int().to_string(),
    "mixture.bits.variance1 " + mixture.variance1.reinterpret_as_int().to_string(),
    "mixture.bits.mu2 " + mixture.mu2.reinterpret_as_int().to_string(),
    "mixture.bits.variance2 " + mixture.variance2.reinterpret_as_int().to_string(),
    "mixture.bits.errorMin " + mixture.error_min.reinterpret_as_int().to_string(),
    "mixture.bits.diffMu " + mixture.diff_mu.reinterpret_as_int().to_string(),
    "mixture.bits.realThreshold " + Float::from_int(mixture.real_threshold).reinterpret_as_int().to_string(),
  ]
  scalars
}

///|
/// The 4- and 8-connected labeling of `Blob_Labeler`.
///
/// The Java plugin raises an `ArrayIndexOutOfBoundsException` when the image
/// has more labels than `size/2`; the reference harness reports that
/// failure the same way it reports a plugin that found no labels: an empty
/// label map and zero labels. The port does the same.
fn algo_blob(
  img : @moonbit_ImageSegmentation.GrayImage,
  outdir : String
) -> Array[String] {
  let blob4 = @moonbit_ImageSegmentation.blob_label(img, 0, false, true)
  write_label_map(outdir + "/blob4_map.raw", blob4)
  let blob8 = @moonbit_ImageSegmentation.blob_label(img, 0, true, true)
  write_label_map(outdir + "/blob8_map.raw", blob8)
  let scalars = [
    "blob4.numberOfLabels " + blob4.number_of_labels.to_string(),
    "blob4.failed " + (if blob4.failed { "1" } else { "0" }),
    "blob8.numberOfLabels " + blob8.number_of_labels.to_string(),
    "blob8.failed " + (if blob8.failed { "1" } else { "0" }),
  ]
  // The plugin reads its background colour and its edge correction from
  // static fields, so every combination of them is a branch of the plugin.
  let noedge4 = @moonbit_ImageSegmentation.blob_label(img, 0, false, false)
  write_label_map(outdir + "/blob4_noedge_map.raw", noedge4)
  let noedge8 = @moonbit_ImageSegmentation.blob_label(img, 0, true, false)
  write_label_map(outdir + "/blob8_noedge_map.raw", noedge8)
  scalars.push("blob4.noedge.numberOfLabels " + noedge4.number_of_labels.to_string())
  scalars.push("blob4.noedge.failed " + (if noedge4.failed { "1" } else { "0" }))
  scalars.push("blob8.noedge.numberOfLabels " + noedge8.number_of_labels.to_string())
  scalars.push("blob8.noedge.failed " + (if noedge8.failed { "1" } else { "0" }))
  let bgcol4 = @moonbit_ImageSegmentation.blob_label(img, 1, false, true)
  write_label_map(outdir + "/blob4_bgcol_map.raw", bgcol4)
  let bgcol8 = @moonbit_ImageSegmentation.blob_label(img, 1, true, true)
  write_label_map(outdir + "/blob8_bgcol_map.raw", bgcol8)
  scalars.push("blob4.bgcol.numberOfLabels " + bgcol4.number_of_labels.to_string())
  scalars.push("blob4.bgcol.failed " + (if bgcol4.failed { "1" } else { "0" }))
  scalars.push("blob8.bgcol.numberOfLabels " + bgcol8.number_of_labels.to_string())
  scalars.push("blob8.bgcol.failed " + (if bgcol8.failed { "1" } else { "0" }))
  scalars
}

///|
/// The watershed of `Watershed_Algorithm`.
fn algo_watershed(
  img : @moonbit_ImageSegmentation.GrayImage,
  outdir : String
) -> Array[String] {
  write_gray(outdir + "/watershed.raw", @moonbit_ImageSegmentation.watershed(img))
  []
}
///|
/// The 1- and 3-channel densitometry.
fn algo_densitometry(
  img : @moonbit_ImageSegmentation.GrayImage,
  outdir : String
) -> Array[String] {
  let rgb = gray_to_rgb(img)
  let colors = @moonbit_ImageSegmentation.DensitometryColors::default()
  let options = @moonbit_ImageSegmentation.DensitometryOptions::default()
  write_rgb(
    outdir + "/densitometry1.rgb.raw",
    @moonbit_ImageSegmentation.densitometry_1_channel(rgb, colors, options)
  )
  write_rgb(
    outdir + "/densitometry3.rgb.raw",
    @moonbit_ImageSegmentation.densitometry_3_channel(rgb, colors, options)
  )
  // The binarised and the inverted variant: both are branches of the
  // plugins (the static fields `blnFill` and `blnInvr`).
  let binary = options.configured(true, false, @moonbit_ImageSegmentation.DensitometryRegion::full())
  write_rgb(
    outdir + "/densitometry1_binary.rgb.raw",
    @moonbit_ImageSegmentation.densitometry_1_channel(rgb, colors, binary)
  )
  write_rgb(
    outdir + "/densitometry3_binary.rgb.raw",
    @moonbit_ImageSegmentation.densitometry_3_channel(rgb, colors, binary)
  )
  let inverse = options.configured(true, true, @moonbit_ImageSegmentation.DensitometryRegion::full())
  write_rgb(
    outdir + "/densitometry1_inverse.rgb.raw",
    @moonbit_ImageSegmentation.densitometry_1_channel(rgb, colors, inverse)
  )
  write_rgb(
    outdir + "/densitometry3_inverse.rgb.raw",
    @moonbit_ImageSegmentation.densitometry_3_channel(rgb, colors, inverse)
  )
  // The plugins only iterate the ROI of the image, so a run on the whole
  // image never reaches that branch.
  let roi = densitometry_roi(img.width, img.height)
  let region = options.configured(false, false, roi)
  write_rgb(
    outdir + "/densitometry1_roi.rgb.raw",
    @moonbit_ImageSegmentation.densitometry_1_channel(rgb, colors, region)
  )
  // The tolerance is a parameter of the plugins too (the static fields
  // `intTol` and `intRtol` / `intGtol` / `intBtol`), and a different
  // tolerance sends other pixels through the branches above. The three
  // channel tolerances are different from each other, so a mix-up of the
  // channels would show up as well.
  let tolerance = options.with_tolerances(64, 64, 32, 16)
  write_rgb(
    outdir + "/densitometry1_tol.rgb.raw",
    @moonbit_ImageSegmentation.densitometry_1_channel(rgb, colors, tolerance)
  )
  write_rgb(
    outdir + "/densitometry3_tol.rgb.raw",
    @moonbit_ImageSegmentation.densitometry_3_channel(rgb, colors, tolerance)
  )
  []
}

///|
/// The region of interest the densitometry variant works on: the middle half
/// of the image (at least one pixel).
///
/// The Java reference harness computes the same rectangle (see
/// `densitometryRoi` in ref/harness/Harness.java).
fn densitometry_roi(
  width : Int,
  height : Int
) -> @moonbit_ImageSegmentation.DensitometryRegion {
  let x = width / 4
  let y = height / 4
  let mut w = width / 2
  if w < 1 {
    w = 1
  }
  let mut h = height / 2
  if h < 1 {
    h = 1
  }
  if x + w > width {
    w = width - x
  }
  if y + h > height {
    h = height - y
  }
  @moonbit_ImageSegmentation.DensitometryRegion::new(x, y, w, h)
}

///|
/// The helpers of `RetFM_J`.
fn algo_retfm(
  img : @moonbit_ImageSegmentation.GrayImage,
  outdir : String
) -> Array[String] {
  let rgb = gray_to_rgb(img)
  let retfm_gray = @moonbit_ImageSegmentation.retfm_convert_to_grayscale(rgb, [
    true,
    true,
    true,
  ])
  write_gray(outdir + "/retfm_gray.raw", retfm_gray)
  let threshold = @moonbit_ImageSegmentation.retfm_otsu_threshold(retfm_gray)
  write_gray(
    outdir + "/retfm_otsu_image.raw",
    @moonbit_ImageSegmentation.retfm_threshold_and_invert(retfm_gray, threshold)
  )
  let scalars = [
    "retfm.otsuThreshold " + threshold.to_string(),
  ]
  // The same helper with another selection of the channels: the plugin
  // averages the selected channels, so the divisor is the number of the
  // selected channels and every selected channel contributes its own plane.
  // The empty selection divides by zero, the product becomes NaN and the
  // Java original returns an all zero image.
  scalars.push(
    "retfm.red.otsuThreshold " +
    retfm_variant(rgb, outdir, "red", [true, false, false]).to_string(),
  )
  scalars.push(
    "retfm.green.otsuThreshold " +
    retfm_variant(rgb, outdir, "green", [false, true, false]).to_string(),
  )
  scalars.push(
    "retfm.blue.otsuThreshold " +
    retfm_variant(rgb, outdir, "blue", [false, false, true]).to_string(),
  )
  scalars.push(
    "retfm.rg.otsuThreshold " +
    retfm_variant(rgb, outdir, "rg", [true, true, false]).to_string(),
  )
  scalars.push(
    "retfm.rb.otsuThreshold " +
    retfm_variant(rgb, outdir, "rb", [true, false, true]).to_string(),
  )
  scalars.push(
    "retfm.gb.otsuThreshold " +
    retfm_variant(rgb, outdir, "gb", [false, true, true]).to_string(),
  )
  scalars.push(
    "retfm.none.otsuThreshold " +
    retfm_variant(rgb, outdir, "none", [false, false, false]).to_string(),
  )
  scalars
}

///|
/// The grayscale conversion of `RetFM_J` for one selection of the channels.
///
/// The grayscale image is written to `<outdir>/retfm_<name>_gray.raw` and the
/// Otsu threshold of **that** image is returned.
fn retfm_variant(
  rgb : @moonbit_ImageSegmentation.RgbImage,
  outdir : String,
  name : String,
  channels : Array[Bool]
) -> Int {
  let gray = @moonbit_ImageSegmentation.retfm_convert_to_grayscale(rgb, channels)
  write_gray(outdir + "/retfm_" + name + "_gray.raw", gray)
  @moonbit_ImageSegmentation.retfm_otsu_threshold(gray)
}

///|
/// The regionalised automatic threshold selection (`RATS_`).
fn algo_rats(
  img : @moonbit_ImageSegmentation.GrayImage,
  outdir : String
) -> Array[String] {
  let result = @moonbit_ImageSegmentation.rats(
    img,
    @moonbit_ImageSegmentation.RatsOptions::default()
  )
  write_gray(outdir + "/rats_mask.raw", result.mask)
  [
    "rats.mask.width " + result.mask.width.to_string(),
    "rats.mask.height " + result.mask.height.to_string(),
    "rats.failed " + (if result.failed { "1" } else { "0" }),
  ]
}

///|
/// The segmentation of `SioxSegmentator`.
fn algo_siox(
  img : @moonbit_ImageSegmentation.GrayImage,
  outdir : String
) -> Array[String] {
  let rgb = gray_to_rgb(img)
  let cm = Array::make(img.width * img.height, 0.5F)
  let mut i = 0
  while i < cm.length() {
    let v = img.pixels[i]
    cm[i] = if v <= 63 {
      0.0F
    } else if v >= 192 {
      1.0F
    } else {
      0.5F
    }
    i = i + 1
  }
  let result = @moonbit_ImageSegmentation.siox_segmentate(
    rgb,
    cm,
    1,
    4.0,
    @moonbit_ImageSegmentation.siox_default_limits()
  )
  write_siox_confidence(outdir + "/siox_cm.raw", result.confidence)
  write_siox_mask(outdir + "/siox_mask.raw", result.confidence)
  [
    "siox.success " + (if result.success { "1" } else { "0" }),
    "siox.failed " + (if result.failed { "1" } else { "0" }),
  ]
}

///|
/// The level mapping helpers of `Multi_Thresholder`.
fn algo_multithresholder(outdir : String) -> Array[String] {
  let table = @moonbit_ImageSegmentation.multi_thresholder_table()
  let mut text = ""
  let mut t = 0
  while t < table.length() {
    text = text + table[t] + "\n"
    t = t + 1
  }
  write_file_bytes(outdir + "/multithresholder.txt", @utf8.encode(text))
  []
}

// ---------------------------------------------------------------------------
// the commands
// ---------------------------------------------------------------------------

///|
/// `seg run`: run every algorithm and write the reference output set.
fn cmd_run(opts : Options) -> Unit {
  let img = load_input_gray(opts)
  let outdir = opts.outdir
  create_dir_safe(outdir)
  let scalars = []
  let mut k = 0
  // The order is the order of the key list of the Java harness.
  let parts = [
    algo_otsu(img, outdir),
    algo_multi_otsu(img, outdir),
    algo_autothreshold(img, outdir),
    algo_mixture(img, outdir),
    algo_blob(img, outdir),
    algo_watershed(img, outdir),
    algo_densitometry(img, outdir),
    algo_retfm(img, outdir),
    algo_rats(img, outdir),
    algo_siox(img, outdir),
    algo_multithresholder(outdir),
  ]
  while k < parts.length() {
    let part = parts[k]
    let mut j = 0
    while j < part.length() {
      scalars.push(part[j])
      j = j + 1
    }
    k = k + 1
  }
  write_scalars(outdir, scalars)
}

///|
/// `seg <algorithm>`: run a single algorithm and write its output files.
///
/// The `scalars.txt` of the output directory holds the scalars of that
/// algorithm only.
fn cmd_algorithm(opts : Options, name : String) -> Unit {
  let outdir = opts.outdir
  if outdir == "" {
    println("error: --outdir is required")
    abort("usage error")
  }
  create_dir_safe(outdir)
  if name == "multithresholder" {
    write_scalars(outdir, algo_multithresholder(outdir))
    return
  }
  let img = load_input_gray(opts)
  let scalars = match name {
    "otsu" => algo_otsu(img, outdir)
    "multiotsu" => algo_multi_otsu(img, outdir)
    "autothreshold" => algo_autothreshold(img, outdir)
    "mixture" => algo_mixture(img, outdir)
    "blob" => algo_blob(img, outdir)
    "watershed" => algo_watershed(img, outdir)
    "densitometry" => algo_densitometry(img, outdir)
    "retfm" => algo_retfm(img, outdir)
    "rats" => algo_rats(img, outdir)
    "siox" => algo_siox(img, outdir)
    _ => {
      println("error: unknown algorithm " + name)
      abort("usage error")
    }
  }
  write_scalars(outdir, scalars)
}

///|
/// `seg multithresholder`: the level mapping helpers of the plugin.
///
/// The helpers do not work on an image, so the command needs no input.
fn cmd_multithresholder(opts : Options) -> Unit {
  cmd_algorithm(opts, "multithresholder")
}

///|
/// `seg otsu`: print the Otsu threshold of the input image.
///
/// With `--outdir` the output files of the algorithm are written as well.
fn cmd_otsu(opts : Options) -> Unit {
  let img = load_input_gray(opts)
  let threshold = @moonbit_ImageSegmentation.otsu_threshold(img)
  println("otsu.threshold " + threshold.to_string())
  if opts.outdir != "" {
    create_dir_safe(opts.outdir)
    write_scalars(
      opts.outdir,
      algo_otsu(img, opts.outdir)
    )
  }
}
