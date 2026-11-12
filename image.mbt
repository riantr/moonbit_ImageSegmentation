///|
/// 8-bit grayscale image, row-major, one pixel per element.
///
/// Mirrors ImageJ's `ij.process.ByteProcessor`: the Java sources keep pixels
/// in a *signed* `byte[]` and therefore mask every read with `0xff`. Here the
/// values are plain `Int`s in `0..255`, which is the same unsigned view of
/// the very same bytes.
pub struct GrayImage {
  width: Int
  height: Int
  pixels: Array[Int]
}

///|
/// 24-bit RGB image, row-major, three `Int`s per pixel (`R, G, B`).
///
/// Mirrors ImageJ's `ij.process.ColorProcessor`, whose `int[]` pixels pack
/// the channels as `0x00RRGGBB`.
pub struct RgbImage {
  width: Int
  height: Int
  pixels: Array[Int]
}

///|
/// Create a grayscale image of `width` x `height` filled with `fill`.
pub fn GrayImage::new(width : Int, height : Int, fill : Int) -> GrayImage {
  { width, height, pixels: Array::make(width * height, fill) }
}

///|
/// Build a grayscale image from a flat row-major pixel array.
pub fn GrayImage::from_pixels(
  width : Int,
  height : Int,
  pixels : Array[Int]
) -> GrayImage {
  { width, height, pixels }
}

///|
/// Pixel count (`width * height`).
pub fn GrayImage::size(self : GrayImage) -> Int {
  self.width * self.height
}

///|
/// Pixel value at `(x, y)`.
pub fn GrayImage::get(self : GrayImage, x : Int, y : Int) -> Int {
  self.pixels[y * self.width + x]
}

///|
/// Set the pixel value at `(x, y)`.
pub fn GrayImage::set(self : GrayImage, x : Int, y : Int, value : Int) -> Unit {
  let pixels = self.pixels
  pixels[y * self.width + x] = value
}

///|
/// Deep copy of this image.
pub fn GrayImage::copy(self : GrayImage) -> GrayImage {
  let src = self.pixels
  let n = src.length()
  let dst = Array::make(n, 0)
  let mut i = 0
  while i < n {
    dst[i] = src[i]
    i = i + 1
  }
  { width: self.width, height: self.height, pixels: dst }
}

///|
/// 256-bin intensity histogram, the equivalent of
/// `ImageProcessor.getHistogram()`.
pub fn GrayImage::histogram(self : GrayImage) -> Array[Int] {
  let hist = Array::make(256, 0)
  let pixels = self.pixels
  let n = pixels.length()
  let mut i = 0
  while i < n {
    let v = pixels[i]
    hist[v] = hist[v] + 1
    i = i + 1
  }
  hist
}

///|
/// Create an RGB image of `width` x `height` filled with `(r, g, b)`.
pub fn RgbImage::new(
  width : Int,
  height : Int,
  r : Int,
  g : Int,
  b : Int
) -> RgbImage {
  let n = width * height
  let pixels = Array::make(n * 3, 0)
  let mut i = 0
  while i < n {
    pixels[i * 3] = r
    pixels[i * 3 + 1] = g
    pixels[i * 3 + 2] = b
    i = i + 1
  }
  { width, height, pixels }
}

///|
/// Build an RGB image from a flat row-major `R,G,B` array.
pub fn RgbImage::from_pixels(
  width : Int,
  height : Int,
  pixels : Array[Int]
) -> RgbImage {
  { width, height, pixels }
}

///|
/// Number of pixels.
pub fn RgbImage::size(self : RgbImage) -> Int {
  self.width * self.height
}

///|
/// Read the red channel of pixel `(x, y)`.
pub fn RgbImage::red(self : RgbImage, x : Int, y : Int) -> Int {
  self.pixels[(y * self.width + x) * 3]
}

///|
/// Read the green channel of pixel `(x, y)`.
pub fn RgbImage::green(self : RgbImage, x : Int, y : Int) -> Int {
  self.pixels[(y * self.width + x) * 3 + 1]
}

///|
/// Read the blue channel of pixel `(x, y)`.
pub fn RgbImage::blue(self : RgbImage, x : Int, y : Int) -> Int {
  self.pixels[(y * self.width + x) * 3 + 2]
}

///|
/// Pack pixel `(x, y)` the way ImageJ's `ColorProcessor` does, i.e. as
/// `0x00RRGGBB`.
pub fn RgbImage::packed(self : RgbImage, x : Int, y : Int) -> Int {
  let i = (y * self.width + x) * 3
  (self.pixels[i] << 16) + (self.pixels[i + 1] << 8) + self.pixels[i + 2]
}

///|
/// Set pixel `(x, y)` from separate channels.
pub fn RgbImage::set(
  self : RgbImage,
  x : Int,
  y : Int,
  r : Int,
  g : Int,
  b : Int
) -> Unit {
  let pixels = self.pixels
  let i = (y * self.width + x) * 3
  pixels[i] = r
  pixels[i + 1] = g
  pixels[i + 2] = b
}

///|
/// Copy of this image with an independent pixel buffer.
pub fn RgbImage::copy(self : RgbImage) -> RgbImage {
  let src = self.pixels
  let n = src.length()
  let dst = Array::make(n, 0)
  let mut i = 0
  while i < n {
    dst[i] = src[i]
    i = i + 1
  }
  { width: self.width, height: self.height, pixels: dst }
}
