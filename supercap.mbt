// supercap.mbt
// 依据：GB/T 32960.3-2025 表 25（超级电容器数据）、表 26（超级电容器极值数据）

///|
/// 超级电容器数据（信息类型标志 0x31，表 25）。
///
/// 布局：管理系统号(1) 总电压(2) 总电流(2) 单体总数(2) 单体电压(2×M)
/// 温度探针总数(2) 探针温度(1×N)
pub(all) struct SuperCapacitor {
  system_no : Int32
  total_voltage_raw : Int32
  total_current_raw : Int32
  cell_voltages_raw : Array[Int32]
  probe_temps_raw : Array[Int32]
}

///|
pub fn SuperCapacitor::decode_at(
  bytes : BytesView,
  offset : Int32,
  end : Int32,
) -> (SuperCapacitor, Int32) raise FrameError {
  ensure_at(bytes, offset, 7, what="超级电容器数据")
  let cell_count_raw = u16_be(bytes, offset + 5)
  let m = match FieldState::word(cell_count_raw) {
    Valid => {
      check_count(cell_count_raw, 1, 65531, field="超级电容单体总数")
      cell_count_raw
    }
    _ => 0
  }
  let mut cursor = offset + 7
  if cursor + m * 2 > end {
    raise Payload(message="超级电容: 单体数 \{m} 超出剩余字节")
  }
  let voltages : Array[Int32] = []
  for i in 0..<m {
    voltages.push(u16_be(bytes, cursor + i * 2))
  }
  cursor = cursor + m * 2
  ensure_at(bytes, cursor, 2, what="超级电容温度探针总数")
  let probe_count_raw = u16_be(bytes, cursor)
  let n = match FieldState::word(probe_count_raw) {
    Valid => {
      check_count(
        probe_count_raw,
        1,
        65531,
        field="超级电容温度探针总数",
      )
      probe_count_raw
    }
    _ => 0
  }
  cursor = cursor + 2
  if cursor + n > end {
    raise Payload(message="超级电容: 探针数 \{n} 超出剩余字节")
  }
  let temps : Array[Int32] = []
  for i in 0..<n {
    temps.push(bytes[cursor + i].to_int())
  }
  cursor = cursor + n
  (
    {
      system_no: bytes[offset].to_int(),
      total_voltage_raw: u16_be(bytes, offset + 1),
      total_current_raw: u16_be(bytes, offset + 3),
      cell_voltages_raw: voltages,
      probe_temps_raw: temps,
    },
    cursor - offset,
  )
}

///|
pub fn SuperCapacitor::to_bytes(self : SuperCapacitor) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.system_no.to_byte())
  push_u16_be(out, self.total_voltage_raw)
  push_u16_be(out, self.total_current_raw)
  push_u16_be(out, self.cell_voltages_raw.length())
  for value in self.cell_voltages_raw {
    push_u16_be(out, value)
  }
  push_u16_be(out, self.probe_temps_raw.length())
  for value in self.probe_temps_raw {
    out.push(value.to_byte())
  }
  Bytes::from_array(out)
}

///|
/// 超级电容器极值数据（信息类型标志 0x32，表 26），固定 18 字节。
pub(all) struct SuperCapacitorExtreme {
  max_voltage_system : Int32
  max_voltage_cell : Int32
  max_voltage_raw : Int32
  min_voltage_system : Int32
  min_voltage_cell : Int32
  min_voltage_raw : Int32
  max_temp_system : Int32
  max_temp_probe : Int32
  max_temp_raw : Int32
  min_temp_system : Int32
  min_temp_probe : Int32
  min_temp_raw : Int32
}

///|
pub const SUPERCAP_EXTREME_LEN : Int32 = 18

///|
pub fn SuperCapacitorExtreme::decode(
  bytes : BytesView,
) -> SuperCapacitorExtreme raise FrameError {
  expect_len(
    bytes.length(),
    SUPERCAP_EXTREME_LEN,
    what="超级电容器极值数据",
  )
  {
    max_voltage_system: bytes[0].to_int(),
    max_voltage_cell: u16_be(bytes, 1),
    max_voltage_raw: u16_be(bytes, 3),
    min_voltage_system: bytes[5].to_int(),
    min_voltage_cell: u16_be(bytes, 6),
    min_voltage_raw: u16_be(bytes, 8),
    max_temp_system: bytes[10].to_int(),
    max_temp_probe: u16_be(bytes, 11),
    max_temp_raw: bytes[13].to_int(),
    min_temp_system: bytes[14].to_int(),
    min_temp_probe: u16_be(bytes, 15),
    min_temp_raw: bytes[17].to_int(),
  }
}

///|
pub fn SuperCapacitorExtreme::to_bytes(self : SuperCapacitorExtreme) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.max_voltage_system.to_byte())
  push_u16_be(out, self.max_voltage_cell)
  push_u16_be(out, self.max_voltage_raw)
  out.push(self.min_voltage_system.to_byte())
  push_u16_be(out, self.min_voltage_cell)
  push_u16_be(out, self.min_voltage_raw)
  out.push(self.max_temp_system.to_byte())
  push_u16_be(out, self.max_temp_probe)
  out.push(self.max_temp_raw.to_byte())
  out.push(self.min_temp_system.to_byte())
  push_u16_be(out, self.min_temp_probe)
  out.push(self.min_temp_raw.to_byte())
  Bytes::from_array(out)
}
