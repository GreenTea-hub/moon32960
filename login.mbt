// login.mbt
// 依据：GB/T 32960.3-2025 表 6（车辆登入）、表 28（车辆登出）、表 29（平台登入）、表 30（平台登出）

///|
/// 电池管理系统（BMS）及其管理的动力蓄电池包编码。
///
/// 2025 版表 6 用「电池管理系统数 + 每系统包个数 + 24 位包编码」描述储能配置，
/// 取代了 2016 版的「可充电储能子系统数 + 编码长度 + 变长编码」。
pub(all) struct BatteryManagementSystem {
  /// 该 BMS 管理的动力蓄电池包个数，有效范围 0~50。
  pack_count : Int32
  /// 各包 24 字符编码，按 GB/T 34014。长度应等于 pack_count。
  pack_codes : Array[String]
}

///|
/// 动力蓄电池包编码长度，按 GB/T 34014 固定 24 字符。
pub const PACK_CODE_LEN : Int32 = 24

///|
/// 电池管理系统数上限（表 6：有效值范围 0~20）。
pub const MAX_BMS_COUNT : Int32 = 20

///|
/// 单个 BMS 管理的包数上限（表 6：有效范围 0~50）。
pub const MAX_PACK_PER_BMS : Int32 = 50

///|
/// 车辆登入数据单元（表 6）。
///
/// 布局：数据采集时间(6) 登入流水号(2) ICCID(20) 电池管理系统数 n(1)
/// BMS 包个数 BYTE[n] 包编码 Σn(m)×24
pub(all) struct VehicleLogin {
  time : Time
  sequence : Int32
  iccid : String
  systems : Array[BatteryManagementSystem]
}

///|
/// 登入数据单元固定前段长度：时间 6 + 流水号 2 + ICCID 20 + BMS 数 1。
pub const LOGIN_FIXED_LEN : Int32 = 29

///|
pub fn VehicleLogin::new(
  time~ : Time,
  sequence~ : Int32,
  iccid~ : String,
  systems~ : Array[BatteryManagementSystem],
) -> VehicleLogin raise FrameError {
  // 表 6：流水号 1~65531，逐次加一，跨天归零
  if sequence < 1 || sequence > 65531 {
    raise FieldOutOfRange(field="登入流水号", value=sequence, low=1, high=65531)
  }
  check_count(systems.length(), 0, MAX_BMS_COUNT, field="电池管理系统数")
  for system in systems {
    check_count(system.pack_count, 0, MAX_PACK_PER_BMS, field="BMS 对应动力蓄电池包个数")
    if system.pack_codes.length() != system.pack_count {
      raise Payload(
        message="包个数 \{system.pack_count} 与编码条数 \{system.pack_codes.length()} 不一致",
      )
    }
    for code in system.pack_codes {
      if code.length() != PACK_CODE_LEN {
        raise Payload(message="动力蓄电池包编码应为 \{PACK_CODE_LEN} 字符，实际 \{code.length()}")
      }
    }
  }
  { time, sequence, iccid, systems }
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
  out.push(self.systems.length().to_byte())
  for system in self.systems {
    out.push(system.pack_count.to_byte())
  }
  for system in self.systems {
    for code in system.pack_codes {
      for byte in @utf8.encode(code) {
        out.push(byte)
      }
    }
  }
  Bytes::from_array(out)
}

///|
pub fn VehicleLogin::decode(bytes : BytesView) -> VehicleLogin raise FrameError {
  ensure_at(bytes, 0, LOGIN_FIXED_LEN, what="车辆登入")
  let time = Time::from_bytes(bytes[0:6])
  let sequence = u16_be(bytes, 6)
  if sequence < 1 || sequence > 65531 {
    raise FieldOutOfRange(field="登入流水号", value=sequence, low=1, high=65531)
  }
  let iccid = decode_iccid(bytes[8:28])
  let bms_count = bytes[28].to_int()
  check_count(bms_count, 0, MAX_BMS_COUNT, field="电池管理系统数")
  // 读取各 BMS 的包个数
  ensure_at(bytes, LOGIN_FIXED_LEN, bms_count, what="BMS 对应动力蓄电池包个数")
  let pack_counts : Array[Int32] = []
  let mut total_packs = 0
  for i in 0..<bms_count {
    let count = bytes[LOGIN_FIXED_LEN + i].to_int()
    check_count(count, 0, MAX_PACK_PER_BMS, field="BMS 对应动力蓄电池包个数")
    pack_counts.push(count)
    total_packs = total_packs + count
  }
  // 读取包编码：每包 24 字符
  let codes_at = LOGIN_FIXED_LEN + bms_count
  let need = codes_at + total_packs * PACK_CODE_LEN
  if bytes.length() < need {
    raise Payload(
      message="包编码区需要 \{need} 字节，实际 \{bytes.length()}",
    )
  }
  if bytes.length() > need {
    raise BadLength(expected=need, actual=bytes.length())
  }
  let systems : Array[BatteryManagementSystem] = []
  let mut cursor = codes_at
  for i in 0..<bms_count {
    let count = pack_counts[i]
    let codes : Array[String] = []
    for _ in 0..<count {
      let raw = bytes[cursor:cursor + PACK_CODE_LEN]
      codes.push(@utf8.decode(raw) catch {
        _ => raise Payload(message="动力蓄电池包编码不是合法 UTF-8")
      })
      cursor = cursor + PACK_CODE_LEN
    }
    systems.push({ pack_count: count, pack_codes: codes })
  }
  { time, sequence, iccid, systems }
}

///|
/// 登入数据单元的总字节数（用于校核声明长度）。
pub fn VehicleLogin::byte_len(self : VehicleLogin) -> Int32 {
  let mut packs = 0
  for system in self.systems {
    packs = packs + system.pack_codes.length()
  }
  LOGIN_FIXED_LEN + self.systems.length() + packs * PACK_CODE_LEN
}

///|
/// 车辆登出数据单元（表 28）：登出时间(6) 登出流水号(2)，流水号与当次登入一致。
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
  { time: Time::from_bytes(bytes[0:6]), sequence: u16_be(bytes, 6) }
}

///|
/// 平台登入数据单元（表 29）：时间(6) 流水号(2) 用户名(12) 密码(20) 加密规则(1)。
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
/// 平台登出数据单元（表 30）：登出时间(6) 流水号(2)，与表 28 同形。
///|
/// 平台登出数据单元（表 30）与车辆登出（表 28）同形，直接复用 `VehicleLogout::decode`。
