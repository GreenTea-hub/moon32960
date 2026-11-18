// login.mbt
///|
/// 车辆登入数据单元（GB/T 32960.3-2016 表 6）。
///
/// 布局：登入时间(6) | 登入流水号(2) | ICCID(20) | 可充电储能子系统数 n(1) | 编码长度 m(1) | 编码(n×m)
/// 最小长度 30 字节；`storage_codes` 为 n 个等长（m 字节）的子系统编码。
pub(all) struct VehicleLogin {
  time : Time
  sequence : Int32
  iccid : String
  storage_codes : Array[String]
  code_len : Int32
}

///|
pub const VEHICLE_LOGIN_MIN_LEN : Int32 = 30

///|
/// 登入流水号取自 1~65531，逐次加一，跨天归零。
pub fn VehicleLogin::new(
  time~ : Time,
  sequence~ : Int32,
  iccid~ : String,
  storage_codes~ : Array[String],
  code_len~ : Int32,
) -> VehicleLogin raise FrameError {
  if sequence < 1 || sequence > 65531 {
    raise FieldOutOfRange(field="登录流水号", value=sequence, low=1, high=65531)
  }
  check_count(storage_codes.length(), 0, 250, field="可充电储能子系统数")
  check_count(code_len, 0, 50, field="可充电储能系统编码长度")
  if code_len == 0 && storage_codes.length() > 0 {
    raise Payload(message="编码长度为 0，但传入了子系统编码")
  }
  for code in storage_codes {
    if code.length() != code_len {
      raise Payload(
        message="子系统编码长度 \{code.length()} 与声明长度 \{code_len} 不符",
      )
    }
  }
  { time, sequence, iccid, storage_codes, code_len }
}

///|
pub fn VehicleLogin::to_bytes(self : VehicleLogin) -> Bytes raise FrameError {
  let out : Array[Byte] = []
  for byte in self.time.to_bytes() {
    out.push(byte)
  }
  push_u16_be(out, self.sequence)
  for byte in encode_iccid(self.iccid) {
    out.push(byte)
  }
  out.push(self.storage_codes.length().to_byte())
  out.push(self.code_len.to_byte())
  for code in self.storage_codes {
    for byte in @utf8.encode(code) {
      out.push(byte)
    }
  }
  Bytes::from_array(out)
}

///|
pub fn VehicleLogin::decode_at(
  bytes : BytesView,
  offset : Int32,
) -> (VehicleLogin, Int32) raise FrameError {
  ensure_at(bytes, offset, VEHICLE_LOGIN_MIN_LEN, what="车辆登入")
  let time = Time::from_bytes(bytes[offset:offset + 6])
  let sequence = u16_be(bytes, offset + 6)
  if sequence < 1 || sequence > 65531 {
    raise FieldOutOfRange(
      field="登录流水号",
      value=sequence,
      low=1,
      high=65531,
    )
  }
  let iccid = decode_iccid(bytes[offset + 8:offset + 28])
  let count = bytes[offset + 28].to_int()
  check_count(count, 0, 250, field="可充电储能子系统数")
  let code_len = bytes[offset + 29].to_int()
  check_count(code_len, 0, 50, field="可充电储能系统编码长度")
  let total = VEHICLE_LOGIN_MIN_LEN + count * code_len
  ensure_at(bytes, offset, total, what="车辆登入子系统编码")
  let codes : Array[String] = []
  for i in 0..<count {
    let start = offset + VEHICLE_LOGIN_MIN_LEN + i * code_len
    let raw = bytes[start:start + code_len]
    codes.push(@utf8.decode(raw) catch {
      _ => raise Payload(message="子系统编码不是合法 UTF-8")
    })
  }
  let login : VehicleLogin = {
    time,
    sequence,
    iccid,
    storage_codes: codes,
    code_len,
  }
  (login, total)
}

///|
pub fn VehicleLogin::decode(bytes : BytesView) -> VehicleLogin raise FrameError {
  let (login, consumed) = VehicleLogin::decode_at(bytes, 0)
  expect_len(bytes.length(), consumed, what="车辆登入")
  login
}

///|
/// 车辆登出数据单元（表 8）：登出时间(6) | 登出流水号(2)。
pub(all) struct VehicleLogout {
  time : Time
  sequence : Int32
}

///|
pub const VEHICLE_LOGOUT_LEN : Int32 = 8

///|
pub fn VehicleLogout::to_bytes(self : VehicleLogout) -> Bytes {
  let out : Array[Byte] = []
  for byte in self.time.to_bytes() {
    out.push(byte)
  }
  push_u16_be(out, self.sequence)
  Bytes::from_array(out)
}

///|
pub fn VehicleLogout::decode(bytes : BytesView) -> VehicleLogout raise FrameError {
  expect_len(bytes.length(), VEHICLE_LOGOUT_LEN, what="车辆登出")
  {
    time: Time::from_bytes(bytes[0:6]),
    sequence: u16_be(bytes, 6),
  }
}

///|
/// 平台登入数据单元：登入时间(6) | 登入流水号(2) | 平台用户名(12) | 平台密码(20) | 加密规则(1)。
pub(all) struct PlatformLogin {
  time : Time
  sequence : Int32
  username : String
  password : String
  encryption_rule : Int32
}

///|
pub const PLATFORM_LOGIN_LEN : Int32 = 41

///|
pub fn PlatformLogin::decode(bytes : BytesView) -> PlatformLogin raise FrameError {
  expect_len(bytes.length(), PLATFORM_LOGIN_LEN, what="平台登入")
  let username = @utf8.decode(bytes[8:20]) catch {
    _ => raise Payload(message="平台用户名不是合法 UTF-8")
  }
  let password = @utf8.decode(bytes[20:40]) catch {
    _ => raise Payload(message="平台密码不是合法 UTF-8")
  }
  {
    time: Time::from_bytes(bytes[0:6]),
    sequence: u16_be(bytes, 6),
    username,
    password,
    encryption_rule: bytes[40].to_int(),
  }
}

///|
pub fn PlatformLogin::to_bytes(self : PlatformLogin) -> Bytes raise FrameError {
  let username = @utf8.encode(self.username)
  let password = @utf8.encode(self.password)
  expect_len(username.length(), 12, what="平台用户名")
  expect_len(password.length(), 20, what="平台密码")
  let out : Array[Byte] = []
  for byte in self.time.to_bytes() {
    out.push(byte)
  }
  push_u16_be(out, self.sequence)
  for byte in username {
    out.push(byte)
  }
  for byte in password {
    out.push(byte)
  }
  out.push(self.encryption_rule.to_byte())
  Bytes::from_array(out)
}

///|
/// 心跳（0x07）数据单元为空；早期设备可能携带一段状态字，读到额外字节时保留为原始负载。
pub fn heartbeat_payload() -> Bytes {
  Bytes::new(0)
}
