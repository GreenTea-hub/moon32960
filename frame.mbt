// frame.mbt
// 依据：GB/T 32960.3-2025 表 2（数据包结构）、6.3.2（应答）

///|
/// 固定报头长度：起始符 2 + 命令单元 2 + 唯一识别码 17 + 加密方式 1 + 数据单元长度 2。
pub const HEADER_LEN : Int32 = 24

///|
/// 最小帧长：报头 + 校验码。
pub const MIN_FRAME_LEN : Int32 = HEADER_LEN + 1

///|
/// 协议版本由起始符区分：`##`(0x23) 表示 2016 年版协议，`$$`(0x24) 表示 2025 版。
pub(all) enum FrameVersion {
  V2016
  V2025
}

///|
pub fn FrameVersion::name(self : FrameVersion) -> String {
  match self {
    V2016 => "GB/T 32960.3-2016"
    V2025 => "GB/T 32960.3-2025"
  }
}

///|
pub fn FrameVersion::start_bytes(self : FrameVersion) -> (Byte, Byte) {
  match self {
    V2016 => (b'\x23', b'\x23')
    V2025 => (b'\x24', b'\x24')
  }
}

///|
/// 报头视图，解密失败或数据单元畸形时仍可用于生成应答。
pub(all) struct FrameHeader {
  version : FrameVersion
  command : Command
  response : ResponseFlag
  vin : String
  encryption : Encryption
  payload_len : Int32
}

///|
/// 完整帧。`version` 由起始符解析得出，编码时可显式覆盖。
pub(all) struct Frame {
  version : FrameVersion
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
  version~ : FrameVersion = V2025,
) -> Frame {
  { version, command, response, vin, encryption, payload, }
}

///|
pub fn peek_header(data : Bytes) -> FrameHeader raise FrameError {
  if data.length() < MIN_FRAME_LEN {
    raise TooShort(needed=MIN_FRAME_LEN, actual=data.length())
  }
  let version = match (data[0].to_int(), data[1].to_int()) {
    (0x23, 0x23) => V2016
    (0x24, 0x24) => V2025
    _ => raise InvalidStart(bytes=to_hex(data[0:2]))
  }
  let declared = u16_be(data, 22)
  let actual = data.length() - HEADER_LEN - 1
  if declared != actual {
    raise BadLength(expected=declared, actual~)
  }
  {
    version,
    command: Command::from_byte(data[2]),
    response: ResponseFlag::from_byte(data[3]),
    vin: decode_vin(data[4:21]),
    encryption: Encryption::from_byte(data[21]),
    payload_len: declared,
  }
}

///|
/// 组帧：先加密再算 BCC，校验覆盖密文。
pub fn encode_frame(
  frame : Frame,
  key~ : KeyMaterial = NoKey,
) -> Bytes raise FrameError {
  let vin = encode_vin(frame.vin)
  if frame.payload.length() > 65531 {
    raise BadLength(expected=65531, actual=frame.payload.length())
  }
  let payload = encrypt_payload(frame.encryption, frame.payload, key~)
  let (start0, start1) = frame.version.start_bytes()
  let out : Array[Byte] = []
  out.push(start0)
  out.push(start1)
  out.push(frame.command.to_byte())
  out.push(frame.response.to_byte())
  for byte in vin {
    out.push(byte)
  }
  out.push(frame.encryption.to_byte())
  push_u16_be(out, payload.length())
  for byte in payload {
    out.push(byte)
  }
  let body = Bytes::from_array(out)
  let checksum = bcc(body[2:])
  let result : Array[Byte] = []
  for byte in body {
    result.push(byte)
  }
  result.push(checksum)
  Bytes::from_array(result)
}

///|
/// 解帧：验 BCC（密文）→ 解密 → 交给业务层。`expect_version` 非空时校验起始符版本。
pub fn decode_frame(
  data : Bytes,
  key~ : KeyMaterial = NoKey,
  expect_version? : FrameVersion,
) -> Frame raise FrameError {
  let header = peek_header(data)
  match expect_version {
    Some(expected) =>
      match (expected, header.version) {
        (V2025, V2016) =>
          raise Payload(
            message="起始符为 ##，这是 2016 年版协议的帧",
          )
        (V2016, V2025) =>
          raise Payload(message="起始符为 $$，这是 2025 版协议的帧")
        _ => ()
      }
    None => ()
  }
  let checksum_at = data.length() - 1
  let expected = data[checksum_at].to_int()
  let actual_checksum = bcc(data[2:checksum_at]).to_int()
  if expected != actual_checksum {
    raise BadChecksum(expected~, actual=actual_checksum)
  }
  let cipher_text = data[HEADER_LEN:checksum_at].to_owned()
  let payload = decrypt_payload(header.encryption, cipher_text, key~)
  {
    version: header.version,
    command: header.command,
    response: header.response,
    vin: header.vin,
    encryption: header.encryption,
    payload,
  }
}

///|
pub fn Frame::hex(
  self : Frame,
  key~ : KeyMaterial = NoKey,
) -> String raise FrameError {
  to_hex(encode_frame(self, key~))
}
