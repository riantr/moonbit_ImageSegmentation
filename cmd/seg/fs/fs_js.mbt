///|
#module("node:fs")
extern "js" fn read_file_sync(path : String) -> Bytes = "readFileSync"

///|
#external
priv type FsUnitResult

///|
extern "js" fn FsUnitResult::is_ok(self : Self) -> Bool =
  #| (res) => res.ok

///|
extern "js" fn FsUnitResult::error_message(self : Self) -> String =
  #| (res) => res.content

///|
#external
priv type FsBytesResult

///|
extern "js" fn FsBytesResult::is_ok(self : Self) -> Bool =
  #| (res) => res.ok

///|
extern "js" fn FsBytesResult::content(self : Self) -> Bytes =
  #| (res) => res.content

///|
extern "js" fn FsBytesResult::error_message(self : Self) -> String =
  #| (res) => res.content

///|
extern "js" fn read_file_ffi(
  read_file : (String) -> Bytes,
  path : String,
) -> FsBytesResult =
  #| function(readFile, path) {
  #|   try {
  #|     const content = readFile(path);
  #|     return { ok: true, content };
  #|   } catch (error) {
  #|     return { ok: false, content: String(error && error.message ? error.message : error) };
  #|   }
  #| }

///|
fn read_file_to_bytes_internal(path : String) -> Bytes raise IOError {
  let res = read_file_ffi(read_file_sync, path)
  if !res.is_ok() {
    raise IOError(res.error_message())
  }
  res.content()
}

///|
#module("node:fs")
extern "js" fn write_file_sync(path : String, content : Bytes) -> Unit = "writeFileSync"

///|
extern "js" fn write_file_ffi(
  write_file : (String, Bytes) -> Unit,
  path : String,
  content : Bytes,
) -> FsUnitResult =
  #| function(writeFile, path, content) {
  #|   try {
  #|     writeFile(path, Buffer.from(content));
  #|     return { ok: true, content: "" };
  #|   } catch (error) {
  #|     return { ok: false, content: String(error && error.message ? error.message : error) };
  #|   }
  #| }

///|
fn write_bytes_to_file_internal(path : String, content : Bytes) -> Unit raise IOError {
  let res = write_file_ffi(write_file_sync, path, content)
  if !res.is_ok() {
    raise IOError(res.error_message())
  }
}

///|
#external
priv type FsOptions

///|
#module("node:fs")
extern "js" fn mkdir_sync(path : String, options : FsOptions) -> Unit = "mkdirSync"

///|
extern "js" fn mkdir_ffi(
  mkdir : (String, FsOptions) -> Unit,
  path : String,
) -> FsUnitResult =
  #| function(mkdir, path) {
  #|   try {
  #|     mkdir(path, { recursive: true });
  #|     return { ok: true, content: "" };
  #|   } catch (error) {
  #|     return { ok: false, content: String(error && error.message ? error.message : error) };
  #|   }
  #| }

///|
fn create_dir_internal(path : String) -> Unit raise IOError {
  let res = mkdir_ffi(mkdir_sync, path)
  if !res.is_ok() {
    raise IOError(res.error_message())
  }
}
