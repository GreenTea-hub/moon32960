// position.mbt
///|
/// 车辆位置数据（信息类型标志 0x05），表 21/表 22。
///
/// 布局（共 9 字节）：定位状态(1) | 经度(4) | 纬度(4)。
/// 经纬度以度为单位的数值乘以 10^6，按 GCJ-02 坐标系传输。
pub(all) struct VehicleLocation {
  position_status : Int32
  longitude_raw : Int32
  latitude_raw : Int32
}

///|
pub const LOCATION_LEN : Int32 = 9

///|
pub fn VehicleLocation::decode(bytes : BytesView) -> VehicleLocation raise FrameError {
  expect_len(bytes.length(), LOCATION_LEN, what="车辆位置数据")
  {
    position_status: bytes[0].to_int(),
    longitude_raw: u32_be(bytes, 1),
    latitude_raw: u32_be(bytes, 5),
  }
}

///|
pub fn VehicleLocation::to_bytes(self : VehicleLocation) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.position_status.to_byte())
  push_u32_be(out, self.longitude_raw)
  push_u32_be(out, self.latitude_raw)
  Bytes::from_array(out)
}

///|
/// 第 0 位：0 有效定位，1 无效定位。
pub fn VehicleLocation::is_fix_valid(self : VehicleLocation) -> Bool {
  self.position_status % 2 == 0
}

///|
/// 第 1 位：0 北纬，1 南纬。
pub fn VehicleLocation::is_south(self : VehicleLocation) -> Bool {
  (self.position_status / 2) % 2 == 1
}

///|
/// 第 2 位：0 东经，1 西经。
pub fn VehicleLocation::is_west(self : VehicleLocation) -> Bool {
  (self.position_status / 4) % 2 == 1
}

///|
/// 经度（十进制度，东经为正）；定位无效时返回 None。
pub fn VehicleLocation::longitude(self : VehicleLocation) -> Double? {
  if !self.is_fix_valid() {
    return None
  }
  let magnitude = self.longitude_raw.to_double() / 1000000.0
  if self.is_west() {
    Some(-magnitude)
  } else {
    Some(magnitude)
  }
}

///|
/// 纬度（十进制度，北纬为正）；定位无效时返回 None。
pub fn VehicleLocation::latitude(self : VehicleLocation) -> Double? {
  if !self.is_fix_valid() {
    return None
  }
  let magnitude = self.latitude_raw.to_double() / 1000000.0
  if self.is_south() {
    Some(-magnitude)
  } else {
    Some(magnitude)
  }
}

///|
/// 极值数据（信息类型标志 0x06），表 20。
///
/// 布局（共 14 字节）：最高电压子系统号(1) | 最高电压单体代号(1) | 单体电压最高值(2)
/// | 最低电压子系统号(1) | 最低电压单体代号(1) | 单体电压最低值(2)
/// | 最高温度子系统号(1) | 最高温度探针序号(1) | 最高温度值(1)
/// | 最低温度子系统号(1) | 最低温度探针序号(1) | 最低温度值(1)
pub(all) struct Extreme {
  max_voltage_subsystem : Int32
  max_voltage_cell : Int32
  max_cell_voltage_raw : Int32
  min_voltage_subsystem : Int32
  min_voltage_cell : Int32
  min_cell_voltage_raw : Int32
  max_temp_subsystem : Int32
  max_temp_probe : Int32
  max_temp_raw : Int32
  min_temp_subsystem : Int32
  min_temp_probe : Int32
  min_temp_raw : Int32
}

///|
pub const EXTREME_LEN : Int32 = 14

///|
pub fn Extreme::decode(bytes : BytesView) -> Extreme raise FrameError {
  expect_len(bytes.length(), EXTREME_LEN, what="极值数据")
  {
    max_voltage_subsystem: bytes[0].to_int(),
    max_voltage_cell: bytes[1].to_int(),
    max_cell_voltage_raw: u16_be(bytes, 2),
    min_voltage_subsystem: bytes[4].to_int(),
    min_voltage_cell: bytes[5].to_int(),
    min_cell_voltage_raw: u16_be(bytes, 6),
    max_temp_subsystem: bytes[8].to_int(),
    max_temp_probe: bytes[9].to_int(),
    max_temp_raw: bytes[10].to_int(),
    min_temp_subsystem: bytes[11].to_int(),
    min_temp_probe: bytes[12].to_int(),
    min_temp_raw: bytes[13].to_int(),
  }
}

///|
pub fn Extreme::to_bytes(self : Extreme) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.max_voltage_subsystem.to_byte())
  out.push(self.max_voltage_cell.to_byte())
  push_u16_be(out, self.max_cell_voltage_raw)
  out.push(self.min_voltage_subsystem.to_byte())
  out.push(self.min_voltage_cell.to_byte())
  push_u16_be(out, self.min_cell_voltage_raw)
  out.push(self.max_temp_subsystem.to_byte())
  out.push(self.max_temp_probe.to_byte())
  out.push(self.max_temp_raw.to_byte())
  out.push(self.min_temp_subsystem.to_byte())
  out.push(self.min_temp_probe.to_byte())
  out.push(self.min_temp_raw.to_byte())
  Bytes::from_array(out)
}

///|
/// 单体电压最高值，单位 V（原始值乘以 0.001）。
pub fn Extreme::max_cell_voltage_v(self : Extreme) -> Double? {
  match FieldState::word(self.max_cell_voltage_raw) {
    Valid => Some(self.max_cell_voltage_raw.to_double() * 0.001)
    _ => None
  }
}

///|
/// 单体电压最低值，单位 V（原始值乘以 0.001）。
pub fn Extreme::min_cell_voltage_v(self : Extreme) -> Double? {
  match FieldState::word(self.min_cell_voltage_raw) {
    Valid => Some(self.min_cell_voltage_raw.to_double() * 0.001)
    _ => None
  }
}

///|
/// 探测温度换算：原始值减 40 ℃；异常或无效时返回 None。
pub fn probe_temperature(raw : Int32) -> Int32? {
  match FieldState::byte(raw) {
    Valid => Some(raw - 40)
    _ => None
  }
}
