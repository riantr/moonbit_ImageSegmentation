///|
#external
priv type Handler

///|
#cfg(platform="windows")
priv struct OsString(String)

///|
#cfg(not(platform="windows"))
priv struct OsString(Bytes)

///|
#cfg(platform="windows")
fn OsString::from_string(str : String) -> OsString {
  OsString(str)
}

///|
#cfg(not(platform="windows"))
fn OsString::from_string(str : String) -> OsString {
  let buf : Array[Byte] = []
  let mut i = 0
  while i < str.length() {
    let c = str.code_unit_at(i).to_int()
    if c < 0x80 {
      buf.push(c.to_byte())
    } else if c < 0x800 {
      buf.push((0xC0 | (c >> 6)).to_byte())
      buf.push((0x80 | (c & 0x3F)).to_byte())
    } else {
      buf.push((0xE0 | (c >> 12)).to_byte())
      buf.push((0x80 | ((c >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (c & 0x3F)).to_byte())
    }
    i = i + 1
  }
  buf.push(b'\x00')
  OsString(Bytes::from_array(buf))
}

///|
#borrow(path, mode)
extern "C" fn fopen_ffi(path : OsString, mode : OsString) -> Handler = "moonbitlang_x_fs_fopen_ffi"

///|
extern "C" fn is_null(ptr : Handler) -> Int = "moonbitlang_x_fs_is_null"

///|
#borrow(ptr)
extern "C" fn fread_ffi(ptr : Bytes, size : Int, nitems : Int, stream : Handler) -> Int = "moonbitlang_x_fs_fread_ffi"

///|
#borrow(ptr)
extern "C" fn fwrite_ffi(ptr : Bytes, size : Int, nitems : Int, stream : Handler) -> Int = "moonbitlang_x_fs_fwrite_ffi"

///|
extern "C" fn get_error_message_ffi() -> Bytes = "moonbitlang_x_fs_get_error_message"

///|
extern "C" fn fseek_ffi(file : Handler, offset : Int, whence : Int) -> Int = "moonbitlang_x_fs_fseek_ffi"

///|
extern "C" fn ftell_ffi(file : Handler) -> Int = "moonbitlang_x_fs_ftell_ffi"

///|
extern "C" fn fflush_ffi(stream : Handler) -> Int = "moonbitlang_x_fs_fflush_ffi"

///|
extern "C" fn fclose_ffi(file : Handler) -> Int = "moonbitlang_x_fs_fclose_ffi"

///|
#borrow(path)
extern "C" fn create_dir_ffi(path : OsString) -> Int = "moonbitlang_x_fs_create_dir_ffi"

///|
fn decode_utf8_lossy(bytes : Bytes) -> String {
  let buf = StringBuilder()
  let mut i = 0
  while i < bytes.length() {
    let b = bytes[i].to_int() & 0xff
    if b < 0x80 {
      buf.write_char(Int::unsafe_to_char(b))
      i = i + 1
    } else if b < 0xE0 && i + 1 < bytes.length() {
      let c = ((b & 0x1F) << 6) | (bytes[i + 1].to_int() & 0x3F)
      buf.write_char(Int::unsafe_to_char(c))
      i = i + 2
    } else if b < 0xF0 && i + 2 < bytes.length() {
      let c = ((b & 0x0F) << 12) | ((bytes[i + 1].to_int() & 0x3F) << 6) | (bytes[i + 2].to_int() & 0x3F)
      buf.write_char(Int::unsafe_to_char(c))
      i = i + 3
    } else {
      buf.write_char('?')
      i = i + 1
    }
  }
  buf.to_string()
}

///|
fn get_error_message() -> String {
  decode_utf8_lossy(get_error_message_ffi())
}

///|
fn read_file_to_bytes_internal(path : String) -> Bytes raise IOError {
  let file = fopen_ffi(OsString::from_string(path), OsString::from_string("rb"))
  guard is_null(file) == 0 else { raise IOError(get_error_message()) }
  guard fseek_ffi(file, 0, 2) == 0 else { raise IOError(get_error_message()) }
  let size = ftell_ffi(file)
  guard size >= 0 else { raise IOError(get_error_message()) }
  guard fseek_ffi(file, 0, 0) == 0 else { raise IOError(get_error_message()) }
  let bytes = Bytes::make(size, 0)
  if size > 0 {
    let bytes_read = fread_ffi(bytes, 1, size, file)
    guard bytes_read == size else {
      let _ = fclose_ffi(file)
      raise IOError(get_error_message())
    }
  }
  guard fclose_ffi(file) == 0 else { raise IOError(get_error_message()) }
  bytes
}

///|
fn write_bytes_to_file_internal(path : String, content : Bytes) -> Unit raise IOError {
  let file = fopen_ffi(OsString::from_string(path), OsString::from_string("wb"))
  guard is_null(file) == 0 else { raise IOError(get_error_message()) }
  let len = content.length()
  if len > 0 {
    let bytes_written = fwrite_ffi(content, 1, len, file)
    guard bytes_written == len else {
      let _ = fclose_ffi(file)
      raise IOError(get_error_message())
    }
  }
  guard fflush_ffi(file) == 0 else { raise IOError(get_error_message()) }
  guard fclose_ffi(file) == 0 else { raise IOError(get_error_message()) }
}

///|
fn create_dir_internal(path : String) -> Unit raise IOError {
  guard create_dir_ffi(OsString::from_string(path)) == 0 else {
    raise IOError(get_error_message())
  }
}
