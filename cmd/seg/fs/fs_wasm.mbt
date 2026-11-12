///|
#external
priv type XStringCreateHandle

///|
#external
priv type XStringReadHandle

///|
#external
priv type XExternString

///|
#external
priv type XByteArrayCreateHandle

///|
#external
priv type XByteArrayReadHandle

///|
#external
priv type XExternByteArray

///|
fn begin_create_string() -> XStringCreateHandle = "__moonbit_fs_unstable" "begin_create_string"

///|
fn string_append_char(handle : XStringCreateHandle, ch : Int) = "__moonbit_fs_unstable" "string_append_char"

///|
fn finish_create_string(handle : XStringCreateHandle) -> XExternString = "__moonbit_fs_unstable" "finish_create_string"

///|
fn begin_read_string(s : XExternString) -> XStringReadHandle = "__moonbit_fs_unstable" "begin_read_string"

///|
fn string_read_char(handle : XStringReadHandle) -> Int = "__moonbit_fs_unstable" "string_read_char"

///|
fn finish_read_string(handle : XStringReadHandle) = "__moonbit_fs_unstable" "finish_read_string"

///|
fn begin_create_byte_array() -> XByteArrayCreateHandle = "__moonbit_fs_unstable" "begin_create_byte_array"

///|
fn byte_array_append_byte(handle : XByteArrayCreateHandle, ch : Int) = "__moonbit_fs_unstable" "byte_array_append_byte"

///|
fn finish_create_byte_array(handle : XByteArrayCreateHandle) -> XExternByteArray = "__moonbit_fs_unstable" "finish_create_byte_array"

///|
fn begin_read_byte_array(s : XExternByteArray) -> XByteArrayReadHandle = "__moonbit_fs_unstable" "begin_read_byte_array"

///|
fn byte_array_read_byte(handle : XByteArrayReadHandle) -> Int = "__moonbit_fs_unstable" "byte_array_read_byte"

///|
fn finish_read_byte_array(handle : XByteArrayReadHandle) = "__moonbit_fs_unstable" "finish_read_byte_array"

///|
fn string_to_extern(s : String) -> XExternString {
  let handle = begin_create_string()
  let mut i = 0
  while i < s.length() {
    string_append_char(handle, s.code_unit_at(i).to_int())
    i = i + 1
  }
  finish_create_string(handle)
}

///|
fn string_from_extern(e : XExternString) -> String {
  let buf = StringBuilder::new()
  let handle = begin_read_string(e)
  while true {
    let ch = string_read_char(handle)
    if ch == -1 {
      break
    } else {
      buf.write_char(Int::unsafe_to_char(ch))
    }
  }
  finish_read_string(handle)
  buf.to_string()
}

///|
fn byte_array_to_extern(s : Bytes) -> XExternByteArray {
  let handle = begin_create_byte_array()
  let mut i = 0
  while i < s.length() {
    byte_array_append_byte(handle, s[i].to_int())
    i = i + 1
  }
  finish_create_byte_array(handle)
}

///|
fn byte_array_from_extern(e : XExternByteArray) -> Bytes {
  let buf : Array[Byte] = []
  let handle = begin_read_byte_array(e)
  while true {
    let ch = byte_array_read_byte(handle)
    if ch == -1 {
      break
    } else {
      buf.push(ch.to_byte())
    }
  }
  finish_read_byte_array(handle)
  Bytes::from_array(buf)
}

///|
fn read_file_to_bytes_ffi(path : XExternString) -> Int = "__moonbit_fs_unstable" "read_file_to_bytes_new"

///|
fn write_bytes_to_file_ffi(path : XExternString, content : XExternByteArray) -> Int = "__moonbit_fs_unstable" "write_bytes_to_file_new"

///|
fn create_dir_ffi(path : XExternString) -> Int = "__moonbit_fs_unstable" "create_dir_new"

///|
fn get_error_message_ffi() -> XExternString = "__moonbit_fs_unstable" "get_error_message"

///|
fn get_file_content_ffi() -> XExternByteArray = "__moonbit_fs_unstable" "get_file_content"

///|
fn get_error_message() -> String {
  string_from_extern(get_error_message_ffi())
}

///|
fn read_file_to_bytes_internal(path : String) -> Bytes raise IOError {
  let res = read_file_to_bytes_ffi(string_to_extern(path))
  guard res != -1 else { raise IOError(get_error_message()) }
  byte_array_from_extern(get_file_content_ffi())
}

///|
fn write_bytes_to_file_internal(path : String, content : Bytes) -> Unit raise IOError {
  let res = write_bytes_to_file_ffi(string_to_extern(path), byte_array_to_extern(content))
  guard res != -1 else { raise IOError(get_error_message()) }
}

///|
fn create_dir_internal(path : String) -> Unit raise IOError {
  let res = create_dir_ffi(string_to_extern(path))
  guard res != -1 else { raise IOError(get_error_message()) }
}
