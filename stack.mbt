// stack.mbt
// 依据：GB/T 32960.3-2025 表 18/19（燃料电池电堆数据）

///|
/// 单个燃料电池电堆（表 19）：序号(1) 电压(2) 电流(2) 氢气入口压力(2)
/// 空气入口压力(2) 空气入口温度(1) 冷却水探针总数(2) 冷却水温度(1×N)
pub(all) struct FuelCellStackUnit {
  sequence : Int32
  voltage_raw : Int32
  current_raw : Int32
  hydrogen_inlet_pressure_raw : Int32
  air_inlet_pressure_raw : Int32
  air_inlet_temp_raw : Int32
  cooling_temps_raw : Array[Int32]
}

///|
/// 燃料电池电堆数据（信息类型标志 0x30，表 18）：个数(1) + 各电堆。
pub(all) struct FuelCellStackData {
  count_raw : Int32
  stacks : Array[FuelCellStackUnit]
}

///|
pub fn FuelCellStackData::decode_at(
  bytes : BytesView,
  offset : Int32,
  end : Int32,
) -> (FuelCellStackData, Int32) raise FrameError {
  ensure_at(bytes, offset, 1, what="燃料电池电堆个数")
  let count_raw = bytes[offset].to_int()
  let n = match FieldState::byte(count_raw) {
    Valid => {
      check_count(count_raw, 0, 253, field="燃料电池电堆个数")
      count_raw
    }
    _ => 0
  }
  let mut cursor = offset + 1
  let stacks : Array[FuelCellStackUnit] = []
  for _ in 0..<n {
    ensure_at(bytes, cursor, 12, what="燃料电池电堆")
    let probe_count_raw = u16_be(bytes, cursor + 10)
    let m = match FieldState::word(probe_count_raw) {
      Valid => {
        check_count(
          probe_count_raw,
          0,
          65531,
          field="冷却水出水口温度探针总数",
        )
        probe_count_raw
      }
      _ => 0
    }
    let need = 12 + m
    if cursor + need > end {
      raise Payload(
        message="燃料电池电堆: 探针数 \{m} 超出剩余字节",
      )
    }
    let temps : Array[Int32] = []
    for i in 0..<m {
      temps.push(bytes[cursor + 12 + i].to_int())
    }
    stacks.push({
      sequence: bytes[cursor].to_int(),
      voltage_raw: u16_be(bytes, cursor + 1),
      current_raw: u16_be(bytes, cursor + 3),
      hydrogen_inlet_pressure_raw: u16_be(bytes, cursor + 5),
      air_inlet_pressure_raw: u16_be(bytes, cursor + 7),
      air_inlet_temp_raw: bytes[cursor + 9].to_int(),
      cooling_temps_raw: temps,
    })
    cursor = cursor + need
  }
  ({ count_raw, stacks, }, cursor - offset)
}

///|
pub fn FuelCellStackData::to_bytes(self : FuelCellStackData) -> Bytes {
  let out : Array[Byte] = []
  out.push(self.stacks.length().to_byte())
  for stack in self.stacks {
    out.push(stack.sequence.to_byte())
    push_u16_be(out, stack.voltage_raw)
    push_u16_be(out, stack.current_raw)
    push_u16_be(out, stack.hydrogen_inlet_pressure_raw)
    push_u16_be(out, stack.air_inlet_pressure_raw)
    out.push(stack.air_inlet_temp_raw.to_byte())
    push_u16_be(out, stack.cooling_temps_raw.length())
    for value in stack.cooling_temps_raw {
      out.push(value.to_byte())
    }
  }
  Bytes::from_array(out)
}
