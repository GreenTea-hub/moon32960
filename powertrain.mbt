// powertrain.mbt
///|
/// 单个驱动电机数据（表 15/表 16），固定 12 字节。
///
/// 布局：驱动电机序号(1) | 状态(1) | 控制器温度(1) | 转速(2) | 转矩(2)
/// | 电机温度(1) | 控制器输入电压(2) | 控制器直流母线电流(2)
pub(all) struct DriveMotor {
  sequence : Int32
  status : Int32
  controller_temp_raw : Int32
  speed_raw : Int32
  torque_raw : Int32
  motor_temp_raw : Int32
  input_voltage_raw : Int32
  bus_current_raw : Int32
}

///|
pub const DRIVE_MOTOR_LEN : Int32 = 12

///|
pub fn DriveMotor::decode(bytes : BytesView) -> DriveMotor raise FrameError {
  expect_len(bytes.length(), DRIVE_MOTOR_LEN, what="单个驱动电机")
  {
    sequence: bytes[0].to_int(),
    status: bytes[1].to_int(),
    controller_temp_raw: bytes[2].to_int(),
    speed_raw: u16_be(bytes, 3),
    torque_raw: u16_be(bytes, 5),
    motor_temp_raw: bytes[7].to_int(),
    input_voltage_raw: u16_be(bytes, 8),
    bus_current_raw: u16_be(bytes, 10),
  }
}

///|
pub fn DriveMotor::to_bytes(self : DriveMotor) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.sequence.to_byte())
  out.push(self.status.to_byte())
  out.push(self.controller_temp_raw.to_byte())
  push_u16_be(out, self.speed_raw)
  push_u16_be(out, self.torque_raw)
  out.push(self.motor_temp_raw.to_byte())
  push_u16_be(out, self.input_voltage_raw)
  push_u16_be(out, self.bus_current_raw)
  Bytes::from_array(out)
}

///|
/// 驱动电机转速，单位 r/min：原始值减 32000 偏移；异常或无效时返回 None。
pub fn DriveMotor::speed_rpm(self : DriveMotor) -> Int32? {
  match FieldState::word(self.speed_raw) {
    Valid => Some(self.speed_raw - 32000)
    _ => None
  }
}

///|
/// 驱动电机转矩，单位 N·m：原始值乘以 0.1 后减 2000；异常或无效时返回 None。
pub fn DriveMotor::torque_nm(self : DriveMotor) -> Double? {
  match FieldState::word(self.torque_raw) {
    Valid => Some(self.torque_raw.to_double() * 0.1 - 2000.0)
    _ => None
  }
}

///|
pub fn DriveMotor::status_name(self : DriveMotor) -> String {
  match self.status {
    0x01 => "耗电状态"
    0x02 => "发电状态"
    0x03 => "关闭状态"
    0x04 => "准备状态"
    0xfe => "异常"
    0xff => "无效"
    _ => "其他"
  }
}

///|
/// 驱动电机数据（信息类型标志 0x02）：电机个数(1) 后跟 n 个 12 字节电机记录。
///
/// 个数为 0xFE/0xFF 时表示异常或无效，本实现按零个电机解析并保留原始码值。
pub(all) struct DriveMotorData {
  count_raw : Int32
  motors : Array[DriveMotor]
}

///|
pub fn DriveMotorData::decode_at(
  bytes : BytesView,
  offset : Int32,
  end : Int32,
) -> (DriveMotorData, Int32) raise FrameError {
  ensure_at(bytes, offset, 1, what="驱动电机个数")
  let count_raw = bytes[offset].to_int()
  let count = match FieldState::byte(count_raw) {
    Valid => {
      check_count(count_raw, 0, 253, field="驱动电机个数")
      count_raw
    }
    _ => 0
  }
  let need = 1 + count * DRIVE_MOTOR_LEN
  if offset + need > end {
    raise Payload(
      message="驱动电机数据: 声明 \{count} 个电机需要 \{need} 字节，实际不足",
    )
  }
  let motors : Array[DriveMotor] = []
  for i in 0..<count {
    let start = offset + 1 + i * DRIVE_MOTOR_LEN
    motors.push(DriveMotor::decode(bytes[start:start + DRIVE_MOTOR_LEN]))
  }
  ({ count_raw, motors }, need)
}

///|
pub fn DriveMotorData::to_bytes(self : DriveMotorData) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.motors.length().to_byte())
  for motor in self.motors {
    for byte in motor.to_bytes() {
      out.push(byte)
    }
  }
  Bytes::from_array(out)
}

///|
/// 燃料电池数据（信息类型标志 0x03），2016 版表 17。
///
/// 布局：电压(2) | 电流(2) | 氢消耗率(2) | 温度探针总数(2) | 探针温度(n×1)
/// | 氢系统最高温度(2) | 该探针编号(1) | 氢系统最高浓度(2) | 该探针编号(1)
/// | 氢系统最高压力(2) | 该探针编号(1) | DC-DC 状态(1)
///
/// 固定部分 16 字节，探针温度按声明总数展开。
pub(all) struct FuelCell {
  voltage_raw : Int32
  current_raw : Int32
  hydrogen_consumption_raw : Int32
  probe_total : Int32
  probe_temps : Array[Int32]
  max_hydrogen_temp_raw : Int32
  max_hydrogen_temp_probe : Int32
  max_hydrogen_concentration_raw : Int32
  max_hydrogen_concentration_probe : Int32
  max_hydrogen_pressure_raw : Int32
  max_hydrogen_pressure_probe : Int32
  dc_dc_status : Int32
}

///|
/// 不含探针温度时的固定总长：头部 8 字节（电压、电流、消耗率、探针总数）+ 尾部 10 字节。
pub const FUEL_CELL_FIXED_LEN : Int32 = 18

///|
/// 头部长度：探针温度区之前的部分。
pub const FUEL_CELL_HEAD_LEN : Int32 = 8

///|
pub fn FuelCell::decode_at(
  bytes : BytesView,
  offset : Int32,
  end : Int32,
) -> (FuelCell, Int32) raise FrameError {
  ensure_at(bytes, offset, FUEL_CELL_FIXED_LEN, what="燃料电池数据")
  let probe_total_raw = u16_be(bytes, offset + 6)
  let n = match FieldState::word(probe_total_raw) {
    Valid => {
      check_count(probe_total_raw, 1, 65531, field="燃料电池温度探针总数")
      probe_total_raw
    }
    _ => 0
  }
  let total = FUEL_CELL_FIXED_LEN + n
  if offset + total > end {
    raise Payload(message="燃料电池数据: 温度探针数 \{n} 超出剩余字节")
  }
  let probes : Array[Int32] = []
  for i in 0..<n {
    probes.push(bytes[offset + FUEL_CELL_HEAD_LEN + i].to_int())
  }
  let tail = offset + FUEL_CELL_HEAD_LEN + n
  (
    {
      voltage_raw: u16_be(bytes, offset),
      current_raw: u16_be(bytes, offset + 2),
      hydrogen_consumption_raw: u16_be(bytes, offset + 4),
      probe_total: probe_total_raw,
      probe_temps: probes,
      max_hydrogen_temp_raw: u16_be(bytes, tail),
      max_hydrogen_temp_probe: bytes[tail + 2].to_int(),
      max_hydrogen_concentration_raw: u16_be(bytes, tail + 3),
      max_hydrogen_concentration_probe: bytes[tail + 5].to_int(),
      max_hydrogen_pressure_raw: u16_be(bytes, tail + 6),
      max_hydrogen_pressure_probe: bytes[tail + 8].to_int(),
      dc_dc_status: bytes[tail + 9].to_int(),
    },
    total,
  )
}

///|
pub fn FuelCell::to_bytes(self : FuelCell) -> Bytes {
  let out : Array[Byte] = []
  push_u16_be(out, self.voltage_raw)
  push_u16_be(out, self.current_raw)
  push_u16_be(out, self.hydrogen_consumption_raw)
  push_u16_be(out, self.probe_temps.length())
  for value in self.probe_temps {
    out.push(value.to_byte())
  }
  push_u16_be(out, self.max_hydrogen_temp_raw)
  out.push(self.max_hydrogen_temp_probe.to_byte())
  push_u16_be(out, self.max_hydrogen_concentration_raw)
  out.push(self.max_hydrogen_concentration_probe.to_byte())
  push_u16_be(out, self.max_hydrogen_pressure_raw)
  out.push(self.max_hydrogen_pressure_probe.to_byte())
  out.push(self.dc_dc_status.to_byte())
  Bytes::from_array(out)
}

///|
/// 发动机数据（信息类型标志 0x04），固定 5 字节。
///
/// 布局：发动机状态(1) | 曲轴转速(2) | 燃料消耗率(2)
pub(all) struct Engine {
  status : Int32
  crankshaft_speed_raw : Int32
  fuel_consumption_raw : Int32
}

///|
pub const ENGINE_LEN : Int32 = 5

///|
pub fn Engine::decode(bytes : BytesView) -> Engine raise FrameError {
  expect_len(bytes.length(), ENGINE_LEN, what="发动机数据")
  {
    status: bytes[0].to_int(),
    crankshaft_speed_raw: u16_be(bytes, 1),
    fuel_consumption_raw: u16_be(bytes, 3),
  }
}

///|
pub fn Engine::to_bytes(self : Engine) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.status.to_byte())
  push_u16_be(out, self.crankshaft_speed_raw)
  push_u16_be(out, self.fuel_consumption_raw)
  Bytes::from_array(out)
}

///|
pub fn Engine::status_name(self : Engine) -> String {
  match self.status {
    0x01 => "运行"
    0x02 => "关闭"
    0xfe => "异常"
    0xff => "无效"
    _ => "其他"
  }
}
