// storage.mbt
///|
/// 一个可充电储能子系统内的单体电压分组（表 17）。
pub(all) struct StorageVoltageGroup {
  subsystem : Int32
  cell_count : Int32
  cell_voltages_raw : Array[Int32]
}

///|
/// 可充电储能装置电压数据（信息类型标志 0x08）。
///
/// 布局：子系统数 n(1) | n 组[子系统号(1) | 单体电池总数(2) | 单体电压(2×m)]。
pub(all) struct StorageVoltage {
  groups : Array[StorageVoltageGroup]
}

///|
/// 最少 1 个字节（子系统数），通常每个子系统至少 3 字节。
pub fn StorageVoltage::decode_at(
  bytes : BytesView,
  offset : Int32,
  end : Int32,
) -> (StorageVoltage, Int32) raise FrameError {
  ensure_at(bytes, offset, 1, what="可充电储能装置电压数据")
  let count_raw = bytes[offset].to_int()
  let n = match FieldState::byte(count_raw) {
    Valid => {
      check_count(count_raw, 1, 250, field="可充电储能子系统数")
      count_raw
    }
    _ => 0
  }
  let mut cursor = offset + 1
  let groups : Array[StorageVoltageGroup] = []
  for _ in 0..<n {
    ensure_at(bytes, cursor, 3, what="储能子系统电压分组")
    let subsystem = bytes[cursor].to_int()
    let cell_count_raw = u16_be(bytes, cursor + 1)
    let m = match FieldState::word(cell_count_raw) {
      Valid => {
        check_count(cell_count_raw, 1, 65531, field="单体电池总数")
        cell_count_raw
      }
      _ => 0
    }
    let need = 3 + m * 2
    if cursor + need > end {
      raise Payload(message="储能电压: 单体电池数 \{m} 超出剩余字节")
    }
    let voltages : Array[Int32] = []
    for i in 0..<m {
      voltages.push(u16_be(bytes, cursor + 3 + i * 2))
    }
    groups.push({ subsystem, cell_count: cell_count_raw, cell_voltages_raw: voltages })
    cursor = cursor + need
  }
  ({ groups }, cursor - offset)
}

///|
pub fn StorageVoltage::to_bytes(self : StorageVoltage) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.groups.length().to_byte())
  for group in self.groups {
    out.push(group.subsystem.to_byte())
    push_u16_be(out, group.cell_voltages_raw.length())
    for value in group.cell_voltages_raw {
      push_u16_be(out, value)
    }
  }
  Bytes::from_array(out)
}

///|
/// 单体电压换算：原始值乘以 0.001，单位 V；异常或无效时返回 None。
pub fn cell_voltage_v(raw : Int32) -> Double? {
  match FieldState::word(raw) {
    Valid => Some(raw.to_double() * 0.001)
    _ => None
  }
}

///|
/// 一个可充电储能子系统的温度探针分组。
pub(all) struct StorageTempGroup {
  subsystem : Int32
  probe_count : Int32
  probe_temps_raw : Array[Int32]
}

///|
/// 可充电储能装置温度数据（信息类型标志 0x09）。
///
/// 布局：子系统数 n(1) | n 组[子系统号(1) | 探针个数(2) | 探针温度(1×m)]
/// | 最高温度子系统号(1) | 最高温度探针序号(1) | 最高温度值(1)
/// | 最低温度子系统号(1) | 最低温度探针序号(1) | 最低温度值(1)
pub(all) struct StorageTemperature {
  groups : Array[StorageTempGroup]
  max_temp_subsystem : Int32
  max_temp_probe : Int32
  max_temp_raw : Int32
  min_temp_subsystem : Int32
  min_temp_probe : Int32
  min_temp_raw : Int32
}

///|
pub fn StorageTemperature::decode_at(
  bytes : BytesView,
  offset : Int32,
  end : Int32,
) -> (StorageTemperature, Int32) raise FrameError {
  ensure_at(bytes, offset, 7, what="可充电储能装置温度数据")
  let count_raw = bytes[offset].to_int()
  let n = match FieldState::byte(count_raw) {
    Valid => {
      check_count(count_raw, 1, 250, field="可充电储能子系统个数")
      count_raw
    }
    _ => 0
  }
  let mut cursor = offset + 1
  let groups : Array[StorageTempGroup] = []
  for _ in 0..<n {
    ensure_at(bytes, cursor, 3, what="储能子系统温度分组")
    let subsystem = bytes[cursor].to_int()
    let probe_count_raw = u16_be(bytes, cursor + 1)
    let m = match FieldState::word(probe_count_raw) {
      Valid => {
        check_count(probe_count_raw, 1, 65531, field="可充电储能温度探针个数")
        probe_count_raw
      }
      _ => 0
    }
    let need = 3 + m
    if cursor + need > end {
      raise Payload(message="储能温度: 探针数 \{m} 超出剩余字节")
    }
    let temps : Array[Int32] = []
    for i in 0..<m {
      temps.push(bytes[cursor + 3 + i].to_int())
    }
    groups.push({ subsystem, probe_count: probe_count_raw, probe_temps_raw: temps })
    cursor = cursor + need
  }
  ensure_at(bytes, cursor, 6, what="储能温度极值字段")
  (
    {
      groups,
      max_temp_subsystem: bytes[cursor].to_int(),
      max_temp_probe: bytes[cursor + 1].to_int(),
      max_temp_raw: bytes[cursor + 2].to_int(),
      min_temp_subsystem: bytes[cursor + 3].to_int(),
      min_temp_probe: bytes[cursor + 4].to_int(),
      min_temp_raw: bytes[cursor + 5].to_int(),
    },
    cursor - offset + 6,
  )
}

///|
pub fn StorageTemperature::to_bytes(self : StorageTemperature) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.groups.length().to_byte())
  for group in self.groups {
    out.push(group.subsystem.to_byte())
    push_u16_be(out, group.probe_temps_raw.length())
    for value in group.probe_temps_raw {
      out.push(value.to_byte())
    }
  }
  out.push(self.max_temp_subsystem.to_byte())
  out.push(self.max_temp_probe.to_byte())
  out.push(self.max_temp_raw.to_byte())
  out.push(self.min_temp_subsystem.to_byte())
  out.push(self.min_temp_probe.to_byte())
  out.push(self.min_temp_raw.to_byte())
  Bytes::from_array(out)
}
