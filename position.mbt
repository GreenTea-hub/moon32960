// position.mbt
// 依据：GB/T 32960.3-2025 表 21（车辆位置数据）、表 22（状态位）

///|
/// 车辆位置数据（信息类型标志 0x05），固定 10 字节。
///
/// 布局：定位状态(1) 坐标系(1) 经度(4) 纬度(4)
/// 相比 2016 版：新增 1 字节坐标系字段。
pub(all) struct VehicleLocation {
  position_status : Int32
  coordinate_system : Int32
  longitude_raw : Int32
  latitude_raw : Int32
}

///|
pub const LOCATION_LEN : Int32 = 10

///|
pub fn VehicleLocation::decode(bytes : BytesView) -> VehicleLocation raise FrameError {
  expect_len(bytes.length(), LOCATION_LEN, what="车辆位置数据")
  {
    position_status: bytes[0].to_int(),
    coordinate_system: bytes[1].to_int(),
    longitude_raw: u32_be(bytes, 2),
    latitude_raw: u32_be(bytes, 6),
  }
}

///|
pub fn VehicleLocation::to_bytes(self : VehicleLocation) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.position_status.to_byte())
  out.push(self.coordinate_system.to_byte())
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
/// 坐标系名称：0x01 WGS84、0x02 GCJ02、0x03 其他。
pub fn VehicleLocation::coordinate_system_name(self : VehicleLocation) -> String {
  match self.coordinate_system {
    0x01 => "WGS84"
    0x02 => "GCJ02"
    0x03 => "其他坐标系"
    _ => "未定义"
  }
}

///|
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
