// powertrain.mbt
// 依据：GB/T 32960.3-2025 表 15/16（驱动电机）、表 17（燃料电池发动机及车载氢系统）、表 20（发动机）

///|
/// 单个驱动电机（表 16），固定 10 字节。
///
/// 布局：序号(1) 状态(1) 控制器温度(1) 转速(2) 转矩(4) 电机温度(1)
/// 相比 2016 版：转矩由 WORD 改为 DWORD；删除控制器输入电压与母线电流。
pub(all) struct DriveMotor {
  sequence : Int32
  status : Int32
  controller_temp_raw : Int32
  speed_raw : Int32
  torque_raw : Int32
  motor_temp_raw : Int32
}

///|
pub const DRIVE_MOTOR_LEN : Int32 = 10

///|
pub fn DriveMotor::decode(bytes : BytesView) -> DriveMotor raise FrameError {
  expect_len(bytes.length(), DRIVE_MOTOR_LEN, what="单个驱动电机")
  {
    sequence: bytes[0].to_int(),
    status: bytes[1].to_int(),
    controller_temp_raw: bytes[2].to_int(),
    speed_raw: u16_be(bytes, 3),
    torque_raw: u32_be(bytes, 5),
    motor_temp_raw: bytes[9].to_int(),
  }
}

///|
pub fn DriveMotor::to_bytes(self : DriveMotor) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.sequence.to_byte())
  out.push(self.status.to_byte())
  out.push(self.controller_temp_raw.to_byte())
  push_u16_be(out, self.speed_raw)
  push_u32_be(out, self.torque_raw)
  out.push(self.motor_temp_raw.to_byte())
  Bytes::from_array(out)
}

///|
/// 转速：原始值 − 32000 r/min。
pub fn DriveMotor::speed_rpm(self : DriveMotor) -> Int32? {
  match FieldState::word(self.speed_raw) {
    Valid => Some(self.speed_raw - 32000)
    _ => None
  }
}

///|
/// 转矩：原始值 ×0.1 − 20000 N·m。
pub fn DriveMotor::torque_nm(self : DriveMotor) -> Double? {
  match FieldState::dword(self.torque_raw) {
    Valid => Some(self.torque_raw.to_double() * 0.1 - 20000.0)
    _ => None
  }
}

///|
pub fn DriveMotor::status_name(self : DriveMotor) -> String {
  match self.status {
    0x01 => "耗电"
    0x02 => "发电"
    0x03 => "关闭状态"
    0x04 => "准备状态"
    0xfe => "异常"
    0xff => "无效"
    _ => "其他"
  }
}

///|
/// 驱动电机数据（信息类型标志 0x02）：个数(1) + n 个 10 字节电机。
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
      message="驱动电机数据: 声明 \{count} 个需要 \{need} 字节，实际不足",
    )
  }
  let motors : Array[DriveMotor] = []
  for i in 0..<count {
    let start = offset + 1 + i * DRIVE_MOTOR_LEN
    motors.push(DriveMotor::decode(bytes[start:start + DRIVE_MOTOR_LEN]))
  }
  ({ count_raw, motors, }, need)
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
/// 燃料电池发动机及车载氢系统（信息类型标志 0x03，表 17），固定 12 字节。
///
/// 布局：车载氢系统最高温度(2) 探针代号(1) 氢气最高浓度(2) 传感器代号(1)
/// 氢气最高压力(2) 传感器代号(1) 高压DC/DC状态(1) 剩余氢量百分比(1) 高压DC/DC控制器温度(1)
///
/// 相比 2016 版：不再按探针总数展开，字段顺序与含义全部重排。
pub(all) struct FuelCellHydrogen {
  max_hydrogen_temp_raw : Int32
  max_hydrogen_temp_probe : Int32
  hydrogen_concentration_raw : Int32
  hydrogen_concentration_sensor : Int32
  hydrogen_pressure_raw : Int32
  hydrogen_pressure_sensor : Int32
  dc_dc_status : Int32
  remaining_hydrogen_percent : Int32
  dc_dc_controller_temp_raw : Int32
}

///|
pub const FUEL_CELL_HYDROGEN_LEN : Int32 = 12

///|
pub fn FuelCellHydrogen::decode(
  bytes : BytesView,
) -> FuelCellHydrogen raise FrameError {
  expect_len(
    bytes.length(),
    FUEL_CELL_HYDROGEN_LEN,
    what="燃料电池发动机及车载氢系统",
  )
  {
    max_hydrogen_temp_raw: u16_be(bytes, 0),
    max_hydrogen_temp_probe: bytes[2].to_int(),
    hydrogen_concentration_raw: u16_be(bytes, 3),
    hydrogen_concentration_sensor: bytes[5].to_int(),
    hydrogen_pressure_raw: u16_be(bytes, 6),
    hydrogen_pressure_sensor: bytes[8].to_int(),
    dc_dc_status: bytes[9].to_int(),
    remaining_hydrogen_percent: bytes[10].to_int(),
    dc_dc_controller_temp_raw: bytes[11].to_int(),
  }
}

///|
pub fn FuelCellHydrogen::to_bytes(self : FuelCellHydrogen) -> Bytes {
  let out : Array[Byte] = []
  push_u16_be(out, self.max_hydrogen_temp_raw)
  out.push(self.max_hydrogen_temp_probe.to_byte())
  push_u16_be(out, self.hydrogen_concentration_raw)
  out.push(self.hydrogen_concentration_sensor.to_byte())
  push_u16_be(out, self.hydrogen_pressure_raw)
  out.push(self.hydrogen_pressure_sensor.to_byte())
  out.push(self.dc_dc_status.to_byte())
  out.push(self.remaining_hydrogen_percent.to_byte())
  out.push(self.dc_dc_controller_temp_raw.to_byte())
  Bytes::from_array(out)
}

///|
/// 发动机数据（信息类型标志 0x04，表 20）：只有曲轴转速(2)。
pub(all) struct Engine {
  crankshaft_speed_raw : Int32
}

///|
pub const ENGINE_LEN : Int32 = 2

///|
pub fn Engine::decode(bytes : BytesView) -> Engine raise FrameError {
  expect_len(bytes.length(), ENGINE_LEN, what="发动机数据")
  { crankshaft_speed_raw: u16_be(bytes, 0), }
}

///|
pub fn Engine::to_bytes(self : Engine) -> Bytes {
  let out : Array[Byte] = []
  push_u16_be(out, self.crankshaft_speed_raw)
  Bytes::from_array(out)
}
