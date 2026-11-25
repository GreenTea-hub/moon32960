// battery.mbt
// 依据：GB/T 32960.3-2025 表 11/12（动力蓄电池最小并联单元电压）、表 13/14（动力蓄电池温度）

///|
/// 一个动力蓄电池包的最小并联单元电压组（表 12）。
pub(all) struct BatteryPackVoltage {
  pack_no : Int32
  voltage_raw : Int32
  current_raw : Int32
  cell_count : Int32
  cell_voltages_raw : Array[Int32]
}

///|
/// 动力蓄电池最小并联单元电压数据（信息类型标志 0x07）。
///
/// 布局：包数(1) + 每包[包号(1) 包电压(2) 包电流(2) 单元总数(2) 单元电压(2×N)]
pub(all) struct BatteryCellVoltage {
  packs : Array[BatteryPackVoltage]
}

///|
pub fn BatteryCellVoltage::decode_at(
  bytes : BytesView,
  offset : Int32,
  end : Int32,
) -> (BatteryCellVoltage, Int32) raise FrameError {
  ensure_at(bytes, offset, 1, what="动力蓄电池包个数")
  let count_raw = bytes[offset].to_int()
  let n = match FieldState::byte(count_raw) {
    Valid => {
      check_count(count_raw, 0, 50, field="动力蓄电池包个数")
      count_raw
    }
    _ => 0
  }
  let mut cursor = offset + 1
  let packs : Array[BatteryPackVoltage] = []
  for _ in 0..<n {
    ensure_at(bytes, cursor, 7, what="动力蓄电池包电压组")
    let cell_count_raw = u16_be(bytes, cursor + 5)
    let m = match FieldState::word(cell_count_raw) {
      Valid => {
        check_count(cell_count_raw, 1, 65531, field="最小并联单元总数")
        cell_count_raw
      }
      _ => 0
    }
    let need = 7 + m * 2
    if cursor + need > end {
      raise Payload(message="蓄电池电压: 单元数 \{m} 超出剩余字节")
    }
    let voltages : Array[Int32] = []
    for i in 0..<m {
      voltages.push(u16_be(bytes, cursor + 7 + i * 2))
    }
    packs.push({
      pack_no: bytes[cursor].to_int(),
      voltage_raw: u16_be(bytes, cursor + 1),
      current_raw: u16_be(bytes, cursor + 3),
      cell_count: cell_count_raw,
      cell_voltages_raw: voltages,
    })
    cursor = cursor + need
  }
  ({ packs }, cursor - offset)
}

///|
pub fn BatteryCellVoltage::to_bytes(self : BatteryCellVoltage) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.packs.length().to_byte())
  for pack in self.packs {
    out.push(pack.pack_no.to_byte())
    push_u16_be(out, pack.voltage_raw)
    push_u16_be(out, pack.current_raw)
    push_u16_be(out, pack.cell_voltages_raw.length())
    for value in pack.cell_voltages_raw {
      push_u16_be(out, value)
    }
  }
  Bytes::from_array(out)
}

///|
/// 单体电压换算：原始值 ×0.001 V。
pub fn cell_voltage_v(raw : Int32) -> Double? {
  match FieldState::word(raw) {
    Valid => Some(raw.to_double() * 0.001)
    _ => None
  }
}

///|
/// 一个动力蓄电池包的温度组（表 14）。
pub(all) struct BatteryPackTemperature {
  pack_no : Int32
  probe_count : Int32
  probe_temps_raw : Array[Int32]
}

///|
/// 动力蓄电池温度数据（信息类型标志 0x08）。
///
/// 布局：包数(1) + 每包[包号(1) 探针数(2) 探针温度(1×N)]
pub(all) struct BatteryTemperature {
  packs : Array[BatteryPackTemperature]
}

///|
pub fn BatteryTemperature::decode_at(
  bytes : BytesView,
  offset : Int32,
  end : Int32,
) -> (BatteryTemperature, Int32) raise FrameError {
  ensure_at(bytes, offset, 1, what="动力蓄电池包个数")
  let count_raw = bytes[offset].to_int()
  let n = match FieldState::byte(count_raw) {
    Valid => {
      check_count(count_raw, 0, 50, field="动力蓄电池包个数")
      count_raw
    }
    _ => 0
  }
  let mut cursor = offset + 1
  let packs : Array[BatteryPackTemperature] = []
  for _ in 0..<n {
    ensure_at(bytes, cursor, 3, what="动力蓄电池包温度组")
    let probe_count_raw = u16_be(bytes, cursor + 1)
    let m = match FieldState::word(probe_count_raw) {
      Valid => {
        check_count(probe_count_raw, 1, 65531, field="温度探针个数")
        probe_count_raw
      }
      _ => 0
    }
    let need = 3 + m
    if cursor + need > end {
      raise Payload(message="蓄电池温度: 探针数 \{m} 超出剩余字节")
    }
    let temps : Array[Int32] = []
    for i in 0..<m {
      temps.push(bytes[cursor + 3 + i].to_int())
    }
    packs.push({
      pack_no: bytes[cursor].to_int(),
      probe_count: probe_count_raw,
      probe_temps_raw: temps,
    })
    cursor = cursor + need
  }
  ({ packs }, cursor - offset)
}

///|
pub fn BatteryTemperature::to_bytes(self : BatteryTemperature) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.packs.length().to_byte())
  for pack in self.packs {
    out.push(pack.pack_no.to_byte())
    push_u16_be(out, pack.probe_temps_raw.length())
    for value in pack.probe_temps_raw {
      out.push(value.to_byte())
    }
  }
  Bytes::from_array(out)
}

///|
/// 探针温度换算：原始值 − 40 ℃。
pub fn probe_temperature(raw : Int32) -> Int32? {
  match FieldState::byte(raw) {
    Valid => Some(raw - 40)
    _ => None
  }
}
