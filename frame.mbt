// frame.mbt
///|
/// Size of the fixed frame header, in bytes.
///
/// start(2) + command(1) + response(1) + vin(17) + encryption(1) + length(2)
pub const HEADER_LEN : Int32 = 24

///|
/// Start marker of every frame: two 0x23 bytes, conventionally `##`.
pub const START_BYTE : Byte = b'\x23'

///|
/// A decoded GB/T 32960 frame: fixed header plus an opaque payload.
///
/// Payload interpretation is per command and lives in `payload.mbt`; keeping
/// the frame itself payload-agnostic lets the gateway route before it decodes.
pub(all) struct Frame {
  command : Command
  response : ResponseFlag
  vin : String
  encryption : Encryption
  payload : Bytes
}

///|
pub fn Frame::new(
  command~ : Command,
  response~ : ResponseFlag,
  vin~ : String,
  encryption~ : Encryption,
  payload~ : Bytes,
) -> Frame {
  { command, response, vin, encryption, payload }
}

///|
/// Encode a frame header and payload into the on-wire byte layout.
pub fn encode_frame(frame : Frame) -> Bytes raise FrameError {
  let vin = encode_vin(frame.vin)
  if frame.payload.length() > 0xFFFF {
    raise BadLength(expected=0xFFFF, actual=frame.payload.length())
  }
  let out : Array[Byte] = []
  out.push(START_BYTE)
  out.push(START_BYTE)
  out.push(frame.command.to_byte())
  out.push(frame.response.to_byte())
  for byte in vin {
    out.push(byte)
  }
  out.push(frame.encryption.to_byte())
  push_u16_be(out, frame.payload.length())
  for byte in frame.payload {
    out.push(byte)
  }
  Bytes::from_array(out)
}

///|
/// Decode a frame from raw bytes.
///
/// All bounds are checked before indexing, so malformed input raises a typed
/// `FrameError` instead of panicking.
pub fn decode_frame(data : Bytes) -> Frame raise FrameError {
  if data.length() < HEADER_LEN {
    raise TooShort(needed=HEADER_LEN, actual=data.length())
  }
  if data[0] != START_BYTE || data[1] != START_BYTE {
    raise InvalidStart(bytes=to_hex(data[0:2]))
  }
  let command = Command::from_byte(data[2])
  let response = ResponseFlag::from_byte(data[3])
  let vin = decode_vin(data[4:21])
  let encryption = Encryption::from_byte(data[21])
  let declared = u16_be(data, 22)
  let actual = data.length() - HEADER_LEN
  if declared != actual {
    raise BadLength(expected=declared, actual=actual)
  }
  Frame::new(
    command~,
    response~,
    vin~,
    encryption~,
    payload=data[24:].to_owned(),
  )
}