// codec.mbt
///|
/// Shared byte helpers used by the frame and payload codecs.
///
/// Reads go through `BytesView` so callers can slice without copying, and
/// every helper returns an explicit result instead of panicking on short input.
pub fn u16_be(bytes : BytesView, offset : Int32) -> Int32 {
  bytes[offset].to_int() * 256 + bytes[offset + 1].to_int()
}

///|
pub fn push_u16_be(out : Array[Byte], value : Int32) -> Unit {
  out.push((value / 256).to_byte())
  out.push((value % 256).to_byte())
}

///|
/// VIN carried by GB/T 32960 is exactly 17 ASCII bytes.
pub const VIN_LEN : Int32 = 17

///|
/// Validate that a string is a 17-character VIN.
///
/// The check is deliberately strict: length, ASCII-only and the characters the
/// VIN alphabet excludes (`I`, `O`, `Q`) are all rejected, because a platform
/// that stores a malformed VIN cannot route reports to the right vehicle.
pub fn validate_vin(vin : String) -> Unit raise FrameError {
  if vin.length() != VIN_LEN {
    raise BadVin(vin~)
  }
  for ch in vin {
    let code = ch.to_int()
    let digit = code >= 48 && code <= 57
    let upper = code >= 65 && code <= 90
    let excluded = ch == 'I' || ch == 'O' || ch == 'Q'
    if !(digit || (upper && !excluded)) {
      raise BadVin(vin~)
    }
  }
}

///|
pub fn encode_vin(vin : String) -> Bytes raise FrameError {
  validate_vin(vin)
  let raw = @utf8.encode(vin)
  if raw.length() != VIN_LEN {
    raise BadVin(vin~)
  }
  raw
}

///|
pub fn decode_vin(bytes : BytesView) -> String raise FrameError {
  let vin = @utf8.decode(bytes) catch {
    _ => raise BadVin(vin="<not valid utf8>")
  }
  validate_vin(vin)
  vin
}

///|
/// Calendar time carried by 32960 payloads: six bytes, one per field.
///
/// Year is stored as an offset from 2000 (``0`` meaning 2000) so that a
/// single byte covers 2000..2099. Field order and encoding must be re-checked
/// against the standard text before claiming conformance (see
/// `docs/PROTOCOL.md`).
pub(all) struct Time {
  year : Int32
  month : Int32
  day : Int32
  hour : Int32
  minute : Int32
  second : Int32
}

///|
fn in_range(value : Int32, low : Int32, high : Int32) -> Bool {
  value >= low && value <= high
}

///|
pub fn Time::new(
  year~ : Int32,
  month~ : Int32,
  day~ : Int32,
  hour~ : Int32,
  minute~ : Int32,
  second~ : Int32,
) -> Time raise FrameError {
  if !in_range(year, 2000, 2099) ||
    !in_range(month, 1, 12) ||
    !in_range(day, 1, 31) ||
    !in_range(hour, 0, 23) ||
    !in_range(minute, 0, 59) ||
    !in_range(second, 0, 59) {
    raise BadTime(
      bytes=render(year, month, day, hour, minute, second),
    )
  }
  { year, month, day, hour, minute, second }
}

///|
fn render(
  year : Int32,
  month : Int32,
  day : Int32,
  hour : Int32,
  minute : Int32,
  second : Int32,
) -> String {
  "\{year}-\{month}-\{day} \{hour}:\{minute}:\{second}"
}

///|
pub fn Time::to_bytes(self : Time) -> Bytes {
  let out : Array[Byte] = []
  out.push((self.year - 2000).to_byte())
  out.push(self.month.to_byte())
  out.push(self.day.to_byte())
  out.push(self.hour.to_byte())
  out.push(self.minute.to_byte())
  out.push(self.second.to_byte())
  Bytes::from_array(out)
}

///|
pub fn Time::from_bytes(bytes : BytesView) -> Time raise FrameError {
  if bytes.length() < 6 {
    raise TooShort(needed=6, actual=bytes.length())
  }
  Time::new(
    year=2000 + bytes[0].to_int(),
    month=bytes[1].to_int(),
    day=bytes[2].to_int(),
    hour=bytes[3].to_int(),
    minute=bytes[4].to_int(),
    second=bytes[5].to_int(),
  )
}

///|
/// Interval between two timestamps in whole seconds, assuming the same month.
/// Sufficient for heartbeat freshness and re-send windows; a full calendar
/// difference is a later milestone.
pub fn Time::seconds_since(self : Time, earlier : Time) -> Int32 {
  let a = self.hour * 3600 + self.minute * 60 + self.second
  let b = earlier.hour * 3600 + earlier.minute * 60 + earlier.second
  let days = self.day - earlier.day
  days * 86400 + a - b
}

///|
pub fn to_hex(bytes : BytesView) -> String {
  let sb = StringBuilder()
  for byte in bytes {
    sb.write_string(byte.to_hex())
  }
  sb.to_string()
}

///|
pub fn from_hex(text : String) -> Bytes raise FrameError {
  let digits : Array[Int32] = []
  for ch in text {
    if ch != ' ' && ch != '\n' && ch != '\t' && ch != '\r' {
      digits.push(hex_digit(ch))
    }
  }
  if digits.length() % 2 != 0 {
    raise Payload(message="hex input must have an even length")
  }
  let out : Array[Byte] = []
  let mut i = 0
  while i < digits.length() {
    out.push((digits[i] * 16 + digits[i + 1]).to_byte())
    i = i + 2
  }
  Bytes::from_array(out)
}

///|
fn hex_digit(ch : Char) -> Int32 raise FrameError {
  let code = ch.to_int()
  if code >= 48 && code <= 57 {
    code - 48
  } else if code >= 97 && code <= 102 {
    code - 87
  } else if code >= 65 && code <= 70 {
    code - 55
  } else {
    raise Payload(message="invalid hex digit: \{ch}")
  }
}