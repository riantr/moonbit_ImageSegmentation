///|
/// Adler-32 checksum implementation for zlib.
///
/// The actual byte loop lives in target-conditional companion files:
///   * `adler32_scalar.mbt` 鈥?non-wasm targets (js, wasm-gc, native, llvm)
///   * `adler32_simd.mbt`   鈥?wasm target only; inline-WAT v128 SIMD,
///     ~7.7脳 faster than scalar on 256 KB inputs (bench: 22 碌s vs 166 碌s)
///
/// The SIMD path was adapted from an inline-WAT SIMD implementation.
/// wasm-gc / js fall through to scalar because their inline-WAT FFI
/// rejects `Bytes` and `FixedArray[Byte]` (GC ref vs i32 mismatch).
let adler_mod : UInt = Int::reinterpret_as_uint(65521)

///|
let adler_nmax : Int = 5552

///|
/// Compute Adler-32 checksum.
pub fn adler32(data : Bytes) -> Int {
  adler32_impl(data)
}

///|
/// Compute Adler-32 checksum from FixedArray.
pub fn adler32_fixed(data : FixedArray[Byte]) -> Int {
  adler32_fixed_impl(data)
}

