// frame.mbt
///|
/// 固定报头长度：起始符 2 + 命令单元 1 + 应答标志 1 + VIN 17 + 加密方式 1 + 数据单元长度 2。
pub const HEADER_LEN : Int32 = 24

///|
/// 一帧的最小长度：报头 + 校验码，数据单元为空。
pub const MIN_FRAME_LEN : Int32 = HEADER_LEN + 1

///|
/// 起始符，固定为 ASCII `##`。
pub const START_BYTE : Byte = b'\x23'

///|
/// 只解析报头、不碰数据单元的帧头视图。
///
/// 解密失败或数据单元畸形时，平台仍需要 VIN 与命令来生成应答，因此先取报头。
pub(all) struct FrameHeader {
  command : Command
  response : ResponseFlag
  vin : String
  encryption : Encryption
  payload_len : Int32
}

///|
/// 数据包结构：起始符(2) | 命令单元(1) | 应答标志(1) | VIN(17) | 加密方式(1) | 数据单元长度(2) | 数据单元(N) | 校验码(1)
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
/// 报头读取：只做结构与长度检查，不解密、不解析数据单元。
pub fn peek_header(data : Bytes) -> FrameHeader raise FrameError {
  if data.length() < MIN_FRAME_LEN {
    raise TooShort(needed=MIN_FRAME_LEN, actual=data.length())
  }
  if data[0] != START_BYTE || data[1] != START_BYTE {
    raise InvalidStart(bytes=to_hex(data[0:2]))
  }
  let declared = u16_be(data, 22)
  let actual = data.length() - HEADER_LEN - 1
  if declared != actual {
    raise BadLength(expected=declared, actual=actual)
  }
  {
    command: Command::from_byte(data[2]),
    response: ResponseFlag::from_byte(data[3]),
    vin: decode_vin(data[4:21]),
    encryption: Encryption::from_byte(data[21]),
    payload_len: declared,
  }
}

///|
/// 组帧：先按加密方式加密数据单元，再算 BCC，因此校验码覆盖密文。
pub fn encode_frame(
  frame : Frame,
  key~ : KeyMaterial = NoKey,
) -> Bytes raise FrameError {
  let vin = encode_vin(frame.vin)
  if frame.payload.length() > 65531 {
    raise BadLength(expected=65531, actual=frame.payload.length())
  }
  let payload = encrypt_payload(frame.encryption, frame.payload, key~)
  let out : Array[Byte] = []
  out.push(START_BYTE)
  out.push(START_BYTE)
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
/// 解帧：先验校验码（密文），再按加密方式解密，最后才交给业务层解析。
pub fn decode_frame(
  data : Bytes,
  key~ : KeyMaterial = NoKey,
) -> Frame raise FrameError {
  let header = peek_header(data)
  let checksum_at = data.length() - 1
  let expected = data[checksum_at].to_int()
  let actual_checksum = bcc(data[2:checksum_at]).to_int()
  if expected != actual_checksum {
    raise BadChecksum(expected~, actual=actual_checksum)
  }
  let cipher_text = data[HEADER_LEN:checksum_at].to_owned()
  let payload = decrypt_payload(header.encryption, cipher_text, key~)
  Frame::new(
    command=header.command,
    response=header.response,
    vin=header.vin,
    encryption=header.encryption,
    payload~,
  )
}

///|
/// 帧的十六进制摘要，用于日志去重与案卷比对。
pub fn Frame::hex(self : Frame, key~ : KeyMaterial = NoKey) -> String raise FrameError {
  to_hex(encode_frame(self, key~))
}
