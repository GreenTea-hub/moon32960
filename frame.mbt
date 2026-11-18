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
/// 数据包结构的纯字节视图，保留原始负载与校验码，便于网关在解析前先做完整性判断。
///
/// 结构：起始符(2) | 命令单元(1) | 应答标志(1) | VIN(17) | 加密方式(1) | 数据单元长度(2) | 数据单元(N) | 校验码(1)
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
pub fn encode_frame(frame : Frame) -> Bytes raise FrameError {
  let vin = encode_vin(frame.vin)
  if frame.payload.length() > 65531 {
    raise BadLength(expected=65531, actual=frame.payload.length())
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
  let body = Bytes::from_array(out)
  // 校验码覆盖命令单元首字节到数据单元末字节，即剔除前两个起始符。
  let checksum = bcc(body[2:])
  let result : Array[Byte] = []
  for byte in body {
    result.push(byte)
  }
  result.push(checksum)
  Bytes::from_array(result)
}

///|
pub fn decode_frame(data : Bytes) -> Frame raise FrameError {
  if data.length() < MIN_FRAME_LEN {
    raise TooShort(needed=MIN_FRAME_LEN, actual=data.length())
  }
  if data[0] != START_BYTE || data[1] != START_BYTE {
    raise InvalidStart(bytes=to_hex(data[0:2]))
  }
  let command = Command::from_byte(data[2])
  let response = ResponseFlag::from_byte(data[3])
  let vin = decode_vin(data[4:21])
  let encryption = Encryption::from_byte(data[21])
  let declared = u16_be(data, 22)
  let actual = data.length() - HEADER_LEN - 1
  if declared != actual {
    raise BadLength(expected=declared, actual=actual)
  }
  let checksum_at = data.length() - 1
  let expected = data[checksum_at].to_int()
  let actual_checksum = bcc(data[2:checksum_at]).to_int()
  if expected != actual_checksum {
    raise BadChecksum(expected~, actual=actual_checksum)
  }
  Frame::new(
    command~,
    response~,
    vin~,
    encryption~,
    payload=data[HEADER_LEN:checksum_at].to_owned(),
  )
}

///|
/// 帧的十六进制摘要，用于日志去重与案卷比对。
pub fn Frame::hex(self : Frame) -> String raise FrameError {
  to_hex(encode_frame(self))
}
