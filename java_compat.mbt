///|
/// Java compatible numeric conversions.
///
/// The Java sources cast doubles and floats to `int` in a number of places
/// (`(int)Math.round(x)`, `(int)Math.floor(x)`, `(int)mu1`, ...). Java's
/// narrowing conversion is well defined for every input:
///
/// - `NaN` becomes `0`
/// - values above `Integer.MAX_VALUE` saturate to `Integer.MAX_VALUE`
/// - values below `Integer.MIN_VALUE` saturate to `Integer.MIN_VALUE`
/// - everything else truncates towards zero
///
/// MoonBit's `to_int` traps on `NaN` and out-of-range values instead, so
/// the conversions are wrapped here.

///|
/// `Integer.MAX_VALUE`.
pub const JAVA_INT_MAX : Int = 2147483647

///|
/// `Integer.MIN_VALUE`.
pub const JAVA_INT_MIN : Int = -2147483648

///|
/// Java `(int) someDouble`.
pub fn java_double_to_int(x : Double) -> Int {
  if x.is_nan() {
    0
  } else if x >= 2147483647.0 {
    JAVA_INT_MAX
  } else if x <= -2147483648.0 {
    JAVA_INT_MIN
  } else {
    x.to_int()
  }
}

///|
/// Java `(int) someFloat`.
pub fn java_float_to_int(x : Float) -> Int {
  if x.is_nan() {
    0
  } else if x >= 2147483647.0F {
    JAVA_INT_MAX
  } else if x <= -2147483648.0F {
    JAVA_INT_MIN
  } else {
    x.to_int()
  }
}

///|
/// Java `Math.round(double)` = `floor(x + 0.5)`, truncated to an `int`.
pub fn java_round_double(x : Double) -> Int {
  java_double_to_int(@math.floor(x + 0.5))
}

///|
/// Java `Math.round(float)` = `floor(x + 0.5f)` in float precision.
pub fn java_round_float(x : Float) -> Int {
  java_float_to_int(Float::floor(x + 0.5F))
}
