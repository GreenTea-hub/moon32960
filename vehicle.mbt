// vehicle.mbt
// 依据：GB/T 32960.3-2025 表 10（整车数据），共 18 字节 11 字段

///|
/// 整车数据（信息类型标志 0x01）。
///
/// 布局：车辆状态(1) 充电状态(1) 运行模式(1) 车速(2) 累计里程(4)
/// 总电压(2) 总电流(2) SOC(1) DC-DC状态(1) 挡位(1) 绝缘电阻(2)
///
/// 相比 2016 版：删除加速踏板行程值与制动踏板状态；车速范围扩到 0~5000（0.1 km/h）。
pub(all) struct WholeVehicle {
  vehicle_status : Int32
  charge_status : Int32
  operation_mode : Int32
  speed_raw : Int32
  odometer_raw : Int32
  total_voltage_raw : Int32
  total_current_raw : Int32
  soc : Int32
  dc_dc_status : Int32
  gear : Int32
  insulation_raw : Int32
}

///|
pub const WHOLE_VEHICLE_LEN : Int32 = 18

///|
pub fn WholeVehicle::decode(bytes : BytesView) -> WholeVehicle raise FrameError {
  expect_len(bytes.length(), WHOLE_VEHICLE_LEN, what="整车数据")
  {
    vehicle_status: bytes[0].to_int(),
    charge_status: bytes[1].to_int(),
    operation_mode: bytes[2].to_int(),
    speed_raw: u16_be(bytes, 3),
    odometer_raw: u32_be(bytes, 5),
    total_voltage_raw: u16_be(bytes, 9),
    total_current_raw: u16_be(bytes, 11),
    soc: bytes[13].to_int(),
    dc_dc_status: bytes[14].to_int(),
    gear: bytes[15].to_int(),
    insulation_raw: u16_be(bytes, 16),
  }
}

///|
pub fn WholeVehicle::to_bytes(self : WholeVehicle) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.vehicle_status.to_byte())
  out.push(self.charge_status.to_byte())
  out.push(self.operation_mode.to_byte())
  push_u16_be(out, self.speed_raw)
  push_u32_be(out, self.odometer_raw)
  push_u16_be(out, self.total_voltage_raw)
  push_u16_be(out, self.total_current_raw)
  out.push(self.soc.to_byte())
  out.push(self.dc_dc_status.to_byte())
  out.push(self.gear.to_byte())
  push_u16_be(out, self.insulation_raw)
  Bytes::from_array(out)
}

///|
pub fn WholeVehicle::speed_kmh(self : WholeVehicle) -> Double? {
  match FieldState::word(self.speed_raw) {
    Valid => Some(self.speed_raw.to_double() * 0.1)
    _ => None
  }
}

///|
pub fn WholeVehicle::odometer_km(self : WholeVehicle) -> Double? {
  match FieldState::dword(self.odometer_raw) {
    Valid => Some(self.odometer_raw.to_double() * 0.1)
    _ => None
  }
}

///|
pub fn WholeVehicle::total_voltage_v(self : WholeVehicle) -> Double? {
  match FieldState::word(self.total_voltage_raw) {
    Valid => Some(self.total_voltage_raw.to_double() * 0.1)
    _ => None
  }
}

///|
/// 总电流：原始值 ×0.1 − 3000 A。
pub fn WholeVehicle::total_current_a(self : WholeVehicle) -> Double? {
  match FieldState::word(self.total_current_raw) {
    Valid => Some(self.total_current_raw.to_double() * 0.1 - 3000.0)
    _ => None
  }
}

///|
pub fn WholeVehicle::insulation_kohm(self : WholeVehicle) -> Int32? {
  match FieldState::word(self.insulation_raw) {
    Valid => Some(self.insulation_raw)
    _ => None
  }
}

///|
pub fn WholeVehicle::charge_status_name(self : WholeVehicle) -> String {
  match self.charge_status {
    0x01 => "停车充电"
    0x02 => "行驶充电"
    0x03 => "未充电"
    0x04 => "充电完成"
    0xfe => "异常"
    0xff => "无效"
    _ => "其他"
  }
}

///|
pub fn WholeVehicle::vehicle_status_name(self : WholeVehicle) -> String {
  match self.vehicle_status {
    0x01 => "车辆启动状态"
    0x02 => "熄火"
    0x03 => "其他状态"
    0xfe => "异常"
    0xff => "无效"
    _ => "其他"
  }
}

///|
pub fn WholeVehicle::operation_mode_name(self : WholeVehicle) -> String {
  match self.operation_mode {
    0x01 => "纯电"
    0x02 => "混动"
    0x03 => "燃油"
    0xfe => "异常"
    0xff => "无效"
    _ => "其他"
  }
}
