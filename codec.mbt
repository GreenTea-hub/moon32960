// codec.mbt
///|
/// 大端（网络字节序）读取：GB/T 32960.3 的字（WORD）与双字（DWORD）均以大端传递。
pub fn u16_be(bytes : BytesView, offset : Int32) -> Int32 {
  bytes[offset].to_int() * 256 + bytes[offset + 1].to_int()
}

///|
pub fn u32_be(bytes : BytesView, offset : Int32) -> Int32 {
  bytes[offset].to_int() * 16777216 +
  bytes[offset + 1].to_int() * 65536 +
  bytes[offset + 2].to_int() * 256 +
  bytes[offset + 3].to_int()
}

///|
pub fn push_u16_be(out : Array[Byte], value : Int32) -> Unit {
  out.push((value / 256).to_byte())
  out.push((value % 256).to_byte())
}

///|
pub fn push_u32_be(out : Array[Byte], value : Int32) -> Unit {
  out.push((value / 16777216).to_byte())
  out.push(((value / 65536) % 256).to_byte())
  out.push(((value / 256) % 256).to_byte())
  out.push((value % 256).to_byte())
}

///|
/// 车辆识别码 VIN，17 位 ASCII。GB/T 32960.3 中长度固定。
pub const VIN_LEN : Int32 = 17

///|
/// SIM 卡 ICCID，20 位 ASCII，登入数据单元必备字段。
pub const ICCID_LEN : Int32 = 20

///|
/// 严格 VIN 校验（GB 16735）：17 位、ASCII、不含 I/O/Q。
///
/// 表 2 规定「传输车辆数据时用 VIN，传输其他数据时用唯一自定义编码」，
/// 因此帧层只用 `validate_identifier` 做宽松校验，车辆数据在业务层再调本函数。
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
/// 唯一识别码的帧层校验：固定 17 字节、可打印 ASCII（GB/T 1988 范围）。
///
/// 传输车辆数据时应为 VIN；传输其他数据时允许厂商唯一自定义编码，
/// 因此这里不强制 VIN 字母表。
pub fn validate_identifier(text : String) -> Unit raise FrameError {
  if text.length() != VIN_LEN {
    raise BadVin(vin=text)
  }
  for ch in text {
    let code = ch.to_int()
    if code < 0x20 || code > 0x7e {
      raise BadVin(vin=text)
    }
  }
}

///|
pub fn encode_vin(vin : String) -> Bytes raise FrameError {
  validate_identifier(vin)
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
  validate_identifier(vin)
  vin
}

///|
/// 校验 ICCID：20 位且全为数字。终端应从 SIM 卡读取，不是人工填写。
pub fn validate_iccid(iccid : String) -> Unit raise FrameError {
  if iccid.length() != ICCID_LEN {
    raise BadIccid(iccid~)
  }
  for ch in iccid {
    let code = ch.to_int()
    if code < 48 || code > 57 {
      raise BadIccid(iccid~)
    }
  }
}

///|
pub fn encode_iccid(iccid : String) -> Bytes raise FrameError {
  validate_iccid(iccid)
  @utf8.encode(iccid)
}

///|
pub fn decode_iccid(bytes : BytesView) -> String raise FrameError {
  let text = @utf8.decode(bytes) catch {
    _ => raise BadIccid(iccid="<not valid utf8>")
  }
  validate_iccid(text)
  text
}

///|
/// 时间：6 字节，依次为年、月、日、时、分、秒，均按北京时间。
///
/// 年字段有效值 0~99，表示 2000~2099 年；本结构保存四位年份，编码时减 2000。
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
      bytes="\{year}-\{month}-\{day} \{hour}:\{minute}:\{second}",
    )
  }
  { year, month, day, hour, minute, second }
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
/// 显示为 `YYYY-MM-DD HH:MM:SS`，便于 CLI 与日志。
pub fn Time::to_display(self : Time) -> String {
  let pad = fn(value : Int32) -> String {
    if value < 10 {
      "0\{value}"
    } else {
      "\{value}"
    }
  }
  let ymd = "\{self.year}-\{pad(self.month)}-\{pad(self.day)}"
  let hms = "\{pad(self.hour)}:\{pad(self.minute)}:\{pad(self.second)}"
  "\{ymd} \{hms}"
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

///|
/// BCC 异或校验：校验范围为命令单元首字节至校验码前一字节。
pub fn bcc(bytes : BytesView) -> Byte {
  let mut acc = 0
  for byte in bytes {
    acc = acc ^ byte.to_int()
  }
  acc.to_byte()
}
