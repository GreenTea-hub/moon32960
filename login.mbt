// login.mbt
///|

///|
/// Payload of a vehicle login message.
///
/// Layout used by this package (see `docs/PROTOCOL.md`): login time (6 bytes),
/// login sequence (2 bytes, big endian). Re-check field widths against the
/// standard text before claiming wire-level conformance.
pub(all) struct LoginData {
  time : Time
  sequence : Int32
}

///|
pub fn LoginData::new(time~ : Time, sequence~ : Int32) -> LoginData raise FrameError {
  if sequence < 0 || sequence > 0xFFFF {
    raise Payload(message="login sequence out of range: \{sequence}")
  }
  { time, sequence }
}

///|
pub fn LoginData::to_bytes(self : LoginData) -> Bytes {
  let out : Array[Byte] = []
  for byte in self.time.to_bytes() {
    out.push(byte)
  }
  push_u16_be(out, self.sequence)
  Bytes::from_array(out)
}

///|
pub fn LoginData::parse(bytes : BytesView) -> LoginData raise FrameError {
  if bytes.length() != 8 {
    raise Payload(message="login payload must be 8 bytes, got \{bytes.length()}")
  }
  LoginData::new(
    time=Time::from_bytes(bytes[0:6]),
    sequence=u16_be(bytes, 6),
  )
}

///|
/// Payload of a vehicle logout message.
pub(all) struct LogoutData {
  time : Time
  sequence : Int32
}

///|
pub fn LogoutData::to_bytes(self : LogoutData) -> Bytes {
  let out : Array[Byte] = []
  for byte in self.time.to_bytes() {
    out.push(byte)
  }
  push_u16_be(out, self.sequence)
  Bytes::from_array(out)
}

///|
pub fn LogoutData::parse(bytes : BytesView) -> LogoutData raise FrameError {
  if bytes.length() != 8 {
    raise Payload(message="logout payload must be 8 bytes, got \{bytes.length()}")
  }
  {
    time: Time::from_bytes(bytes[0:6]),
    sequence: u16_be(bytes, 6),
  }
}
