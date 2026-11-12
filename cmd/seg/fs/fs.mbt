///|
pub(all) suberror IOError {
  IOError(String)
}

///|
pub fn read_file_to_bytes(path : String) -> Bytes raise IOError {
  read_file_to_bytes_internal(path)
}

///|
pub fn write_bytes_to_file(path : String, content : Bytes) -> Unit raise IOError {
  write_bytes_to_file_internal(path, content)
}

///|
pub fn create_dir(path : String) -> Unit raise IOError {
  create_dir_internal(path)
}
