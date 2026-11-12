///|
/// The PNG front end of the `seg` CLI.
///
/// The byte exact reference path (`seg run`) works on raw grayscale files,
/// because that is the input contract of the Java harness. These commands
/// add the two conveniences that are missing from it:
///
/// - `seg run` also accepts a PNG file, so the algorithms can be driven
///   with ordinary image files;
/// - `seg to-png` and `seg results-png` write the results as PNG files, so
///   that they can be looked at.
///
/// The PNG codec itself lives in the library package (`png_io.mbt`); it
/// handles 8 bit grayscale and 8 bit RGB images without interlacing.

///|
/// Whether the buffer starts with the PNG signature.
fn is_png(bytes : Bytes) -> Bool {
  if bytes.length() < 8 {
    return false
  }
  let signature = b"\x89PNG\r\n\x1a\n"
  let mut i = 0
  while i < 8 {
    if bytes.at(i) != signature.at(i) {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// The grayscale samples of a decoded PNG.
fn gray_from_png(image : @moonbit_ImageSegmentation.PngImage) -> @moonbit_ImageSegmentation.GrayImage {
  @moonbit_ImageSegmentation.GrayImage::from_pixels(
    image.width,
    image.height,
    image.pixels
  )
}

///|
/// The RGB samples of a decoded PNG.
fn rgb_from_png(image : @moonbit_ImageSegmentation.PngImage) -> @moonbit_ImageSegmentation.RgbImage {
  @moonbit_ImageSegmentation.RgbImage::from_pixels(
    image.width,
    image.height,
    image.pixels
  )
}

///|
/// The luma of an RGB image, with the ITU-R BT.601 weights.
///
/// The weights are applied to integers and rounded to the nearest integer,
/// so that a grey pixel (`R = G = B`) keeps its value exactly: the three
/// weights add up to one.
fn rgb_to_luma(image : @moonbit_ImageSegmentation.PngImage) -> @moonbit_ImageSegmentation.GrayImage {
  let n = image.width * image.height
  let pixels = Array::make(n, 0)
  let mut i = 0
  while i < n {
    let r = image.pixels[i * 3]
    let g = image.pixels[i * 3 + 1]
    let b = image.pixels[i * 3 + 2]
    pixels[i] = (299 * r + 587 * g + 114 * b + 500) / 1000
    i = i + 1
  }
  @moonbit_ImageSegmentation.GrayImage::from_pixels(image.width, image.height, pixels)
}

///|
/// Read a raw 8 bit grayscale file, refusing a file whose length does not
/// match the given dimensions.
///
/// The Java reference harness raises an exception in that case, so the port
/// must not silently work on a padded image instead.
fn load_raw_gray(
  path : String,
  width : Int,
  height : Int
) -> @moonbit_ImageSegmentation.GrayImage {
  let bytes = read_file_bytes(path)
  if bytes.length() == 0 {
    println("error: cannot read the input file " + path)
    abort("input error")
  }
  if width <= 0 || height <= 0 {
    println(
      "error: --width and --height are required for a raw input file"
    )
    abort("usage error")
  }
  let n = width * height
  if bytes.length() != n {
    println(
      "error: expected " + n.to_string() + " bytes in " + path +
      " but got " + bytes.length().to_string()
    )
    abort("input error")
  }
  read_gray(path, width, height)
}

///|
/// Load the input image of the options.
///
/// A PNG file is decoded (grayscale as is, RGB through its BT.601 luma); a
/// raw file is read as 8 bit grayscale with the given dimensions.
///
/// A file that cannot be read, and a raw file whose length does not match
/// the given dimensions, are refused: the Java reference harness raises an
/// exception in both cases, so the port must not silently work on an empty
/// image instead.
fn load_input_gray(opts : Options) -> @moonbit_ImageSegmentation.GrayImage {
  let bytes = read_file_bytes(opts.input)
  if bytes.length() == 0 {
    println("error: cannot read the input file " + opts.input)
    abort("input error")
  }
  if is_png(bytes) {
    try {
      let image = @moonbit_ImageSegmentation.png_decode(bytes)
      if image.channels == 1 {
        gray_from_png(image)
      } else {
        rgb_to_luma(image)
      }
    } catch {
      e => {
        println("error: cannot decode " + opts.input + ": " + e.message())
        abort("png error")
      }
    }
  } else {
    load_raw_gray(opts.input, opts.width, opts.height)
  }
}

///|
/// `seg to-png`: convert an image into a PNG file.
fn cmd_to_png(opts : Options) -> Unit {
  if opts.out == "" {
    println("error: --out is required")
    abort("usage error")
  }
  let bytes = read_file_bytes(opts.input)
  if is_png(bytes) {
    try {
      let image = @moonbit_ImageSegmentation.png_decode(bytes)
      if image.channels == 1 {
        write_file_bytes(
          opts.out,
          @moonbit_ImageSegmentation.png_encode_gray(gray_from_png(image))
        )
      } else {
        write_file_bytes(
          opts.out,
          @moonbit_ImageSegmentation.png_encode_rgb(rgb_from_png(image))
        )
      }
    } catch {
      e => {
        println("error: cannot decode " + opts.input + ": " + e.message())
        abort("png error")
      }
    }
  } else {
    let img = load_raw_gray(opts.input, opts.width, opts.height)
    write_file_bytes(opts.out, @moonbit_ImageSegmentation.png_encode_gray(img))
  }
  println("wrote " + opts.out)
}

///|
/// Read a raw 8 bit grayscale file into a `GrayImage`.
fn read_gray_raw(path : String, width : Int, height : Int) -> @moonbit_ImageSegmentation.GrayImage {
  let bytes = read_file_bytes(path)
  let n = width * height
  let pixels = Array::make(n, 0)
  let mut i = 0
  while i < n && i < bytes.length() {
    pixels[i] = bytes.at(i).to_int() & 0xff
    i = i + 1
  }
  @moonbit_ImageSegmentation.GrayImage::from_pixels(width, height, pixels)
}

///|
/// Read a raw RGB file into an `RgbImage`.
fn read_rgb_raw(path : String, width : Int, height : Int) -> @moonbit_ImageSegmentation.RgbImage {
  let bytes = read_file_bytes(path)
  let n = width * height * 3
  let pixels = Array::make(n, 0)
  let mut i = 0
  while i < n && i < bytes.length() {
    pixels[i] = bytes.at(i).to_int() & 0xff
    i = i + 1
  }
  @moonbit_ImageSegmentation.RgbImage::from_pixels(width, height, pixels)
}

///|
/// `seg results-png`: render the result set of a `seg run` directory as PNG
/// files.
///
/// Every 8 bit result image of the directory is written next to it with a
/// `.png` suffix. The label maps of the blob labeling are int16 and have no
/// direct PNG representation, so they are skipped.
fn cmd_results_png(opts : Options) -> Unit {
  let dir = opts.dir
  let width = opts.width
  let height = opts.height
  if width <= 0 || height <= 0 {
    println("error: --width and --height are required")
    abort("usage error")
  }
  // (file name, width, height) of the 8 bit result images. The RATS mask
  // has its dimensions swapped with respect to the input, exactly like in
  // the Java plugin.
  let gray_results = [
    ("otsu_image", width, height),
    ("mixture_image", width, height),
    ("watershed", width, height),
    ("retfm_gray", width, height),
    ("retfm_otsu_image", width, height),
    ("retfm_red_gray", width, height),
    ("retfm_green_gray", width, height),
    ("retfm_blue_gray", width, height),
    ("retfm_rg_gray", width, height),
    ("retfm_rb_gray", width, height),
    ("retfm_gb_gray", width, height),
    ("retfm_none_gray", width, height),
    ("siox_mask", width, height),
    ("rats_mask", height, width),
    ("multiotsu_region0", width, height),
    ("multiotsu_region1", width, height),
    ("multiotsu_region2", width, height),
    ("multiotsu_region3", width, height),
  ]
  let mut k = 0
  while k < gray_results.length() {
    let (name, w, h) = gray_results[k]
    let path = dir + "/" + name + ".raw"
    if file_exists(path) {
      let image = read_gray_raw(path, w, h)
      write_file_bytes(
        dir + "/" + name + ".png",
        @moonbit_ImageSegmentation.png_encode_gray(image)
      )
      println("wrote " + dir + "/" + name + ".png")
    }
    k = k + 1
  }
  let rgb_results = [
    ("densitometry1.rgb", width, height),
    ("densitometry3.rgb", width, height),
    ("densitometry1_binary.rgb", width, height),
    ("densitometry3_binary.rgb", width, height),
    ("densitometry1_inverse.rgb", width, height),
    ("densitometry3_inverse.rgb", width, height),
    ("densitometry1_roi.rgb", width, height),
    ("densitometry1_tol.rgb", width, height),
    ("densitometry3_tol.rgb", width, height),
  ]
  k = 0
  while k < rgb_results.length() {
    let (name, w, h) = rgb_results[k]
    let path = dir + "/" + name + ".raw"
    if file_exists(path) {
      let image = read_rgb_raw(path, w, h)
      write_file_bytes(
        dir + "/" + name + ".png",
        @moonbit_ImageSegmentation.png_encode_rgb(image)
      )
      println("wrote " + dir + "/" + name + ".png")
    }
    k = k + 1
  }
}

///|
/// Whether a file exists and can be read.
fn file_exists(path : String) -> Bool {
  try {
    let _ = @fs.read_file_to_bytes(normalize_path(path))
    true
  } catch {
    _ => false
  }
}

