///|
/// Port of the `Densitometry_1_Channel_` and `Densitometry_3_Channel_`
/// ImageJ plugins (Gholam Reza Kaka & Kaiser Niknam, 2012).
///
/// Both plugins measure the density of a reference colour inside the ROI of
/// an RGB image and replace the pixels with the background colour (or, with
/// binarisation enabled, with the inverted background colour).
///
/// NOTE: the Java code packs the background colour with the channels
/// swapped (`BackgroundB` in the high byte, `BackgroundR` in the middle and
/// `BackgroundG` in the low byte). That quirk is reproduced verbatim.

///|
/// The colour used as the reference / background of the ImageJ toolbar.
pub struct DensitometryColors {
  foreground_r : Int
  foreground_g : Int
  foreground_b : Int
  background_r : Int
  background_g : Int
  background_b : Int
}

///|
/// Default colours: white foreground, black background (the ImageJ
/// toolbar defaults).
pub fn DensitometryColors::default() -> DensitometryColors {
  {
    foreground_r: 255,
    foreground_g: 255,
    foreground_b: 255,
    background_r: 0,
    background_g: 0,
    background_b: 0,
  }
}

///|
/// Pack the background colour the way the Java plugins do (channels
/// swapped).
fn densitometry_background(c : DensitometryColors) -> Int {
  ((c.background_b & 0xff) << 16) + ((c.background_r & 0xff) << 8) +
  (c.background_g & 0xff)
}

///|
/// Pack the inverted background colour the way the Java plugins do
/// (channels swapped).
fn densitometry_inverted_background(c : DensitometryColors) -> Int {
  (((255 - c.background_b) & 0xff) << 16) + (((255 - c.background_r) & 0xff) << 8) +
  ((255 - c.background_g) & 0xff)
}

///|
/// The region of the image the densitometry plugins work on.
///
/// The Java plugins iterate the **ROI** of the image (`ip.getRoi()`), not the
/// whole image; every pixel outside the ROI keeps its value. The default is
/// the whole image (a negative width or height means "the whole image").
pub struct DensitometryRegion {
  x : Int
  y : Int
  width : Int
  height : Int
}

///|
/// The whole image (the default ROI of an ImageJ processor).
pub fn DensitometryRegion::full() -> DensitometryRegion {
  { x: 0, y: 0, width: -1, height: -1 }
}

///|
/// Build a region (ImageJ's ROI).
pub fn DensitometryRegion::new(
  x : Int,
  y : Int,
  width : Int,
  height : Int
) -> DensitometryRegion {
  { x, y, width, height }
}

///|
/// The bounds of the region on an image of `width` x `height` pixels.
fn densitometry_bounds(
  region : DensitometryRegion,
  width : Int,
  height : Int
) -> (Int, Int, Int, Int) {
  if region.width < 0 || region.height < 0 {
    (0, 0, width, height)
  } else {
    (region.x, region.y, region.width, region.height)
  }
}

///|
/// Options of the densitometry plugins.
pub struct DensitometryOptions {
  /// tolerance used by the 1-channel variant
  tolerance : Int
  /// per channel tolerances used by the 3-channel variant
  red_tolerance : Int
  green_tolerance : Int
  blue_tolerance : Int
  /// replace the non matching pixels with the inverted background colour
  binarize : Bool
  /// invert the decision (foreground / background swapped)
  inverse : Bool
  /// the region of the image the plugin works on (ImageJ's ROI)
  region : DensitometryRegion
}

///|
/// Default options of the plugins (tolerance 127, no binarisation, no
/// inversion, the whole image).
pub fn DensitometryOptions::default() -> DensitometryOptions {
  {
    tolerance: 127,
    red_tolerance: 127,
    green_tolerance: 127,
    blue_tolerance: 127,
    binarize: false,
    inverse: false,
    region: DensitometryRegion::full(),
  }
}

///|
/// The options with the given binarisation, inversion and region.
///
/// The Java plugins read these three settings from static fields and from the
/// ROI of the image, so every combination of them is a branch of the plugin.
pub fn DensitometryOptions::configured(
  self : DensitometryOptions,
  binarize : Bool,
  inverse : Bool,
  region : DensitometryRegion
) -> DensitometryOptions {
  {
    tolerance: self.tolerance,
    red_tolerance: self.red_tolerance,
    green_tolerance: self.green_tolerance,
    blue_tolerance: self.blue_tolerance,
    binarize,
    inverse,
    region,
  }
}

///|
/// The options with the given tolerances.
///
/// The Java plugins read the tolerance from a static field — `intTol` for the
/// 1-channel variant and `intRtol` / `intGtol` / `intBtol` for the 3-channel
/// one — so the tolerance is a **parameter** of the plugin and not a constant.
pub fn DensitometryOptions::with_tolerances(
  self : DensitometryOptions,
  tolerance : Int,
  red_tolerance : Int,
  green_tolerance : Int,
  blue_tolerance : Int
) -> DensitometryOptions {
  {
    tolerance,
    red_tolerance,
    green_tolerance,
    blue_tolerance,
    binarize: self.binarize,
    inverse: self.inverse,
    region: self.region,
  }
}

///|
/// One channel densitometry.
///
/// Port of `Densitometry_1_Channel_.run(ImageProcessor)`: a pixel is
/// considered *background* when the squared distance to the reference colour
/// is larger than `tolerance^2`.
pub fn densitometry_1_channel(
  img : RgbImage,
  colors : DensitometryColors,
  options : DensitometryOptions
) -> RgbImage {
  let out = img.copy()
  let pixels = out.pixels
  let tol = options.tolerance
  let tol2 = tol * tol
  let background = densitometry_background(colors)
  let inverted = densitometry_inverted_background(colors)
  // Java iterates the ROI of the image, not the whole image.
  let (rx, ry, rw, rh) = densitometry_bounds(options.region, img.width, img.height)
  let mut y = ry
  while y < ry + rh {
    let row = y * img.width
    let mut x = rx
    while x < rx + rw {
      let i = row + x
      let c = (pixels[i * 3] << 16) | (pixels[i * 3 + 1] << 8) | pixels[i * 3 + 2]
      let r = (c & 0xff0000) >> 16
      let g = (c & 0x00ff00) >> 8
      let b = c & 0x0000ff
      let dr = r - colors.foreground_r
      let dg = g - colors.foreground_g
      let db = b - colors.foreground_b
      let distance = dr * dr + dg * dg + db * db - tol2
      if options.inverse {
        if distance < 0 {
          pixels[i * 3] = (background >> 16) & 0xff
          pixels[i * 3 + 1] = (background >> 8) & 0xff
          pixels[i * 3 + 2] = background & 0xff
        } else if options.binarize {
          pixels[i * 3] = (inverted >> 16) & 0xff
          pixels[i * 3 + 1] = (inverted >> 8) & 0xff
          pixels[i * 3 + 2] = inverted & 0xff
        }
      } else if distance > 0 {
        pixels[i * 3] = (background >> 16) & 0xff
        pixels[i * 3 + 1] = (background >> 8) & 0xff
        pixels[i * 3 + 2] = background & 0xff
      } else if options.binarize {
        pixels[i * 3] = (inverted >> 16) & 0xff
        pixels[i * 3 + 1] = (inverted >> 8) & 0xff
        pixels[i * 3 + 2] = inverted & 0xff
      }
      x = x + 1
    }
    y = y + 1
  }
  out
}

///|
/// Three channel densitometry.
///
/// Port of `Densitometry_3_Channel_.run(ImageProcessor)`: a pixel is
/// considered *background* when any of the three channel differences
/// exceeds its own tolerance.
pub fn densitometry_3_channel(
  img : RgbImage,
  colors : DensitometryColors,
  options : DensitometryOptions
) -> RgbImage {
  let out = img.copy()
  let pixels = out.pixels
  let background = densitometry_background(colors)
  let inverted = densitometry_inverted_background(colors)
  // Java iterates the ROI of the image, not the whole image.
  let (rx, ry, rw, rh) = densitometry_bounds(options.region, img.width, img.height)
  let mut y = ry
  while y < ry + rh {
    let row = y * img.width
    let mut x = rx
    while x < rx + rw {
      let i = row + x
      let c = (pixels[i * 3] << 16) | (pixels[i * 3 + 1] << 8) | pixels[i * 3 + 2]
      let r = (c & 0xff0000) >> 16
      let g = (c & 0x00ff00) >> 8
      let b = c & 0x0000ff
      let dr = (r - colors.foreground_r).abs()
      let dg = (g - colors.foreground_g).abs()
      let db = (b - colors.foreground_b).abs()
      if options.inverse {
        if dr < options.red_tolerance &&
          dg < options.green_tolerance &&
          db < options.blue_tolerance {
          pixels[i * 3] = (background >> 16) & 0xff
          pixels[i * 3 + 1] = (background >> 8) & 0xff
          pixels[i * 3 + 2] = background & 0xff
        } else if options.binarize {
          pixels[i * 3] = (inverted >> 16) & 0xff
          pixels[i * 3 + 1] = (inverted >> 8) & 0xff
          pixels[i * 3 + 2] = inverted & 0xff
        }
      } else if dr > options.red_tolerance ||
        dg > options.green_tolerance ||
        db > options.blue_tolerance {
        pixels[i * 3] = (background >> 16) & 0xff
        pixels[i * 3 + 1] = (background >> 8) & 0xff
        pixels[i * 3 + 2] = background & 0xff
      } else if options.binarize {
        pixels[i * 3] = (inverted >> 16) & 0xff
        pixels[i * 3 + 1] = (inverted >> 8) & 0xff
        pixels[i * 3 + 2] = inverted & 0xff
      }
      x = x + 1
    }
    y = y + 1
  }
  out
}
