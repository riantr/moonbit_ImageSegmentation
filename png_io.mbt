///|
/// Minimal PNG encoder and decoder (8-bit grayscale and 8-bit RGB).
///
/// Uses the internal zlib implementation (`internal/zlib`) for the zlib
/// (DEFLATE) stream of the IDAT chunk and for the CRC-32 of every chunk.
///
/// Only the subset that the segmentation pipelines need is supported:
/// bit depth 8, colour types 0 (grayscale) and 2 (RGB), no interlacing.
pub suberror PngError {
  /// the file does not start with the PNG signature
  InvalidHeader
  /// the PNG uses a feature that is not supported (bit depth, colour type,
  /// interlacing, ...)
  UnsupportedFormat
  /// the file ended in the middle of a chunk
  TruncatedData
  /// the zlib stream could not be inflated
  ZlibFailed
}

///|
/// A human readable description of the error.
pub fn PngError::message(self : PngError) -> String {
  match self {
    InvalidHeader => "PNG: invalid header"
    UnsupportedFormat => "PNG: unsupported format"
    TruncatedData => "PNG: truncated data"
    ZlibFailed => "PNG: zlib stream could not be inflated"
  }
}

///|
/// The eight byte PNG signature.
const PNG_SIGNATURE : Bytes = b"\x89PNG\r\n\x1a\n"

///|
/// Read a big endian 32 bit unsigned integer from a byte sequence.
fn read_u32_be(bytes : Bytes, offset : Int) -> Int {
  (bytes.at(offset).to_int() << 24) +
  (bytes.at(offset + 1).to_int() << 16) +
  (bytes.at(offset + 2).to_int() << 8) +
  bytes.at(offset + 3).to_int()
}

///|
/// The four big endian bytes of `value` (byte 0 = MSB).
fn u32_be_byte0(value : Int) -> Byte {
  ((value >> 24) & 0xff).to_byte()
}

///|
fn u32_be_byte1(value : Int) -> Byte {
  ((value >> 16) & 0xff).to_byte()
}

///|
fn u32_be_byte2(value : Int) -> Byte {
  ((value >> 8) & 0xff).to_byte()
}

///|
fn u32_be_byte3(value : Int) -> Byte {
  (value & 0xff).to_byte()
}

///|
/// The CRC-32 of a PNG chunk (the chunk type and the chunk data).
fn chunk_crc(chunk_type : Bytes, data : Bytes) -> Int {
  let payload = Bytes::add(chunk_type, data)
  @zlib.crc32(payload).reinterpret_as_int()
}

///|
/// Build a PNG chunk (length, type, data, CRC) as a byte array.
fn png_chunk(chunk_type : Bytes, data : Bytes) -> Array[Byte] {
  let length = data.length()
  let type_length = chunk_type.length()
  let buf : Array[Byte] = Array::make(4 + type_length + length + 4, b'\x00')
  buf[0] = u32_be_byte0(length)
  buf[1] = u32_be_byte1(length)
  buf[2] = u32_be_byte2(length)
  buf[3] = u32_be_byte3(length)
  let mut i = 0
  while i < type_length {
    buf[4 + i] = chunk_type.at(i)
    i = i + 1
  }
  i = 0
  while i < length {
    buf[4 + type_length + i] = data.at(i)
    i = i + 1
  }
  let crc = chunk_crc(chunk_type, data)
  let crc_offset = 4 + type_length + length
  buf[crc_offset] = u32_be_byte0(crc)
  buf[crc_offset + 1] = u32_be_byte1(crc)
  buf[crc_offset + 2] = u32_be_byte2(crc)
  buf[crc_offset + 3] = u32_be_byte3(crc)
  buf
}

///|
/// Concatenate several byte arrays into one.
fn concat_bytes(parts : Array[Array[Byte]]) -> Array[Byte] {
  let mut total = 0
  let mut i = 0
  while i < parts.length() {
    total = total + parts[i].length()
    i = i + 1
  }
  let out : Array[Byte] = Array::make(total, b'\x00')
  let mut offset = 0
  i = 0
  while i < parts.length() {
    let part = parts[i]
    let mut k = 0
    while k < part.length() {
      out[offset + k] = part[k]
      k = k + 1
    }
    offset = offset + part.length()
    i = i + 1
  }
  out
}

///|
/// Encode a grayscale image as a PNG file.
pub fn png_encode_gray(img : GrayImage) -> Bytes {
  let w = img.width
  let h = img.height
  let pixels = img.pixels
  let raw : Array[Byte] = Array::make(h * (w + 1), b'\x00')
  let mut row = 0
  while row < h {
    let offset = row * (w + 1)
    raw[offset] = b'\x00'
    let mut col = 0
    while col < w {
      raw[offset + 1 + col] = pixels[row * w + col].to_byte()
      col = col + 1
    }
    row = row + 1
  }
  png_assemble(w, h, 0, Bytes::from_array(raw))
}

///|
/// Encode an RGB image as a PNG file.
pub fn png_encode_rgb(img : RgbImage) -> Bytes {
  let w = img.width
  let h = img.height
  let pixels = img.pixels
  let raw : Array[Byte] = Array::make(h * (w * 3 + 1), b'\x00')
  let mut row = 0
  while row < h {
    let offset = row * (w * 3 + 1)
    raw[offset] = b'\x00'
    let mut col = 0
    while col < w * 3 {
      raw[offset + 1 + col] = pixels[row * w * 3 + col].to_byte()
      col = col + 1
    }
    row = row + 1
  }
  png_assemble(w, h, 2, Bytes::from_array(raw))
}

///|
/// Assemble the PNG file from the raw (filtered) scan lines.
fn png_assemble(
  width : Int,
  height : Int,
  color_type : Int,
  raw : Bytes
) -> Bytes {
  let ihdr : Array[Byte] = [
    u32_be_byte0(width),
    u32_be_byte1(width),
    u32_be_byte2(width),
    u32_be_byte3(width),
    u32_be_byte0(height),
    u32_be_byte1(height),
    u32_be_byte2(height),
    u32_be_byte3(height),
    b'\x08', // bit depth
    color_type.to_byte(), // colour type
    b'\x00', // compression method
    b'\x00', // filter method
    b'\x00', // interlace method
  ]
  let compressed = @zlib.zlib_compress(raw)
  let parts : Array[Array[Byte]] = [
    PNG_SIGNATURE.to_array(),
    png_chunk(b"IHDR", Bytes::from_array(ihdr)),
    png_chunk(b"IDAT", compressed),
    png_chunk(b"IEND", b""),
  ]
  Bytes::from_array(concat_bytes(parts))
}

///|
/// The decoded contents of a PNG file.
pub struct PngImage {
  width : Int
  height : Int
  /// number of channels (1 = grayscale, 3 = RGB)
  channels : Int
  /// row major samples, `width * height * channels` values in 0..255
  pixels : Array[Int]
}

///|
/// Decode a PNG file into its raw samples.
///
/// Raises `PngError` for unsupported or damaged files.
pub fn png_decode(bytes : Bytes) -> PngImage raise PngError {
  if bytes.length() < 8 {
    raise PngError::InvalidHeader
  }
  let mut i = 0
  while i < 8 {
    if bytes.at(i) != PNG_SIGNATURE.at(i) {
      raise PngError::InvalidHeader
    }
    i = i + 1
  }
  let mut width = 0
  let mut height = 0
  let mut color_type = 0
  let mut interlace = 0
  let mut idat : Array[Byte] = []
  let mut saw_ihdr = false
  let mut offset = 8
  while offset + 8 <= bytes.length() {
    let length = read_u32_be(bytes, offset)
    let data_start = offset + 8
    if data_start + length + 4 > bytes.length() {
      raise PngError::TruncatedData
    }
    let chunk_type = Bytes::makei(4, k => bytes.at(offset + 4 + k))
    let data = Bytes::makei(length, k => bytes.at(data_start + k))
    let c0 = chunk_type.at(0)
    let c1 = chunk_type.at(1)
    let c2 = chunk_type.at(2)
    let c3 = chunk_type.at(3)
    if c0 == b'I' && c1 == b'H' && c2 == b'D' && c3 == b'R' {
      if length < 13 {
        raise PngError::TruncatedData
      }
      width = read_u32_be(data, 0)
      height = read_u32_be(data, 4)
      let bit_depth = data.at(8).to_int()
      color_type = data.at(9).to_int()
      interlace = data.at(12).to_int()
      if bit_depth != 8 || interlace != 0 {
        raise PngError::UnsupportedFormat
      }
      if color_type != 0 && color_type != 2 {
        raise PngError::UnsupportedFormat
      }
      saw_ihdr = true
    } else if c0 == b'I' && c1 == b'D' && c2 == b'A' && c3 == b'T' {
      idat = concat_bytes([idat, data.to_array()])
    } else if c0 == b'I' && c1 == b'E' && c2 == b'N' && c3 == b'D' {
      break
    }
    offset = data_start + length + 4
  }
  if !saw_ihdr {
    raise PngError::InvalidHeader
  }
  let channels = if color_type == 0 { 1 } else { 3 }
  let raw = try {
    @zlib.zlib_decompress(Bytes::from_array(idat))
  } catch {
    _ => raise PngError::ZlibFailed
  }
  let pixels = png_unfilter(raw, width, height, channels)
  { width, height, channels, pixels }
}

///|
/// Decode a PNG file into a grayscale image.
pub fn png_decode_gray(bytes : Bytes) -> GrayImage raise PngError {
  let image = png_decode(bytes)
  if image.channels != 1 {
    raise PngError::UnsupportedFormat
  }
  GrayImage::from_pixels(image.width, image.height, image.pixels)
}

///|
/// Decode a PNG file into an RGB image.
pub fn png_decode_rgb(bytes : Bytes) -> RgbImage raise PngError {
  let image = png_decode(bytes)
  if image.channels != 3 {
    raise PngError::UnsupportedFormat
  }
  RgbImage::from_pixels(image.width, image.height, image.pixels)
}

///|
/// The PNG Paeth predictor.
fn paeth(a : Int, b : Int, c : Int) -> Int {
  let p = a + b - c
  let pa = (p - a).abs()
  let pb = (p - b).abs()
  let pc = (p - c).abs()
  if pa <= pb && pa <= pc {
    a
  } else if pb <= pc {
    b
  } else {
    c
  }
}

///|
/// Undo the PNG row filters.
fn png_unfilter(
  raw : Bytes,
  width : Int,
  height : Int,
  channels : Int
) -> Array[Int] {
  let stride = width * channels
  let out = Array::make(stride * height, 0)
  let prev = Array::make(stride, 0)
  let mut row = 0
  while row < height {
    let filter = raw.at(row * (stride + 1)).to_int()
    let mut x = 0
    while x < stride {
      let value = raw.at(row * (stride + 1) + 1 + x).to_int()
      let a = if x >= channels { out[row * stride + x - channels] } else { 0 }
      let b = prev[x]
      let c = if x >= channels { prev[x - channels] } else { 0 }
      let restored = match filter {
        0 => value
        1 => value + a
        2 => value + b
        3 => value + (a + b) / 2
        4 => value + paeth(a, b, c)
        _ => value
      }
      out[row * stride + x] = restored & 0xff
      x = x + 1
    }
    x = 0
    while x < stride {
      prev[x] = out[row * stride + x]
      x = x + 1
    }
    row = row + 1
  }
  out
}

